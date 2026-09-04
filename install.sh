#!/usr/bin/env bash
set -Eeuo pipefail

readonly ARCHIVE_URL="https://github.com/Axxel-L/linux-optimizer-professional-server/archive/refs/heads/main.tar.gz"

if [[ "${EUID}" -ne 0 ]]; then
    printf 'Erreur : cet installateur doit être lancé avec sudo ou en root.\n' >&2
    exit 1
fi

for command_name in mktemp wget tar chmod; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Erreur : commande requise introuvable : %s\n' "$command_name" >&2
        exit 1
    fi
done

temporary_directory="$(mktemp -d)"
cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

archive_path="${temporary_directory}/linux-optimizer.tar.gz"
wget -qO "$archive_path" "$ARCHIVE_URL"
tar -xzf "$archive_path" -C "$temporary_directory"

repository_directory="$(find "$temporary_directory" -mindepth 1 -maxdepth 1 -type d -print -quit)"
if [[ -z "$repository_directory" || ! -f "${repository_directory}/linux-optimizer.sh" ]]; then
    printf 'Erreur : dépôt Linux Optimizer introuvable après extraction.\n' >&2
    exit 1
fi

chmod +x "${repository_directory}/linux-optimizer.sh" "${repository_directory}"/scripts/*.sh
cd "$repository_directory"
exec ./linux-optimizer.sh "$@"