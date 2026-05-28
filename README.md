# LinuxGuard-Go

LinuxGuard-Go is a lightweight Linux personal cybersecurity agent written in Go. It is ported from WinGuard-Go and keeps the same core guard surface: brute-force detection, firewall-backed IP blocking, outbound process monitoring, Telegram alerts, JSONL storage, a local dashboard, and service helpers.

## Implemented Surface

- Linux firewall manager for inbound and outbound IP blocks using `iptables` / `ip6tables`
- Duplicate-rule protection with a local LinuxGuard rule registry
- SSH brute-force detection from `journalctl` for `ssh` / `sshd`
- Outbound connection scanner using `ss` with `netstat` fallback
- Linux process path and ancestry lookup through `/proc`
- Suspicious outbound process scoring and optional process termination
- Telegram alert sender with test command
- JSONL-backed local storage for alerts, blocked IPs, and outbound events
- Local dashboard at `127.0.0.1:8765`
- systemd install, uninstall, and status helpers

## Quick Start

```bash
cp configs/config.example.yaml configs/config.yaml
go build -o bin/linuxguard ./cmd/linuxguard
sudo ./bin/linuxguard serve --config configs/config.yaml
```

Open the dashboard:

```text
http://127.0.0.1:8765
```

## CLI Commands

```text
linuxguard serve
linuxguard install-service
linuxguard uninstall-service
linuxguard status
linuxguard rules list
linuxguard rules block-ip <ip>
linuxguard rules unblock-ip <ip>
linuxguard rules block-app <path>
linuxguard rules unblock-app <path>
linuxguard scan outbound
linuxguard test telegram
```

## Service Mode

Build and install as a systemd service:

```bash
go build -o bin/linuxguard ./cmd/linuxguard
sudo ./bin/linuxguard install-service --config "$(pwd)/configs/config.yaml"
```

From the parent `xAVG` workspace, the full One Secure installer can also install and start the service:

```bash
sudo ./one-secure-setup.sh
```

Or use the helper for foreground-style background runs during development:

```bash
./run-service.sh -build -start
./run-service.sh -stop
```

## Notes

- Run as root, or with equivalent capabilities, when applying firewall rules, reading protected journal entries, or terminating blocked processes.
- `rules block-app` persists an application block in LinuxGuard's local registry. Linux does not have a direct built-in equivalent to Windows Firewall per-executable rules, so enforcement for app blocks happens through outbound scan detection plus process termination.
- IP blocks are enforced with comments matching the configured `firewall.rule_prefix`, allowing LinuxGuard-Go to clean up expired rules it created.
