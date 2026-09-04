#!/usr/bin/env bash
# =============================================================================
# AxelL - Migration interactive Debian vers la prochaine stable
# =============================================================================
set -Eeuo pipefail

readonly LOG_DIR="/var/log/linux-optimizer"
readonly REPORT_FILE="${LOG_DIR}/release-upgrade-$(date +%Y%m%d-%H%M%S).txt"
readonly BACKUP_DIR="/var/backups/linux-optimizer/release-$(date +%Y%m%d-%H%M%S)"
REPORT_ERROR_RECORDED=0

mkdir -p "$LOG_DIR" 2>/dev/null || true

report_line() {
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$REPORT_FILE" 2>/dev/null || true
}

record_error() {
    local rc="${1:-$?}"
    (( REPORT_ERROR_RECORDED )) && return 0
    REPORT_ERROR_RECORDED=1
    report_line "[CRASH] Code retour : $rc"
    report_line "[CRASH] Commande : ${BASH_COMMAND:-inconnue}"
    report_line "[CRASH] Contexte : ${BASH_SOURCE[1]:-inconnu}:${BASH_LINENO[0]:-0}"
}

on_error() {
    local rc=$?
    record_error "$rc"
    return "$rc"
}

on_exit() {
    local rc=$?
    if (( rc != 0 )); then
        record_error "$rc"
        printf '[FAIL] Migration interrompue (code %s). Rapport : %s\n' "$rc" "$REPORT_FILE" >&2
    else
        printf 'Rapport disponible : %s\n' "$REPORT_FILE"
    fi
    return "$rc"
}

trap on_error ERR
trap on_exit EXIT

info() {
    report_line "[INFO] $*"
    printf '[INFO] %s\n' "$*"
}

warn() {
    report_line "[WARN] $*"
    printf '[WARN] %s\n' "$*"
}

fail() {
    report_line "[FAIL] $*"
    printf '[FAIL] %s\n' "$*" >&2
}

ask() {
    local question="$1" answer=""
    printf '\n[?] %s [y/N] : ' "$question" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    [[ "$answer" =~ ^[yY]$ ]]
}

run_logged() {
    local command_text="$*"
    report_line "[CMD] $command_text"
    set +e
    "$@" 2>&1 | tee -a "$REPORT_FILE"
    local command_rc=${PIPESTATUS[0]}
    set -e
    return "$command_rc"
}

is_lxc_container() {
    local container_type=""
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        container_type=$(systemd-detect-virt --container 2>/dev/null || true)
        [[ "$container_type" == lxc ]] && return 0
    fi
    if [[ -r /run/systemd/container ]] && [[ "$(< /run/systemd/container)" == lxc ]]; then
        return 0
    fi
    grep -qaE '(^|/)(lxc|lxc\.payload)(/|$)' /proc/1/cgroup 2>/dev/null
}

load_os() {
    [[ -r /etc/os-release ]] || { fail "/etc/os-release est introuvable."; return 1; }
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == debian ]] || { fail "Cette migration est reservee a Debian."; return 1; }
    CURRENT_VERSION="${VERSION_ID:-}"
    CURRENT_CODENAME="${VERSION_CODENAME:-}"
    [[ "$CURRENT_VERSION" =~ ^[0-9]+$ && -n "$CURRENT_CODENAME" ]] || {
        fail "Version Debian ou codename actuel introuvable."
        return 1
    }
}

discover_target() {
    local metadata_file official_version official_codename
    metadata_file=$(mktemp /tmp/linux-optimizer-stable.XXXXXX)
    if command -v curl >/dev/null 2>&1; then
        curl --fail --silent --show-error --max-time 10 \
            https://deb.debian.org/debian/dists/stable/Release > "$metadata_file" 2>/dev/null || {
            rm -f "$metadata_file"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$metadata_file" --timeout=10 https://deb.debian.org/debian/dists/stable/Release || {
            rm -f "$metadata_file"
            return 1
        }
    else
        rm -f "$metadata_file"
        return 1
    fi
    official_version=$(awk -F': ' '$1 == "Version" {print $2; exit}' "$metadata_file")
    official_version="${official_version%%.*}"
    official_codename=$(awk -F': ' '$1 == "Codename" {print $2; exit}' "$metadata_file")
    rm -f "$metadata_file"
    [[ "$official_version" =~ ^[0-9]+$ && -n "$official_codename" ]] || return 1
    if [[ -z "$TARGET_VERSION" && -z "$TARGET_CODENAME" ]]; then
        TARGET_VERSION="$official_version"
        TARGET_CODENAME="$official_codename"
        return 0
    fi
    [[ "$TARGET_VERSION" == "$official_version" && "$TARGET_CODENAME" == "$official_codename" ]]
}

