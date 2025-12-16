#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# 1. Обновление системы и базовые утилиты
# -------------------------------------------------
sudo apt update
sudo apt install -y wget gnupg2 software-properties-common apt-transport-https

# -------------------------------------------------
# 2. Установка MySQL (MariaDB) – будет использоваться Grafana
# -------------------------------------------------
sudo apt install -y mariadb-server

# Защищённая инициализация (корневой пароль пустой, но доступ только локально)
sudo mysql <<SQL
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

# Создаём базу и пользователя для Grafana
DB_NAME="grafana"
DB_USER="grafana"
DB_PASS="grafana_pass"

sudo mysql <<SQL
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# -------------------------------------------------
# 3. Установка Prometheus
# -------------------------------------------------
PROM_VER="2.53.0"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-amd64.tar.gz"
TMP_DIR="/tmp/prometheus_install"

mkdir -p "$TMP_DIR"
wget -qO- "$PROM_URL" | tar -xz -C "$TMP_DIR" --strip-components=1

sudo mv "$TMP_DIR" /opt/prometheus
sudo useradd --no-create-home --shell /usr/sbin/nologin prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp /opt/prometheus/prometheus.yml /etc/prometheus/
sudo cp -r /opt/prometheus/consoles /opt/prometheus/console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus /opt/prometheus

# Systemd‑служба Prometheus
cat <<'EOF' | sudo tee /etc/systemd/system/prometheus.service > /dev/null
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/prometheus/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus

# -------------------------------------------------
# 4. Установка Grafana (с MySQL‑бэкендом)
# -------------------------------------------------
# Добавляем репозиторий Grafana
wget -qO- https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt update
sudo apt install -y grafana

# Включаем MySQL‑датасорс в Grafana (конфиг в /etc/grafana/grafana.ini)
sudo sed -i "s/;type = mysql/type = mysql/" /etc/grafana/grafana.ini
sudo sed -i "s/;host = .*/host = 127.0.0.1:3306/" /etc/grafana/grafana.ini
sudo sed -i "s/;name = .*/name = ${DB_NAME}/" /etc/grafana/grafana.ini
sudo sed -i "s/;user = .*/user = ${DB_USER}/" /etc/grafana/grafana.ini
sudo sed -i "s/;password = .*/password = ${DB_PASS}/" /etc/grafana/grafana.ini

sudo systemctl enable --now grafana-server

# -------------------------------------------------
# 5. Открытие портов (ufw, если установлен)
# -------------------------------------------------
if command -v ufw >/dev/null; then
    sudo ufw allow 9090/tcp   # Prometheus
    sudo ufw allow 3000/tcp   # Grafana
    sudo ufw allow 3306/tcp   # MySQL (локальный доступ уже открыт)
fi

# -------------------------------------------------
# 6. Информационное сообщение
# -------------------------------------------------
cat <<EOF
=== Установка завершена ===

Prometheus: http://<your_ip>:9090
Grafana:   http://<your_ip>:3000   (admin / admin)

Grafana использует MySQL‑базу:
  DB   = ${DB_NAME}
  User = ${DB_USER}
  Pass = ${DB_PASS}

Не забудьте сменить пароль admin в Grafana после первого входа.
EOF
