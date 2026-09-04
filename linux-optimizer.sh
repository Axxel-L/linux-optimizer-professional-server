#!/usr/bin/env bash
# =============================================================================
# AxelL - Linux Optimmisateur - lanceur Debian
# -----------------------------------------------------------------------------
# Audit en lecture seule puis application d'un profil d'optimisation, avec un
# tableau de bord terminal mis a jour en direct (etapes, pourcentage, chrono).
#
# Usage :
#   sudo ./linux-optimizer.sh                 mode interactif (menu)
#   sudo ./linux-optimizer.sh --full          optimisation complete automatique
#   sudo ./linux-optimizer.sh --audit         rapport seul, aucune modification
#   sudo ./linux-optimizer.sh --help
#
# Interface :
#   - Ecran d'accueil (splash) avec logo, nom et version apres le nettoyage
#     du terminal.
#   - Chaque transition d'etape redessine l'ecran : liste des etapes avec
#     etat en direct (en attente / en cours / fait / ignore / echec),
#     pourcentage global, barre de progression et temps ecoule.
#     Ni spinner ni estimation.
#   - Sortie non-TTY (journal, pipe, CI) : lignes de texte simples, sans
#     aucun code d'echappement.
#
# Journalisation :
#   Chaque evenement est ecrit, horodate et sans ANSI, dans :
#     /var/log/linux-optimizer/report-<date>.txt
#
# Rendu du profil :
#   Le moteur (scripts/debian-optimizer.sh) est source apres le choix du
#   profil (variables PROFILE_MODE / AUTO_APPLY), puis ses etapes STEP_FUNCS
#   sont executees une par une. Convention des codes de retour :
#     0 = succes   1 = erreur (abandon)   2 = etape ignoree/declinee.
#
# Variables d'environnement :
#   NO_COLOR=1  desactive les couleurs.
# =============================================================================
set -Eeuo pipefail

readonly APP_NAME="AxelL - Linux Optimmisateur"
readonly APP_VERSION="2.2.0"
readonly APP_LICENSE="MIT"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENGINE="${SCRIPT_DIR}/scripts/debian-optimizer.sh"
readonly LOG_DIR="/var/log/linux-optimizer"
readonly REPORT_FILE="${LOG_DIR}/report-$(date +%Y%m%d-%H%M%S).txt"
# Attention : pas de substitution de commande ici, le stdout y est un pipe et
# -t 1 serait toujours faux.
if [[ -t 1 ]]; then readonly IS_TTY=1; else readonly IS_TTY=0; fi
readonly IS_UTF8=$([[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]-8* ]] && printf 1 || printf 0)

