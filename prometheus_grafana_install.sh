#!/bin/bash

# Variables
PROMETHEUS_VERSION="3.8.1"
GRAFANA_VERSION="latest"
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000

# Install required packages
sudo apt-get update -y
sudo apt-get install -y wget tar gnupg curl ca-certificates jq

# Create prometheus user and group
sudo useradd --no-create-home --shell /bin/false prometheus
sudo groupadd prometheus

# Download and install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar -xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chmod 0755 /usr/local/bin/prometheus

# Create prometheus config
sudo mkdir -p /etc/prometheus
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
sudo chown -R prometheus:prometheus /etc/prometheus

# Create systemd service for Prometheus
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file /etc/prometheus/prometheus.yml \
  --storage.tsdb.path /var/lib/prometheus \
  --web.console.templates /etc/prometheus/consoles \
  --web.console.libraries /etc/prometheus/console_libraries

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Prometheus
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus

# Install Grafana
sudo apt-get install -y apt-transport-https
sudo curl -fsSL https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update -y
sudo apt-get install -y grafana

# Create systemd service for Grafana
sudo tee /etc/systemd/system/grafana.service > /dev/null <<EOF
[Unit]
Description=Grafana
Wants=network-online.target
After=network-online.target

[Service]
User=grafana
Group=grafana
Type=simple
ExecStart=/usr/sbin/grafana-server \
  --config /etc/grafana/grafana.ini

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Grafana
sudo systemctl daemon-reload
sudo systemctl enable --now grafana

# Open ports in firewall
sudo ufw allow ${PROMETHEUS_PORT}/tcp
sudo ufw allow ${GRAFANA_PORT}/tcp
sudo ufw reload

echo "Prometheus installed and running on port ${PROMETHEUS_PORT}"
echo "Grafana installed and running on port ${GRAFANA_PORT}"
