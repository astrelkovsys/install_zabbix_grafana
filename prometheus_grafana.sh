#!/bin/bash

#chmod +x prometheus_grafana.sh
#./prometheus_grafana.sh

# Update system
sudo apt update -y

# Step #1: Creating Prometheus System Users and Directory
sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

# Step #2: Download Prometheus Binary File
cd /tmp/
wget https://github.com/prometheus/prometheus/releases/download/v3.4.1/prometheus-3.4.1.linux-amd64.tar.gz
tar -xvf prometheus-3.4.1.linux-amd64.tar.gz
cd prometheus-3.4.1.linux-amd64
sudo mv consoles console_libraries prometheus.yml /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus
sudo mv prometheus /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus

# Step #3: Creating Prometheus Configuration File
if [ ! -f /etc/prometheus/prometheus.yml ]; then
  echo "Prometheus configuration file already exists. Verify its contents."
else
  cat <<EOT | sudo tee /etc/prometheus/prometheus.yml
# Default Prometheus configuration file
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOT
fi

# Step #4: Creating Prometheus Systemd Service File
cat <<EOT | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOT

# Reload systemd and start Prometheus
sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus
sudo ufw allow 9090/tcp

# Step #5: Installing Grafana OSS

wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
sudo systemctl status grafana-server


# Allow Grafana in firewall
sudo ufw allow 3000/tcp
sudo ufw reload

# Print completion message with access details
echo "Prometheus is running at: http://<server-ip>:9090"
echo "Grafana is running at: http://<server-ip>:3000 (Username: admin, Password: admin)"
