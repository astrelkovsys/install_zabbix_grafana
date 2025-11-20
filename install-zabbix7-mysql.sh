#!/usr/bin/env bash
set -euo pipefail

# === Configuration (edit as needed) ===
ZABBIX_VERSION="7.0"
DB_ROOT_PASS="ChangeMeRoot!23"         # change before running
ZABBIX_DB="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PASS="ChangeMeZbx!23"        # change before running
TIMEZONE="UTC"
HOSTNAME="$(hostname -f || hostname)"
# =====================================

log() { echo "==> $*"; }

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

# Detect distro family
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO_ID=${ID,,}
  DISTRO_LIKE=${ID_LIKE:-}
else
  echo "Unsupported OS"
  exit 1
fi

install_prereqs_debian() {
  log "Updating APT and installing prerequisites"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg2 wget lsb-release ca-certificates curl unzip software-properties-common apt-transport-https
}

install_prereqs_rhel() {
  log "Installing prerequisites (yum/dnf)"
  if command -v dnf >/dev/null 2>&1; then
    PKG_MGR=dnf
  else
    PKG_MGR=yum
  fi
  $PKG_MGR install -y wget curl unzip gnupg2 ca-certificates
}

install_mariadb_debian() {
  log "Installing MariaDB server (Debian/Ubuntu)"
  apt-get install -y mariadb-server mariadb-client
  systemctl enable --now mariadb
}

install_mariadb_rhel() {
  log "Installing MariaDB server (RHEL/CentOS/Alma/Rocky)"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y mariadb-server mariadb
    systemctl enable --now mariadb
  else
    yum install -y mariadb-server mariadb
    systemctl enable --now mariadb
  fi
}

secure_mariadb() {
  log "Securing MariaDB and setting root password (non-interactive)"
  mysql --version >/dev/null 2>&1

  # Check if root auth_socket is in use (Debian default). We'll set a password and update auth plugin.
  mysql -uroot <<SQL
ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
}

create_zabbix_database() {
  log "Creating Zabbix database and user"
  mysql -uroot -p"${DB_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${ZABBIX_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${ZABBIX_DB}\`.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
}

add_zabbix_repo_debian() {
  log "Adding Zabbix repository for Debian/Ubuntu"
  wget -qO- https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-1+$(lsb_release -cs)_all.deb > /tmp/zabbix-release.deb || {
    # fallback generic repo install
    curl -sS https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/zabbix-release_${ZABBIX_VERSION}-1+$(lsb_release -cs)_all.deb -o /tmp/zabbix-release.deb
  }
  dpkg -i /tmp/zabbix-release.deb
  apt-get update
}

add_zabbix_repo_rhel() {
  log "Adding Zabbix repository for RHEL/CentOS/Alma/Rocky"
  # Use official Zabbix repo RPM
  rpm_url="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/rhel/\$(rpm -E %{rhel})/x86_64/zabbix-release-${ZABBIX_VERSION}-1.el\$(rpm -E %{rhel}).noarch.rpm"
  # Simpler approach: download by constructing for major release
  MAJOR=$(rpm -E %{rhel})
  rpm -Uvh "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/rhel/${MAJOR}/x86_64/zabbix-release-${ZABBIX_VERSION}-1.el${MAJOR}.noarch.rpm"
  if command -v dnf >/dev/null 2>&1; then
    dnf makecache
  else
    yum makecache
  fi
}

install_zabbix_packages_debian() {
  log "Installing Zabbix server, frontend, and agent (Debian/Ubuntu)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent php php-mbstring php-xml php-bcmath php-gd php-mysql
}

install_zabbix_packages_rhel() {
  log "Installing Zabbix server, frontend, and agent (RHEL family)"
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-agent
    # install PHP and extensions if not present
    dnf install -y php php-mbstring php-xml php-bcmath php-gd php-mysqlnd
  else
    yum install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-agent php php-mbstring php-xml php-bcmath php-gd php-mysql
  fi
}

import_zabbix_schema_debian() {
  log "Importing Zabbix initial schema into MySQL (Debian path)"
  ZBX_SCHEMA_SQL="/usr/share/doc/zabbix-sql-scripts/mysql/server.sql.gz"
  if [ ! -f "$ZBX_SCHEMA_SQL" ]; then
    # newer package path:
    ZBX_SCHEMA_SQL="/usr/share/zabbix-sql-scripts/mysql/server.sql.gz"
  fi
  if [ -f "$ZBX_SCHEMA_SQL" ]; then
    gunzip -c "$ZBX_SCHEMA_SQL" | mysql -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
  else
    log "Zabbix schema file not found at expected locations."
    exit 1
  fi
}

