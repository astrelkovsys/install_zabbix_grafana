#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# 1. Обновление системы и базовые утилиты
# -------------------------------------------------
sudo apt update
sudo apt install -y wget gnupg2 software-properties-common apt-transport-https

# -------------------------------------------------
# 2. Установка Zabbix (сервер, веб‑интерфейс, агент)
# -------------------------------------------------
ZABBIX_VER="6.4"
DEB_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb"
TMP_DEB="/tmp/zabbix-release_${ZABBIX_VER}.deb"

# Скачиваем .deb‑файл в /tmp и устанавливаем его
wget -qO "$TMP_DEB" "$DEB_URL"
sudo dpkg -i "$TMP_DEB"

# Обновляем индексы пакетов
sudo apt update

# Устанавливаем сервер, веб‑интерфейс (Apache) и агент
sudo apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-apache-conf zabbix-agent

# -------------------------------------------------
# 3. Настройка PostgreSQL для Zabbix
# -------------------------------------------------
sudo apt install -y postgresql

# Создаём базу и пользователя Zabbix
sudo -u postgres psql <<SQL
CREATE DATABASE zabbix;
CREATE USER zabbix WITH ENCRYPTED PASSWORD 'zabbix_pass';
GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;
SQL

# Инициализируем схему
zcat /usr/share/doc/zabbix-server-pgsql/create.sql.gz | \
    sudo -u zabbix psql -d zabbix

# Конфиг сервера
sudo sed -i "s/^# DBPassword=/DBPassword=zabbix_pass/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBName=\/var\/lib\/zabbix\/zabbix_server\.db/DBName=zabbix/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBUser=zabbix/DBUser=zabbix/" /etc/zabbix/zabbix_server.conf

# -------------------------------------------------
# 4. Запуск и включение сервисов Zabbix
# -------------------------------------------------
sudo systemctl restart postgresql
sudo systemctl enable --now zabbix-server zabbix-agent apache2

# -------------------------------------------------
# 5. Установка Grafana
# -------------------------------------------------
wget -qO- https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server

# -------------------------------------------------
# 6. Открытие портов в firewall (если используется ufw)
# -------------------------------------------------
if command -v ufw >/dev/null; then
    sudo ufw allow 10050/tcp   # Zabbix агент
    sudo ufw allow 10051/tcp   # Zabbix сервер
    sudo ufw allow 3000/tcp    # Grafana
    sudo ufw allow 80/tcp      # HTTP (Zabbix UI)
    sudo ufw allow 443/tcp     # HTTPS (по желанию)
fi

# -------------------------------------------------
# 7. Информационное сообщение
# -------------------------------------------------
cat <<EOF
=== Установка завершена ===

Zabbix веб‑интерфейс: http://<your_ip>/zabbix
  - логин: Admin
  - пароль: zabbix

Grafana: http://<your_ip>:3000
  - логин: admin
  - пароль: admin

Не забудьте сменить пароли при первом входе.
EOF
