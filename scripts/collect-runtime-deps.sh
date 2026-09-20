#!/usr/bin/env bash
set -euo pipefail
trap 'status=$?; echo "runtime dependency collector failed at line ${BASH_LINENO[0]}: ${BASH_COMMAND}" >&2; exit "$status"' ERR

[ "$#" -ge 2 ] || { echo "usage: $0 ROOTFS EXECUTABLE..." >&2; exit 2; }
ROOTFS=$1
shift
mkdir -p "$ROOTFS"
declare -A PROCESSED=()

cp_with_parents() {
    local src=$1 dst="$ROOTFS$1"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$src" ]; then
        cp -a "$src" "$dst"
        local resolved
        resolved=$(readlink -f "$src")
        [ -e "$resolved" ] && cp_with_parents "$resolved"
    else
        cp -aT "$src" "$dst"
    fi
}

collect_ldd() {
    local output token path
    output=$(ldd "$1" 2>&1) || case "$output" in
        *"not a dynamic executable"*|*"statically linked"*) return 0 ;; *) echo "$output" >&2; return 1 ;; esac
    while read -r token; do
        case "$token" in
            /*) path=${token%%(*}; [ -e "$path" ] || continue; cp_with_parents "$path" ;;
        esac
    done <<< "$output"
}

process() {
    local src=$1 resolved shebang interpreter
    [ -e "$src" ] || { echo "runtime dependency source does not exist: $src" >&2; return 1; }
    resolved=$(readlink -f "$src")
    cp_with_parents "$src"
    [ "${PROCESSED[$resolved]:-}" ] && return
    PROCESSED[$resolved]=1
    collect_ldd "$src"
    IFS= read -r shebang < "$src" 2>/dev/null || true
    if [[ "$shebang" == '#!'* ]]; then
        interpreter=${shebang#\#!}; interpreter=${interpreter%% *}
        process "$interpreter"
    fi
}

for requested in "$@"; do
    if [[ "$requested" == /* ]]; then
        path=$requested
    else
        path=$(command -v "$requested") || { echo "missing executable: $requested" >&2; exit 1; }
    fi
    process "$path"
done

for path in /etc/ssl/certs /etc/passwd /etc/group /etc/ld.so.cache /etc/ld.so.conf /etc/ld.so.conf.d /usr/share/zoneinfo; do
    [ -e "$path" ] && cp_with_parents "$path"
done

# Debian's /bin is usr-merged; make the shell available at both paths.
mkdir -p "$ROOTFS/bin" "$ROOTFS/usr/bin"
if [ -e "$ROOTFS/usr/bin/dash" ]; then
    ln -sf /usr/bin/dash "$ROOTFS/bin/sh"
    ln -sf /usr/bin/dash "$ROOTFS/usr/bin/sh"
fi
