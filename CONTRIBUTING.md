# Contributing

## Building

Requires Ubuntu 24.04 (amd64), clang, cmake, git, debhelper.

```bash
sudo apt install build-essential debhelper cmake clang git curl ca-certificates
dpkg-buildpackage -us -uc -b
```

## Testing

```bash
./test-socket-activation.sh
```

## Socket Activation Patch

This package patches llama.cpp to support systemd socket activation.

The modification adds ~15 lines to `server.cpp`:
- Check `LISTEN_FDS` and `LISTEN_PID` environment variables
- If set by systemd, use fd 3 instead of calling `bind()`
- Add `set_socket()` method to httplib::Server

Changes are applied via sed in [debian/rules](debian/rules) (lines 24-38).

### Upstream Status

Not yet submitted. Plan:
1. Open issue on [ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp)
2. Port sed modifications to a proper commit
3. Submit PR with test evidence (112 KB idle vs 1.4 GB always-on)

### Why Upstream Would Accept This

- Minimal change (~15 lines in server.cpp, ~3 lines in httplib.h)
- Backward compatible (no-op without LISTEN_FDS)
- Solves real problem (resource-constrained deployments)
- Standard systemd API (sd_listen_fds protocol)

## Reporting Issues

Open an issue with:
- Ubuntu version
- `systemctl status bitnet-server.socket`
- `journalctl -u bitnet-server.service -n 50`