validate_target() {
    discover_target || {
        fail "Impossible de confirmer la stable Debian officielle ou la cible fournie ne correspond pas."
        return 1
    }
    [[ "$TARGET_VERSION" =~ ^[0-9]+$ && -n "$TARGET_CODENAME" ]] || {
        fail "Cible Debian invalide."
        return 1
    }
    (( TARGET_VERSION == CURRENT_VERSION + 1 )) || {
        fail "Seule la stable Debian suivante est autorisee (${CURRENT_VERSION} vers ${TARGET_VERSION})."
        return 1
    }
    [[ "$TARGET_CODENAME" != "$CURRENT_CODENAME" ]] || {
        fail "Le codename cible est identique au codename actuel."
        return 1
    }
}

check_prerequisites() {
    local available_mb apt_state
    (( EUID == 0 )) || { fail "Lancez cette migration avec sudo ou depuis une session root."; return 1; }
    [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]] || {
        fail "Une migration Debian exige un terminal interactif."; return 1;
    }
    if is_lxc_container; then
        fail "Migration refusee dans un conteneur LXC : migrez l'hote ou recreez le conteneur selon la plateforme.";
        return 1
    fi
    command -v apt-get >/dev/null 2>&1 || { fail "apt-get est introuvable."; return 1; }
    available_mb=$(df -Pm / | awk 'NR == 2 {print $4}')
    (( available_mb >= 2048 )) || {
        fail "Espace libre insuffisant : ${available_mb} MiB disponibles, 2048 MiB minimum."; return 1;
    }
    if ! dpkg --audit; then
        fail "Des paquets sont dans un etat incomplet. Corrigez dpkg avant la migration."; return 1
    fi
    if ! apt-get check; then
        fail "L'etat des dependances APT n'est pas sain."; return 1
    fi
    apt_state=$(dpkg-query -W -f='${Status}\n' apt 2>/dev/null || true)
    [[ "$apt_state" == *'install ok installed'* ]] || { fail "Le paquet apt est indisponible."; return 1; }
}

show_audit() {
    info "Version actuelle : Debian ${CURRENT_VERSION} (${CURRENT_CODENAME})"
    info "Version cible : Debian ${TARGET_VERSION} (${TARGET_CODENAME})"
    info "Espace libre racine : $(df -hP / | awk 'NR == 2 {print $4}')"
    info "Paquets installes : $(dpkg-query -f '\${binary:Package}\n' -W 2>/dev/null | wc -l | tr -d ' ')"
    info "Services actifs : $(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}' | paste -sd' ' -)"
    if find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print -quit 2>/dev/null | grep -q .; then
        warn "Des fichiers de depots supplementaires ont ete detectes dans /etc/apt/sources.list.d/."
    fi
}

backup_system() {
    mkdir -p "$BACKUP_DIR"
    cp -a /etc/apt "$BACKUP_DIR/apt"
    dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$BACKUP_DIR/packages.tsv"
    systemctl list-unit-files --state=enabled --no-legend > "$BACKUP_DIR/enabled-services.txt" 2>/dev/null || true
    tar -czf "$BACKUP_DIR/configs.tar.gz" \
        /etc/ssh /etc/systemd /etc/fstab /etc/hosts /etc/hostname /etc/linux-optimizer \
        2>/dev/null || true
    report_line "[INFO] Sauvegardes creees dans $BACKUP_DIR"
    info "Sauvegardes creees dans $BACKUP_DIR"
}

is_official_debian_source() {
    grep -Eiq '^[[:space:]]*(deb|URIs:).*([.]debian[.]org|debian.org)' "$1"
}

