#!/bin/bash
set -euo pipefail

# ------------------------------
# 0. Variables
# ------------------------------
PROM_VERSION="2.53.0"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
TMP_DIR="/tmp/prometheus-setup"
IP=$(hostname -I | awk '{print $1}')

# ------------------------------
# 1. System update
# ------------------------------
sudo apt update -y

# ------------------------------
# 2. Create prometheus user & dirs
# ------------------------------
sudo useradd --no-create-home --shell /usr/sbin/nologin prometheus || true
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# ------------------------------
# 3. Download & install Prometheus
# ------------------------------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

if [ ! -f "prometheus-${PROM_VERSION}.linux-amd64.tar.gz" ]; then
    wget "$PROM_URL"
fi

tar -xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
cd "prometheus-${PROM_VERSION}.linux-amd64"

sudo mv consoles console_libraries prometheus.yml /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus
sudo mv prometheus /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus

# ------------------------------
# 4. prometheus.yml (if missing)
# ------------------------------
if [ -f /etc/prometheus/prometheus.yml ]; then
    echo "Prometheus configuration file already exists. Verify its contents."
else
    cat <<'EOT' | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOT
    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
fi

# ------------------------------
# 5. Systemd service
# ------------------------------
cat <<'EOT' | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
sudo ufw allow 9090/tcp

# ------------------------------
# 6. Install Grafana
# ------------------------------
curl -fsSL https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server
sudo ufw allow 3000/tcp
sudo ufw reload

# ------------------------------
# 7. Completion message
# ------------------------------
echo "Prometheus is running at: http://$IP:9090"
echo "Grafana is running at: http://$IP:3000 (Username: admin, Password: admin)"
