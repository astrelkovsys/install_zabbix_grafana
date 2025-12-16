#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------
# 1. Обновление системы и базовые утилиты
# -------------------------------------------------
sudo apt update
sudo apt install -y wget gnupg2 software-properties-common apt-transport-https

# -------------------------------------------------
# 2. Добавление репозитория Zabbix
# -------------------------------------------------
ZABBIX_VER="6.4"
DEB_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb"
TMP_DEB="/tmp/zabbix-release_${ZABBIX_VER}.deb"

wget -qO "$TMP_DEB" "$DEB_URL"
sudo dpkg -i "$TMP_DEB"
sudo apt update

# -------------------------------------------------
# 3. Установка пакетов Zabbix и PostgreSQL
# -------------------------------------------------
sudo apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-apache-conf \
                    zabbix-agent postgresql

# -------------------------------------------------
# 4. Создание базы и роли (если их ещё нет)
# -------------------------------------------------
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='zabbix';")
ROLE_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='zabbix';")

if [[ "$DB_EXISTS" != "1" ]]; then
    sudo -u postgres psql <<SQL
CREATE DATABASE zabbix;
SQL
fi

if [[ "$ROLE_EXISTS" != "1" ]]; then
    sudo -u postgres psql <<SQL
CREATE USER zabbix WITH ENCRYPTED PASSWORD 'zabbix_pass';
SQL
fi

# Даем права роли на базу (выполняем независимо от того, была она создана или нет)
sudo -u postgres psql -d zabbix -c "GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;"

# -------------------------------------------------
# 5. Инициализация схемы Zabbix
# -------------------------------------------------
# Пытаемся найти уже установленный файл
SQL_GZ=$(dpkg -L zabbix-server-pgsql | grep '/create\.sql\.gz$' || true)

if [[ -z "$SQL_GZ" ]]; then
    echo "Файл create.sql.gz не найден в пакете – скачиваем его вручную."
    # URL официального скрипта с схемой (из репозитория Zabbix)
    SCHEMA_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/source/zabbix-${ZABBIX_VER}.tar.gz"
    TMP_TAR="/tmp/zabbix-${ZABBIX_VER}.tar.gz"
    wget -qO "$TMP_TAR" "$SCHEMA_URL"
    mkdir -p /tmp/zabbix_src
    tar -xzf "$TMP_TAR" -C /tmp/zabbix_src --strip-components=1 \
        "database/postgresql/create.sql"
    SQL_FILE="/tmp/zabbix_src/create.sql"
else
    SQL_FILE="/tmp/create.sql"
    zcat "$SQL_GZ" > "$SQL_FILE"
fi

# Загружаем схему в базу
sudo -u zabbix psql -d zabbix -f "$SQL_FILE"

# -------------------------------------------------
# 6. Конфигурация сервера Zabbix
# -------------------------------------------------
sudo sed -i "s/^# DBPassword=/DBPassword=zabbix_pass/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBName=\/var\/lib\/zabbix\/zabbix_server\.db/DBName=zabbix/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBUser=zabbix/DBUser=zabbix/" /etc/zabbix/zabbix_server.conf

# -------------------------------------------------
# 7. Запуск и включение сервисов Zabbix
# -------------------------------------------------
sudo systemctl restart postgresql
sudo systemctl enable --now zabbix-server zabbix-agent apache2

# -------------------------------------------------
# 8. Установка Grafana
# -------------------------------------------------
wget -qO- https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server

# -------------------------------------------------
# 9. Открытие портов (ufw, если установлен)
# -------------------------------------------------
if command -v ufw >/dev/null; then
    sudo ufw allow 10050/tcp   # Zabbix агент
    sudo ufw allow 10051/tcp   # Zabbix сервер
    sudo ufw allow 3000/tcp    # Grafana
    sudo ufw allow 80/tcp      # HTTP (Zabbix UI)
    sudo ufw allow 443/tcp     # HTTPS (по желанию)
fi

# -------------------------------------------------
# 10. Информационное сообщение
# -------------------------------------------------
cat <<EOF
=== Установка завершена ===

Zabbix UI: http://<your_ip>/zabbix   (логин: Admin, пароль: zabbix)
Grafana:   http://<your_ip>:3000    (логин: admin, пароль: admin)

Поменяйте пароли при первом входе.
EOF
