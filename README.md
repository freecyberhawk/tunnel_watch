![Tunnel Watch](inc/tunnel_watch.jpg)

# 🚇 Tunnel Watch

**Tunnel Watch** is a lightweight and flexible tunnel/port monitoring tool for Linux. It watches local or remote ports (e.g., VPNs, SSH tunnels, reverse proxies) and **automatically restarts** a given `systemd` service if the tunnel fails multiple times in a row.

---

## 🔧 Features

- 🔌 Monitor one or more **ports** (e.g., `443`, `8443`, `2053`)
- 📡 Supports multiple **tunnel types**: `ping`, `http`, `ssh`, `frp`, `wireguard`
- ♻️ Automatically **restarts a systemd service** if the connection fails
- ⏱ Configurable **failure threshold** and **cooldown time**
- 🧩 Fully **interactive installer**
- 💻 Runs as a persistent, auto-restarting `systemd` service

---

## 🚀 Quick Start

Run this in your terminal (you need root access):

```bash
bash <(curl -s https://raw.githubusercontent.com/freecyberhawk/tunnel_watch/main/install.sh)
```

The installer will ask:

1. Destination IP or domain (e.g., `1.2.3.4`)
2. Comma-separated list of ports to monitor (e.g., `443,8443`)
3. Type of tunnel to monitor: `ping`, `http`, `ssh`, `frp`, `wireguard`
4. The name of the `systemd` service to restart (e.g., `hawk-proxy`)
5. Number of consecutive failures before restarting the service
6. Number of seconds to wait after restarting before checking again

---

## ⚙️ Tunnel Types & Requirements

| Tunnel Type | Purpose                       | Requirements on Remote (Target)                      | Requirements on Local (Monitor)           | Test Method              |
| ----------- | ----------------------------- | ---------------------------------------------------- | ----------------------------------------- | ------------------------ |
| `ping`      | Basic IP availability         | Responds to ICMP ping (enabled in firewall)          | `ping` installed                          | ICMP ping                |
| `http`      | Web tunnel or proxy check     | HTTP server running with `/ping` that returns `pong` | `curl` installed                          | Check HTTP response      |
| `ssh`       | SSH tunnel or port forwarding | SSH server running, key-based auth set up            | Private key in `~/.ssh/`, `ssh` installed | Run `ssh user@host exit` |
| `frp`       | Reverse proxy tunnel like FRP | `frps` running, reverse port exposed                 | `nc` (netcat) installed                   | Port check with `nc`     |
| `wireguard` | VPN tunnel with private IPs   | `wg` active, peer config valid                       | `ping`, WireGuard interface up            | Ping remote private IP   |

---

## 🛠 Dependencies

Make sure these tools are installed on the **monitoring server**:

- `bash`
- `nc` (netcat)
- `ping`
- `curl` (for HTTP mode)
- `ssh` (for SSH mode)
- A systemd-based Linux system

### 📦 Install missing tools

```bash
sudo apt update
sudo apt install netcat curl openssh-client iputils-ping
```

---

## 🌐 Example

To monitor an SSH tunnel to `10.0.0.2` on port `2222`, and restart the service `my-ssh-tunnel` after 3 failures:

```bash
bash <(curl -s https://raw.githubusercontent.com/freecyberhawk/tunnel_watch/main/install.sh)
```

Example answers to prompts:

```
Destination IP: 10.0.0.2
Ports to monitor: 2222
Tunnel type: ssh
Systemd service to restart: my-ssh-tunnel
Failures before restart: 3
Cooldown time: 10
```

---

## 💡 Advanced Tips

- For `http`, you can create a simple `ping_server.py` file on your server:

```python
from http.server import BaseHTTPRequestHandler, HTTPServer

class PingHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"pong")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server_address = ('0.0.0.0', 8080)  # you can change the port
    httpd = HTTPServer(server_address, PingHandler)
    print("🟢 HTTP Ping Server running on port 8080")
    httpd.serve_forever()
```

- For `ssh`, ensure your public key is added to the remote server's `~/.ssh/authorized_keys`.
- For `wireguard`, make sure the remote peer responds to ping over the VPN interface (e.g., `10.66.66.1`).

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
