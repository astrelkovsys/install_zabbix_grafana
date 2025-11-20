#!/bin/bash

# Обновление системы
sudo apt update
sudo apt upgrade -y

# Установка необходимых пакетов
sudo apt install -y wget apt-transport-https software-properties-common

# Добавление репозитория Zabbix
wget https://repo.zabbix.com/zabbix-official-repo.key
sudo apt-key add zabbix-official-repo.key
sudo add-apt-repository 'deb https://repo.zabbix.com/zabbix/7.4/ubuntu/ focal main'
sudo apt update

# Установка Zabbix Server, Frontend, Agent и Apache
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent

# Установка MySQL Server
sudo apt install -y mysql-server

# Настройка MySQL для Zabbix
sudo mysql -u root -e "CREATE DATABASE zabbix CHARACTER SET UTF8 COLLATE UTF8_BIN;"
sudo mysql -u root -e "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'zabbix';"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"

# Импорт схемы базы данных Zabbix
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -pzabbix zabbix

# Настройка Zabbix Server
sudo sed -i 's/# DBPassword=/DBPassword=zabbix/' /etc/zabbix/zabbix_server.conf

# Перезапуск сервисов
sudo systemctl restart zabbix-server zabbix-agent apache2
sudo systemctl enable zabbix-server zabbix-agent apache2

# Установка PHP и необходимых расширений
sudo apt install -y php libapache2-mod-php php-mysql php-xml php-bcmath php-mbstring php-curl php-gd php-intl php-json php-zip

# Настройка PHP для Zabbix
sudo sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/7.4/apache2/php.ini
sudo sed -i 's/memory_limit = 128M/memory_limit = 256M/' /etc/php/7.4/apache2/php.ini
sudo sed -i 's/post_max_size = 8M/post_max_size = 16M/' /etc/php/7.4/apache2/php.ini
sudo sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 16M/' /etc/php/7.4/apache2/php.ini

# Перезапуск Apache
sudo systemctl restart apache2

echo "Установка Zabbix 7.4 завершена. Перейдите по адресу http://<ваш_сервер_ip>/zabbix для завершения настройки."
