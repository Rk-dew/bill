#!/bin/bash

set -e

# Variables
APP_DIR="/var/www/bill"
SQL_FILE="database.sql"
DB_NAME="billingci"
DB_USER="bill_user"
DB_PASS="strongpassword"
PHP_VERSION="7.4"  # Update based on requirement

echo "[+] Updating system..."
sudo apt update

echo "[+] Installing PHP $PHP_VERSION, Nginx, MySQL, Composer..."
sudo apt install -y nginx mysql-server unzip curl git composer \
    php$PHP_VERSION php$PHP_VERSION-cli php$PHP_VERSION-fpm php$PHP_VERSION-mysql \
    php$PHP_VERSION-mbstring php$PHP_VERSION-xml php$PHP_VERSION-curl

echo "[+] Creating MySQL database and user..."
sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "[+] Deploying CodeIgniter app..."
sudo rm -rf $APP_DIR
sudo cp -r bill $APP_DIR
sudo chown -R www-data:www-data $APP_DIR
sudo chmod -R 755 $APP_DIR

echo "[+] Installing Composer dependencies..."
cd $APP_DIR
[ -f composer.json ] && composer install || echo "No composer.json found, skipping..."

echo "[+] Importing database..."
mysql -u root ${DB_NAME} < ${APP_DIR}/${SQL_FILE}

echo "[+] Downloading missing libraries..."

# PHPExcel
mkdir -p ${APP_DIR}/application/third_party
curl -L -o PHPExcel.zip https://github.com/PHPOffice/PHPExcel/archive/refs/heads/master.zip
unzip PHPExcel.zip
mv PHPExcel-master/Classes/PHPExcel ${APP_DIR}/application/third_party/PHPExcel
rm -rf PHPExcel.zip PHPExcel-master

# TCPDF
mkdir -p ${APP_DIR}/application/libraries
curl -L -o tcpdf.zip https://github.com/tecnickcom/tcpdf/archive/refs/heads/main.zip
unzip tcpdf.zip
mv tcpdf-main ${APP_DIR}/application/libraries/tcpdf
rm -rf tcpdf.zip tcpdf-main

echo "[+] Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/bill"
cat <<EOL | sudo tee $NGINX_CONF
server {
    listen 80;
    server_name _;

    root ${APP_DIR}/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

    error_log /var/log/nginx/bill_error.log;
    access_log /var/log/nginx/bill_access.log;
}
EOL

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl restart php${PHP_VERSION}-fpm

echo "[+] DONE: App is live at http://your-server-ip/"
echo "[*] Admin Login => Username: admin | Password: Password@123"
