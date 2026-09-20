.PHONY: build build-builder-tools build-latest shell clean prune-cache

ENGINE ?= $(shell command -v podman >/dev/null 2>&1 && echo podman || echo docker)
USER_UID := $(shell id -u)
USER_GID := $(shell id -g)
OMP_VERSION ?= 18.2.6

build:
	$(ENGINE) build --build-arg USER_UID=$(USER_UID) --build-arg USER_GID=$(USER_GID) --build-arg OMP_VERSION=$(OMP_VERSION) -t omp-container:latest .

build-builder-tools:
	$(ENGINE) build --build-arg USER_UID=$(USER_UID) --build-arg USER_GID=$(USER_GID) --build-arg OMP_VERSION=$(OMP_VERSION) --target builder-tools -t omp-container:builder-tools .

build-latest:
	@latest=$$(python3 -c 'import json,urllib.request; print(json.load(urllib.request.urlopen("https://registry.npmjs.org/@oh-my-pi%2Fpi-coding-agent"))["dist-tags"]["latest"])') && \
	$(MAKE) build OMP_VERSION=$$latest

shell: build-builder-tools
	$(ENGINE) run --rm -it --entrypoint /bin/sh --read-only --tmpfs /tmp:exec,size=512m,mode=1777 \
		--cap-drop=ALL --security-opt=no-new-privileges \
		-v "$(PWD)/workspace:/workspace:rw,Z" omp-container:builder-tools

clean:
	-$(ENGINE) rmi omp-container:latest omp-container:builder-tools

prune-cache:
	$(ENGINE) builder prune -f
