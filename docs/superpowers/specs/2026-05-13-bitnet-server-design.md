# bitnet-server — v0.1 Design

**Status:** Approved (pending user review of this spec)
**Date:** 2026-05-13
**Author:** Jeet (with Claude as design collaborator)
**License of work:** MIT

---

## 1. Problem statement

A user on Ubuntu 24.04 wants to call `curl localhost:11435/v1/chat/completions` on their box and get a response from a small local LLM, without setting up a Python environment, downloading models manually, or knowing what bitnet.cpp is.

Concretely: the entire setup should be:

```
sudo add-apt-repository ppa:jeet/bitnet-server
sudo apt update
sudo apt install bitnet-server
curl localhost:11435/v1/chat/completions -d '{"messages":[{"role":"user","content":"hi"}]}'
```

If that works on a clean Ubuntu 24.04 amd64 VM, v0.1 is done.

## 2. Target audience

- Developers on low-RAM Linux machines without a GPU
- Self-hosters on cheap CPU-only VPSes (Hetzner CX11, $5/mo droplets) and SBCs (Raspberry Pi 5, Orange Pi)
- Privacy-focused users embedding an LLM into scripts, Home Assistant, n8n, etc.
- People who want OpenAI-compatible local inference *without* the heavier Ollama / llama.cpp stack and *without* a GPU

Explicitly **not** targeting: users who want top-tier quality (use Gemma 3 / Qwen 3 via Ollama), users with GPUs, users who want a chat UI, users who want multi-tenant team hosting.

## 3. Decisions locked

| Area | Decision | Rationale |
|---|---|---|
| Distribution channel | Debian PPA on Launchpad | Idiomatic Linux experience; highest user value for target audience |
| Support matrix | Ubuntu 24.04 LTS, amd64 only | Smallest viable matrix; forces shipping; v0.2 adds arm64 + 22.04 |
| Model | BitNet b1.58 2B4T only | Single model, hardcoded URL, simplest UX |
| Model delivery | Auto-fetch on first start | Avoids 1.2 GB .deb; Launchpad has size limits anyway |
| Daemon implementation | Pure passthrough of upstream bitnet.cpp `llama-server` | We package; we don't wrap; minimum surface area |
| Process lifecycle | **systemd socket-activated service** | Idle memory ~0; cold-start (~5–10 s) on first request after idle; better fit for low-RAM target audience than always-on |
| Port | `127.0.0.1:11435` | Loopback-only by default (security); one off from Ollama's 11434 to avoid conflict |
| Project name | `bitnet-server` | Boring, descriptive, follows Debian naming conventions |
| Build approach | Build bitnet.cpp from source in CI as part of .deb construction | Idiomatic Debian; tracks upstream via a single pinned commit/tag |
| License | MIT | Consistent with upstream bitnet.cpp and BitNet model weights |
| v0.1 done | PPA install works, service activates, curl succeeds, README has 3-command quickstart | Tight scope; iterate post-ship |

## 4. Architecture

### 4.1 Files installed by the .deb

| Path | Purpose |
|---|---|
| `/usr/bin/bitnet-server` | The compiled `llama-server` binary from upstream bitnet.cpp (renamed) |
| `/lib/systemd/system/bitnet-server.socket` | systemd socket unit listening on `127.0.0.1:11435` |
| `/lib/systemd/system/bitnet-server.service` | systemd service unit, started by the socket |
| `/usr/libexec/bitnet-server/fetch-model` | Shell script that downloads the model if missing, validates SHA256 |
| `/usr/libexec/bitnet-server/preflight` | Shell script that verifies free RAM and disk before model load |
| `/etc/bitnet-server/config.env` | systemd `EnvironmentFile` (port, threads, ctx size, model path, idle timeout) |
| `/usr/share/doc/bitnet-server/README.Debian` | Standard Debian doc: where logs live, where config lives, how to disable autostart |
| `/usr/share/doc/bitnet-server/copyright` | License attribution to bitnet.cpp and BitNet weights |

### 4.2 Things the .deb creates at install (postinst)

- `bitnet` system user/group (via `adduser --system --group --no-create-home --home /var/lib/bitnet-server`)
- `/var/lib/bitnet-server/` (owned by `bitnet:bitnet`, mode 750)
- `/var/lib/bitnet-server/models/` (subdir for the GGUF)
- Enables the **socket** (not the service) by default — zero idle memory cost

### 4.3 Things the .deb removes on `apt remove --purge`

- All installed files
- The `bitnet` system user
- `/var/lib/bitnet-server/` including the downloaded model
- On `apt remove` (no `--purge`): keeps `/var/lib/bitnet-server/` so reinstalls skip the model download

### 4.4 Repo layout

