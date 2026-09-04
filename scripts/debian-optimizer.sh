#!/usr/bin/env bash
# =============================================================================
# AxelL - Linux Optimmisateur - moteur du profil Debian 13
# -----------------------------------------------------------------------------
# Ce fichier contient TOUTE la logique d'optimisation du profil Debian :
# paquets, sysctl, limites, SSH, pare-feu, swap et DNS Cloudflare.
#
# Deux modes d'utilisation :
#
#   1. Source (normal)  : charge par linux-optimizer.sh, qui fournit l'interface
#      (info/success/warn/error/note/confirm) puis execute les etapes definies
#      dans STEP_FUNCS / STEP_LABELS. Ce moteur est re-source par le lanceur
#      apres le choix du profil (variables PROFILE_MODE / AUTO_APPLY).
#
#   2. Executable seul (debug) : lance le profil ${PROFILE_MODE:-base} avec une
#      sortie texte simple et aucune dependance. Exemple :
#        sudo PROFILE_MODE=web AUTO_APPLY=1 ./scripts/debian-optimizer.sh
#
# Valeurs de retour des etapes (convention partagee avec le lanceur) :
#   0  = etape terminee avec succes
#   1  = erreur (le lanceur interrompt le profil)
#   2  = etape ignoree / declinee (pas une erreur)
#
# Fichiers geres :
#   /etc/linux-optimizer/sysctl-<profil>.conf   reglages noyau
#   /etc/linux-optimizer/limits.conf            limites nofile
#   /etc/linux-optimizer/sshd.conf              durcissement SSH
#   /etc/systemd/resolved.conf.d/99-linux-optimizer-dns.conf (systemd-resolved)
#   /etc/netplan/99-linux-optimizer-dns.yaml    (netplan)
#   /etc/resolvconf/resolv.conf.d/head          (openresolv)
#   /etc/resolv.conf                            (mode statique)
#
# Toute modification est precedee d'une sauvegarde datee (.bak) sur place.
# =============================================================================
set -Eeuo pipefail

# --- Primitives de sortie : le lanceur fournit des versions adaptees a son
# interface graphique quand ce fichier est source. En execution directe, on
# retombe sur une sortie texte simple.
ENGINE_STANDALONE=0
if ! declare -F info >/dev/null 2>&1; then
    ENGINE_STANDALONE=1
    ENGINE_ERROR_RECORDED=0
    ENGINE_LOG_DIR="/var/log/linux-optimizer"
    ENGINE_REPORT_FILE="${ENGINE_LOG_DIR}/report-engine-$(date +%Y%m%d-%H%M%S).txt"
    mkdir -p "$ENGINE_LOG_DIR" 2>/dev/null || true
    engine_report_line() {
        mkdir -p "$ENGINE_LOG_DIR" 2>/dev/null || return 0
        printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$ENGINE_REPORT_FILE" 2>/dev/null || true
    }
    engine_log_diagnostic() {
        local line
        while IFS= read -r line || [[ -n "$line" ]]; do
            engine_report_line "[CMD] $line"
        done
    }
    info()    { engine_report_line "[INFO] $*"; printf '[INFO] %s\n' "$*"; }
    success() { engine_report_line "[ OK ] $*"; printf '[ OK ] %s\n' "$*"; }
    warn()    { engine_report_line "[WARN] $*"; printf '[WARN] %s\n' "$*"; }
    error()   { engine_report_line "[FAIL] $*"; printf '[FAIL] %s\n' "$*" >&2; }
    note()    { engine_report_line "[INFO] $*"; printf '[....] %s\n' "$*"; }
    engine_runtime_error() {
        local rc="${1:-$?}"
        (( ENGINE_ERROR_RECORDED )) && return 0
        ENGINE_ERROR_RECORDED=1
        engine_report_line "[CRASH] Code retour : $rc"
        engine_report_line "[CRASH] Commande : ${BASH_COMMAND:-inconnue}"
        engine_report_line "[CRASH] Contexte : ${BASH_SOURCE[1]:-inconnu}:${BASH_LINENO[0]:-0}"
    }
    engine_exit() {
        local rc=$?
        if (( rc != 0 )); then
            engine_runtime_error "$rc"
            printf '[FAIL] Echec du moteur (code %s). Rapport : %s\n' "$rc" "$ENGINE_REPORT_FILE" >&2
        else
            printf 'Rapport disponible : %s\n' "$ENGINE_REPORT_FILE"
        fi
        return "$rc"
    }
    trap engine_runtime_error ERR
    trap engine_exit EXIT
