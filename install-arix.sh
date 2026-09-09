#!/bin/bash

# Zorg dat het script stopt bij onverwachte fouten
set -e

# --- FUNCTIES ---
show_spinner() {
    local pid=$1
    local delay=0.1
    local spin='|/-\\'
    local i=0
    tput civis
    while kill -0 $pid 2>/dev/null; do
        printf "\r[%c] %s" "${spin:i++%${#spin}:1}" "$SPINNER_TEXT"
        sleep $delay
    done
    printf "\r[✔] %s\n" "$SPINNER_TEXT"
    tput cnorm
}

run_step() {
    SPINNER_TEXT="$1"
    shift
    "$@" > /dev/null 2>&1 &
    show_spinner $!
}

# Controleer root rechten
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[31m[✖] Voer dit script uit als root (sudo bash install-arix.sh)\e[0m"
    exit 1
fi

# --- CONFIGURATIE ---
THEME_URL="https://github.com/denzivps/arix-theme-installer/releases/download/arix/arix.zip"
TEMP_DIR=$(mktemp -d)
PTERO_DIR="/var/www/pterodactyl"

if [ ! -d "$PTERO_DIR" ]; then
    echo -e "\e[31m[✖] Map $PTERO_DIR niet gevonden! Is Pterodactyl geïnstalleerd?\e[0m"
    exit 1
fi

echo -e "\e[36m🚀 Start Arix Theme v1.3.1 Installatie...\e[0m"

# 1. Node.js 22 & Yarn & Systeempakketten Installeren/Upgraden
echo "🔧 Node.js 22, Yarn en tools voorbereiden..."
run_step "Node.js 22 & benodigdheden installeren..." bash -c '
    apt-get update
    apt-get install -y ca-certificates curl gnupg rsync unzip
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
    apt-get update
    apt-get install -y nodejs
    npm install -g yarn
'

# 2. Theme downloaden en uitpakken
echo "⏬ Arix Theme ophalen..."
run_step "Downloaden van arix.zip..." curl -L "$THEME_URL" -o "$TEMP_DIR/arix.zip"
run_step "Uitpakken..." unzip -q "$TEMP_DIR/arix.zip" -d "$TEMP_DIR/extracted"

echo "🔁 Bestanden overzetten naar Pterodactyl..."
run_step "Themabestanden samenvoegen..." bash -c "
    if [ -d '$TEMP_DIR/extracted/pterodactyl' ]; then
        rsync -a '$TEMP_DIR/extracted/pterodactyl/' '$PTERO_DIR/'
    else
        rsync -a '$TEMP_DIR/extracted/' '$PTERO_DIR/'
    fi
"

# 3. Naar de Pterodactyl map gaan
cd "$PTERO_DIR"

# 4. Composer & Autoload bijwerken
echo "📦 PHP Autoload & Cache verwerken..."
run_step "Composer autoload optimaliseren..." bash -c 'COMPOSER_ALLOW_SUPERUSER=1 composer dump-autoload --optimize'
run_step "Artisan cache legen..." php artisan optimize:clear

# 5. Arix Installatieproces
echo "🏗️ Arix installer en productie build uitvoeren..."
export NODE_OPTIONS="--openssl-legacy-provider --max-old-space-size=4096"

# Voert de arix installatie automatisch uit (bevestigt 'yes', kiest '0', bevestigt 'yes')
# Zonder run_step zodat je live voortgang van het bouwen ziet
if ! printf "yes\n0\nyes\n" | php artisan arix install; then
    echo -e "\e[33m⚠️ Artisan arix build gaf een melding, handmatige yarn build uitvoeren...\e[0m"
    yarn build:production
fi

# 6. Afronden (Database, Cache, Rechten)
echo "🧹 Systeem afronden & optimaliseren..."
run_step "Database migreren..." php artisan migrate --force
run_step "Artisan cache legen & optimaliseren..." bash -c '
    php artisan optimize:clear
    php artisan optimize
'
run_step "Bestandsrechten herstellen..." bash -c "
    chown -R www-data:www-data '$PTERO_DIR'/*
    chmod -R 755 '$PTERO_DIR/storage' '$PTERO_DIR/bootstrap/cache'
"

# 7. Webserver herstarten
echo "🔄 Webserver herstarten..."
systemctl restart nginx 2>/dev/null || systemctl restart apache2 2>/dev/null || true

# 8. Schoonmaken
rm -rf "$TEMP_DIR"

echo -e "\n\e[92m✅ INSTALLATIE VOLTOOID!\e[0m"
echo -e "\e[33mJe Arix v1.3.1 theme is succesvol geïnstalleerd.\e[0m"
echo -e "Ga naar: \e[36m/admin/arix\e[0m in je browser om het thema te configureren."
