#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# 1. Обновление системы и установка базовых пакетов
# -------------------------------------------------
sudo apt update
sudo apt install -y wget gnupg2 software-properties-common apt-transport-https

# -------------------------------------------------
# 2. Установка Zabbix (сервер, веб‑интерфейс, агент)
# -------------------------------------------------
ZABBIX_VER="6.4"
REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu"

# Добавляем репозиторий Zabbix
wget -qO- "${REPO_URL}/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb" \
    | sudo dpkg -i -

sudo apt update

# Устанавливаем сервер, веб‑интерфейс (Apache) и агент
sudo apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-apache-conf zabbix-agent

# -------------------------------------------------
# 3. Настройка PostgreSQL для Zabbix
# -------------------------------------------------
# Устанавливаем PostgreSQL, если ещё не установлен
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

# Настраиваем файл /etc/zabbix/zabbix_server.conf
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
# Добавляем репозиторий Grafana
wget -qO- https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update
sudo apt install -y grafana

# Включаем и стартуем Grafana
sudo systemctl enable --now grafana-server

# -------------------------------------------------
# 6. Открытие портов в firewall (если используется ufw)
# -------------------------------------------------
if command -v ufw >/dev/null; then
    sudo ufw allow 10050/tcp   # Zabbix агент
    sudo ufw allow 10051/tcp   # Zabbix сервер
    sudo ufw allow 3000/tcp    # Grafana
    sudo ufw allow 80/tcp      # HTTP (Zabbix веб‑интерфейс)
    sudo ufw allow 443/tcp     # HTTPS (при необходимости)
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

При первом входе в Grafana рекомендуется сменить пароль.
EOF
