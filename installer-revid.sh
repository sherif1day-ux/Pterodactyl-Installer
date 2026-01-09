#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Error Handling
set -e
trap 'echo -e "${RED}[ERROR] Terjadi kesalahan pada baris $LINENO. Script dihentikan.${NC}"' ERR

# Check Root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Script ini harus dijalankan sebagai root${NC}" 
   exit 1
fi

clear
echo -e "${GREEN}
################################################################################
#                                                                              #
#                      REVIACTYL AUTO INSTALLER (FULL STACK)                   #
#                                                                              #
################################################################################
${NC}"

# Inputs
echo -e "${YELLOW}Masukkan URL Repository Git Anda (Contoh: https://github.com/username/reviactyl.git):${NC}"
read REPO_URL

echo -e "${YELLOW}Masukkan Domain Panel (Contoh: panel.domain.com):${NC}"
read DOMAIN

echo -e "${YELLOW}Masukkan Nama Database (Default: reviactyl):${NC}"
read DB_NAME
DB_NAME=${DB_NAME:-reviactyl}

echo -e "${YELLOW}Masukkan Username Database (Default: reviactyl):${NC}"
read DB_USER
DB_USER=${DB_USER:-reviactyl}

echo -e "${YELLOW}Masukkan Password Database:${NC}"
read -s DB_PASS

echo -e "${YELLOW}Masukkan Email Admin:${NC}"
read ADMIN_EMAIL

echo -e "${YELLOW}Masukkan Username Admin:${NC}"
read ADMIN_USER

echo -e "${YELLOW}Masukkan Nama Depan Admin:${NC}"
read ADMIN_FIRST

echo -e "${YELLOW}Masukkan Nama Belakang Admin:${NC}"
read ADMIN_LAST

echo -e "${YELLOW}Masukkan Password Admin:${NC}"
read -s ADMIN_PASS

echo -e "\n${GREEN}[+] Memulai Instalasi...${NC}"

# 1. Install Dependencies
echo -e "${GREEN}[+] Menginstall System Dependencies...${NC}"
apt update -y
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg cron git unzip tar

# Install PHP 8.3 & Extensions
echo -e "${GREEN}[+] Menginstall PHP 8.3...${NC}"
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y php8.3 php8.3-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx

# Install Node.js & Yarn (Untuk Build Assets jika diperlukan)
echo -e "${GREEN}[+] Menginstall Node.js & Yarn...${NC}"
curl -sL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
npm install -g yarn

# Install Composer
echo -e "${GREEN}[+] Menginstall Composer...${NC}"
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# 2. Setup Database
echo -e "${GREEN}[+] Setup Database MariaDB...${NC}"
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

# 3. Setup Project
echo -e "${GREEN}[+] Setup Project Directory...${NC}"
mkdir -p /var/www/reviactyl
cd /var/www/reviactyl

# Backup & Clone
if [ "$(ls -A /var/www/reviactyl)" ]; then
    if [ -d ".git" ]; then
        echo "Directory is already a git repo. Pulling latest..."
        git pull
    else
        echo "Directory not empty. Backing up..."
        cd ..
        mv reviactyl reviactyl_backup_$(date +%s)
        mkdir -p reviactyl
        cd reviactyl
        git clone $REPO_URL .
    fi
else
    git clone $REPO_URL .
fi

# 4. Install Project Dependencies
echo -e "${GREEN}[+] Installing Composer Dependencies...${NC}"
if [ ! -f "composer.json" ]; then
    echo -e "${RED}[ERROR] composer.json tidak ditemukan di /var/www/reviactyl${NC}"
    exit 1
fi
export COMPOSER_ALLOW_SUPERUSER=1
/usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction

# Build Assets if package.json exists
if [ -f "package.json" ]; then
    echo -e "${GREEN}[+] Mendeteksi package.json, melakukan build assets...${NC}"
    yarn install
    yarn build:production
fi

# 5. Environment Setup
echo -e "${GREEN}[+] Konfigurasi .env...${NC}"
cp .env.example .env
php artisan key:generate --force

# Update .env programmatically
sed -i "s|^APP_URL=.*|APP_URL=http://${DOMAIN}|" .env
sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env
sed -i "s|^DB_PORT=.*|DB_PORT=3306|" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env
sed -i "s|^APP_ENV=.*|APP_ENV=production|" .env
sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env

# 6. Database Migration & Seeding
echo -e "${GREEN}[+] Migrasi Database...${NC}"
php artisan migrate --seed --force

# 7. Create Admin User
echo -e "${GREEN}[+] Membuat User Admin...${NC}"
php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name-first="$ADMIN_FIRST" --name-last="$ADMIN_LAST" --password="$ADMIN_PASS" --admin=1

# 8. Permissions
echo -e "${GREEN}[+] Mengatur Permissions...${NC}"
chown -R www-data:www-data /var/www/reviactyl/*
chmod -R 755 storage/* bootstrap/cache/

# 9. NGINX Configuration (Non-SSL as requested)
echo -e "${GREEN}[+] Konfigurasi NGINX...${NC}"
cat > /etc/nginx/sites-available/reviactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root /var/www/reviactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/reviactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable Config
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/reviactyl.conf /etc/nginx/sites-enabled/reviactyl.conf
systemctl restart nginx

# 10. Queue Worker
echo -e "${GREEN}[+] Setup Queue Service...${NC}"
cat > /etc/systemd/system/reviactyl.service <<EOF
[Unit]
Description=Reviactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/reviactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now reviactyl

# 11. Auto Update Script
echo -e "${GREEN}[+] Setup Auto Update...${NC}"
cat > /var/www/reviactyl/auto_update.sh <<EOF
#!/bin/bash
cd /var/www/reviactyl
git pull origin main
composer install --no-dev --optimize-autoloader
if [ -f "package.json" ]; then
    yarn install
    yarn build:production
fi
php artisan migrate --force
php artisan view:clear
php artisan config:clear
chown -R www-data:www-data /var/www/reviactyl/*
EOF

chmod +x /var/www/reviactyl/auto_update.sh

# Cron Job (Every 5 minutes)
(crontab -l 2>/dev/null | grep -v "/var/www/reviactyl/auto_update.sh"; echo "*/5 * * * * /var/www/reviactyl/auto_update.sh >> /var/log/reviactyl_update.log 2>&1") | crontab -

echo -e "${GREEN}
################################################################################
#                                                                              #
#                      INSTALLATION SUCCESSFUL                                 #
#                                                                              #
################################################################################
URL: http://${DOMAIN}
Admin Email: ${ADMIN_EMAIL}
Admin Password: (Hidden)
Database: ${DB_NAME}

Panel siap digunakan!
${NC}"