fi

if ! declare -F confirm >/dev/null 2>&1; then
    # confirm "message" [force] : reponse y/N. force=1 pose la question meme en
    # mode automatique (AUTO_APPLY=1), pour les changements sensibles (DNS).
    confirm() {
        local msg="${1:-Confirmer ?}" force="${2:-0}" answer
        if [[ "${AUTO:-0}" == 1 && "$force" != 1 ]]; then
            return 0
        fi
        printf '%s [y/N] ' "$msg"
        read -r answer || true
        [[ "$answer" =~ ^[yY]$ ]]
    }
fi

# --- Profil courant (relu a chaque source par le lanceur) --------------------
PROFILE="${PROFILE_MODE:-base}"
AUTO="${AUTO_APPLY:-0}"
CONFIG_DIR="/etc/linux-optimizer"
SYSCTL_FILE="${CONFIG_DIR}/sysctl-${PROFILE}.conf"
LIMITS_FILE="${CONFIG_DIR}/limits.conf"
SSH_FILE="${CONFIG_DIR}/sshd.conf"

# --- Etapes du profil (ordre d'execution) -------------------------------------
STEP_LABELS=(
    "Mise a jour du systeme et du noyau"
    "Installation des outils du profil"
    "Reglages noyau et reseau"
    "Limites de fichiers pour les services"
    "Validation et durcissement SSH"
    "Pare-feu et ports"
    "Verification de la swap"
    "DNS Cloudflare (1.1.1.1)"
)
STEP_FUNCS=(
    update_system
    install_base_packages
    apply_sysctl
    apply_limits
    apply_ssh
    apply_firewall
    apply_swap
    apply_dns
)

# --- Helpers ------------------------------------------------------------------

has_role() {
    [[ ",$PROFILE," == *",$1,"* || "$PROFILE" == full ]]
}

backup_file() {
    local file="$1"
    if [[ -e "$file" || -L "$file" ]]; then
        cp -a -- "$file" "${file}.linux-optimizer.$(date +%Y%m%d-%H%M%S).bak"
    fi
}

write_config() {
    local file="$1" content="$2"
    mkdir -p "$CONFIG_DIR"
    backup_file "$file"
    printf '%b\n' "$content" > "$file"
    chmod 0644 "$file"
}

available_sysctl() {
    local key="$1" value="$2"
    if sysctl -q "$key" >/dev/null 2>&1; then
        printf '%s = %s\n' "$key" "$value"
    fi
    return 0
}

# --- Systeme : APT -----------------------------------------------------------

run_apt() {
    local label="$1" output_file line
    shift
    info "Lancement : $label"
    output_file=$(mktemp /tmp/linux-optimizer-apt.XXXXXX)
    if DEBIAN_FRONTEND=noninteractive apt-get -q "$@" >"$output_file" 2>&1; then
        rm -f "$output_file"
        success "$label termine."
        return 0
    fi
    if (( ENGINE_STANDALONE )); then
        engine_log_diagnostic < "$output_file"
    else
        while IFS= read -r line || [[ -n "$line" ]]; do
            report_line "[CMD] $line"
        done < "$output_file"
    fi
    cat "$output_file" >&2
    rm -f "$output_file"
    error "Echec de l'etape APT : $label"
    return 1
}

update_system() {
    run_apt "Mise a jour des index APT" update
    run_apt "Mise a jour des paquets Debian" -y upgrade
    if apt-cache policy linux-image-amd64 2>/dev/null | awk '$1 == "Candidate:" && $2 != "(none)" {found=1} END {exit !found}'; then
        run_apt "Mise a jour du noyau Debian si disponible" -y install --only-upgrade linux-image-amd64 linux-headers-amd64
    else
        warn "Paquet de noyau Debian generique indisponible : noyau actuel conserve."
    fi
}

