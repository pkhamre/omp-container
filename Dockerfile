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
       ca-certificates curl bash file findutils git openssh-client unzip \
       libc-bin libgcc-s1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && bun --version

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
       cat mkdir ls find grep sed awk sort cut head tail cp mv rm chmod wc env date tr \
       dirname basename git ssh \
    && echo 'collecting native module dependencies' \
    && find /opt/omp -type f -name '*.node' -print -exec \
       /usr/local/bin/collect-runtime-deps.sh /opt/runtime-rootfs {} \; \
    && mkdir -p /opt/runtime-rootfs/app/.omp /opt/runtime-rootfs/workspace \
    && chown -R "${USER_UID}:${USER_GID}" /opt/runtime-rootfs/app /opt/runtime-rootfs/workspace \
    && printf 'omp:x:%s:%s:OMP User:/app:/bin/sh\n' "${USER_UID}" "${USER_GID}" >> /opt/runtime-rootfs/etc/passwd \
    && printf 'omp:x:%s:\n' "${USER_GID}" >> /opt/runtime-rootfs/etc/group

FROM gcr.io/distroless/base-debian13@sha256:9ef50bca108839d5986e4d84b7f7b2d79024c9293b7c35b162c6c55485bd5868 AS final

ARG USER_UID=1000
ARG USER_GID=1000

WORKDIR /app
ENV HOME=/app \
    OMP_HOME=/app/.omp \
    PI_CODING_AGENT_DIR=/app/.omp/agent \
    PATH=/opt/bun/bin:/usr/local/bin:/usr/bin:/bin

COPY --from=builder-tools /opt/runtime-rootfs/ /

USER ${USER_UID}:${USER_GID}
ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]
CMD []
