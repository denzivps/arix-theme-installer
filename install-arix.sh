#!/bin/bash
# ============================================================
#  Arix Theme v1.3.1-fixed - Installer voor Pterodactyl 1.15.x
#  Download: https://github.com/denzivps/arix-theme-installer/releases/download/arix/arix.zip
#  Gebruik: sudo bash script.sh [--yes] [--uninstall]
# ============================================================
set -uo pipefail

THEME_ZIP_URL="https://github.com/denzivps/arix-theme-installer/releases/download/arix/arix.zip"
PTERO_DIR="/var/www/pterodactyl"
STAMP="$(date +%F-%H%M%S)"
BACKUP_DIR="/var/backups/pterodactyl-arix-${STAMP}"
WORK_DIR="$(mktemp -d)"
LOG_FILE="/tmp/arix-install-${STAMP}.log"
AUTO_YES=0
DO_UNINSTALL=0

C_RST="\e[0m"; C_BLU="\e[1;34m"; C_GRN="\e[1;32m"; C_YEL="\e[1;33m"; C_RED="\e[1;31m"; C_DIM="\e[2m"

for arg in "$@"; do
  case "$arg" in
    --yes|-y) AUTO_YES=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    --help|-h)
      echo "Gebruik: sudo bash script.sh [--yes] [--uninstall]"
      echo "  --yes        geen vragen stellen"
      echo "  --uninstall  backup terugzetten uit /var/backups"
      exit 0
      ;;
  esac
done

msg()  { echo -e "${C_BLU}[arix]${C_RST} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${C_GRN}[ok]${C_RST} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${C_YEL}[let op]${C_RST} $*" | tee -a "$LOG_FILE"; }
fail() { echo -e "${C_RED}[fout]${C_RST} $*" | tee -a "$LOG_FILE"; exit 1; }

# Andere spinner dan het voorbeeld: braille + verstreken tijd
spin_run() {
  local label="$1"; shift
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local start=$SECONDS
  echo "$ label: $* " >>"$LOG_FILE" 2>&1
  "$@" >>"$LOG_FILE" 2>&1 &
  local pid=$!
  printf "%s " "$label" | tee -a "$LOG_FILE" >/dev/null
  tput civis 2>/dev/null || true
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    local el=$((SECONDS - start))
    printf "\r%s %s (%ss)" "${frames:i++%${#frames}:1}" "$label" "$el"
    sleep 0.12
  done
  wait "$pid"
  local code=$?
  tput cnorm 2>/dev/null || true
  if [ $code -eq 0 ]; then
    printf "\r✔ %s (%ss)\n" "$label" "$((SECONDS - start))"
  else
    printf "\n"
    fail "$label mislukt (code $code). Bekijk $LOG_FILE"
  fi
}

banner() {
  echo -e "${C_BLU}"
  echo "   ___    ____  _______  __"
  echo "  /   |  / __ \/  _/  |/  /"
  echo " / /| | / /_/ // / |   /   "
  echo "/ ___ |/ _, _// / /   |    "
  echo "/_/  |_/_/ |_/___//_/|_|    v1.3.1-fixed"
  echo -e "${C_RST}"
  echo -e "${C_DIM}Pterodactyl 1.15.x | Node >=22 | merge-install, nooit wissen${C_RST}"
}

need_root() {
  [ "$(id -u)" -eq 0 ] || fail "Draai als root: sudo bash script.sh"
}

ask_yes() {
  [ "$AUTO_YES" -eq 1 ] && return 0
  read -rp "$1 [J/n]: " ans
  [[ "$ans" =~ ^[Nn]$ ]] && fail "Afgebroken door gebruiker."
}

check_panel() {
  [ -d "$PTERO_DIR" ] || fail "$PTERO_DIR niet gevonden."
  [ -f "$PTERO_DIR/artisan" ] || fail "Geen Pterodactyl installatie in $PTERO_DIR."
  local ver
  ver=$(grep -o "'version' *=> *'[^']*'" "$PTERO_DIR/config/app.php" 2>/dev/null | head -1 || echo "onbekend")
  msg "Panel gevonden in $PTERO_DIR ($ver)"
}

install_sysdeps() {
  msg "Systeem-pakketten controleren (curl, unzip, rsync, git)..."
  spin_run "apt update + deps" bash -c 'apt-get update && apt-get install -y ca-certificates curl unzip rsync git gnupg'
}

