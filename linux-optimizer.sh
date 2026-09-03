#!/usr/bin/env bash

set -o pipefail

readonly APP_NAME="AxelL - Linux Optimmisateur"
readonly APP_VERSION="2.0.1"
readonly APP_LICENSE="MIT"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log/linux-optimizer"
readonly REPORT_FILE="${LOG_DIR}/report-$(date +%Y%m%d-%H%M%S).txt"
readonly IS_TTY="$( [[ -t 1 ]] && printf 'yes' || printf 'no' )"

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
    if [[ "$IS_TTY" == yes ]]; then
        printf '\033[2J\033[H'
    fi
    printf '%b\n' "$C_CYAN"
    printf '  +--------------------------------------------------------+\n'
    printf '  |  %-52s  |\n' "$APP_NAME"
    printf '  |  %-52s  |\n' "Professional server optimizer"
    printf '  |  Version %-8s | Licence %-31s |\n' "$APP_VERSION" "$APP_LICENSE"
    printf '  +--------------------------------------------------------+\n'
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
    width=28
    filled=$((current * width / total))
    empty=$((width - filled))
    if [[ "$IS_TTY" == yes ]]; then
        printf '\033[2K\r%b  [%s%s]%b %3d%%  %-31s  %02dm%02ds  ETA %02dm%02ds' "$C_CYAN" "$(printf '%*s' "$filled" '' | tr ' ' '=')" "$(printf '%*s' "$empty" '')" "$C_RESET" "$((current * 100 / total))" "$label" "$((elapsed / 60))" "$((elapsed % 60))" "$((eta / 60))" "$((eta % 60))"
    else
        printf '[%3d%%] %-31s (%02dm%02ds)\n' "$((current * 100 / total))" "$label" "$((elapsed / 60))" "$((elapsed % 60))"
    fi
    if (( current == total || IS_TTY != yes )); then printf '\n'; fi
}

animate_progress() {
    local label="$1" current="$2" total="$3" frame=0 frames='|/-\\'
    if [[ "$IS_TTY" != yes ]]; then
        progress "$current" "$total" "$label"
        return
    fi
    while (( frame < 8 )); do
        progress "$current" "$total" "$label ${frames:frame%4:1}"
        sleep 0.08
        ((frame += 1))
    done
    progress "$current" "$total" "$label"
}

run_profile() {
    local profile="$1" auto_apply="${2:-0}"
    if [[ "$OS_ID" != debian ]]; then
        error "Cette version complete cible Debian. Systeme detecte : $OS_NAME."
        warn "Les scripts historiques des autres distributions ne sont plus executes automatiquement."
        return 1
    fi
    if [[ ! -f "$SCRIPT_DIR/scripts/debian-optimizer.sh" ]]; then
        error "Profil Debian introuvable dans le depot local."
        return 1
    fi
    PROFILE_MODE="$profile" AUTO_APPLY="$auto_apply" bash "$SCRIPT_DIR/scripts/debian-optimizer.sh"
}

choose_roles() {
    local roles="base" choice
    printf '\n%bCONFIGURATION DU SERVEUR%b\n' "$C_CYAN" "$C_RESET"
    printf 'Repondez y/n pour chaque role detecte ou utilise sur ce serveur.\n\n'
    read -r -p 'Docker / conteneurs [n] : ' choice
    [[ "$choice" =~ ^[yY]$ ]] && roles+=",docker"
    read -r -p 'Web / Nginx / Apache / PHP [n] : ' choice
    [[ "$choice" =~ ^[yY]$ ]] && roles+=",web"
    read -r -p 'Applications Node.js / Python [n] : ' choice
    [[ "$choice" =~ ^[yY]$ ]] && roles+=",app"
    read -r -p 'Pterodactyl / Wings [n] : ' choice
    [[ "$choice" =~ ^[yY]$ ]] && roles+=",pterodactyl"
    read -r -p 'KeyHelp [n] : ' choice
    [[ "$choice" =~ ^[yY]$ ]] && roles+=",keyhelp"
    printf '\n'
    info "Roles selectionnes : $roles"
    run_profile "$roles" 0
}

choose_mode() {
    local choice
    printf '\n%bMODE D OPTIMISATION%b\n' "$C_CYAN" "$C_RESET"
    printf '  1  Optimisation complete automatique\n'
    printf '  2  Choisir les roles du serveur\n'
    printf '  3  Audit uniquement\n'
    printf '  q  Quitter\n\n'
    read -r -p 'Votre choix [3] : ' choice
    case "$choice" in
        1) run_profile full 1 ;;
        2) choose_roles ;;
        3|'') success "Audit termine. Aucune modification appliquee." ;;
        q|Q) exit 0 ;;
        *) warn "Choix invalide."; choose_mode ;;
    esac
}

main() {
    require_root
    load_os
    show_splash
    START_TIME=$(date +%s)
    animate_progress "Detection de l'environnement" 1 3
    detect_services
    show_audit
    animate_progress "Audit et estimation des risques" 2 3
    if [[ "${1:-}" == "--audit" || "${1:-}" == "--dry-run" ]]; then
        success "Mode audit : aucune modification appliquee."
        animate_progress "Rapport genere" 3 3
        return 0
    fi
    if [[ "${1:-}" == "--full" ]]; then
        run_profile full 1 || error "Le profil automatique a rencontre une erreur. Consultez le journal."
    else
        choose_mode
    fi
    animate_progress "Session terminee" 3 3
    info "Rapport disponible : $REPORT_FILE"
}

main "$@"
