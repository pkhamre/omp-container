# syntax=docker/dockerfile:1.7

ARG BUN_VERSION=1.3.14
ARG OMP_VERSION=18.2.6

FROM debian:13-slim AS builder-tools

ARG BUN_VERSION
ARG OMP_VERSION
ARG USER_UID=1000
ARG USER_GID=1000

ENV BUN_INSTALL=/opt/bun \
    PATH=/opt/bun/bin:/usr/local/bin:/usr/bin:/bin \
    npm_config_update_notifier=false

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
       ca-certificates curl bash file findutils git openssh-client openssl \
       libpcre2-8-0 libatomic1 libgomp1 libgcc-s1 libstdc++6 \
       python3 python3-venv unzip libc-bin \
    && rm -rf /var/lib/apt/lists/*

# Install an optional PEM bundle before any build-time HTTPS downloads. The
# bind mount keeps custom-ca.crt out of the image layer history.
RUN --mount=type=bind,source=.,target=/build-context,ro \
    set -eu; \
    if [ -s /build-context/custom-ca.crt ]; then \
      mkdir -p /usr/local/share/ca-certificates; \
      awk '\
        /-----BEGIN CERTIFICATE-----/ {\
          n++;\
          output=sprintf("/usr/local/share/ca-certificates/omp-custom-ca-%03d.crt", n);\
          in_cert=1;\
        }\
        in_cert { print > output }\
        /-----END CERTIFICATE-----/ { close(output); in_cert=0 }\
      ' /build-context/custom-ca.crt; \
      found=0; \
      for certificate in /usr/local/share/ca-certificates/omp-custom-ca-*.crt; do \
        [ -f "$certificate" ] || continue; \
        found=1; \
        if ! openssl x509 -in "$certificate" -noout >/dev/null 2>&1; then \
          echo "invalid PEM X.509 certificate in custom-ca.crt: $certificate" >&2; \
          exit 1; \
        fi; \
      done; \
      if [ "$found" -eq 0 ]; then \
        echo "custom-ca.crt does not contain a PEM X.509 certificate" >&2; \
        exit 1; \
      fi; \
      update-ca-certificates; \
    fi

# Bun/npm use the generated Debian bundle for registry TLS.
ENV NPM_CONFIG_CAFILE=/etc/ssl/certs/ca-certificates.crt

RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && bun --version \
    && python3 --version \
    && python3 -m venv /tmp/build-venv \
    && rm -rf /tmp/build-venv

WORKDIR /opt/omp
RUN printf '%s\n' '{"private":true,"dependencies":{"@oh-my-pi/pi-coding-agent":"'"${OMP_VERSION}"'"}}' > package.json \
    && bun install --production --no-save \
    && test -f node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js \
    && bun /opt/omp/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js --version

COPY bootstrap.sh /usr/local/bin/bootstrap.sh
COPY scripts/collect-runtime-deps.sh /usr/local/bin/collect-runtime-deps.sh
RUN printf '%s\n' \
    '#!/bin/sh' \
    'exec /opt/bun/bin/bun /opt/omp/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js "$@"' \
    > /usr/local/bin/omp \
    && chmod 0755 /usr/local/bin/omp /usr/local/bin/bootstrap.sh /usr/local/bin/collect-runtime-deps.sh

RUN mkdir -p /opt/runtime-rootfs /opt/runtime-rootfs/opt \
    && cp -a /opt/bun /opt/runtime-rootfs/opt/bun \
    && cp -a /opt/omp /opt/runtime-rootfs/opt/omp \
    && echo 'collecting base runtime dependencies' \
    && /usr/local/bin/collect-runtime-deps.sh /opt/runtime-rootfs \
       /usr/local/bin/bootstrap.sh /usr/local/bin/omp /opt/bun/bin/bun /usr/bin/sh \
       python3 cat mkdir ls find grep sed awk sort cut head tail cp mv rm chmod wc env date tr \
       dirname basename git ssh \
       /usr/lib/git-core/git-remote-http /usr/lib/git-core/git-remote-https \
    && echo 'collecting native module dependencies' \
    && find /opt/omp -type f -name '*.node' -print > /tmp/omp-native-modules \
    && while IFS= read -r native; do \
         case "$native" in *musl*|*/darwin/*|*/win32/*|*/arm64/*) continue ;; esac; \
         echo "collecting native module: $native"; \
         echo "native module metadata:"; \
         file "$native"; \
         echo "native module dependencies:"; \
         ldd "$native"; \
         if /usr/local/bin/collect-runtime-deps.sh /opt/runtime-rootfs "$native"; then :; else \
           status=$?; \
           echo "native dependency collection failed for $native (status $status); tracing retry" >&2; \
           /bin/bash -x /usr/local/bin/collect-runtime-deps.sh /opt/runtime-rootfs "$native" || true; \
           exit "$status"; \
         fi; \
       done < /tmp/omp-native-modules \
    && rm -f /tmp/omp-native-modules \
    && mkdir -p /opt/runtime-rootfs/app/.omp /opt/runtime-rootfs/workspace \
    && chown -R "${USER_UID}:${USER_GID}" /opt/runtime-rootfs/app /opt/runtime-rootfs/workspace \
     && printf 'omp:x:%s:%s:OMP User:/app:/bin/sh\n' "${USER_UID}" "${USER_GID}" >> /opt/runtime-rootfs/etc/passwd \
     && printf 'omp:x:%s:\n' "${USER_GID}" >> /opt/runtime-rootfs/etc/group \
     && for required in \
          /opt/runtime-rootfs/lib64/ld-linux-x86-64.so.2 \
          /opt/runtime-rootfs/usr/local/bin/bootstrap.sh \
          /opt/runtime-rootfs/usr/local/bin/omp \
          /opt/runtime-rootfs/bin/sh \
          /opt/runtime-rootfs/usr/bin/dash; do \
          if [ ! -x "$required" ]; then \
            echo "required runtime file missing or not executable: $required" >&2; \
            ls -ld "$(dirname "$required")" "$required" 2>&1 || true; \
            exit 1; \
          fi; \
        done

FROM gcr.io/distroless/base-debian13@sha256:9ef50bca108839d5986e4d84b7f7b2d79024c9293b7c35b162c6c55485bd5868 AS final

ARG USER_UID=1000
ARG USER_GID=1000

WORKDIR /app
ENV HOME=/app \
    OMP_HOME=/app/.omp \
    PI_CODING_AGENT_DIR=/app/.omp/agent \
    NPM_CONFIG_CAFILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/opt/bun/bin:/usr/local/bin:/usr/bin:/bin

COPY --from=builder-tools /opt/runtime-rootfs/ /

USER ${USER_UID}:${USER_GID}
ENTRYPOINT ["/bin/sh", "/usr/local/bin/bootstrap.sh"]
CMD []