install_base_packages() {
    local packages=(ca-certificates curl jq htop vim-tiny unzip rsync openssh-client)
    if [[ "$PROFILE" != full ]] && has_role app; then packages+=(python3 python3-venv nodejs npm); fi
    if [[ "$PROFILE" != full ]] && has_role web; then packages+=(nginx); fi
    if [[ "$PROFILE" != full ]] && has_role docker; then packages+=(uidmap); fi
    run_apt "Installation des outils serveur" -y install "${packages[@]}"
}

# --- Noyau et reseau ----------------------------------------------------------

build_sysctl() {
    local file="$SYSCTL_FILE" file_max port_range
    file_max=$(cat /proc/sys/fs/file-max 2>/dev/null || printf '1048576')
    port_range=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null || true)
    {
        printf '# Generated by AxelL Linux Optimmisateur - profile %s\n' "$PROFILE"
        printf '# File: %s - restore: sysctl --load on the dated .bak\n' "$SYSCTL_FILE"
        printf 'fs.file-max = %s\n' "$file_max"

        # Filet de base
        available_sysctl net.core.somaxconn 4096
        available_sysctl net.core.netdev_max_backlog 4096
        available_sysctl net.ipv4.tcp_syncookies 1
        available_sysctl net.ipv4.tcp_slow_start_after_idle 1
        available_sysctl net.ipv4.tcp_keepalive_time 600
        available_sysctl net.ipv4.tcp_keepalive_intvl 60
        available_sysctl net.ipv4.tcp_keepalive_probes 5
        available_sysctl net.ipv4.conf.default.rp_filter 2
        available_sysctl net.ipv4.conf.all.rp_filter 2
        available_sysctl vm.swappiness 10
        available_sysctl vm.vfs_cache_pressure 100

        # Connexions TCP plus soutenues (valeurs prudentes, exposees par le noyau)
        available_sysctl net.ipv4.tcp_max_syn_backlog 8192
        available_sysctl net.ipv4.tcp_fin_timeout 30
        available_sysctl net.ipv4.tcp_tw_reuse 1
        available_sysctl net.ipv4.tcp_mtu_probing 1
        available_sysctl net.ipv4.tcp_rmem "4096 87380 4194304"
        available_sysctl net.ipv4.tcp_wmem "4096 16384 4194304"
        if [[ "$port_range" == "32768 60999" ]]; then
            available_sysctl net.ipv4.ip_local_port_range "1024 65535"
        else
            printf '# net.ipv4.ip_local_port_range deja personnalise (%s) : conserve\n' "$port_range"
        fi

        # BBR + fq uniquement si le noyau les expose
        if sysctl -n net.ipv4.tcp_allowed_congestion_control 2>/dev/null | tr ' ' '\n' | grep -qx bbr; then
            available_sysctl net.ipv4.tcp_congestion_control bbr
        else
            warn "BBR indisponible : conservation de l'algorithme TCP actuel."
        fi
        if sysctl -q net.core.default_qdisc >/dev/null 2>&1; then
            available_sysctl net.core.default_qdisc fq
        fi

        # Roles
        if has_role docker; then
            available_sysctl fs.inotify.max_user_instances 1024
            available_sysctl fs.inotify.max_user_watches 524288
        fi
        if has_role web; then
            available_sysctl net.core.somaxconn 8192
        fi
        if has_role pterodactyl; then
            available_sysctl net.ipv4.ip_forward 1
            available_sysctl net.ipv6.conf.all.forwarding 1
        fi
    } > "$file"
}

apply_sysctl() {
    local output_file line
    info "Preparation des reglages noyau adaptes au profil."
    mkdir -p "$CONFIG_DIR"
    backup_file "$SYSCTL_FILE"
    build_sysctl
    output_file=$(mktemp /tmp/linux-optimizer-sysctl.XXXXXX)
    if ! sysctl --load="$SYSCTL_FILE" >"$output_file" 2>&1; then
        if (( ENGINE_STANDALONE )); then
            engine_log_diagnostic < "$output_file"
        else
            while IFS= read -r line || [[ -n "$line" ]]; do
                report_line "[CMD] $line"
            done < "$output_file"
        fi
        cat "$output_file" >&2
        rm -f "$output_file" "$SYSCTL_FILE"
        error "Les reglages noyau n'ont pas ete appliques."
        return 1
    fi
    rm -f "$output_file"
    success "Reglages noyau appliques dans $SYSCTL_FILE."
}

