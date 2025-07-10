![Tunnel Watch](inc/tunnel_watch.jpg)

# 🚇 Tunnel Watch

**Tunnel Watch** is a lightweight and flexible tunnel/port monitoring tool for Linux. It watches local or remote ports (e.g., VPNs, SSH tunnels, reverse proxies) and `automatically restarts` a given `systemd` service if the tunnel fails multiple times in a row.

---

## 🔧 Features

- 📡 Supports multiple `tunnel types`: `ping`, `http`, `ssh`, `frp`, `wireguard`
- 🔌 Monitor one or more `ports` (e.g., `443`, `8443`, `2053`)
- ♻️ Automatically `restarts a systemd service` if the connection fails
- ⏱ Configurable `failure threshold` and `cooldown time`
- 🧩 Fully `interactive installer`
- 💻 Runs as a persistent, auto-restarting `systemd` service

---

## 🚀 Quick Start

Run this in your terminal (you need root access):

```bash
bash <(curl -s https://raw.githubusercontent.com/freecyberhawk/tunnel_watch/main/install.sh)
```

The installer will ask:

1. Tunnel type to monitor: `ping`, `http`, `ssh`, `frp`, `wireguard`
2. Depending on the tunnel type:
   - `ping`, `ssh`, `frp`, `wireguard`: enter the remote IP to check
   - `http`: uses `127.0.0.1` and launches built-in Python servers automatically
3. Comma-separated list of ports to monitor (not required for `ping`/`ssh`)
4. The name of the `systemd` service to restart (e.g., `hawk-proxy`)
5. Number of consecutive failures before restarting the service
6. Number of seconds to wait after restarting before checking again

---

## ⚙️ Tunnel Types & Requirements

| Tunnel Type | Purpose                       | Auto Target Address | Remote Requirements                 | Local Requirements          | Test Method            |
| ----------- | ----------------------------- | ------------------- | ----------------------------------- | --------------------------- | ---------------------- |
| `ping`      | Basic IP availability         | User-defined IP     | ICMP enabled in firewall            | `ping`                      | ICMP ping              |
| `http`      | Web tunnel or proxy check     | `127.0.0.1`         | Nothing required                    | `curl`, auto-starts Python  | `/ping` → `pong`       |
| `ssh`       | SSH tunnel or port forwarding | User-defined IP     | SSH server + key-based auth         | `ssh`, private key setup    | `ssh user@host exit`   |
| `frp`       | Reverse proxy tunnel like FRP | User-defined IP     | `frps` running + reverse ports open | `nc` (netcat)               | Port check with `nc`   |
| `wireguard` | VPN tunnel with private IPs   | User-defined IP     | `wg` configured + ICMP reachable    | `ping`, WireGuard interface | Ping remote private IP |

---

## 🛠 Dependencies

Make sure these tools are installed on the `monitoring server`:

- `bash`
- `nc` (netcat)
- `ping`
- `curl` (for `http` mode)
- `ssh` (for `ssh` mode)
- A `systemd`-based Linux system

### 📦 Install missing tools

```bash
sudo apt update
sudo apt install netcat curl openssh-client iputils-ping
```

---

## 🧩 Systemd Integration

Tunnel Watch installs a service at:

```
/etc/systemd/system/tunnel-monitor.service
```

Start/Stop manually if needed:

```bash
sudo systemctl start tunnel-monitor
sudo systemctl status tunnel-monitor
```

---

## ☕️ Buy me a Coffee

Tether-USDT (BEP20): `0xe52d86cf875b11d8b95ab750e68fd418bba763b8`

---

## 📎 License

MIT License © [freecyberhawk](https://github.com/freecyberhawk)
