#!/usr/bin/env bash
# prometheus_grafana_ubuntu24.04.sh
# Ubuntu 24.04, Prometheus 3.8.1, Grafana provisioning for admin password
set -euo pipefail

PROM_USER="prometheus"
PROM_GROUP="prometheus"
PROM_VER="3.8.1"
PROM_ARCHIVE="prometheus-${PROM_VER}.linux-amd64.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/${PROM_ARCHIVE}"
PROM_INSTALL_BIN="/usr/local/bin/prometheus"
PROM_CONF_DIR="/etc/prometheus"
PROM_DATA_DIR="/var/lib/prometheus"

GRAFANA_KEYRING="/usr/share/keyrings/grafana-archive-keyring.gpg"
GRAFANA_PROV_DIR="/etc/grafana/provisioning"
GRAFANA_USERS_PROV_DIR="${GRAFANA_PROV_DIR}/users"
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASSWORD="ChangeMeNow123!"   # <- замените на безопасный пароль

# Ensure required packages
sudo apt-get update -y
sudo apt-get install -y wget tar gnupg curl ca-certificates jq

# Create prometheus user if needed
if ! id -u "${PROM_USER}" >/dev/null 2>&1; then
  sudo useradd --no-create-home --shell /bin/false "${PROM_USER}"
fi

# Create directories
sudo mkdir -p "${PROM_CONF_DIR}" "${PROM_DATA_DIR}"
sudo chown -R "${PROM_USER}:${PROM_GROUP}" "${PROM_DATA_DIR}"

# Download and install Prometheus
cd /tmp
if ! wget -q --show-progress "${PROM_URL}"; then
  echo "Failed to download Prometheus from ${PROM_URL}" >&2
  exit 1
fi

tar -xzf "${PROM_ARCHIVE}"
EXTRACT_DIR="prometheus-${PROM_VER}.linux-amd64"
if [ ! -d "${EXTRACT_DIR}" ]; then
  echo "Unexpected archive contents: ${EXTRACT_DIR} not found" >&2
  exit 1
fi

sudo mv "${EXTRACT_DIR}/consoles" "${EXTRACT_DIR}/console_libraries" "${PROM_CONF_DIR}/" || true
if [ -f "${EXTRACT_DIR}/prometheus" ]; then
  sudo mv "${EXTRACT_DIR}/prometheus" "${PROM_INSTALL_BIN}"
  sudo chown "${PROM_USER}:${PROM_GROUP}" "${PROM_INSTALL_BIN}"
  sudo chmod 0755 "${PROM_INSTALL_BIN}"
else
  echo "Prometheus binary not found in archive" >&2
  exit 1
fi

# Prometheus config
if [ -f "${PROM_CONF_DIR}/prometheus.yml" ]; then
  echo "Prometheus configuration already exists — leaving intact."
else
  sudo tee "${PROM_CONF_DIR}/prometheus.yml" > /dev/null <<'EOT'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOT
  sudo chown "${PROM_USER}:${PROM_GROUP}" "${PROM_CONF_DIR}/prometheus.yml"
fi
sudo chown -R "${PROM_USER}:${PROM_GROUP}" "${PROM_CONF_DIR}"

# Create systemd service for Prometheus
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOT
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=${PROM_USER}
Group=${PROM_GROUP}
Type=simple
ExecStart=${PROM_INSTALL_BIN} \
  --config.file ${PROM_CONF_DIR}/prometheus.yml \
  --storage.tsdb.path ${PROM_DATA_DIR} \
  --web.console.templates=${PROM_CONF_DIR}/consoles \
  --web.console.libraries=${PROM_CONF_DIR}/console_libraries

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus

# Install Grafana OSS (keyring method) with correct key handling
sudo mkdir -p /usr/share/keyrings
# remove old entries if any
sudo rm -f /etc/apt/sources.list.d/grafana.list "${GRAFANA_KEYRING}" || true

# download key and dearmor
if ! curl -fsSL https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o "${GRAFANA_KEYRING}"; then
  echo "Failed to fetch or dearmor Grafana GPG key" >&2
  exit 1
fi

# add repository with signed-by
echo "deb [signed-by=${GRAFANA_KEYRING}] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# update and install grafana
sudo apt-get update -y
# check for apt update errors related to grafana key
if ! sudo apt-get update -y 2>&1 | tee /tmp/apt-update.log | grep -q "Reading package lists"; then
  echo "apt-get update failed; see /tmp/apt-update.log" >&2
  tail -n 200 /tmp/apt-update.log
  exit 1
fi

sudo apt-get install -y grafana

# Create provisioning to set admin password via grafana-cli oneshot
sudo mkdir -p "${GRAFANA_USERS_PROV_DIR}"

# users.yaml (placeholder; external_user_mgr true avoids changing local users via provisioning)
sudo tee "${GRAFANA_USERS_PROV_DIR}/users.yaml" > /dev/null <<EOT
apiVersion: 1

providers:
  - name: 'default'
    org_id: 1
    external_user_mgr: true
EOT

# oneshot service to reset admin password
sudo tee /etc/systemd/system/grafana-change-admin-password.service > /dev/null <<EOT
[Unit]
Description=Set Grafana admin password once
After=grafana-server.service
Requires=grafana-server.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 5; if command -v grafana-cli >/dev/null 2>&1; then grafana-cli admin reset-admin-password ${GRAFANA_ADMIN_PASSWORD} || true; else echo "grafana-cli not found"; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server
sudo systemctl enable --now grafana-change-admin-password.service || true

# Verify services
if ! systemctl is-active --quiet prometheus; then
  echo "Prometheus failed to start. Check sudo journalctl -u prometheus -b" >&2
  exit 1
fi
if ! systemctl is-active --quiet grafana-server; then
  echo "Grafana failed to start. Check sudo journalctl -u grafana-server -b" >&2
  exit 1
fi

# Firewall (if ufw active)
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q -i active; then
  sudo ufw allow 9090/tcp
  sudo ufw allow 3000/tcp
  sudo ufw reload || true
fi

echo "Installation completed."
echo "Prometheus: http://<server-ip>:9090"
echo "Grafana: http://<server-ip>:3000"
echo "Grafana admin user: ${GRAFANA_ADMIN_USER}"
echo "Grafana admin password: ${GRAFANA_ADMIN_PASSWORD}"