# --- Limites ------------------------------------------------------------------

apply_limits() {
    local nofile
    nofile=$(ulimit -n 2>/dev/null || printf '1024')
    if (( nofile < 65536 )); then nofile=65536; fi
    write_config "$LIMITS_FILE" "# Limits managed by AxelL Linux Optimmisateur\n* soft nofile $nofile\n* hard nofile $nofile"
    success "Limite nofile configuree a $nofile, sans modifier /etc/profile."
}

# --- SSH ----------------------------------------------------------------------

apply_ssh() {
    local sshd_bin
    sshd_bin="$(command -v sshd || true)"
    if [[ -z "$sshd_bin" ]]; then
        warn "sshd absent : configuration SSH ignoree."
        return 2
    fi
    if ! confirm "Appliquer le durcissement SSH ?" 0; then
        warn "Durcissement SSH decline."
        return 2
    fi
    write_config "$SSH_FILE" $'# Managed by AxelL Linux Optimmisateur\nUseDNS no\nTCPKeepAlive yes\nClientAliveInterval 300\nClientAliveCountMax 2\nAllowTcpForwarding no\nGatewayPorts no\nPermitTunnel no\nX11Forwarding no'
    mkdir -p /etc/ssh/sshd_config.d
    backup_file /etc/ssh/sshd_config.d/99-linux-optimizer.conf
    cp "$SSH_FILE" /etc/ssh/sshd_config.d/99-linux-optimizer.conf
    if ! "$sshd_bin" -t; then
        rm -f /etc/ssh/sshd_config.d/99-linux-optimizer.conf
        error "Configuration SSH invalide : aucun redemarrage effectue."
        return 1
    fi
    if confirm "Redemarrer SSH pour appliquer le durcissement maintenant ?" 0; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd
        success "SSH valide et recharge."
    else
        warn "Configuration SSH installee mais non rechargee."
    fi
    return 0
}

# --- Pare-feu -----------------------------------------------------------------

show_ports() {
    local line
    note "Ports actuellement en ecoute :"
    while read -r line; do
        [[ -n "$line" ]] && note "  $line"
    done < <(ss -H -lntu 2>/dev/null | awk '{print $1 " " $5}' | sort -u || true)
    if command -v docker >/dev/null 2>&1; then
        note "Ports Docker publies :"
        while read -r line; do
            [[ -n "$line" ]] && note "  $line"
        done < <(docker ps --format '  {{.Names}}: {{.Ports}}' 2>/dev/null || true)
    fi
}

apply_firewall() {
    show_ports
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        warn "firewalld est actif : aucune installation ou purge de pare-feu ne sera effectuee."
        return 2
    fi
    if ! command -v ufw >/dev/null 2>&1; then
        warn "UFW absent : le pare-feu n'est pas modifie (installez UFW et definissez vos regles metier)."
        return 2
    fi
    if ! confirm "Ajouter uniquement le port SSH detecte et 80/443 a UFW ?" 0; then
        warn "Pare-feu laisse inchange."
        return 2
    fi
    local ssh_port
    ssh_port=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || printf '22')
    ufw allow "${ssh_port}/tcp"
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw reload
    success "Regles minimales ajoutees ; les ports Docker/Pterodactyl restent a definir explicitement."
}

# --- Swap ---------------------------------------------------------------------

apply_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q .; then
        success "Swap deja active : aucune taille imposee."
        return 0
    fi
    warn "Aucune swap active detectee. Sa taille depend du workload et ne sera pas imposee automatiquement."
    if ! confirm "Creer une swap de 1 Gio a /swapfile ?" 0; then
        warn "Swap non creee."
        return 2
    fi
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -qF '/swapfile none swap sw 0 0' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
    success "Swap de 1 Gio activee."
}

# --- DNS Cloudflare -----------------------------------------------------------

ipv6_enabled() {
    [[ -d /proc/sys/net/ipv6 ]] || return 1
    [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || printf '0')" != 1 ]] || return 1
    ip -6 addr show scope global 2>/dev/null | grep -q .
}

