#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENGINE=${CONTAINER_ENGINE:-}
if [ -z "$ENGINE" ]; then
    command -v podman >/dev/null 2>&1 && ENGINE=podman || ENGINE=docker
fi
command -v "$ENGINE" >/dev/null 2>&1 || { echo "no Docker/Podman engine" >&2; exit 1; }
"$ENGINE" build --build-arg USER_UID="$(id -u)" --build-arg USER_GID="$(id -g)" \
    --build-arg OMP_VERSION="${OMP_VERSION:-18.2.6}" -t omp-container:smoke "$ROOT_DIR"
tmp=${TMPDIR:-/tmp}/omp-container-smoke.$$
mkdir "$tmp"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state" "$tmp/secrets" "$tmp/workspace"
chmod 700 "$tmp/state" "$tmp/secrets"
printf 'smoke\n' > "$tmp/workspace/write-test"
run_container() {
    "$ENGINE" run --rm --read-only --tmpfs /tmp:exec,size=512m,mode=1777 --cap-drop=ALL \
        --security-opt=no-new-privileges --user "$(id -u):$(id -g)" --workdir /workspace \
        -v "$tmp/state:/app/.omp:rw,Z" -v "$tmp/secrets:/run/secrets:ro,Z" \
        -v "$tmp/workspace:/workspace:rw,Z" omp-container:smoke "$@"
}
run_binary() {
    binary=$1
    shift
    "$ENGINE" run --rm --read-only --tmpfs /tmp:exec,size=512m,mode=1777 --cap-drop=ALL \
        --security-opt=no-new-privileges --user "$(id -u):$(id -g)" --workdir /workspace \
        -v "$tmp/state:/app/.omp:rw,Z" -v "$tmp/secrets:/run/secrets:ro,Z" \
        -v "$tmp/workspace:/workspace:rw,Z" --entrypoint "$binary" omp-container:smoke "$@"
}
run_binary /bin/sh -c 'test -x /usr/local/bin/bootstrap.sh && test -x /usr/local/bin/omp'


run_binary /usr/bin/python3 --version
run_binary /usr/bin/python3 -m venv /tmp/smoke-venv
run_binary /usr/bin/git --version
run_binary /usr/bin/git -C /workspace init >/dev/null
run_binary /usr/bin/git -C /workspace status --short --branch >/dev/null

run_container --version
run_container --mode rpc --no-session </dev/null >/dev/null
run_container --help >/dev/null
test -f "$tmp/workspace/write-test"
echo "OMP container smoke test passed"
