# bitnet-server

Run Microsoft's [BitNet b1.58 2B4T](https://huggingface.co/microsoft/BitNet-b1.58-2B-4T) locally as an OpenAI-compatible API.

CPU-only. No GPU required. Socket activation: **112 KB idle RAM**.

---

## Install

```bash
sudo add-apt-repository ppa:satyajeet1827/bitnet-server
sudo apt update
sudo apt install bitnet-server
```

Model (~1.2 GB) downloads automatically on first request.

## Usage

```bash
curl http://localhost:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}'
```

```bash
systemctl status bitnet-server.socket   # check socket
journalctl -u bitnet-server.service -f  # view logs
```

## How It Works

```
Idle:     systemd socket listening (112 KB RAM)
          ↓ first request arrives
Active:   llama-server starts, loads model (1.4 GB RAM)
          ↓ handles request
Running:  stays loaded for subsequent requests
```

No daemon running when idle. Service starts on-demand via systemd socket activation.

## Features

| | bitnet-server | Ollama | Manual build |
|---|---|---|---|
| Idle RAM | 112 KB | ~400 MB | N/A |
| BitNet support | ✓ | ✗ | ✓ |
| Install | `apt install` | binary/Docker | cmake + clang |
| Socket activation | ✓ | ✗ | ✗ |
| Systemd integration | ✓ | ✗ | Manual |

Ollama uses standard inference. BitNet requires [specialized kernels](https://github.com/microsoft/BitNet) that Ollama doesn't support.

## Configuration

```bash
sudo nano /etc/bitnet-server/config.env
sudo systemctl restart bitnet-server.service
```

```env
PORT=11435
THREADS=4
CTX_SIZE=2048
```

## Requirements

- Ubuntu 24.04 (amd64)
- 2 GB RAM
- 1.5 GB disk (for model)

## Uninstall

```bash
sudo apt remove bitnet-server    # keep model
sudo apt purge bitnet-server     # remove everything
```

## Development

```bash
dpkg-buildpackage -us -uc -b     # build .deb
./test-socket-activation.sh      # run tests
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for upstream patch details.

## License

MIT. Builds on [bitnet.cpp](https://github.com/microsoft/BitNet) (MIT) and [BitNet b1.58 2B4T](https://huggingface.co/microsoft/bitnet-b1.58-2B-4T) (MIT).
