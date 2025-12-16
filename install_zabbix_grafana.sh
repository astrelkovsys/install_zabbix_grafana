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

# Минимальная защита (корневой доступ только локально)
sudo mysql <<SQL
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

# База и пользователь для Grafana
GRAFANA_DB="grafana"
GRAFANA_USER="grafana"
GRAFANA_PASS="grafana_pass"

sudo mysql <<SQL
CREATE DATABASE ${GRAFANA_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${GRAFANA_USER}'@'localhost' IDENTIFIED BY '${GRAFANA_PASS}';
GRANT ALL PRIVILEGES ON ${GRAFANA_DB}.* TO '${GRAFANA_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# -------------------------------------------------
# 3. Добавление репозитория Zabbix 7
# -------------------------------------------------
ZABBIX_VER="7.0"
DEB_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb"
TMP_DEB="/tmp/zabbix-release_${ZABBIX_VER}.deb"

wget -qO "$TMP_DEB" "$DEB_URL"
sudo dpkg -i "$TMP_DEB"
sudo apt update

# -------------------------------------------------
# 4. Установка Zabbix‑сервер, веб‑интерфейс и агент (PostgreSQL не нужен)
# -------------------------------------------------
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent

# -------------------------------------------------
# 5. Создание MySQL‑базы и пользователя для Zabbix
# -------------------------------------------------
ZABBIX_DB="zabbix"
ZABBIX_USER="zabbix"
ZABBIX_PASS="zabbix_pass"

# Если база/пользователь уже существуют – пропускаем создание
DB_EXISTS=$(sudo mysql -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${ZABBIX_DB}';")
USER_EXISTS=$(sudo mysql -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user='${ZABBIX_USER}');")

if [[ -z "$DB_EXISTS" ]]; then
    sudo mysql <<SQL
CREATE DATABASE ${ZABBIX_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SQL
fi

if [[ "$USER_EXISTS" != "1" ]]; then
    sudo mysql <<SQL
CREATE USER '${ZABBIX_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_PASS}';
SQL
fi

sudo mysql <<SQL
GRANT ALL PRIVILEGES ON ${ZABBIX_DB}.* TO '${ZABBIX_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# -------------------------------------------------
# 6. Инициализация схемы Zabbix
# -------------------------------------------------
# Пакет zabbix-server-mysql уже содержит файл schema.sql.gz
SCHEMA_GZ=$(dpkg -L zabbix-server-mysql | grep '/schema.sql.gz$' || true)

if [[ -z "$SCHEMA_GZ" ]]; then
    echo "Ошибка: schema.sql.gz не найден в пакете zabbix-server-mysql."
    exit 1
fi

zcat "$SCHEMA_GZ" | sudo mysql ${ZABBIX_DB}

# -------------------------------------------------
# 7. Конфигурация Zabbix‑сервера (указываем MySQL)
# -------------------------------------------------
sudo sed -i "s/^# DBPassword=/DBPassword=${ZABBIX_PASS}/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBName=\/var\/lib\/zabbix\/zabbix_server\.db/DBName=${ZABBIX_DB}/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBUser=zabbix/DBUser=${ZABBIX_USER}/" /etc/zabbix/zabbix_server.conf

# -------------------------------------------------
# 8. Запуск и включение сервисов Zabbix
# -------------------------------------------------
sudo systemctl enable --now zabbix-server zabbix-agent apache2

# -------------------------------------------------
# 9. Установка Grafana (с MySQL‑бэкендом)
# -------------------------------------------------
wget -qO- https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt update
sudo apt install -y grafana

# Настраиваем Grafana использовать MySQL‑базу, созданную выше
sudo sed -i "s/;type = mysql/type = mysql/" /etc/grafana/grafana.ini
sudo sed -i "s/;host = .*/host = 127.0.0.1:3306/" /etc/grafana/grafana.ini
sudo sed -i "s/;name = .*/name = ${GRAFANA_DB}/" /etc/grafana/grafana.ini
sudo sed -i "s/;user = .*/user = ${GRAFANA_USER}/" /etc/grafana/grafana.ini
sudo sed -i "s/;password = .*/password = ${GRAFANA_PASS}/" /etc/grafana/grafana.ini

sudo systemctl enable --now grafana-server

# -------------------------------------------------
# 10. Открытие портов (ufw, если установлен)
# -------------------------------------------------
if command -v ufw >/dev/null; then
    sudo ufw allow 10050/tcp   # Zabbix агент
    sudo ufw allow 10051/tcp   # Zabbix сервер
    sudo ufw allow 3000/tcp    # Grafana
    sudo ufw allow 80/tcp      # HTTP (Zabbix UI)
    sudo ufw allow 443/tcp     # HTTPS (по желанию)
    sudo ufw allow 3306/tcp    # MySQL (локальный доступ уже открыт)
fi

# -------------------------------------------------
# 11. Информационное сообщение
# -------------------------------------------------
cat <<EOF
=== Установка завершена ===

Zabbix UI: http://<your_ip>/zabbix   (логин: Admin, пароль: zabbix)
Grafana:   http://<your_ip>:3000    (admin / admin)

MySQL‑база для Zabbix:
  DB   = ${ZABBIX_DB}
  User = ${ZABBIX_USER}
  Pass = ${ZABBIX_PASS}

MySQL‑база для Grafana:
  DB   = ${GRAFANA_DB}
  User = ${GRAFANA_USER}
  Pass = ${GRAFANA_PASS}

Поменяйте пароли admin в Grafana и пароль Admin в Zabbix после первого входа.
EOF
