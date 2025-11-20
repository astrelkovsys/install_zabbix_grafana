#!/bin/bash

# Обновляем пакеты
echo "Обновляем пакеты..."
sudo apt update

# Устанавливаем необходимые пакеты
echo "Устанавливаем необходимые пакеты..."
sudo apt install -y wget curl gnupg2 software-properties-common

# Устанавливаем MySQL
echo "Устанавливаем MySQL..."
sudo apt install -y mysql-server
sudo mysql_secure_installation

# Настраиваем MySQL для Zabbix
echo "Настраиваем MySQL для Zabbix..."
sudo mysql -uroot -p`sudo cat /etc/mysql/debian.cnf | grep password | awk '{print $3}'` <<EOF
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'%' IDENTIFIED BY 'zabbix';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%';
FLUSH PRIVILEGES;
EOF

# Устанавливаем Apache
echo "Устанавливаем Apache..."
sudo apt install -y apache2

# Добавляем репозиторий Zabbix
echo "Добавляем репозиторий Zabbix..."
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo apt update

# Устанавливаем Zabbix
echo "Устанавливаем Zabbix..."
sudo apt install -y zabbix-server-mysql zabbix-web-mysql zabbix-agent

# Настраиваем Zabbix
echo "Настраиваем Zabbix..."
sudo nano /etc/zabbix/zabbix_server.conf
# В файле /etc/zabbix/zabbix_server.conf раскомментируйте и измените строки:
# DBHost=localhost
# DBName=zabbix
# DBUser=zabbix
# DBPassword=zabbix

# Настраиваем Zabbix web
echo "Настраиваем Zabbix web..."
sudo nano /etc/zabbix/web/zabbix.conf.php
# В файле /etc/zabbix/web/zabbix.conf.php измените строки:
# $DB['TYPE']     = 'MYSQLI';
# $DB['SERVER']   = 'localhost';
# $DB['PORT']     = '3306';
# $DB['DATABASE'] = 'zabbix';
# $DB['USER']     = 'zabbix';
# $DB['PASSWORD'] = 'zabbix';

# Перезапускаем службы
echo "Перезапускаем службы..."
sudo systemctl restart apache2
sudo systemctl restart zabbix-server

# Добавляем репозиторий Grafana
echo "Добавляем репозиторий Grafana..."
sudo apt install -y gnupg
wget https://packages.grafana.com/gpg.key
sudo apt-key add gpg.key
sudo add-apt-repository https://packages.grafana.com/ubuntu
sudo apt update

# Устанавливаем Grafana
echo "Устанавливаем Grafana..."
sudo apt install -y grafana-server

# Настраиваем Grafana
echo "Настраиваем Grafana..."
sudo nano /etc/grafana/grafana.ini
# В файле /etc/grafana/grafana.ini раскомментируйте и измените строки:
# [server]
# http_port = 3000

# Перезапускаем Grafana
echo "Перезапускаем Grafana..."
sudo systemctl daemon-reload
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

echo "Установка завершена."
