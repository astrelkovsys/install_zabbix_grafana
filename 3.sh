#!/bin/bash
set -euo pipefail

PROM_VERSION="3.8.1"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
TMP_DIR="/tmp/prometheus-setup"
IP=$(hostname -I | awk '{print $1}')

# ---------- подготовка ----------
sudo apt update -y
sudo useradd --no-create-home --shell /usr/sbin/nologin prometheus || true
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# ---------- загрузка ----------
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

if [ ! -f "prometheus-${PROM_VERSION}.linux-amd64.tar.gz" ]; then
    wget "$PROM_URL"
fi

tar -xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
cd "prometheus-${PROM_VERSION}.linux-amd64"

# ---------- отладочный вывод (можно убрать после проверки) ----------
echo "Содержимое каталога после распаковки:"
ls -1

# ---------- перемещение файлов с проверкой наличия ----------
# consoles
if [ -d consoles ]; then
    sudo mv consoles /etc/prometheus/
    sudo chown -R prometheus:prometheus /etc/prometheus/consoles
else
    echo "Каталог 'consoles' не найден — пропускаем."
fi

# console_libraries
if [ -d console_libraries ]; then
    sudo mv console_libraries /etc/prometheus/
    sudo chown -R prometheus:prometheus /etc/prometheus/console_libraries
else
    echo "Каталог 'console_libraries' не найден — пропускаем."
fi

# prometheus.yml
if [ -f prometheus.yml ]; then
    sudo mv prometheus.yml /etc/prometheus/
    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
else
    echo "Файл prometheus.yml не найден — проверьте архив."
    exit 1
fi

# бинарник
if [ -f prometheus ]; then
    sudo mv prometheus /usr/local/bin/
    sudo chown prometheus:prometheus /usr/local/bin/prometheus
else
    echo "Бинарник 'prometheus' не найден — проверьте архив."
    exit 1
fi

# ---------- конфиг (если ещё нет) ----------
if [ -f /etc/prometheus/prometheus.yml ]; then
    echo "Конфигурационный файл уже существует."
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

# ---------- systemd service ----------
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

# ---------- Grafana ----------
curl -fsSL https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server
sudo ufw allow 3000/tcp
sudo ufw reload

# ---------- завершение ----------
echo "Prometheus запущен: http://$IP:9090"
echo "Grafana запущен: http://$IP:3000 (admin / admin)"