prepare_sources() {
    local source_file disabled_file
    if ! is_official_debian_source /etc/apt/sources.list; then
        warn "Aucune source Debian officielle clairement identifiee dans /etc/apt/sources.list."
    fi
    if find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print -quit 2>/dev/null | grep -q .; then
        if ! ask "Desactiver les depots tiers avant la migration ? Ils peuvent etre incompatibles avec Debian ${TARGET_VERSION}."; then
            fail "Les depots tiers doivent etre desactives ou verifies avant la migration."
            return 1
        fi
        while IFS= read -r source_file; do
            [[ -n "$source_file" ]] || continue
            if ! is_official_debian_source "$source_file"; then
                disabled_file="${source_file}.disabled"
                mv "$source_file" "$disabled_file"
                report_line "[INFO] Depot tiers desactive : $source_file -> $disabled_file"
                info "Depot tiers desactive : $source_file"
            fi
        done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print)
    fi
    if ! ask "Remplacer le codename ${CURRENT_CODENAME} par ${TARGET_CODENAME} dans les depots Debian officiels ?"; then
        fail "Modification des depots annulee."
        return 1
    fi
    if [[ -f /etc/apt/sources.list ]]; then
        sed -i "s/${CURRENT_CODENAME}/${TARGET_CODENAME}/g" /etc/apt/sources.list
    fi
    while IFS= read -r source_file; do
        [[ -n "$source_file" ]] || continue
        if is_official_debian_source "$source_file"; then
            sed -i "s/${CURRENT_CODENAME}/${TARGET_CODENAME}/g" "$source_file"
        fi
    done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print)
}

restore_apt_configuration() {
    [[ -d "$BACKUP_DIR/apt" ]] || return 0
    rm -rf /etc/apt
    cp -a "$BACKUP_DIR/apt" /etc/apt
    report_line "[INFO] Configuration APT restauree depuis $BACKUP_DIR/apt"
    info "Configuration APT restauree depuis la sauvegarde."
}

main() {
    TARGET_VERSION=""
    TARGET_CODENAME=""
    while (($#)); do
        case "$1" in
            --target-version) TARGET_VERSION="${2:-}"; shift 2 ;;
            --target-codename) TARGET_CODENAME="${2:-}"; shift 2 ;;
            --help|-h)
                printf 'Usage: sudo %s [--target-version N --target-codename codename]\n' "$0"
                printf 'Sans cible, la stable Debian suivante est detectee automatiquement.\n'
                return 0
                ;;
            *) fail "Option inconnue : $1"; return 1 ;;
        esac
    done
    load_os
    validate_target
    check_prerequisites
    show_audit
    info "Aucune migration ne sera lancee sans confirmation a chaque phase."
    ask "Commencer les sauvegardes avant migration Debian ${TARGET_VERSION} (${TARGET_CODENAME}) ?" || { info "Migration annulee."; return 0; }
    backup_system
    if ! prepare_sources; then
        restore_apt_configuration
        return 1
    fi
    ask "Lancer apt-get update avec les nouveaux depots ?" || { restore_apt_configuration; info "Migration annulee avant apt-get update."; return 0; }
    if ! run_logged apt-get update; then
        restore_apt_configuration
        fail "apt-get update a echoue : les depots precedents ont ete restaures."
        return 1
    fi
    ask "Simuler apt-get full-upgrade avant toute installation ?" || { restore_apt_configuration; info "Migration arretee avant simulation."; return 0; }
    if ! run_logged apt-get -s full-upgrade; then
        restore_apt_configuration
        fail "La simulation full-upgrade a echoue : les depots precedents ont ete restaures."
        return 1
    fi
    info "La simulation est terminee. Les changements seront maintenant proposes par APT."
    ask "Lancer apt-get full-upgrade maintenant ? Cette phase peut supprimer ou remplacer des paquets et interrompre des services." || { info "Migration arretee avant installation."; return 0; }
    if ! run_logged env DEBIAN_FRONTEND=readline apt-get full-upgrade; then
        warn "full-upgrade a echoue apres modification du systeme : aucun rollback complet n'est possible."
        return 1
    fi
    ask "Lancer le nettoyage apt-get autoremove ?" && run_logged apt-get autoremove || info "Nettoyage non execute."
    if [[ "$(. /etc/os-release; printf '%s' "${VERSION_ID:-}")" == "$TARGET_VERSION" ]]; then
        info "Migration Debian terminee. Aucun redemarrage automatique ne sera execute."
        warn "Redemarrez manuellement lorsque vous serez pret, puis relancez l'optimiseur."
    else
        warn "La version Debian cible n'est pas encore detectee. Verifiez APT et terminez la migration manuellement."
        return 1
    fi
}

main "$@"