# --- Couleurs (terminal uniquement, NO_COLOR respecte) -----------------------
if [[ "$IS_TTY" == 1 && -z "${NO_COLOR:-}" ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_CYAN=$'\033[36m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_RED=$'\033[31m'
    readonly C_DIM=$'\033[2m'
else
    readonly C_RESET=""
    readonly C_CYAN=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_RED=""
    readonly C_DIM=""
fi

# --- Jeu de caracteres (fallback ASCII hors locale UTF-8) ---------------------
if [[ "$IS_UTF8" == 1 ]]; then
    readonly S_DONE='✓'; readonly S_RUN='▶'; readonly S_FAIL='✗'
    readonly S_SKIP='–'; readonly S_WAIT='·'
    readonly S_FILL='█'; readonly S_EMPTY='░'; readonly S_RULE='━'
    readonly S_TL='┌'; readonly S_TR='┐'; readonly S_BL='└'; readonly S_BR='┘'
    readonly S_VL='│'
else
    readonly S_DONE='v'; readonly S_RUN='>'; readonly S_FAIL='x'
    readonly S_SKIP='-'; readonly S_WAIT='.'
    readonly S_FILL='#'; readonly S_EMPTY='.'; readonly S_RULE='='
    readonly S_TL='+'; readonly S_TR='+'; readonly S_BL='+'; readonly S_BR='+'
    readonly S_VL='|'
fi

char_rule() {
    local n="$1" ch="$2" out=""
    while (( n-- > 0 )); do out+="$ch"; done
    printf '%s' "$out"
}
readonly UI_RULE="$(char_rule 70 "$S_RULE")"
readonly UI_RULE_SMALL="$(char_rule 34 "$S_RULE")"

# --- Etat global de l'interface -------------------------------------------------
DASH=0            # 1 = tableau de bord plein ecran (profil en cours sur TTY)
AUTO=0            # 1 = mode automatique (confirmations sautees, sauf force)
PROFILE=""        # profil actif (fixe par le moteur au moment du source)
START_TIME=0
CURRENT_STEP_INDEX=-1
CURRENT_STEP_PROGRESS=0
TIMER_ROW=0
readonly NOTES_FILE="$(mktemp /tmp/linux-optimizer-notes.XXXXXX 2>/dev/null || mktemp)"
readonly WARN_FILE="$(mktemp /tmp/linux-optimizer-warn.XXXXXX 2>/dev/null || mktemp)"
readonly PROGRESS_FILE="$(mktemp /tmp/linux-optimizer-progress.XXXXXX 2>/dev/null || mktemp)"
REPORT_ERROR_RECORDED=0
REPORT_ANNOUNCE=1
declare -a STEP_STATES=()

# --- Sortie console / journal ---------------------------------------------------
mkdir -p "$LOG_DIR" 2>/dev/null || true

cleanup() {
    rm -f "$NOTES_FILE" "$WARN_FILE" "$PROGRESS_FILE"
}

report_open() {
    [[ -e "$REPORT_FILE" ]] && return 0
    mkdir -p "$LOG_DIR" 2>/dev/null || return 1
    : > "$REPORT_FILE" 2>/dev/null
}

report_line() {
    report_open || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$REPORT_FILE" 2>/dev/null || true
}

record_runtime_error() {
    local rc="$1"
    (( REPORT_ERROR_RECORDED )) && return 0
    REPORT_ERROR_RECORDED=1
    report_line "[CRASH] Code retour : $rc"
    report_line "[CRASH] Commande : ${BASH_COMMAND:-inconnue}"
    report_line "[CRASH] Contexte : ${BASH_SOURCE[1]:-inconnu}:${BASH_LINENO[0]:-0}"
}

on_error() {
    local rc=$?
    (( rc == 2 )) && return 0
    record_runtime_error "$rc"
    return "$rc"
}

on_exit() {
    local rc=$?
    if (( ! REPORT_ANNOUNCE )); then
        cleanup
        return "$rc"
    elif (( rc != 0 )); then
        record_runtime_error "$rc"
        printf '%s\n' "[FAIL] Echec du script (code $rc). Rapport : $REPORT_FILE" >&2
    else
        printf '%s\n' "Rapport disponible : $REPORT_FILE"
    fi
    cleanup
    return "$rc"
}

trap on_error ERR
trap on_exit EXIT

out() { printf '%b\n' "$*"; }

info() {
    report_line "[INFO] $*"
    (( DASH )) || out "${C_CYAN}[INFO]${C_RESET} $*"
}

note() {
    report_line "[INFO] $*"
    if (( DASH )); then
        printf '%s\n' "$*" >> "$NOTES_FILE"
    else
        out "${C_DIM}[....]${C_RESET} $*"
    fi
}

success() {
    report_line "[ OK ] $*"
    (( DASH )) || out "${C_GREEN}[ OK ]${C_RESET} $*"
}

warn() {
    report_line "[WARN] $*"
    printf '%s\n' "$*" >> "$WARN_FILE"
    (( DASH )) || out "${C_YELLOW}[WARN]${C_RESET} $*"
}

error() {
    report_line "[FAIL] $*"
    if (( DASH )); then
        printf '%s\n' "$*" >> "$NOTES_FILE"
    else
        out "${C_RED}[FAIL]${C_RESET} $*" >&2
    fi
}

_prompt() {
    if [[ -w /dev/tty ]]; then
        printf '%s' "$1" > /dev/tty
    else
        printf '%s' "$1"
    fi
}

# --- Questions ---------------------------------------------------------------
# ask "message" : reponse y/N (defaut N), retour 0 si oui.
ask() {
    local msg="$1" answer=""
    if (( DASH )); then ui_render; fi
    _prompt "$(printf '\n%b%s [y/N]%b ' "$C_YELLOW" "$msg" "$C_RESET")"
    read -r answer || answer=""
    [[ "$answer" =~ ^[yY]$ ]]
}

# confirm "message" [force] : en mode AUTO, seule une confirmation forcee
# (changements sensibles comme le DNS) est conservee.
confirm() {
    local msg="${1:-Confirmer ?}" force="${2:-0}"
    if [[ "$AUTO" == 1 && "$force" != 1 ]]; then
        return 0
    fi
    ask "$msg"
}

# prompt_read "texte" : imprime un texte puis lit une ligne (menus).
prompt_read() {
    local text="$1" answer=""
    _prompt "$text"
    read -r answer || answer=""
    printf '%s\n' "$answer"
}

# --- Rendu du tableau de bord ------------------------------------------------
elapsed_text() {
    local s=$(( $(date +%s) - START_TIME ))
    printf '%02dm%02ds' $(( s / 60 )) $(( s % 60 ))
}

status_span() {
    local state="$1"
    case "$state" in
        done)    printf '%b[%s]%b' "$C_GREEN" "$S_DONE" "$C_RESET" ;;
        running) printf '%b[%s]%b' "$C_CYAN" "$S_RUN" "$C_RESET" ;;
        fail)    printf '%b[%s]%b' "$C_RED" "$S_FAIL" "$C_RESET" ;;
        skip)    printf '%b[%s]%b' "$C_YELLOW" "$S_SKIP" "$C_RESET" ;;
        *)       printf '%b[%s]%b' "$C_DIM" "$S_WAIT" "$C_RESET" ;;
    esac
}

