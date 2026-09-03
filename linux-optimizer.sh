#!/usr/bin/env bash

set -o pipefail

readonly APP_NAME="AxelL - Linux Optimmisateur"
readonly APP_VERSION="2.0.0"
readonly APP_LICENSE="MIT"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log/linux-optimizer"
readonly REPORT_FILE="${LOG_DIR}/report-$(date +%Y%m%d-%H%M%S).txt"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_CYAN=$'\033[36m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_RED=$'\033[31m'
else
    readonly C_RESET=""
    readonly C_CYAN=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_RED=""
fi

mkdir -p "$LOG_DIR" 2>/dev/null || true
exec > >(tee -a "$REPORT_FILE") 2>&1

info() { printf '%b[INFO]%b %s\n' "$C_CYAN" "$C_RESET" "$*"; }
success() { printf '%b[ OK ]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error() { printf '%b[FAIL]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

show_splash() {
    clear 2>/dev/null || true
    printf '%b\n' "$C_CYAN"
    printf '  +----------------------------------------------------------+\n'
    printf '  |          %-42s  |\n' "$APP_NAME"
    printf '  |          Professional server optimizer                 |\n'
    printf '  |          v%-8s | Licence %-8s               |\n' "$APP_VERSION" "$APP_LICENSE"
    printf '  +----------------------------------------------------------+\n'
    printf '%b\n' "$C_RESET"
    warn "Aucun changement ne sera applique avant votre confirmation."
    info "Journal : $REPORT_FILE"
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "Lancez ce script avec sudo ou depuis une session root."
        exit 1
    fi
}

load_os() {
    if [[ ! -r /etc/os-release ]]; then
        error "/etc/os-release est introuvable."
        exit 1
    fi
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-$OS_ID}"
}

detect_services() {
    local services=(docker containerd nginx apache2 php*-fpm node python3 redis-server mysql mariadb postgresql wings keyhelp ufw firewalld)
    local service
    DETECTED_SERVICES=()
    for service in "${services[@]}"; do
        if systemctl list-unit-files "${service}.service" --no-legend 2>/dev/null | grep -q .; then
            DETECTED_SERVICES+=("$service")
        fi
    done
}

show_audit() {
    local memory swap kernel ports
    memory=$(awk '/MemTotal:/ {printf "%.1f GiB", $2 / 1024 / 1024}' /proc/meminfo)
    swap=$(awk '/SwapTotal:/ {printf "%.1f GiB", $2 / 1024 / 1024}' /proc/meminfo)
    kernel=$(uname -r)
    ports=$(ss -H -lntu 2>/dev/null | awk '{print $5}' | sed 's/.*://' | sort -n -u | paste -sd, -)
    printf '\n%bAUDIT PREALABLE%b\n' "$C_CYAN" "$C_RESET"
    printf '  OS             : %s (%s)\n' "$OS_NAME" "$OS_VERSION"
    printf '  Architecture   : %s\n' "$(uname -m)"
    printf '  Noyau          : %s\n' "$kernel"
    printf '  Memoire / swap : %s / %s\n' "$memory" "$swap"
    printf '  BBR            : %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf 'indisponible')"
    printf '  Ports en ecoute: %s\n' "${ports:-aucun detecte}"
    printf '  Services       : %s\n' "${DETECTED_SERVICES[*]:-aucun detecte}"
    if printf '%s\n' "${DETECTED_SERVICES[@]}" | grep -qx docker; then
        info "Docker detecte : les ports publies seront preserves dans le profil Docker."
    fi
    if systemctl is-active --quiet ufw 2>/dev/null; then
        info "UFW actif : aucune regle ne sera remplacee sans confirmation."
    elif systemctl is-active --quiet firewalld 2>/dev/null; then
        info "firewalld actif : UFW ne sera pas installe automatiquement."
    fi
    if docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -qi unhealthy; then
        warn "Un conteneur Docker unhealthy a ete detecte. Le script ne le reparera pas automatiquement."
    fi
}

progress() {
    local current="$1" total="$2" label="$3" now elapsed eta width filled empty
    now=$(date +%s)
    elapsed=$((now - START_TIME))
    if (( current > 0 )); then eta=$((elapsed * total / current - elapsed)); else eta=0; fi
    width=30
    filled=$((current * width / total))
    empty=$((width - filled))
    printf '\r%b[%s%s]%b %3d%% | %-30s | ecoule %02dm%02ds | ETA ~%02dm%02ds' "$C_CYAN" "$(printf '%*s' "$filled" '' | tr ' ' '#')" "$(printf '%*s' "$empty" '')" "$C_RESET" "$((current * 100 / total))" "$label" "$((elapsed / 60))" "$((elapsed % 60))" "$((eta / 60))" "$((eta % 60))"
    if (( current == total )); then printf '\n'; fi
}

run_profile() {
    local profile="$1"
    if [[ "$OS_ID" != debian ]]; then
        error "Cette version complete cible Debian. Systeme detecte : $OS_NAME."
        warn "Les scripts historiques des autres distributions ne sont plus executes automatiquement."
        return 1
    fi
    if [[ ! -f "$SCRIPT_DIR/scripts/debian-optimizer.sh" ]]; then
        error "Profil Debian introuvable dans le depot local."
        return 1
    fi
    PROFILE_MODE="$profile" SCRIPT_DIR="$SCRIPT_DIR" bash "$SCRIPT_DIR/scripts/debian-optimizer.sh"
}

choose_profile() {
    local choice
    printf '\n%bPROFILS PROFESSIONNELS%b\n' "$C_CYAN" "$C_RESET"
    printf '  1  Base prudente (recommande)\n'
    printf '  2  Hote Docker / multi-conteneurs\n'
    printf '  3  Serveur web / reverse proxy\n'
    printf '  4  Node.js / Python\n'
    printf '  5  Pterodactyl / Wings\n'
    printf '  6  KeyHelp\n'
    printf '  a  Audit uniquement\n'
    printf '  q  Quitter\n\n'
    read -r -p 'Votre choix [a] : ' choice
    case "$choice" in
        1) run_profile base ;;
        2) run_profile docker ;;
        3) run_profile web ;;
        4) run_profile app ;;
        5) run_profile pterodactyl ;;
        6) run_profile keyhelp ;;
        a|A|'') success "Audit termine. Aucune modification appliquee." ;;
        q|Q) exit 0 ;;
        *) warn "Choix invalide."; choose_profile ;;
    esac
}

main() {
    require_root
    load_os
    show_splash
    START_TIME=$(date +%s)
    detect_services
    progress 1 3 "Detection de l'environnement"
    show_audit
    progress 2 3 "Audit et estimation des risques"
    if [[ "${1:-}" == "--audit" || "${1:-}" == "--dry-run" ]]; then
        success "Mode audit : aucune modification appliquee."
        progress 3 3 "Rapport genere"
        return 0
    fi
    choose_profile
    progress 3 3 "Session terminee"
    info "Rapport disponible : $REPORT_FILE"
}

main "$@"