ensure_node22() {
  local cur=""
  cur=$(node -v 2>/dev/null || echo "geen")
  msg "Node nu: $cur (vereist: v22+)"
  if [[ "$cur" == v22* ]]; then ok "Node 22 ok."; return; fi
  warn "Node 22 installeren via nodesource..."
  spin_run "Node 22 + yarn installeren" bash -c '
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    apt-get update
    apt-get install -y nodejs
    npm install -g yarn
  '
  node -v | tee -a "$LOG_FILE"
  yarn -v | tee -a "$LOG_FILE"
}

make_backup() {
  msg "Backup maken naar $BACKUP_DIR ..."
  mkdir -p "$BACKUP_DIR"
  tar -czf "$BACKUP_DIR/panel-backup.tgz" -C "$PTERO_DIR" \
    app config routes resources database public/arix public/themes \
    arix composer.json package.json webpack.config.js tailwind.config.js 2>>"$LOG_FILE" || \
  tar -czf "$BACKUP_DIR/panel-backup.tgz" -C "$PTERO_DIR" app config routes resources 2>>"$LOG_FILE" || true
  cp "$PTERO_DIR/.env" "$BACKUP_DIR/.env.bak" 2>/dev/null || true
  ok "Backup klaar."
}

fetch_theme() {
  msg "Theme downloaden..."
  echo "URL: $THEME_ZIP_URL" | tee -a "$LOG_FILE"
  spin_run "arix.zip downloaden" curl -fL "$THEME_ZIP_URL" -o "$WORK_DIR/arix.zip"
  spin_run "arix.zip uitpakken" bash -c "unzip -q -o '$WORK_DIR/arix.zip' -d '$WORK_DIR/src'"
  echo "Inhoud:" | tee -a "$LOG_FILE"
  ls -R "$WORK_DIR/src" 2>/dev/null | head -40 | tee -a "$LOG_FILE"
}

merge_theme() {
  local src="$WORK_DIR/src"
  # Zip kan pterodactyl/ bevatten, of direct app/ + arix/
  if [ -d "$src/pterodactyl" ]; then src="$src/pterodactyl"; fi
  [ -d "$src/arix" ] || [ -d "$src/app" ] || fail "Zip structuur herkend niet (geen app/ of arix/ in $src)"
  msg "Bestanden mergen (overschrijven, nooit wissen)..."
  # Belangrijk: geen --delete, anders sloopt app/helpers.php zoals vroeger
  if command -v rsync >/dev/null; then
    rsync -a "$src"/ "$PTERO_DIR"/
  else
    cp -rn "$src"/. "$PTERO_DIR"/ 2>/dev/null || cp -r "$src"/. "$PTERO_DIR"/
  fi
  ok "Merge klaar."
}

apply_theme() {
  # De zip staget alleen app/ + arix/vX/. Dit kopieert het thema echt naar het panel.
  # Zonder deze stap build je alleen stock en "doet het thema niks".
  local ver
  ver=$(ls -1 "$PTERO_DIR/arix" 2>/dev/null | sort -V | tail -1 || echo "")
  [ -n "$ver" ] || fail "Geen versie gevonden in $PTERO_DIR/arix (verwacht bijv. v1.3.1)"
  [ -d "$PTERO_DIR/arix/$ver" ] || fail "$PTERO_DIR/arix/$ver ontbreekt."
  msg "Thema toepassen: arix/$ver -> panel root..."
  cp "$PTERO_DIR/config/arix.php" "$WORK_DIR/arix-config-bak.php" 2>/dev/null || true
  rsync -a "$PTERO_DIR/arix/$ver"/ "$PTERO_DIR"/
  # Eigen config behouden als die al bestond (overschrijf alleen bij verse install)
  if [ -f "$WORK_DIR/arix-config-bak.php" ]; then
    cp "$WORK_DIR/arix-config-bak.php" "$PTERO_DIR/config/arix.php"
    msg "Eigen config/arix.php behouden."
  fi
  ok "Thema $ver toegepast."
}