ui_render() {
    [[ "$IS_TTY" == 1 ]] || return 0
    local i total="${#STEP_FUNCS[@]}" done_count=0 bar filled empty pct
    local note_line progress_file_value
    TIMER_ROW=$(( 7 + total ))
    printf '\033[2J\033[H'
    out "${C_CYAN}${UI_RULE}${C_RESET}"
    out "  ${C_GREEN}${APP_NAME}${C_RESET}   ${C_DIM}${OS_LABEL:-Debian} | v${APP_VERSION} | ${APP_LICENSE}${C_RESET}"
    if [[ -n "${PROFILE:-}" ]]; then
        out "  ${C_DIM}Profil : ${PROFILE}${C_RESET}"
    fi
    out "${C_CYAN}${UI_RULE}${C_RESET}"
    out ""
    for (( i = 0; i < total; i++ )); do
        case "${STEP_STATES[$i]}" in
            done|skip|fail) done_count=$((done_count + 1)) ;;
        esac
        printf '  %s  %02d/%02d  %s\n' "$(status_span "${STEP_STATES[$i]}")" \
            "$(( i + 1 ))" "$total" "${STEP_LABELS[$i]}"
    done
    pct=$(( done_count * 100 / total ))
    if (( CURRENT_STEP_INDEX >= 0 && CURRENT_STEP_PROGRESS > 0 )); then
        pct=$(( (done_count * 100 + CURRENT_STEP_PROGRESS) / total ))
    fi
    progress_file_value="$(< "$PROGRESS_FILE")"
    if [[ "$progress_file_value" =~ ^[0-9]+$ ]] && (( CURRENT_STEP_INDEX >= 0 )); then
        pct=$(( (done_count * 100 + progress_file_value) / total ))
    fi
    filled=$(( pct * 34 / 100 ))
    empty=$(( 34 - filled ))
    bar="$(char_rule "$filled" "$S_FILL")$(char_rule "$empty" "$S_EMPTY")"
    out ""
    out "  ${C_CYAN}${bar}${C_RESET}  ${C_GREEN}${pct}%${C_RESET}   ${C_DIM}$(elapsed_text)${C_RESET}"
    if [[ -s "$NOTES_FILE" ]]; then
        out ""
        out "  ${C_DIM}${UI_RULE_SMALL} details ${UI_RULE_SMALL}${C_RESET}"
        while IFS= read -r note_line || [[ -n "$note_line" ]]; do
            out "  ${C_DIM}${note_line}${C_RESET}"
        done < "$NOTES_FILE"
    fi
}