import_zabbix_schema_rhel() {
  log "Importing Zabbix initial schema into MySQL (RHEL path)"
  ZBX_SCHEMA_SQL="/usr/share/doc/zabbix-server-mysql*/create.sql.gz"
  # attempt known location
  if compgen -G "/usr/share/doc/zabbix*/create.sql.gz" >/dev/null 2>&1; then
    gunzip -c /usr/share/doc/zabbix*/create.sql.gz | mysql -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
  elif [ -f /usr/share/zabbix-server-mysql/schema.sql.gz ]; then
    gunzip -c /usr/share/zabbix-server-mysql/schema.sql.gz | mysql -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
  else
    # try package-provided example location
    if [ -f /usr/share/doc/zabbix/create.sql.gz ]; then
      gunzip -c /usr/share/doc/zabbix/create.sql.gz | mysql -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
    else
      log "Zabbix schema not found; aborting."
      exit 1
    fi
  fi
}

configure_zabbix_server() {
  log "Configuring Zabbix server DB connection in /etc/zabbix/zabbix_server.conf"
  sed -i "s/^# DBPassword=.*/DBPassword=${ZABBIX_DB_PASS}/" /etc/zabbix/zabbix_server.conf || true
  # ensure DBUser/DBName set
  sed -i "s/^# DBUser=.*/DBUser=${ZABBIX_DB_USER}/" /etc/zabbix/zabbix_server.conf || true
  sed -i "s/^# DBName=.*/DBName=${ZABBIX_DB}/" /etc/zabbix/zabbix_server.conf || true
}

configure_php_timezone_debian() {
  # PHP config for Zabbix frontend
  PHP_INI="/etc/php/$(php -r 'echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;')/apache2/php.ini" 2>/dev/null || true
  if [ -f "$PHP_INI" ]; then
    sed -i "s~;date.timezone =.*~date.timezone = ${TIMEZONE}~" "$PHP_INI" || true
  else
    # try common path
    if [ -f /etc/php/8.2/apache2/php.ini ]; then
      sed -i "s~;date.timezone =.*~date.timezone = ${TIMEZONE}~" /etc/php/8.2/apache2/php.ini || true
    fi
  fi
}

start_enable_services() {
  log "Enabling and starting Zabbix server, agent, and apache/httpd"
  systemctl enable --now zabbix-server zabbix-agent
  if systemctl list-unit-files | grep -q apache2.service; then
    systemctl enable --now apache2
  elif systemctl list-unit-files | grep -q httpd.service; then
    systemctl enable --now httpd
  fi
}

# Main flow by distro family
case "$DISTRO_ID" in
  ubuntu|debian)
    install_prereqs_debian
    install_mariadb_debian
    secure_mariadb
    create_zabbix_database
    add_zabbix_repo_debian
    install_zabbix_packages_debian
    import_zabbix_schema_debian
    configure_zabbix_server
    configure_php_timezone_debian
    start_enable_services
    ;;
  centos|rhel|rocky|almalinux|alma)
    install_prereqs_rhel
    install_mariadb_rhel
    secure_mariadb
    create_zabbix_database
    add_zabbix_repo_rhel
    install_zabbix_packages_rhel
    import_zabbix_schema_rhel
    configure_zabbix_server
    start_enable_services
    ;;
  *)
    # try ID_LIKE 'debian' or 'rhel' detection
    if echo "$DISTRO_LIKE" | grep -qi debian; then
      install_prereqs_debian
      install_mariadb_debian
      secure_mariadb
      create_zabbix_database
      add_zabbix_repo_debian
      install_zabbix_packages_debian
      import_zabbix_schema_debian
      configure_zabbix_server
      configure_php_timezone_debian
      start_enable_services
    elif echo "$DISTRO_LIKE" | grep -qi rhel; then
      install_prereqs_rhel
      install_mariadb_rhel
      secure_mariadb
      create_zabbix_database
      add_zabbix_repo_rhel
      install_zabbix_packages_rhel
      import_zabbix_schema_rhel
      configure_zabbix_server
      start_enable_services
    else
      echo "Unsupported distribution: $DISTRO_ID"
      exit 1
    fi
    ;;
esac

log "Zabbix 7 installation finished."
echo "Access the web frontend at http://$HOSTNAME/zabbix (default login: Admin / Zabbix)"
echo "Database: ${ZABBIX_DB}, DB user: ${ZABBIX_DB_USER}"

