#!/usr/bin/env bash
# install_zabbix_grafana.sh
# Ubuntu 24.04 – Zabbix 7.4 (MySQL backend, Apache frontend) + Grafana OSS 12.21
# -------------------------------------------------
set -euo pipefail

# -------------------------
# 1️⃣  Variables (edit if needed)
# -------------------------
ZABBIX_VER="7.4"
ZABBIX_REPO="https://repo.zabbix.com/zabbix/${ZABBIX_VER}/ubuntu"
ZABBIX_PKGS="zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent"

MYSQL_ROOT_PWD="StrongRootPass123!"
ZABBIX_DB="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PWD="StrongZabbixPass123!"

GRAFANA_VER="12.21.0"
GRAFANA_REPO="https://apt.grafana.com"
GRAFANA_PKG="grafana"

# -------------------------
# 2️⃣  Helper functions
# -------------------------
log() { echo -e "\e[32m[+] $*\e[0m"; }
die() { echo -e "\e[31m[!] $*\e[0m" >&2; exit 1; }

# -------------------------
# 3️⃣  System update & prerequisites
# -------------------------
log "Updating APT index"
apt-get update -y

log "Installing basic tools"
apt-get install -y wget gnupg2 lsb-release ca-certificates apt-transport-https \
               software-properties-common curl

# -------------------------
# 4️⃣  Install MariaDB (MySQL compatible)
# -------------------------
log "Installing MariaDB server"
apt-get install -y mariadb-server

log "Securing MariaDB"
mysql -e "UPDATE mysql.user SET Password=PASSWORD('${MYSQL_ROOT_PWD}') WHERE User='root';"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "FLUSH PRIVILEGES;"

log "Creating Zabbix database & user"
mysql -uroot -p"${MYSQL_ROOT_PWD}" <<SQL
CREATE DATABASE ${ZABBIX_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PWD}';
GRANT ALL PRIVILEGES ON ${ZABBIX_DB}.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# -------------------------
# 5️⃣  Add Zabbix repo & install packages
# -------------------------
log "Downloading Zabbix repository package"
DEB="/tmp/zabbix-release_${ZABBIX_VER}-1+$(lsb_release -sc)_all.deb"
wget -O "$DEB" "${ZABBIX_REPO}/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VER}-1+$(lsb_release -sc)_all.deb"
dpkg -i "$DEB"
apt-get update -y

log "Installing Zabbix server, frontend and agent"
DEBIAN_FRONTEND=noninteractive apt-get install -y ${ZABBIX_PKGS}

# -------------------------
# 6️⃣  Configure Zabbix to use MySQL
# -------------------------
log "Configuring /etc/zabbix/zabbix_server.conf"
sed -i "s/^# DBPassword=/DBPassword=${ZABBIX_DB_PWD}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^# DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sed -i "s/^# DBName=zabbix/DBName=${ZABBIX_DB}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^# DBUser=zabbix/DBUser=${ZABBIX_DB_USER}/" /etc/zabbix/zabbix_server.conf

log "Importing initial schema"
zcat /usr/share/doc/zabbix-server-mysql/create.sql.gz | \
    mysql -u${ZABBIX_DB_USER} -p${ZABBIX_DB_PWD} ${ZABBIX_DB}

# -------------------------
# 7️⃣  Enable & start Zabbix & Apache
# -------------------------
log "Enabling services"
systemctl enable zabbix-server zabbix-agent apache2
log "Starting services"
systemctl restart zabbix-server zabbix-agent apache2

# -------------------------
# 8️⃣  Install Grafana OSS 12.21
# -------------------------
log "Adding Grafana GPG key"
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg

log "Adding Grafana APT source"
echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] ${GRAFANA_REPO} stable main" \
    > /etc/apt/sources.list.d/grafana.list

log "Updating APT index for Grafana"
apt-get update -y

log "Installing Grafana ${GRAFANA_VER}"
apt-get install -y ${GRAFANA_PKG}=${GRAFANA_VER}*

log "Enabling and starting Grafana"
systemctl enable grafana-server
systemctl start grafana-server

# -------------------------
# 9️⃣  Finish
# -------------------------
log "Installation finished"
echo "🔹 Zabbix UI   : http://<your_ip>/zabbix"
echo "🔹 Grafana UI : http://<your_ip>:3000 (default admin / admin)"
