#!/bin/bash

# Скрипт установки Zabbix 7.4 с MySQL, Apache и Grafana OSS на Ubuntu 24.04

# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка необходимых зависимостей
sudo apt install -y wget curl software-properties-common gnupg2

# Добавление репозитория Zabbix
wget https://repo.zabbix.com/zabbix/7.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.4-1+ubuntu24.04_all.deb
sudo dpkg -i zabbix-release_7.4-1+ubuntu24.04_all.deb
sudo apt update

# Установка MySQL
sudo apt install -y mysql-server mysql-client

# Настройка безопасности MySQL
sudo mysql_secure_installation

# Создание базы данных для Zabbix
sudo mysql -e "CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
sudo mysql -e "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'your_strong_password';"
sudo mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Установка Apache
sudo apt install -y apache2

# Установка Zabbix
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent

# Импорт схемы базы данных Zabbix
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | sudo mysql -uzabbix -p zabbix

# Настройка PHP для Zabbix
sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/max_input_time = 60/max_input_time = 300/g' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/memory_limit = 128M/memory_limit = 256M/g' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/post_max_size = 8M/post_max_size = 32M/g' /etc/php/8.3/apache2/php.ini
sudo sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 16M/g' /etc/php/8.3/apache2/php.ini

# Перезапуск Apache
sudo systemctl restart apache2

# Установка Grafana OSS
sudo apt-get install -y apt-transport-https software-properties-common
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana=12.21.0

# Запуск и включение служб
sudo systemctl start zabbix-server
sudo systemctl enable zabbix-server
sudo systemctl start zabbix-agent
sudo systemctl enable zabbix-agent
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# Очистка загруженных пакетов
rm zabbix-release_7.