```
bitnet-server/
├── debian/
│   ├── control                          # Package metadata, deps
│   ├── rules                            # Build orchestration (calls bitnet.cpp's cmake)
│   ├── changelog                        # Hand-curated, Debian-format
│   ├── copyright                        # MIT + attribution
│   ├── compat                           # debhelper version
│   ├── bitnet-server.install            # File-mapping manifest
│   ├── bitnet-server.postinst           # User/dir creation, socket enable
│   ├── bitnet-server.postrm             # Cleanup on --purge
│   ├── bitnet-server.service            # systemd service unit (auto-installed by dh_installsystemd)
│   ├── bitnet-server.socket             # systemd socket unit (auto-installed by dh_installsystemd)
│   └── source/format                    # "3.0 (quilt)"
├── libexec/
│   ├── fetch-model                      # Model puller (POSIX sh + curl)
│   └── preflight                        # RAM + disk check
├── config/
│   └── config.env                       # Default EnvironmentFile
├── .github/workflows/
│   └── build-deb.yml                    # CI: build, lintian, integration test
├── docs/
│   └── superpowers/specs/...            # This spec lives here
├── README.md
├── LICENSE                              # MIT
└── .gitignore
```

## 5. Data flow

### 5.1 Install on a fresh box
1. `sudo add-apt-repository ppa:jeet/bitnet-server`
2. `sudo apt update && sudo apt install bitnet-server`
3. dpkg unpacks files. `postinst` runs:
   - Creates `bitnet` user
   - Creates `/var/lib/bitnet-server/models/` (empty)
   - `systemctl enable --now bitnet-server.socket`
4. The **socket** is now listening on `127.0.0.1:11435`. Service is **not** running. Memory cost: ~0.

### 5.2 First request
1. User runs `curl localhost:11435/v1/chat/completions -d '...'`
2. systemd detects connection on the socket, spawns `bitnet-server.service`
3. `ExecStartPre=/usr/libexec/bitnet-server/preflight` — verifies free RAM and disk
4. `ExecStartPre=/usr/libexec/bitnet-server/fetch-model` — checks for `bitnet-b1.58-2B-4T.gguf`; if missing, `curl -L` from HuggingFace into a `.tmp` file, verifies SHA256 against a pinned hash, atomically renames on success
5. `ExecStart=/usr/bin/bitnet-server --port $PORT --threads $THREADS --ctx-size $CTX -m $MODEL_PATH` (flags read from `config.env`)
6. Server binds the inherited socket, loads the model (~5–10 s on a 4-thread CPU), responds to the buffered request
7. Subsequent requests have no cold-start

### 5.3 Idle behavior
- After `IdleTimeoutSec=300` (5 min) with no requests, systemd stops the service
- The socket remains listening; next request triggers another cold start
- Idle timeout is configurable via `config.env`

### 5.4 Reboot
- Socket is enabled, so it comes back up on boot
- Service is not enabled directly — it's only spawned on demand
- No memory cost between reboot and first request

## 6. Component contracts

### 6.1 `fetch-model`
- Input: env vars `MODEL_URL`, `MODEL_PATH`, `MODEL_SHA256`
- Output: file at `$MODEL_PATH` with matching SHA256, exit 0; or stderr message + non-zero exit
- Idempotent: if `$MODEL_PATH` exists and SHA matches, no-op
- Failure modes: network down → clear stderr; SHA mismatch → delete file, fail (retry on next start)
- Atomic: downloads to `$MODEL_PATH.tmp`, renames on success

### 6.2 `preflight`
- Input: env vars `MIN_FREE_RAM_MB` (default 1500), `MIN_FREE_DISK_MB` (default 1500)
- Output: exit 0 if both checks pass; non-zero with clear stderr if either fails
- Reads `/proc/meminfo` for available RAM; `df` for disk

### 6.3 `bitnet-server.socket`
- `ListenStream=127.0.0.1:11435`
- `Accept=no` (single instance handles all connections)
- `WantedBy=sockets.target`

