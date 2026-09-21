#!/usr/bin/env bash
set -euo pipefail
trap 'status=$?; echo "runtime dependency collector failed at line ${BASH_LINENO[0]}: ${BASH_COMMAND}" >&2; exit "$status"' ERR

[ "$#" -ge 2 ] || { echo "usage: $0 ROOTFS EXECUTABLE..." >&2; exit 2; }
ROOTFS=$1
shift
mkdir -p "$ROOTFS"
declare -A PROCESSED=()

cp_with_parents() {
    local src=$1 dst="$ROOTFS$1" link_target target_path resolved
    mkdir -p "$(dirname "$dst")"
    if [ -L "$src" ]; then
        rm -f "$dst"
        if ! cp -a "$src" "$dst"; then
            echo "failed to copy symlink $src to $dst" >&2
            return 1
        fi
        link_target=$(readlink "$src")
        resolved=$(readlink -f "$src")
        if [ "${link_target#/}" = "$link_target" ]; then
            # Normalize the link text without resolving symlinks in the
            # source path (notably /lib64 -> /usr/lib on Debian).
            target_path=$(realpath -m -s "$(dirname "$src")/$link_target")
        else
            target_path=$link_target
        fi
        if [ -e "$resolved" ]; then
            mkdir -p "$(dirname "$ROOTFS$target_path")"
            if ! cp -aT "$resolved" "$ROOTFS$target_path"; then
                echo "failed to copy symlink target $resolved to $ROOTFS$target_path" >&2
                return 1
            fi
        fi
    else
        if ! cp -aT "$src" "$dst"; then
            echo "failed to copy $src to $dst" >&2
            return 1
        fi
    fi
}

ldd_path() {
    local path="${1%%(*}"
    printf '%s\n' "${path%)}"
}

collect_ldd() {
    local output line token path
    output=$(ldd "$1" 2>&1) || case "$output" in
        *"not a dynamic executable"*|*"statically linked"*) return 0 ;; *) echo "$output" >&2; return 1 ;; esac
    case "$output" in
        *"not found"*) echo "missing shared library for $1: $output" >&2; return 1 ;;
    esac
    while IFS= read -r line; do
        for token in $line; do
            [[ "$token" == /* ]] || continue
            path=$(ldd_path "$token")
            [ -e "$path" ] || { echo "missing shared library $path for $1" >&2; return 1; }
            if ! cp_with_parents "$path"; then
                echo "failed to copy shared library $path for $1" >&2
                return 1
            fi
        done
    done <<< "$output"
}

collect_python() {
    local path extension
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -e "$path" ] || continue
        cp_with_parents "$path"
        while IFS= read -r extension; do
            collect_ldd "$extension"
        done < <(find "$path" -type f \( -name '*.so' -o -name '*.so.*' \) -print)
    done < <("$1" -c '
import site
import sysconfig

paths = set()
for key in ("stdlib", "platstdlib", "purelib", "platlib"):
    value = sysconfig.get_paths().get(key)
    if value:
        paths.add(value)
getsitepackages = getattr(site, "getsitepackages", None)
if callable(getsitepackages):
    paths.update(getsitepackages())
for path in sorted(paths):
    print(path)
' 2>/dev/null || true)
}

process() {
    local src=$1 resolved shebang interpreter name
    [ -e "$src" ] || { echo "runtime dependency source does not exist: $src" >&2; return 1; }
    resolved=$(readlink -f "$src")
    cp_with_parents "$src"
    [ "${PROCESSED[$resolved]:-}" ] && return
    PROCESSED[$resolved]=1
    if ! collect_ldd "$src"; then
        echo "failed to resolve runtime dependencies for $src" >&2
        return 1
    fi
    IFS= read -r shebang < "$src" 2>/dev/null || true
    if [[ "$shebang" == '#!'* ]]; then
        interpreter=${shebang#\#!}; interpreter=${interpreter%% *}
        if ! process "$interpreter"; then
            echo "failed to collect interpreter $interpreter for $src" >&2
            return 1
        fi
    fi
    name=$(basename "$resolved")
    case "$name" in
        python|python3|python3.*) collect_python "$resolved" ;;
    esac
}

for requested in "$@"; do
    if [[ "$requested" == /* ]]; then
        path=$requested
    else
        path=$(command -v "$requested") || { echo "missing executable: $requested" >&2; exit 1; }
    fi
    if ! process "$path"; then
        echo "failed to collect runtime dependencies for $path" >&2
        exit 1
    fi
done

for path in /etc/ssl/certs /usr/local/share/ca-certificates /etc/passwd /etc/group /etc/ld.so.cache /etc/ld.so.conf /etc/ld.so.conf.d /usr/share/zoneinfo; do
    [ -e "$path" ] && cp_with_parents "$path"
done


# Debian's /bin is usr-merged; make the shell available at both paths.
mkdir -p "$ROOTFS/bin" "$ROOTFS/usr/bin"
if [ -e "$ROOTFS/usr/bin/dash" ]; then
    shell=$(readlink -f "$ROOTFS/usr/bin/dash")
    if ! cp -aT --remove-destination "$shell" "$ROOTFS/bin/sh"; then
        echo "failed to copy shell to $ROOTFS/bin/sh" >&2
        exit 1
    fi
    if ! cp -aT --remove-destination "$shell" "$ROOTFS/usr/bin/sh"; then
        echo "failed to copy shell to $ROOTFS/usr/bin/sh" >&2
        exit 1
    fi
fi