dns_server_list() {
    local servers="1.1.1.1 1.0.0.1"
    if ipv6_enabled; then
        printf '%s 2606:4700:4700::1111 2606:4700:4700::1001\n' "$servers"
    else
        printf '%s\n' "$servers"
    fi
}

dns_resolv_nameservers() {
    # glibc ne lit que les 3 premieres entrees de resolv.conf
    if ipv6_enabled; then
        printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 2606:4700:4700::1111\n'
    else
        printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n'
    fi
}

dns_manager() {
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        printf 'systemd-resolved'
    elif command -v netplan >/dev/null 2>&1 && compgen -G '/etc/netplan/*.yaml' >/dev/null 2>&1; then
        printf 'netplan'
    elif command -v resolvconf >/dev/null 2>&1 && [[ -d /etc/resolvconf/resolv.conf.d ]]; then
        printf 'openresolv'
    else
        printf 'resolv.conf statique'
    fi
}

dns_configure_resolved() {
    local dir="/etc/systemd/resolved.conf.d" dropin="$dir/99-linux-optimizer-dns.conf"
    mkdir -p "$dir"
    backup_file "$dropin"
    cat > "$dropin" <<EOF
# Managed by AxelL Linux Optimmisateur - Cloudflare DNS
# Restauration : supprimer ce fichier puis systemctl restart systemd-resolved
[Resolve]
DNS=$(dns_server_list)
FallbackDNS=1.1.1.1 1.0.0.1
EOF
    chmod 0644 "$dropin"
    if ! systemctl restart systemd-resolved; then
        rm -f "$dropin"
        error "systemd-resolved n'a pas accepte la configuration DNS."
        return 1
    fi
    success "systemd-resolved configure ($dropin)."
}

