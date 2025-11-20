#!/bin/bash

# Обновляем пакетный индекс
echo "Обновление списка пакетов..."
sudo apt update && sudo apt upgrade -y

# Устанавливаем необходимые пакеты
echo "Установка необходимых зависимостей..."
sudo apt install -y wget lsb-release gnupg2

# Установка MySQL
echo "Установка MySQL..."
sudo apt install -y mysql-server
sudo mysql_secure_installation

# Установка Apache
echo "Установка Apache..."
sudo apt install -y apache2

# Установка PHP и расширений
echo "Установка PHP и необходимых расширений..."
sudo apt install -y php php-mysql php-gd php-bcmath php-mbstring php-xml php-json php-curl

# Добавляем репозиторий Zabbix
echo "Добавление репозитория Zabbix..."
wget https://repo.zabbix.com/zabbix/7.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_1.0-1+ubuntu_all.deb
sudo dpkg -i zabbix-release_1.0-1+ubuntu_all.deb
sudo apt update

# Установка Zabbix Server, Frontend и Agent
echo "Установка Zabbix Server, Frontend и Agent..."
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-agent

# Настройка базы данных Zabbix
echo "Настройка базы данных Zabbix..."
sudo mysql -uroot -p -e "CREATE DATABASE zabbix CHARACTER SET utf8 COLLATE utf8_bin;"
sudo mysql -uroot -p -e "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'password';"
sudo mysql -uroot -p -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
sudo mysql -uroot -p -e "FLUSH PRIVILEGES;"

# Импортируйте начальную структуру базы данных
echo "Импорт начальной структуры базы данных Zabbix..."
zcat /usr/share/doc/zabbix-server-mysql*/create/schema.sql.gz | mysql -uzabbix -p zabbix
zcat /usr/share/doc/zabbix-server-mysql*/create/images.sql.gz | mysql -uzabbix -p zabbix
zcat /usr/share/doc/zabbix-server-mysql*/create/data.sql.gz | mysql -uzabbix -p zabbix

# Настройка Zabbix сервера
echo "Настройка конфигурации Zabbix..."
sudo sed -i "s/# DBPassword=/DBPassword=password/g" /etc/zabbix/zabbix_server.conf

# Запуск и включение сервисов
echo "Запуск сервисов Zabbix и Apache..."
sudo systemctl restart zabbix-server zabbix-agent apache2
sudo systemctl enable zabbix-server zabbix-agent apache2

# Установка Grafana
echo "Установка Grafana OSS 12.21..."
wget https://dl.grafana.com/oss/release/grafana_12.21.0_amd64.deb
sudo dpkg -i grafana_12.21.0_amd64.deb
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "Установка завершена! Пожалуйста, настройте Zabbix через веб-интерфейс и Grafana."
