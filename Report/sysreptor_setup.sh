#!/bin/bash
set -euo pipefail

info()  { echo "[+] $*"; }
warn()  { echo "[!] $*"; }
error() { echo "[-] $*" >&2; }

is_kali() {
    grep -qi 'kali' /etc/os-release 2>/dev/null
}

ensure_docker_running() {
    if ! systemctl is-active --quiet docker; then
        info "Starting docker daemon"
        systemctl start docker
    fi
}

if [[ $EUID -ne 0 ]]; then
    warn "This script requires root privileges!"
    exit 1
fi

info "Updating APT packages"
apt-get update -q

info "Installing requirements"
apt-get install -y sed curl openssl uuid-runtime coreutils

info "Checking if docker is installed"
if command -v docker &>/dev/null; then
    info "Docker is already installed"
elif is_kali; then
    info "Installing docker"
    apt-get install -y docker.io
else
    info "Installing docker"
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    curl -fsSL https://get.docker.com -o "$tmp"
    bash "$tmp"
fi

info "Checking if docker-compose is installed"
if command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1; then
    info "Docker-compose is already installed"
elif is_kali; then
    info "Installing docker-compose"
    apt-get install -y docker-compose
fi

ensure_docker_running

info "Downloading and running SysReptor"
bash <(curl -fsSL https://docs.sysreptor.com/install.sh)
info "Access your application at http://127.0.0.1:8000/ and use the credentials provided above"

read -rp "[+] Would you like to install reporting templates? [Y/n] " choice
choice=${choice:-Y}

if [[ ${choice^^} == "Y" ]]; then
    if [[ ! -d sysreptor/deploy ]]; then
        error "Unable to find SysReptor folder. Are you sure SysReptor is installed?"
        exit 1
    fi

    echo "[+] Which templates would you like to install?"
    echo "    1) HTB (CPTS, CBBH, CDSA, CWEE, CAPE)"
    echo "    2) Offsec (OSCP, OSWP, OSEP, OSWA, OSWE, OSED, OSMR, OSEE, OSDA)"
    echo "    3) Both"
    read -rp "[+] Enter your choice [1/2/3]: " template_choice

    cd sysreptor/deploy

    if [[ $template_choice == "1" || $template_choice == "3" ]]; then
        info "Downloading HTB reporting templates"
        if curl -fsSL "https://docs.sysreptor.com/assets/htb-designs.tar.gz" | docker compose exec --no-TTY app python3 manage.py importdemodata --type=design &&
           curl -fsSL "https://docs.sysreptor.com/assets/htb-demo-projects.tar.gz" | docker compose exec --no-TTY app python3 manage.py importdemodata --type=project; then
            info "HTB reporting templates successfully downloaded"
        else
            error "An error occurred downloading HTB templates"
        fi
    fi

    if [[ $template_choice == "2" || $template_choice == "3" ]]; then
        info "Downloading Offsec reporting templates"
        if curl -fsSL "https://docs.sysreptor.com/assets/offsec-designs.tar.gz" | docker compose exec --no-TTY app python3 manage.py importdemodata --type=design; then
            info "Offsec reporting templates successfully downloaded"
        else
            error "An error occurred downloading Offsec templates"
        fi
    fi

    if [[ $template_choice != "1" && $template_choice != "2" && $template_choice != "3" ]]; then
        warn "Invalid choice, skipping template installation"
    fi
fi
