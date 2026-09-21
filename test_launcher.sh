#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_DIR=${TMPDIR:-/tmp}/omp-container-test.$$
mkdir "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home" "$TEST_DIR/workspace"
cat > "$TEST_DIR/home/.gitconfig" <<'EOF'
[user]
    name = Test User
EOF
cat > "$TEST_DIR/bin/podman" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$ARGS_FILE"
EOF
chmod +x "$TEST_DIR/bin/podman"
run_wrapper() {
    env -u HTTP_PROXY -u HTTPS_PROXY -u NO_PROXY -u http_proxy -u https_proxy -u no_proxy \
        ARGS_FILE="$TEST_DIR/args" HOME="$TEST_DIR/home" PATH="$TEST_DIR/bin:$PATH" \
        OMP_WORKSPACE="$TEST_DIR/workspace" CONTAINER_ENGINE=podman \
        "$ROOT_DIR/bin/omp-container" "$@"
}
run_wrapper --memory 2g --cpus 2 --host-access -p "hello"
grep -Fx -- '--read-only' "$TEST_DIR/args"
grep -Fx -- '--tmpfs' "$TEST_DIR/args"
grep -Fx -- '/tmp:exec,size=512m,mode=1777' "$TEST_DIR/args"
grep -Fx -- '--cap-drop=ALL' "$TEST_DIR/args"
grep -Fx -- '--security-opt=no-new-privileges' "$TEST_DIR/args"
grep -Fx -- '--memory=2g' "$TEST_DIR/args"
grep -Fx -- '--cpus=2' "$TEST_DIR/args"
grep -Fx -- "$TEST_DIR/home/.omp-container/state:/app/.omp:rw,Z" "$TEST_DIR/args"
grep -Fx -- "$TEST_DIR/home/.omp-container/secrets:/run/secrets:ro,Z" "$TEST_DIR/args"
grep -Fx -- "$TEST_DIR/home/.gitconfig:/app/.gitconfig:ro,Z" "$TEST_DIR/args"
grep -Fx -- "$TEST_DIR/workspace:/workspace:rw,Z" "$TEST_DIR/args"
grep -Fx -- '--userns=keep-id' "$TEST_DIR/args"
grep -Fx -- '-p' "$TEST_DIR/args"
grep -Fx -- 'hello' "$TEST_DIR/args"
grep -F -- 'host.containers.internal:host-gateway' "$TEST_DIR/args"
if run_wrapper --memory >/dev/null 2>&1; then exit 1; fi
if env HTTP_PROXY='http://user:pass@proxy.example:8080' HTTPS_PROXY= NO_PROXY= \
    ARGS_FILE="$TEST_DIR/args" HOME="$TEST_DIR/home" PATH="$TEST_DIR/bin:$PATH" \
    OMP_WORKSPACE="$TEST_DIR/workspace" CONTAINER_ENGINE=podman \
    "$ROOT_DIR/bin/omp-container" >/dev/null 2>&1; then exit 1; fi
if env -u HTTP_PROXY -u HTTPS_PROXY -u NO_PROXY -u http_proxy -u https_proxy -u no_proxy \
    ARGS_FILE="$TEST_DIR/args" HOME="$TEST_DIR/home" PATH="$TEST_DIR/bin:$PATH" \
    OMP_WORKSPACE="$TEST_DIR/missing" CONTAINER_ENGINE=podman \
    "$ROOT_DIR/bin/omp-container" >/dev/null 2>&1; then exit 1; fi
cat > "$TEST_DIR/bin/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$ARGS_FILE"
EOF
chmod +x "$TEST_DIR/bin/docker"
env -u HTTP_PROXY -u HTTPS_PROXY -u NO_PROXY -u http_proxy -u https_proxy -u no_proxy \
    ARGS_FILE="$TEST_DIR/args" HOME="$TEST_DIR/home" PATH="$TEST_DIR/bin:$PATH" \
    CONTAINER_ENGINE=docker OMP_WORKSPACE="$TEST_DIR/workspace" \
    "$ROOT_DIR/bin/omp-container" --help
grep -Fx -- "$TEST_DIR/workspace:/workspace:rw,Z" "$TEST_DIR/args"
echo "launcher tests passed"