dns_configure_netplan() {
    local iface name dropin="/etc/netplan/99-linux-optimizer-dns.yaml" found=0
    for iface in /sys/class/net/*; do
        name=$(basename "$iface")
        case "$name" in
            lo|veth*|docker*|br-*|virbr*|tun*|tap*|vnet*|vmbr*|vlan*|bond*) continue ;;
        esac
        if grep -rqs "^[[:space:]]*${name}:" /etc/netplan/; then
            found=1
        fi
    done
    if (( found == 0 )); then
        warn "Aucune interface netplan connue : DNS Cloudflare non applique au niveau netplan."
        return 2
    fi
    backup_file "$dropin"
    {
        printf '# Managed by AxelL Linux Optimmisateur - Cloudflare DNS\n'
        printf 'network:\n  version: 2\n  ethernets:\n'
        for iface in /sys/class/net/*; do
            name=$(basename "$iface")
            case "$name" in
                lo|veth*|docker*|br-*|virbr*|tun*|tap*|vnet*|vmbr*|vlan*|bond*) continue ;;
            esac
            grep -rqs "^[[:space:]]*${name}:" /etc/netplan/ || continue
            printf '    %s:\n      nameservers:\n        addresses:\n          - 1.1.1.1\n          - 1.0.0.1\n' "$name"
        done
    } > "$dropin"
    chmod 0600 "$dropin"
    if ! netplan apply; then
        rm -f "$dropin"
        error "netplan n'a pas accepte la configuration DNS."
        return 1
    fi
    success "netplan configure ($dropin)."
}

dns_configure_resolvconf() {
    local head="/etc/resolvconf/resolv.conf.d/head" old=""
    if [[ -f "$head" ]]; then
        old=$(grep -vE '^[[:space:]]*nameserver[[:space:]]' "$head" || true)
    fi
    backup_file "$head"
    {
        printf '%s\n' "$old"
        dns_resolv_nameservers
    } > "$head"
    chmod 0644 "$head"
    if ! resolvconf -u; then
        error "openresolv n'a pas regenere la configuration DNS."
        return 1
    fi
    success "openresolv configure ($head)."
}

dns_configure_static() {
    local target="/etc/resolv.conf" real="" old=""
    if [[ -L "$target" ]]; then
        real=$(readlink "$target")
        backup_file "$real"
        if [[ -f "$real" ]]; then
            old=$(grep -E '^(search|domain|options)[[:space:]]' "$real" || true)
        fi
        rm -f "$target"
    else
        backup_file "$target"
        if [[ -f "$target" ]]; then
            old=$(grep -E '^(search|domain|options)[[:space:]]' "$target" || true)
        fi
    fi
    {
        printf '%s\n' "$old"
        dns_resolv_nameservers
    } > "$target"
    chmod 0644 "$target"
    success "resolv.conf reecrit (domaines de recherche preserves)."
}

dns_verify() {
    if getent ahosts one.one.one.one >/dev/null 2>&1; then
        success "Resolution DNS fonctionnelle : one.one.one.one joignable."
    else
        warn "Impossible de verifier la resolution DNS (one.one.one.one). Les sauvegardes .bak permettent une restauration immediate."
    fi
}

apply_dns() {
    local manager
    manager=$(dns_manager)
    note "Gestionnaire DNS detecte : $manager."
    note "Serveurs cibles : $(dns_server_list)."
    if ! confirm "Basculer la resolution DNS sur Cloudflare ($(dns_server_list)) ?" 1; then
        warn "DNS laisse inchange (Cloudflare non applique)."
        return 2
    fi
    case "$manager" in
        systemd-resolved) dns_configure_resolved ;;
        netplan)          dns_configure_netplan ;;
        openresolv)       dns_configure_resolvconf ;;
        *)                dns_configure_static ;;
    esac
    dns_verify
    return 0
}

# --- Divers -------------------------------------------------------------------

kernel_reboot_notice() {
    local running newest
    running=$(uname -r 2>/dev/null || true)
    newest=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V 2>/dev/null | tail -n1 || true)
    if [[ -n "$running" && -n "$newest" && "$newest" != "$running" ]]; then
        warn "Noyau ${newest} installe, ${running} en cours : un redemarrage est recommande pour l'appliquer."
    fi
}

profile_description() {
    if [[ "$PROFILE" == full ]]; then
        printf 'Optimisation complete automatique pour serveur professionnel.'
    elif [[ "$PROFILE" == base || "$PROFILE" == *,* ]]; then
        printf 'Optimisation combinee des roles : %s.' "$PROFILE"
    else
        error "Profil inconnu : $PROFILE"
        return 1
    fi
}

# --- Mode executable seul (debug) ---------------------------------------------

main() {
    if [[ "$EUID" -ne 0 ]]; then
        error "Lancez ce script avec sudo ou depuis une session root."
        exit 1
    fi
    if [[ ! -r /etc/os-release ]]; then
        error "/etc/os-release est introuvable."
        exit 1
    fi
    . /etc/os-release
    if [[ "${ID:-}" != debian ]]; then
        error "Ce profil est reserve a Debian (systeme detecte : ${PRETTY_NAME:-$ID})."
        exit 1
    fi
    printf '\n%s\n' "$(profile_description)"
    printf 'Mode automatique : %s\n' "$([ "$AUTO" == 1 ] && printf 'oui' || printf 'non')"
    engine_report_line "== Profil : $PROFILE (mode automatique: $([ "$AUTO" == 1 ] && printf 'oui' || printf 'non'))"
    local i rc total=${#STEP_FUNCS[@]}
    for (( i = 0; i < total; i++ )); do
        printf '\n[%d/%d] %s ...\n' "$((i + 1))" "$total" "${STEP_LABELS[$i]}"
        engine_report_line "== Etape $((i + 1))/${total} : ${STEP_LABELS[$i]}"
        set +e
        ( trap - ERR; set -e; "${STEP_FUNCS[$i]}" )
        rc=$?
        set -e
        case "$rc" in
            0)
                engine_report_line "== OK : ${STEP_LABELS[$i]}"
                success "${STEP_LABELS[$i]} : termine."
                ;;
            2)
                engine_report_line "== IGNORE : ${STEP_LABELS[$i]}"
                warn "${STEP_LABELS[$i]} : ignore."
                ;;
            *)
                engine_report_line "== FAIL : ${STEP_LABELS[$i]} (code $rc)"
                error "${STEP_LABELS[$i]} : echec. Profil interrompu."
                exit 1
                ;;
        esac
    done
    printf '\n'
    kernel_reboot_notice
    success "Profil $PROFILE termine."
    engine_report_line "== Profil termine"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