refresh_timer() {
    [[ "$IS_TTY" == 1 && "$TIMER_ROW" -gt 0 ]] || return 0
    printf '\0337\033[%d;1H\033[2K  %b%s%b\0338' \
        "$TIMER_ROW" "$C_CYAN" "$(elapsed_text)" "$C_RESET"
}

# --- Splash d'accueil -------------------------------------------------------
readonly SPLASH_W=60

splash_row() {
    # ligne centree dans le cadre : texte brut + code couleur eventuel
    local text="$1" color="${2:-}" len pad_l pad_r
    len=$(printf '%s' "$text" | wc -m | tr -d ' ')
    pad_l=$(( (SPLASH_W - len) / 2 ))
    pad_r=$(( SPLASH_W - len - pad_l ))
    printf '%b%s%b%s%b%s%b%s%b%s%b\n' \
        "$C_CYAN" "$S_VL" "$C_RESET" "$(char_rule "$pad_l" ' ')" \
        "$color" "$text" "$C_RESET" "$(char_rule "$pad_r" ' ')" \
        "$C_CYAN" "$S_VL" "$C_RESET"
}

show_splash() {
    [[ "$IS_TTY" == 1 ]] || return 0
    # Lettres remplacees par le bloc du jeu de caracteres courant (█ ou #).
    local -a a=( ' @@ ' '@  @' '@@@@' '@  @' '@  @' )
    local -a x=( '@  @' ' @ @' '  @ ' ' @ @' '@  @' )
    local -a e=( '@@@@' '@   ' '@@@ ' '@   ' '@@@@' )
    local -a l=( '@   ' '@   ' '@   ' '@   ' '@@@@' )
    local i row
    out "${C_CYAN}${S_TL}$(char_rule "$SPLASH_W" "$S_RULE")${S_TR}${C_RESET}"
    splash_row ""
    for (( i = 0; i < 5; i++ )); do
        row="${a[$i]}  ${x[$i]}  ${e[$i]}  ${l[$i]}"
        splash_row "${row//@/$S_FILL}" "$C_GREEN"
    done
    splash_row ""
    splash_row "$APP_NAME" "$C_GREEN"
    splash_row "Audit et optimisation prudente d'un serveur Debian 13" "$C_DIM"
    splash_row "v$APP_VERSION | $APP_LICENSE" "$C_CYAN"
    splash_row ""
    out "${C_CYAN}${S_BL}$(char_rule "$SPLASH_W" "$S_RULE")${S_BR}${C_RESET}"
    out ""
}

# --- Audit et detection ----------------------------------------------------------
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
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-$OS_ID}"
    OS_LABEL="Debian ${OS_VERSION}"
    [[ -n "${VERSION_CODENAME:-}" ]] && OS_LABEL+=" (${VERSION_CODENAME})"
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

audit_section() {
    out ""
    out "${C_CYAN}$1${C_RESET}"
    report_line "$1"
}

audit_item() {
    printf '  %-15s: %s\n' "$1" "$2"
    report_line "  $1: $2"
}

show_audit() {
    local memory swap kernel ports
    memory=$(awk '/MemTotal:/ {printf "%.1f GiB", $2 / 1024 / 1024}' /proc/meminfo)
    swap=$(awk '/SwapTotal:/ {printf "%.1f GiB", $2 / 1024 / 1024}' /proc/meminfo)
    kernel=$(uname -r)
    ports=$(ss -H -lntu 2>/dev/null | awk '{print $5}' | sed 's/.*://' | sort -n -u | paste -sd, -)
    audit_section "AUDIT PREALABLE (lecture seule)"
    audit_item "OS" "$OS_NAME ($OS_VERSION)"
    audit_item "Architecture" "$(uname -m)"
    audit_item "Noyau" "$kernel"
    audit_item "Memoire / swap" "$memory / $swap"
    audit_item "BBR" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf 'indisponible')"
    audit_item "Ports en ecoute" "${ports:-aucun detecte}"
    audit_item "Services" "${DETECTED_SERVICES[*]:-aucun detecte}"
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

