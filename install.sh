#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/whywherehoo/ansible-master.git"
INSTALL_DIR="/root/ansible-master"

echo "=== Bootstrap Ansible-мастера ==="

if ! command -v git >/dev/null 2>&1 || ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "Устанавливаю git, ansible, sshpass, python3..."
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y git ansible sshpass python3
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Репозиторий уже есть, обновляю..."
    cd "$INSTALL_DIR"
    git pull
else
    echo "Клонирую репозиторий..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

if [[ ! -f inventory/servers.ini ]]; then
    cp inventory/servers.ini.example inventory/servers.ini
    echo "Создан inventory/servers.ini"
fi

if [[ ! -f group_vars/all.yml ]]; then
    cp group_vars/all.yml.example group_vars/all.yml
    OWN_IP=$(curl -s ifconfig.me || true)
    if [[ -n "$OWN_IP" ]]; then
        sed -i "s/^static_whitelist_ips: \[\]/static_whitelist_ips:\n  - ${OWN_IP}/" group_vars/all.yml
        echo "Добавил IP этого сервера (${OWN_IP}) в static_whitelist_ips"
    fi
    echo "Создан group_vars/all.yml — при желании допиши ddns_domains и telegram-токены перед продолжением"
fi

if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    echo "SSH-ключ не найден, генерирую..."
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
fi

chmod +x add-server.sh
echo "=== Мастер настроен в ${INSTALL_DIR} ==="
exec ./add-server.sh
