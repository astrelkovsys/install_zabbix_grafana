#!/usr/bin/env bash
set -euo pipefail

# ---------------------------  Конфигурация  ---------------------------
ZABBIX_VER="7.4"
DB_NAME="zabbix"
DB_USER="zabbix"
DB_PASS="StrongPasswordHere"          # <-- замените на надёжный пароль
TZ="Europe/Moscow"                    # <-- ваш часовой пояс
DOMAIN="yourdomain.com"               # <-- домен, если планируете HTTPS
# --------------------------------------------------------------------

echo "=== Добавляем репозиторий Zabbix $ZABBIX_VER ==="
wget -qO /tmp/zabbix-release.deb \
    "https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb"
sudo dpkg -i /tmp/zabbix-release.deb
rm /tmp/zabbix-release.deb
sudo apt update

echo "=== Устанавливаем пакеты сервера, фронтенда и агента ==="
sudo apt install -y zabbix-server-mysql zabbix-frontend-php \
    zabbix-apache-conf zabbix-agent2 mysql-client

# ---------------------------  База данных  ---------------------------
echo "=== Создаём базу данных MySQL для Zabbix ==="
sudo mysql -u root <<SQL
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "=== Импортируем начальную схему ==="
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | \
    mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME}

# ---------------------------  Конфигурация сервера ---------------------------
echo "=== Настраиваем zabbix_server.conf ==="
sudo sed -i "s/^# DBHost=.*/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBName=.*/DBName=${DB_NAME}/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBUser=.*/DBUser=${DB_USER}/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf

# ---------------------------  PHP / Apache ---------------------------
echo "=== Настраиваем PHP для Zabbix ==="
sudo sed -i "s|^# php_value date.timezone.*|php_value date.timezone ${TZ}|" /etc/zabbix/apache.conf
sudo sed -i "s|^# php_value max_execution_time.*|php_value max_execution_time 300|" /etc/zabbix/apache.conf
sudo sed -i "s|^# php_value memory_limit.*|php_value memory_limit 256M|" /etc/zabbix/apache.conf
sudo sed -i "s|^# php_value post_max_size.*|php_value post_max_size 16M|" /etc/zabbix/apache.conf
sudo sed -i "s|^# php_value upload_max_filesize.*|php_value upload_max_filesize 2M|" /etc/zabbix/apache.conf

# ---------------------------  Запуск служб ---------------------------
echo "=== Перезапускаем и включаем службы ==="
sudo systemctl restart zabbix-server zabbix-agent2 apache2
sudo systemctl enable zabbix-server zabbix-agent2 apache2

# ---------------------------  HTTPS (опционально) ---------------------------
if command -v certbot >/dev/null 2>&1 && [[ -n "${DOMAIN}" ]]; then
    echo "=== Получаем сертификат Let's Encrypt для ${DOMAIN} ==="
    sudo apt install -y certbot python3-certbot-apache
    sudo certbot --apache -d "${DOMAIN}" --non-interactive --agree-tos -m admin@${DOMAIN}
fi

echo "=== Установка завершена ==="
echo "Откройте в браузере http://${DOMAIN:-$(hostname -I | awk '{print $1}')}/zabbix"
echo "Войдите как пользователь 'Admin' с паролем, выведенным в конце веб‑мастера."
