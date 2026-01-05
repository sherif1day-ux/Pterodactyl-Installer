#!/bin/bash
# CtrlPanel Installer: User Choice Domain (DuckDNS / Own Domain)
# Author: @she0rif
# Tested on Ubuntu 22.04/20.04/24.04

set -euo pipefail

random_string() { openssl rand -hex 6; }

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "❌ This script must run as root!"
        exit 1
    fi
}

ask_choice() {
    echo "Pilih metode domain:"
    echo "1) DuckDNS (subdomain gratis otomatis)"
    echo "2) Gunakan domain/subdomain sendiri"
    read -p "Masukkan pilihan [1/2]: " CHOICE
    if [[ "$CHOICE" != "1" && "$CHOICE" != "2" ]]; then
        echo "❌ Pilihan salah!"
        exit 1
    fi
}

install_dependencies() {
    echo "➤ Installing dependencies..."
    apt update && apt upgrade -y
    apt install -y software-properties-common curl git unzip nginx mariadb-server redis-server tar \
    php8.1 php8.1-cli php8.1-fpm php8.1-mbstring php8.1-bcmath php8.1-curl php8.1-xml php8.1-zip php8.1-gd php8.1-openssl php8.1-pdo-mysql \
    composer certbot python3-certbot-nginx jq
}

setup_database() {
    echo "➤ Creating database & user..."
    mysql -u root <<MYSQL_CMDS
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_CMDS
}

download_ctrlpanel() {
    echo "➤ Downloading CtrlPanel..."
    mkdir -p "$APP_PATH"
    cd "$APP_PATH"
    git clone -b main https://github.com/Ctrlpanel-gg/panel.git . || exit 1
}

setup_env_file() {
    echo "➤ Setting up .env file..."
    cp "$APP_PATH/.env.example" "$APP_PATH/.env"
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" "$APP_PATH/.env"
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|" "$APP_PATH/.env"
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" "$APP_PATH/.env"
    sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" "$APP_PATH/.env"
    php "$APP_PATH/artisan" key:generate
}

configure_nginx() {
    echo "➤ Configuring NGINX..."
    cat > /etc/nginx/sites-available/ctrlpanel.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $APP_PATH/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/ctrlpanel.conf /etc/nginx/sites-enabled/
    nginx -t
    systemctl reload nginx
}

install_composer_packages() {
    echo "➤ Installing Composer packages..."
    cd "$APP_PATH"
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
}

set_permissions() {
    echo "➤ Setting permissions..."
    chown -R www-data:www-data "$APP_PATH"
    chmod -R 755 "$APP_PATH/storage" "$APP_PATH/bootstrap/cache"
}

setup_cron_worker() {
    echo "➤ Setting up cron & queue worker..."
    crontab -l | { cat; echo "* * * * * php $APP_PATH/artisan schedule:run >> /dev/null 2>&1"; } | crontab -

    cat > /etc/systemd/system/ctrlpanel-worker.service <<EOF
[Unit]
Description=CtrlPanel Queue Worker
After=network.target

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $APP_PATH/artisan queue:work --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now ctrlpanel-worker.service
}

setup_duckdns() {
    DUCKDNS_TOKEN="$(random_string)"
    DUCKDNS_DOMAIN="ctrlpanel-$(random_string).duckdns.org"
    DOMAIN="$DUCKDNS_DOMAIN"
    EMAIL="admin@$DOMAIN"

    mkdir -p /etc/duckdns
    cat > /etc/duckdns/duck.sh <<EOF
echo url="https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=" | curl -k -s -o /etc/duckdns/duck.log -K -
EOF
    chmod 700 /etc/duckdns/duck.sh
    (crontab -l 2>/dev/null; echo "*/5 * * * * /etc/duckdns/duck.sh >/dev/null 2>&1") | crontab -
    /etc/duckdns/duck.sh
}

setup_ssl() {
    echo "➤ Installing SSL for $DOMAIN..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
}

print_summary() {
    echo
    echo "=============================="
    echo "✅ CtrlPanel Installation Complete!"
    echo "URL: https://$DOMAIN"
    echo "DB Name: $DB_NAME"
    echo "DB User: $DB_USER"
    echo "DB Pass: $DB_PASS"
    echo "Path: $APP_PATH"
    echo "Cron & Worker: Active"
    echo "SSL: Enabled"
    if [[ "$CHOICE" == "1" ]]; then
        echo "DuckDNS Token: $DUCKDNS_TOKEN"
    fi
    echo "=============================="
}

# -----------------------------
# Main
# -----------------------------
check_root
ask_choice

# Auto generate parameters
DB_NAME="ctrlpanel_$(random_string)"
DB_USER="user_$(random_string)"
DB_PASS="$(random_string)"
APP_PATH="/var/www/ctrlpanel"

if [[ "$CHOICE" == "1" ]]; then
    echo "➤ Setting up DuckDNS subdomain..."
    setup_duckdns
else
    read -p "Masukkan domain/subdomain anda: " DOMAIN
    read -p "Masukkan email untuk SSL: " EMAIL
fi

echo "=== CtrlPanel Installer ==="
echo "Domain: $DOMAIN"
echo "DB: $DB_NAME / $DB_USER / $DB_PASS"
echo "Path: $APP_PATH"

install_dependencies
setup_database
download_ctrlpanel
setup_env_file
install_composer_packages
configure_nginx
set_permissions
setup_cron_worker
setup_ssl
print_summary
