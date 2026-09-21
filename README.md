# OMP Container

Run [OMP (oh-my-pi)](https://omp.sh/) in a locked-down Docker or Podman
container. The image uses a configurable non-root UID/GID, a read-only root
filesystem, dropped capabilities, and writable mounts only for the workspace
and OMP state.

## Prerequisites and quick start

Install Docker or Podman and Make, then run:

```sh
make build
mkdir -p ~/.omp-container/secrets
chmod 700 ~/.omp-container/secrets
printf '%s' "$OPENAI_API_KEY" > ~/.omp-container/secrets/openai_api_key
chmod 600 ~/.omp-container/secrets/openai_api_key
bin/omp-container
```

The current directory is mounted read-write at `/workspace`. The wrapper works
from any directory. Add `omp-container/bin` to `PATH`, or set
`OMP_WORKSPACE=/path/to/project` to select another workspace. Set
`CONTAINER_ENGINE=docker` or `CONTAINER_ENGINE=podman`; without it, Podman is
preferred. Set `OMP_CONTAINER_IMAGE` to use another image tag. If
`~/.gitconfig` exists, it is mounted read-only at `/app/.gitconfig` so Git
identity and other user Git settings are available in the container.

## State and secrets

OMP runs with `HOME=/app` and `PI_CODING_AGENT_DIR=/app/.omp/agent`. The host
directory `~/.omp-container/state` is mounted at `/app/.omp`, preserving the
agent database, sessions, settings, models, extensions, and history without
mounting the host home directory. Secrets are mounted read-only at
`/run/secrets` and are never baked into image layers or passed as arguments.

Secret filenames are case-insensitive environment variable names; dots and
dashes become underscores. Unsupported files are ignored. The allowlist follows
OMP's provider documentation and covers Anthropic, OpenAI, Google/Gemini/
Vertex, OpenRouter, Azure, AWS Bedrock, xAI, Groq, Mistral, Together,
Fireworks, DeepSeek, DeepInfra, Cerebras, NVIDIA, Hugging Face, Moonshot/Kimi,
MiniMax, Alibaba, Qwen, Z.AI, SiliconFlow, Cloudflare AI Gateway, Ollama,
LM Studio, llama.cpp, vLLM, and other documented providers.

| Filename | Environment variable |
| --- | --- |
| `anthropic_api_key` | `ANTHROPIC_API_KEY` |
| `openai_api_key` | `OPENAI_API_KEY` |
| `gemini_api_key` | `GEMINI_API_KEY` |
| `google_cloud_project` | `GOOGLE_CLOUD_PROJECT` |
| `google_application_credentials` | `GOOGLE_APPLICATION_CREDENTIALS` |
| `aws_access_key_id` | `AWS_ACCESS_KEY_ID` |
| `aws_secret_access_key` | `AWS_SECRET_ACCESS_KEY` |
| `cloudflare_account_id` | `CLOUDFLARE_ACCOUNT_ID` |
| `cloudflare_gateway_id` | `CLOUDFLARE_GATEWAY_ID` |
| `cloudflare_ai_gateway_api_key` | `CLOUDFLARE_AI_GATEWAY_API_KEY` |

For `GOOGLE_APPLICATION_CREDENTIALS`, the secret file is treated as the JSON
credential file and the variable points to its mounted path. OAuth and `/login`
credentials are not converted into API-key files; use persisted OMP state or a
documented token environment variable. See [provider documentation](https://omp.sh/docs/providers)
and [environment variables](https://omp.sh/docs/environment-variables).

## Wrapper options

```sh
omp-container --memory 8g --cpus 8
omp-container --host-access
omp-container -p 'summarize this repository'
omp-container --mode rpc --no-session
```

`--memory` defaults to `4g` and `--cpus` defaults to `4`. All other arguments
are passed directly to `omp`. `--host-access` adds
`host.docker.internal` for Docker or `host.containers.internal` for Podman and
prints a warning. Proxy variables are forwarded in upper- and lower-case
forms, but URLs with embedded credentials are rejected.

## Build, test, and smoke validation

```sh
make build
make build-builder-tools
make shell
./test_launcher.sh
./test_bootstrap.sh
./smoke_test.sh
make clean
make prune-cache
```

Override versions with `make build OMP_VERSION=18.2.6` or:

```sh
docker build --build-arg OMP_VERSION=18.2.6 \
  --build-arg BUN_VERSION=1.3.14 -t omp-container:latest .
```

The published package is `@oh-my-pi/pi-coding-agent`; its executable is `omp`
and it requires Bun `>=1.3.14`. The final image copies Bun, OMP's package,
native modules, POSIX utilities, Git, and runtime libraries into a distroless
Debian runtime. It intentionally contains no package manager, compiler, or
Node.js.
### Custom CA certificates

Place an optional PEM bundle named `custom-ca.crt` at the build-context root
and run `make build`. Each certificate is split, validated as an X.509
certificate, installed into Debian's trust store, and retained in the final
image. The bundle is installed before Bun downloads OMP, and
`NPM_CONFIG_CAFILE` points build-time and runtime registry access at the
generated system CA bundle.

The file is read through a BuildKit bind mount and is not copied into an
intermediate image layer as a source file. Invalid or non-PEM input fails the
build.

The final image includes Python 3, `python3-venv`, and Git. The runtime
dependency collector also includes Python's standard library and Git's HTTP
remote helpers so `python3 -m venv` and network Git operations work in the
distroless image.

If `git` on the host fails with an error such as
`libpcre2-8.so.0: cannot open shared object file`, the host Git installation
is missing its PCRE2 shared library; this occurs before the container starts.
Install or reinstall the distribution package providing `libpcre2-8.so.0`
(on Debian-based systems, typically `libpcre2-8-0`) and reinstall Git if
needed. The image build explicitly installs that package and fails dependency
collection when `ldd` reports a missing library.

## Security and limitations

- The root filesystem is read-only; `/tmp` is a `tmpfs`.
- All capabilities are dropped and privilege escalation is disabled.
- The workspace and OMP state are the only writable bind mounts.
- Bind mounts use SELinux-compatible `:Z` labels.
- `make build` passes the current host UID/GID; rootless Podman uses
  `--userns=keep-id`.
- Resource limits depend on the engine and cgroup configuration.
- OAuth browser flows may not work in a restricted container; authenticate on a
  trusted host or persist the OMP agent database.
- Host access weakens network isolation. Do not expose unauthenticated host
  administration services to the agent.
