#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/inventory/servers.ini"
VARS_FILE="${SCRIPT_DIR}/group_vars/all.yml"
SSH_KEY="/root/.ssh/id_ed25519"

add_one_server() {
    echo "=== Добавление нового сервера в управление Ansible ==="
    read -rp "Алиас сервера (короткое имя, например usa2): " SRV_NAME
    read -rp "IP адрес сервера: " SRV_IP
    read -rsp "Root пароль сервера: " SRV_PASS
    echo
    read -rp "Домен для Let's Encrypt (Enter чтобы пропустить): " SRV_DOMAIN
    read -rp "Перезагрузить сервер после настройки? (y/n): " DO_REBOOT

    if grep -q "^${SRV_NAME} " "$INVENTORY" 2>/dev/null; then
        echo "Алиас ${SRV_NAME} уже есть в инвентаре, пропускаю."
        return
    fi
    if grep -q "ansible_host=${SRV_IP} " "$INVENTORY" 2>/dev/null; then
        echo "IP ${SRV_IP} уже есть в инвентаре, пропускаю."
        return
    fi

    echo "[1/7] Копирую SSH ключ на новый сервер..."
    sshpass -p "$SRV_PASS" ssh-copy-id -o StrictHostKeyChecking=no -i "${SSH_KEY}.pub" -p 22 root@"$SRV_IP"

    echo "[2/7] Добавляю сервер в инвентарь..."
    if ! grep -q "\[vps_servers\]" "$INVENTORY" 2>/dev/null; then
        echo "[vps_servers]" > "$INVENTORY"
    fi
    sed -i "/\[vps_servers\]/a ${SRV_NAME} ansible_host=${SRV_IP} ansible_port=22 ansible_user=root" "$INVENTORY"

    echo "[3/7] Добавляю IP в общий whitelist static_whitelist_ips..."
    python3 - "$VARS_FILE" "$SRV_IP" <<'PYEOF'
import sys, re
path, ip = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
if ip not in content:
    if re.search(r'static_whitelist_ips:\s*\[\]', content):
        content = re.sub(r'static_whitelist_ips:\s*\[\]', f'static_whitelist_ips:\n  - {ip}', content)
    else:
        content = re.sub(
            r'(static_whitelist_ips:\n(?:  - .*\n)*)',
            lambda m: m.group(1) + f'  - {ip}\n',
            content
        )
    with open(path, 'w') as f:
        f.write(content)
PYEOF

    echo "[4/7] Настраиваю новый сервер (firewall, crowdsec, ssh hardening)..."
    ansible-playbook "${SCRIPT_DIR}/playbooks/add-server.yml" \
        -i "$INVENTORY" \
        -e "target_host=${SRV_NAME}" \
        -e "target_domain=${SRV_DOMAIN}"

    echo "[5/7] Обновляю порт SSH в инвентаре на 22022..."
    sed -i "s/^${SRV_NAME} ansible_host=${SRV_IP} ansible_port=22 /${SRV_NAME} ansible_host=${SRV_IP} ansible_port=22022 /" "$INVENTORY"

    echo "[6/7] Синхронизирую белые списки IP на всех серверах..."
    ansible-playbook "${SCRIPT_DIR}/playbooks/sync-whitelist.yml" -i "$INVENTORY"

    echo "[7/7] Проверка доступности нового сервера на порту 22022..."
    ansible "$SRV_NAME" -i "$INVENTORY" -m ping

    if [[ "$DO_REBOOT" =~ ^[Yy]$ ]]; then
        echo "Перезагружаю сервер..."
        ansible "$SRV_NAME" -i "$INVENTORY" -m reboot -a "reboot_timeout=180"
    fi

    echo "=== Готово. Сервер ${SRV_NAME} (${SRV_IP}) добавлен в управление. ==="
}

while true; do
    add_one_server
    read -rp "Добавить ещё один сервер? (y/n): " MORE
    [[ "$MORE" =~ ^[Yy]$ ]] || break
done

echo "=== Список управляемых серверов: ==="
cat "$INVENTORY"
