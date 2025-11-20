#!/usr/bin/env bash
# Install Zabbix 7.0 LTS and Grafana on Ubuntu 24.04 (Noble Numbat)
# Run as root or with sudo

set -euo pipefail

#------------------------------
# 1. Update system
#------------------------------
apt update && apt upgrade -y

#------------------------------
# 2. Install prerequisites
#------------------------------
apt install -y wget gnupg2 ca-certificates lsb-release software-properties-common

#------------------------------
# 3. Install Zabbix repository
#------------------------------
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu24.04_all.deb
dpkg -i zabbix-release_7.0-1+ubuntu24.04_all.deb
rm zabbix-release_7.0-1+ubuntu24.04_all.deb
apt update

#------------------------------
# 4. Install Zabbix server, frontend, agent and DB (PostgreSQL)
#------------------------------
apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-apache-conf zabbix-agent2 postgresql

#------------------------------
# 5. Configure PostgreSQL for Zabbix
#------------------------------
sudo -u postgres psql <<SQL
CREATE DATABASE zabbix;
CREATE USER zabbix WITH ENCRYPTED PASSWORD 'zabbix_pass';
GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;
SQL

# Initialize DB schema
zcat /usr/share/doc/zabbix-server-pgsql/create.sql.gz | sudo -u postgres psql zabbix

#------------------------------
# 6. Configure Zabbix server
#------------------------------
sed -i "s/^# DBPassword=/DBPassword=zabbix_pass/" /etc/zabbix/zabbix_server.conf
systemctl restart zabbix-server zabbix-agent2
systemctl enable zabbix-server zabbix-agent2

#------------------------------
# 7. Install Grafana (official repo)
#------------------------------
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    | tee /etc/apt/sources.list.d/grafana.list
apt update
apt install -y grafana

#------------------------------
# 8. Start & enable Grafana
#------------------------------
systemctl daemon-reload
systemctl enable --now grafana-server

#------------------------------
# 9. (Optional) Open firewall ports
#------------------------------
if command -v ufw >/dev/null; then
    ufw allow 80/tcp      # HTTP for Zabbix frontend
    ufw allow 443/tcp     # HTTPS (if you enable SSL)
    ufw allow 10051/tcp   # Zabbix server trapper
    ufw allow 3000/tcp    # Grafana
fi

echo "Installation complete."
echo "Zabbix frontend: http://<your_ip_or_domain>/zabbix"
echo "Grafana: http://<your_ip_or_domain>:3000 (default login: admin / admin)"
