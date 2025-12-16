#!/usr/bin/env bash
set -euo pipefail

# 1. Обновление и базовые утилиты
sudo apt update
sudo apt install -y wget gnupg2 software-properties-common apt-transport-https

# 2. Установка Zabbix (репозиторий)
ZABBIX_VER="6.4"
DEB_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb"
TMP_DEB="/tmp/zabbix-release_${ZABBIX_VER}.deb"
wget -qO "$TMP_DEB" "$DEB_URL"
sudo dpkg -i "$TMP_DEB"
sudo apt update

# 3. Установка серверных пакетов и PostgreSQL
sudo apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-apache-conf zabbix-agent postgresql

# 4. Создание БД и пользователя
sudo -u postgres psql <<SQL
CREATE DATABASE zabbix;
CREATE USER zabbix WITH ENCRYPTED PASSWORD 'zabbix_pass';
GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;
SQL

# 5. Инициализация схемы (поиск файла)
SQL_GZ=$(dpkg -L zabbix-server-pgsql | grep '/create\.sql\.gz$' || true)
if [[ -z "$SQL_GZ" ]]; then
    echo "Ошибка: файл create.sql.gz не найден."
    exit 1
fi
zcat "$SQL_GZ" | sudo -u zabbix psql -d zabbix

# 6. Конфигурация сервера Zabbix
sudo sed -i "s/^# DBPassword=/DBPassword=zabbix_pass/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBName=\/var\/lib\/zabbix\/zabbix_server\.db/DBName=zabbix/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^DBUser=zabbix/DBUser=zabbix/" /etc/zabbix/zabbix_server.conf

# 7. Запуск сервисов Zabbix
sudo systemctl restart postgresql
sudo systemctl enable --now zabbix-server zabbix-agent apache2

# 8. Установка Grafana
wget -qO- https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server

# 9. Открытие портов (ufw, если установлен)
if command -v ufw >/dev/null; then
    sudo ufw allow 10050/tcp
    sudo ufw allow 10051/tcp
    sudo ufw allow 3000/tcp
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
fi

# 10. Информация для пользователя
cat <<EOF
=== Установка завершена ===

Zabbix UI: http://<your_ip>/zabbix   (Admin / zabbix)
Grafana:   http://<your_ip>:3000    (admin / admin)

Поменяйте пароли при первом входе.
EOF
