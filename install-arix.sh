#!/usr/bin/env bash

# ==============================================================================
# Arix Theme v1.3.1 Installer voor Pterodactyl
# ==============================================================================

set -e

# Kleuren voor weergave
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PANEL_DIR="/var/www/pterodactyl"
DOWNLOAD_URL="https://github.com/denzivps/arix-theme-installer/releases/download/arix/arix.zip"
TMP_DIR=$(mktemp -d /tmp/arix-installer.XXXXXX)

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCES]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WAARSCHUWING]${NC} $1"; }
log_error() { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

# 1. Controleer of het script als root draait
if [ "$EUID" -ne 0 ]; then
    log_error "Voer dit script uit als root (sudo bash install-arix.sh)."
fi

# 2. Controleer of Pterodactyl map bestaat
if [ ! -d "$PANEL_DIR" ]; then
    log_error "Map $PANEL_DIR niet gevonden! Zorg dat Pterodactyl correct geïnstalleerd is."
fi

clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}    Arix Pterodactyl Theme v1.3.1 Installer       ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# 3. Vereisten controleren en installeren waar nodig
log_info "Controleren van benodigde tools..."

if ! command -v rsync &> /dev/null || ! command -v unzip &> /dev/null || ! command -v curl &> /dev/null; then
    log_info "Installeer ontbrekende tools (rsync, unzip, curl)..."
    apt-get update -y && apt-get install -y rsync unzip curl
fi

# Node.js controle
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    log_info "Node.js versie gevonden: $(node -v)"
    if [ "$NODE_VERSION" -lt 22 ]; then
        log_warn "Pterodactyl 1.15+ vereist Node >= 22. Jouw versie is $(node -v). Dit kan problemen opleveren tijdens het builden!"
    fi
else
    log_warn "Node.js is niet gevonden in PATH. Zorg dat Node >= 22 geïnstalleerd is."
fi

# Yarn controle
if ! command -v yarn &> /dev/null; then
    log_warn "Yarn is niet gedetecteerd. Zorg dat Yarn geïnstalleerd is (npm i -g yarn)."
fi

# 4. Optionele snelle backup maken van de app map
read -p "Wil je voor de zekerheid een backup maken van $PANEL_DIR/app? [Y/n]: " -r MAKE_BACKUP
MAKE_BACKUP=${MAKE_BACKUP:-Y}
if [[ $MAKE_BACKUP =~ ^[Yy]$ ]]; then
    BACKUP_PATH="$PANEL_DIR/app_backup_$(date +%F_%H-%M-%S)"
    log_info "Backup aanmaken naar $BACKUP_PATH..."
    cp -r "$PANEL_DIR/app" "$BACKUP_PATH"
    log_success "Backup voltooid!"
fi

# 5. Downloaden en uitpakken
log_info "Downloaden van Arix zip-bestand..."
curl -L -o "$TMP_DIR/arix.zip" "$DOWNLOAD_URL"

log_info "Bestanden uitpakken..."
unzip -q "$TMP_DIR/arix.zip" -d "$TMP_DIR/extracted"

# Bepaal waar de bronbestanden staan (in zip map `pterodactyl/` of root)
if [ -d "$TMP_DIR/extracted/pterodactyl" ]; then
    SOURCE_DIR="$TMP_DIR/extracted/pterodactyl"
else
    SOURCE_DIR="$TMP_DIR/extracted"
fi

# 6. Bestanden mergen (nooit overschrijven door te deleten)
log_info "Themabestanden samenvoegen (mergen) met $PANEL_DIR..."
rsync -avP "$SOURCE_DIR/" "$PANEL_DIR/"

# Controleer of sleutelbestanden aanwezig zijn
log_info "Controleren van overgezette bestanden..."
if [ -f "$PANEL_DIR/app/Console/Commands/Arix.php" ]; then
    log_success "Arix.php correct overgezet."
else
    log_warn "Arix.php niet direct gevonden in Commands. Controleer de mappenstructuur indien de installatie faalt."
fi

# 7. Composer en Artisan autoload
log_info "Autoload bijwerken via Composer..."
cd "$PANEL_DIR"
export COMPOSER_ALLOW_SUPERUSER=1
composer dump-autoload --optimize

log_info "Artisan cache legen..."
php artisan optimize:clear

# 8. Arix Installer starten
echo ""
echo -e "${YELLOW}[BELANGRIJK]${NC} Het Arix installatie-commando wordt nu gestart."
echo -e "Kies dadelijk: ${GREEN}0${NC} (voor ./arix/v1.3.1) en bevestig met ${GREEN}yes${NC}."
echo ""
read -p "Druk op [ENTER] om door te gaan naar de 'php artisan arix install' prompt..."

# Omgevingsvariabele meegeven voor oudere OpenSSL build fix indien nodig
export NODE_OPTIONS="--openssl-legacy-provider"

# Start de artisan installer interactief
php artisan arix install

# 9. Bestandsrechten herstellen
log_info "Bestandsrechten corrigeren voor www-data..."
chown -R www-data:www-data "$PANEL_DIR"/*
chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

# 10. Cache opnieuw optimaliseren
log_info "Cache herladen en optimaliseren..."
php artisan optimize:clear
php artisan optimize

# 11. Opruimen tijdelijke bestanden
log_info "Tijdelijke downloadbestanden verwijderen..."
rm -rf "$TMP_DIR"

echo ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}      Arix Theme Installatie Voltooid!              ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
echo "Bezoek het Admin Panel via: /admin/arix"
echo "Configuratiebestand: nano $PANEL_DIR/config/arix.php"
echo ""
echo -e "${YELLOW}Mocht de build gefaald zijn, voer dit handmatig uit:${NC}"
echo "  cd $PANEL_DIR"
echo "  export NODE_OPTIONS=--openssl-legacy-provider"
echo "  yarn build:production"
echo "  chown -R www-data:www-data $PANEL_DIR/*"
echo "  php artisan optimize:clear"
echo ""