### 6.4 `bitnet-server.service`
- `User=bitnet`, `Group=bitnet`
- `Type=simple` (bitnet.cpp's `llama-server` is research-grade C++ unlikely to implement `sd_notify`; can be upgraded to `Type=notify` in a later version if upstream adds support)
- `EnvironmentFile=/etc/bitnet-server/config.env`
- `ExecStartPre=/usr/libexec/bitnet-server/preflight`
- `ExecStartPre=/usr/libexec/bitnet-server/fetch-model`
- `ExecStart=/usr/bin/bitnet-server [flags]`
- `Restart=on-failure`
- `RestartSec=5`
- `NoNewPrivileges=true`, `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`
- `ReadWritePaths=/var/lib/bitnet-server`
- `Sockets=bitnet-server.socket`

## 7. Error handling

| Failure | Handler |
|---|---|
| Model fetch network failure | `fetch-model` exits non-zero with clear stderr; systemd `Restart=on-failure` retries with backoff; user sees error in `journalctl -u bitnet-server` |
| SHA256 mismatch | `fetch-model` deletes the partial file, exits non-zero; next start re-fetches |
| Disk full during fetch | Preflight check refuses with clear stderr ("needs ~1.3 GB free in /var/lib/bitnet-server; you have X") |
| Port 11435 already bound | `bitnet-server.socket` fails to start; `systemctl status` surfaces it; README documents how to change port |
| Insufficient RAM | Preflight check refuses with clear stderr; if it slips through, kernel OOM (out of scope) |
| Binary crash during inference | `Restart=on-failure` brings it back; crash visible in `journalctl` |

**Explicitly out of scope at v0.1:** custom diagnostic CLI (`bitnet-server doctor`), structured error codes, alerting, auto-fallback to a different model.

## 8. Testing

| Check | Where | Gate |
|---|---|---|
| `lintian` on the built .deb | CI on every PR/push | Hard fail |
| Docker integration test: ubuntu:24.04 → apt install → curl → assert response shape | CI on every PR/push | Hard fail |
| Manual smoke test on a real Ubuntu 24.04 VM | Before tagging a release | Manual gate |

CI caches the 1.2 GB model file between runs using GitHub Actions cache to keep the integration test under ~30 s.

**Skipped on purpose:** unit tests on the systemd unit, perf benchmarks in CI, cross-distro tests, autopkgtest (defer until pushing to official Debian), stress/fuzz tests.

## 9. Release process

1. CI on every push to `main`: build .deb, run lintian, run integration test.
2. CI on git tag push (`v0.1.0` etc.): same checks + attach the .deb as a GitHub release artifact.
3. Maintainer downloads the .deb, GPG-signs locally with the key registered to Launchpad, runs `dput ppa:jeet/bitnet-server <changes-file>`.
4. Launchpad rebuilds and publishes; users see the new version on next `apt update`.

**Skipped at v0.1:** auto-dput from CI (revisit when release cadence > monthly), auto-generated changelogs, multi-arch builds, RC channels.

## 10. Working mode

This project is a *learning project* for the user. Implementation will proceed in pedagogical mode:

- The user writes all code by hand.
- Claude provides code snippets, explanations, and the order of operations.
- Claude may scaffold empty directories and empty files via Bash, but does **not** use `Write` or `Edit` to fill content during the implementation phase.
- One file at a time, in dependency order.
- After the user marks each file complete, the next begins.
- After the entire project is built, Claude may read the complete project and propose review/improvements.
- Claude pauses to ask for input on architectural choices, unfamiliar tooling, or whenever user judgment beats default conventions.

This is recorded so the implementation plan honors it.

## 11. v0.1 launch criteria

Boolean gate — all must be true:

- [ ] `sudo add-apt-repository ppa:jeet/bitnet-server && sudo apt update && sudo apt install bitnet-server` succeeds on a clean Ubuntu 24.04 amd64 VM
- [ ] After install, `curl localhost:11435/v1/chat/completions -d '{"messages":[{"role":"user","content":"say hi"}]}'` returns a valid OpenAI-shaped response within 30 s (cold start) on a 4-core CPU with ≥ 2 GB free RAM
- [ ] `systemctl status bitnet-server.socket` shows active (listening)
- [ ] `apt remove --purge bitnet-server` cleans up the user, files, and model dir
- [ ] README.md has a 3-command quickstart, troubleshooting section, and points to `journalctl -u bitnet-server` for logs
- [ ] LICENSE is MIT; copyright file in the .deb credits bitnet.cpp and BitNet weights

## 12. Out of scope for v0.1 (explicit non-goals)

- Multiple architectures (arm64, armhf)
- Multiple Ubuntu versions (22.04, 26.04)
- Multiple models or a model picker CLI
- Wrapping bitnet.cpp's server with our own Go/Rust process
- Auth, rate limiting, multi-tenant features
- Snap, Flatpak, Homebrew, Nix, AUR distribution
- Auto-publish from CI
- Custom UI / web admin panel
- Android port (planned v0.3+)
- Upstream contribution to Ollama or llama.cpp (planned v0.2+)

## 13. Post-ship roadmap (informational, not committed)

In rough order of leverage:
1. Android port via Termux (uses AOSP background)
2. PR to Ollama and/or llama.cpp adding BitNet support (highest community reach)
3. arm64 + Pi 5 / Orange Pi support
4. Second distribution channel (Flathub)
5. ARM CPU kernel tuning + benchmarks doc
