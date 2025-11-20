#!/usr/bin/env bash
set -euo pipefail

# === Config ===
ZABBIX_VER="7.4"
DB_ROOT_PASS="ChangeMeRoot!23"    # change before running
ZABBIX_DB="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PASS="ChangeMeZbx!23"   # change before running
TIMEZONE="UTC"
# ==============

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

log(){ echo "==> $*"; }

# Update and prerequisites
log "Updating apt and installing prerequisites"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg2 lsb-release ca-certificates curl unzip software-properties-common

# Install MariaDB
log "Installing MariaDB server"
DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client
systemctl enable --now mariadb

# Secure MariaDB (non-interactive)
log "Securing MariaDB and setting root password"
mysql -uroot <<SQL
ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';
FLUSH PRIVILEGES;
SQL

# Create Zabbix DB and user
log "Creating Zabbix database and user"
mysql -uroot -p"${DB_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${ZABBIX_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${ZABBIX_DB}\`.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# Add Zabbix APT repo for Ubuntu 24.04
log "Adding Zabbix ${ZABBIX_VER} repository"
REPO_DEB="/tmp/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb"
wget -O "$REPO_DEB" "https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+ubuntu24.04_all.deb"
dpkg -i "$REPO_DEB"
apt-get update

# Install Zabbix server, frontend (Apache/PHP), agent
log "Installing Zabbix server, frontend, and agent"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent php8.3 php8.3-mbstring php8.3-xml php8.3-bcmath php8.3-gd php8.3-mysql libapache2-mod-php8.3

# Import initial schema
log "Importing Zabbix DB schema"
if [ -f /usr/share/zabbix-sql-scripts/mysql/server.sql.gz ]; then
  gunzip -c /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
elif [ -f /usr/share/doc/zabbix-sql-scripts/mysql/server.sql.gz ]; then
  gunzip -c /usr/share/doc/zabbix-sql-scripts/mysql/server.sql.gz | mysql -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
else
  log "ERROR: Zabbix schema not found"
  exit 1
fi

# Configure zabbix_server.conf DBPassword (uncomment/set)
log "Configuring Zabbix server DB connection"
ZCONF="/etc/zabbix/zabbix_server.conf"
sed -i "s/^# DBUser=.*/DBUser=${ZABBIX_DB_USER}/" "$ZCONF" || true
sed -i "s/^# DBName=.*/DBName=${ZABBIX_DB}/" "$ZCONF" || true
if grep -q "^DBPassword=" "$ZCONF"; then
  sed -i "s|^DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" "$ZCONF"
else
  echo "DBPassword=${ZABBIX_DB_PASS}" >> "$ZCONF"
fi

# Configure PHP timezone for Apache
log "Setting PHP timezone to ${TIMEZONE}"
PHP_INI="/etc/php/8.3/apache2/php.ini"
if [ -f "$PHP_INI" ]; then
  sed -i "s~;date.timezone =.*~date.timezone = ${TIMEZONE}~" "$PHP_INI" || true
fi

# Enable/start services
log "Enabling and starting services"
systemctl enable --now zabbix-server zabbix-agent apache2

# Firewall (optional: open ports if ufw active)
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then
  log "Allowing ports 80, 443, 10050, 10051 through UFW"
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 10050/tcp
  ufw allow 10051/tcp
fi

log "Finished. Access Zabbix frontend at http://$(hostname -f)/zabbix (login: Admin / zabbix)"