# --- Menus -------------------------------------------------------------------
choose_roles() {
    local roles="base" answer
    out ""
    out "${C_CYAN}CONFIGURATION DU SERVEUR${C_RESET}"
    out "Repondez y/n pour chaque role detecte ou utilise sur ce serveur."
    answer=$(prompt_read "Docker / conteneurs [n] : ")
    [[ "$answer" =~ ^[yY]$ ]] && roles+=",docker"
    answer=$(prompt_read "Web / Nginx / Apache / PHP [n] : ")
    [[ "$answer" =~ ^[yY]$ ]] && roles+=",web"
    answer=$(prompt_read "Applications Node.js / Python [n] : ")
    [[ "$answer" =~ ^[yY]$ ]] && roles+=",app"
    answer=$(prompt_read "Pterodactyl / Wings [n] : ")
    [[ "$answer" =~ ^[yY]$ ]] && roles+=",pterodactyl"
    answer=$(prompt_read "KeyHelp [n] : ")
    [[ "$answer" =~ ^[yY]$ ]] && roles+=",keyhelp"
    start_profile "$roles" 0
}

choose_mode() {
    local choice
    out ""
    out "${C_CYAN}MODE D OPTIMISATION${C_RESET}"
    out "  1  Optimisation complete automatique"
    out "  2  Choisir les roles du serveur"
    out "  3  Audit uniquement"
    out "  q  Quitter"
    choice=$(prompt_read "Votre choix [3] : ")
    case "$choice" in
        1) start_profile full 1 ;;
        2) choose_roles ;;
        3|'') finish_audit ;;
        q|Q) exit 0 ;;
        *) warn "Choix invalide."; choose_mode ;;
    esac
}

# --- Execution du profil -------------------------------------------------------
finish_audit() {
    success "Audit termine. Aucune modification appliquee."
    info "Rapport disponible : $REPORT_FILE"
}

start_profile() {
    local profile="$1" auto="$2" profile_text
    if [[ "$OS_ID" != debian ]]; then
        error "Cette version cible Debian. Systeme detecte : $OS_NAME."
        exit 1
    fi
    if [[ ! -f "$ENGINE" ]]; then
        error "Moteur Debian introuvable dans le depot local ($ENGINE)."
        exit 1
    fi
    PROFILE_MODE="$profile"
    AUTO_APPLY="$auto"
    # shellcheck source=scripts/debian-optimizer.sh
    source "$ENGINE"
    AUTO="$AUTO_APPLY"
    PROFILE="$PROFILE_MODE"
    report_line "== Profil : $PROFILE (mode automatique: $([ "$AUTO" == 1 ] && printf 'oui' || printf 'non'))"
    if [[ "$AUTO" != 1 ]]; then
        profile_text="$(profile_description 2>/dev/null || printf '%s' "$PROFILE")"
        if ! ask "Appliquer le profil ${PROFILE} ? (${profile_text})"; then
            warn "Operation annulee."
            info "Rapport disponible : $REPORT_FILE"
            exit 0
        fi
    fi
    DASH="$IS_TTY"
    run_profile_steps
    DASH=0
}

