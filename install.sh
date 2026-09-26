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

    echo ""
    echo "=== Настройка group_vars/all.yml ==="
    read -rp "Домены DDNS для динамического SSH-whitelist через запятую (Enter чтобы пропустить): " DDNS_INPUT
    read -rp "Telegram bot token для алертов CrowdSec (Enter чтобы пропустить): " TG_TOKEN
    read -rp "Telegram chat_id (Enter чтобы пропустить): " TG_CHAT_ID

    if [[ -n "$DDNS_INPUT" ]]; then
        python3 - "group_vars/all.yml" "$DDNS_INPUT" <<'PYEOF'
import sys, re
path, domains_raw = sys.argv[1], sys.argv[2]
domains = [d.strip() for d in domains_raw.split(',') if d.strip()]
with open(path) as f:
    content = f.read()
block = "ddns_domains:\n" + "\n".join(f'  - {d}' for d in domains) + "\n"
content = re.sub(r'ddns_domains:\s*\[\]\n', block, content)
with open(path, 'w') as f:
    f.write(content)
PYEOF
        echo "Домены добавлены в ddns_domains"
    fi

    if [[ -n "$TG_TOKEN" ]]; then
        sed -i "s|crowdsec_telegram_bot_token: \"\"|crowdsec_telegram_bot_token: \"${TG_TOKEN}\"|" group_vars/all.yml
    fi

    if [[ -n "$TG_CHAT_ID" ]]; then
        sed -i "s|crowdsec_telegram_chat_id: \"\"|crowdsec_telegram_chat_id: \"${TG_CHAT_ID}\"|" group_vars/all.yml
    fi

    echo "Создан group_vars/all.yml"
fi

if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    echo "SSH-ключ не найден, генерирую..."
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
fi

chmod +x add-server.sh
echo "=== Мастер настроен в ${INSTALL_DIR} ==="
exec ./add-server.sh