repair_case_and_polyfill() {
  # 1. Linux is hoofdlettergevoelig: arix.php -> Arix.php
  if [ -f "$PTERO_DIR/app/Console/Commands/arix.php" ] && [ ! -f "$PTERO_DIR/app/Console/Commands/Arix.php" ]; then
    mv "$PTERO_DIR/app/Console/Commands/arix.php" "$PTERO_DIR/app/Console/Commands/Arix.php"
  fi
  if [ -f "$PTERO_DIR/app/Console/Commands/arix.php" ] && [ -f "$PTERO_DIR/app/Console/Commands/Arix.php" ]; then
    rm -f "$PTERO_DIR/app/Console/Commands/arix.php"
  fi
  # 2. Stock helpers.php / Kernel.php mogen nooit weg zijn
  if [ ! -f "$PTERO_DIR/app/helpers.php" ] || [ ! -f "$PTERO_DIR/app/Console/Kernel.php" ]; then
    warn "Stock app/ bestanden missen, herstellen uit backup..."
    tar -xzf "$BACKUP_DIR/panel-backup.tgz" -C "$PTERO_DIR" app/helpers.php app/Console/Kernel.php 2>/dev/null || true
  fi
  [ -f "$PTERO_DIR/app/helpers.php" ] || fail "app/helpers.php ontbreekt nog. Herstel handmatig."
  # 3. Webpack 5 fix: path -> pathe (Pterodactyl 1.15 gebruikt pathe)
  if grep -rq "from 'path'" "$PTERO_DIR/resources/scripts/components/server/files/" 2>/dev/null; then
    msg "pathe-fix toepassen..."
    grep -rl "from 'path'" "$PTERO_DIR/resources/scripts/components/server/files/" | xargs -r sed -i "s/from 'path'/from 'pathe'/g"
  fi
  ok "Case + polyfill checks ok."
}

do_build() {
  cd "$PTERO_DIR"
  msg "Composer autoload..."
  COMPOSER_ALLOW_SUPERUSER=1 composer dump-autoload --optimize
  msg "Laravel cache leegmaken..."
  php artisan optimize:clear
  msg "Database migreren..."
  php artisan migrate --force
  msg "Yarn pakketten (alleen wat ontbreekt)..."
  yarn add @types/md5 md5 react-icons@5.4.0 @types/bbcode-to-react bbcode-to-react i18next-browser-languagedetector@7.2.1 2>&1 | tail -5 | tee -a "$LOG_FILE"
  msg "Frontend builden (duurt 1-3 min, live output)..."
  export NODE_OPTIONS="--openssl-legacy-provider --max-old-space-size=4096"
  yarn build:production
  msg "Permissies + cache..."
  chown -R www-data:www-data "$PTERO_DIR"/*
  chmod -R 755 "$PTERO_DIR/storage"/* "$PTERO_DIR/bootstrap/cache" 2>/dev/null || true
  php artisan optimize:clear
  php artisan optimize
  php artisan language:compile 2>/dev/null || php artisan arix:lang 2>/dev/null || true
  php artisan queue:restart 2>/dev/null || true
  ok "Build + optimize klaar."
}

do_uninstall() {
  local last
  last=$(ls -td /var/backups/pterodactyl-arix-* 2>/dev/null | head -1 || echo "")
  [ -n "$last" ] || fail "Geen backup gevonden in /var/backups."
  msg "Backup terugzetten uit $last ..."
  tar -xzf "$last/panel-backup.tgz" -C "$PTERO_DIR"
  cd "$PTERO_DIR"
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  php artisan view:clear
  php artisan config:clear
  php artisan migrate --force
  chown -R www-data:www-data "$PTERO_DIR"/*
  php artisan queue:restart 2>/dev/null || true
  ok "Uninstall klaar (backup hersteld)."
  exit 0
}

main() {
  banner
  need_root
  echo "Log: $LOG_FILE"
  [ "$DO_UNINSTALL" -eq 1 ] && do_uninstall
  check_panel
  echo ""
  echo "Dit script:"
  echo "  1. maakt backup in /var/backups"
  echo "  2. downloadt $THEME_ZIP_URL"
  echo "  3. merget files (wist niks)"
  echo "  4. past arix/vX toe op panel root"
  echo "  5. fixt Arix.php + pathe + build"
  echo ""
  ask_yes "Doorgaan?"
  install_sysdeps
  ensure_node22
  make_backup
  fetch_theme
  merge_theme
  apply_theme
  repair_case_and_polyfill
  do_build
  systemctl restart nginx 2>/dev/null || true
  systemctl restart php8.2-fpm 2>/dev/null || true
  systemctl restart php8.3-fpm 2>/dev/null || true
  echo ""
  echo -e "${C_GRN}KLAAR.${C_RST} Open /admin/arix. Werkt iets niet? Check:"
  echo "  tail -n 80 $PTERO_DIR/storage/logs/laravel-\$(date +%F).log"
  echo "  php artisan route:list | grep arix"
  echo "Backup staat in: $BACKUP_DIR"
  rm -rf "$WORK_DIR"
}

main "$@"