run_profile_steps() {
    local i rc ok=0 skipped=0 total="${#STEP_FUNCS[@]}" wl
    START_TIME=$(date +%s)
    : > "$NOTES_FILE"
    : > "$WARN_FILE"
    for (( i = 0; i < total; i++ )); do
        STEP_STATES[$i]="pending"
    done
    CURRENT_STEP_INDEX=-1
    CURRENT_STEP_PROGRESS=0
    report_line "== Debut du profil (${total} etapes)"
    (( DASH )) && ui_render
    for (( i = 0; i < total; i++ )); do
        STEP_STATES[$i]="running"
        CURRENT_STEP_INDEX=$i
        CURRENT_STEP_PROGRESS=0
        report_line "== Etape $(( i + 1 ))/${total} : ${STEP_LABELS[$i]}"
        if (( DASH )); then
            ui_render
        else
            info "Etape $(( i + 1 ))/${total} : ${STEP_LABELS[$i]}"
        fi
        : > "$NOTES_FILE"
        : > "$PROGRESS_FILE"
        # Sous-shell : isole l'etape, conserve set -e et laisse le lanceur
        # recuperer son code retour sans sortir lui-meme.
        set +e
        trap - ERR
        ( trap - ERR; set -e; "${STEP_FUNCS[$i]}" ) &
        local step_pid=$!
        while kill -0 "$step_pid" 2>/dev/null; do
            sleep 0.2
            (( DASH )) && refresh_timer
        done
        wait "$step_pid"
        rc=$?
        trap on_error ERR
        set -e
        : > "$PROGRESS_FILE"
        CURRENT_STEP_PROGRESS=100
        case "$rc" in
            0)
                STEP_STATES[$i]="done"
                ok=$((ok + 1))
                report_line "== OK : ${STEP_LABELS[$i]}"
                (( DASH )) || success "${STEP_LABELS[$i]} : termine."
                ;;
            2)
                STEP_STATES[$i]="skip"
                skipped=$((skipped + 1))
                report_line "== IGNORE : ${STEP_LABELS[$i]}"
                (( DASH )) || warn "${STEP_LABELS[$i]} : ignore."
                ;;
            *)
                STEP_STATES[$i]="fail"
                report_line "== FAIL : ${STEP_LABELS[$i]} (code $rc)"
                (( DASH )) && ui_render
                out ""
                out "${C_RED}Echec de l'etape $(( i + 1 ))/${total} : ${STEP_LABELS[$i]}.${C_RESET}"
                out "${C_RED}Profil interrompu. Journal : $REPORT_FILE${C_RESET}"
                exit 1
                ;;
        esac
        CURRENT_STEP_INDEX=-1
        CURRENT_STEP_PROGRESS=0
        (( DASH )) && ui_render
    done
    kernel_reboot_notice
    (( DASH )) && ui_render
    out ""
    out "${C_GREEN}Profil ${PROFILE} termine : ${ok}/${total} etapes reussies, ${skipped} ignoree(s).${C_RESET}"
    report_line "== Profil termine : ${ok}/${total} ok, ${skipped} ignoree(s)"
    if (( DASH )) && [[ -s "$WARN_FILE" ]]; then
        out ""
        out "${C_YELLOW}Avertissements :${C_RESET}"
        while IFS= read -r wl || [[ -n "$wl" ]]; do
            out "  ${C_YELLOW}-${C_RESET} ${wl}"
        done < "$WARN_FILE"
    fi
    out ""
    info "Rapport disponible : $REPORT_FILE"
    return 0
}

# --- Point d'entree -------------------------------------------------------------
usage() {
    cat <<EOF
${APP_NAME} v${APP_VERSION} - audit et optimisation prudente d'un serveur Debian.

Usage :
  sudo $0                mode interactif (menu)
  sudo $0 --full         optimisation complete automatique
  sudo $0 --audit        audit seul (aucune modification)
  sudo $0 --help         cette aide

Variables : NO_COLOR=1 desactive les couleurs.
Journal    : ${LOG_DIR}/report-*.txt
EOF
}

main() {
    [[ "$IS_TTY" == 1 ]] && printf '\033[2J\033[H'
    case "${1:-}" in
        -h|--help) REPORT_ANNOUNCE=0; usage; exit 0 ;;
    esac
    require_root
    load_os
    report_line "== ${APP_NAME} v${APP_VERSION} (${APP_LICENSE})"
    report_line "== OS : ${OS_NAME} ${OS_VERSION} - noyau $(uname -r) - demarrage $(date '+%Y-%m-%d %H:%M:%S')"
    show_splash
    detect_services
    show_audit
    case "${1:-}" in
        --audit|--dry-run) finish_audit ;;
        --full) start_profile full 1 ;;
        *) choose_mode ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
