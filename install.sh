#!/bin/bash

echo -e "\033[1;36m"
cat << "EOF"
 _____                       _  __        __    _       _
|_   _|   _ _ __  _ __   ___| | \ \      / /_ _| |_ ___| |__
  | || | | | '_ \| '_ \ / _ \ |  \ \ /\ / / _` | __/ __| '_ \
  | || |_| | | | | | | |  __/ |   \ V  V / (_| | || (__| | | |
  |_| \__,_|_| |_|_| |_|\___|_|    \_/\_/ \__,_|\__\___|_| |_|
EOF
echo -e "          github.com/\033[4mfreecyberhawk\033[0m"
echo -e "\033[0m"

set -e

echo "Setting up Tunnel Monitor..."

get_input() {
  local prompt="$1"
  local var
  while true; do
    read -p "$prompt" var
    if [[ -n "$var" ]]; then
      echo "$var"
      return
    else
      echo "⚠️ Input cannot be empty. Please try again."
    fi
  done
}

tunnel_type=$(get_input "Enter tunnel type (ping, http, ssh, frp, wireguard): ")

# Defaults for http tunnel type
if [[ "$tunnel_type" == "http" ]]; then
  target_ip="127.0.0.1"
  echo "Using default target IP for HTTP: $target_ip"
else
  target_ip=$(get_input "Enter the destination IP to check tunnel (e.g. 127.0.0.1): ")
fi

ports=$(get_input "Enter comma-separated ports to monitor (e.g. 443,8443): ")
service_name=$(get_input "Enter the systemd service name to restart: ")
fail_limit=$(get_input "Enter the number of consecutive failures to trigger restart: ")
cooldown=$(get_input "Enter seconds to wait after restart before checking again: ")

monitor_script_path="/usr/local/bin/tunnel-monitor.sh"
cat <<EOF > "$monitor_script_path"
#!/bin/bash
target_ip="$target_ip"
ports="$ports"
tunnel_type="$tunnel_type"
service_name="$service_name"
fail_limit=$fail_limit
cooldown=$cooldown

IFS=',' read -ra port_array <<< "\$ports"
fail_counter=0

echo "🟢 Tunnel Monitor started for \$target_ip using tunnel type: \$tunnel_type"

while true; do
  all_ok=true

  case "\$tunnel_type" in
    ping)
      ping -c 1 -W 2 "\$target_ip" >/dev/null 2>&1
      [ \$? -ne 0 ] && echo "[FAIL] Ping failed for \$target_ip" && all_ok=false || echo "[OK] Ping successful"
      ;;

    http)
      monitor_port=9999
      py_script="/usr/local/bin/ping_server_$monitor_port.py"

      # Create ping server script if not already exists
      if [ ! -f "$py_script" ]; then
        cat <<PYEOF > "$py_script"
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

        def log_message(self, format, *args):
            return

    if __name__ == '__main__':
        server_address = ('127.0.0.1', $monitor_port)
        httpd = HTTPServer(server_address, PingHandler)
        print(f"🟢 Ping server running on port {server_address[1]}")
        httpd.serve_forever()
    PYEOF

        chmod +x "$py_script"
      fi

      # Start server only if port not already in use
      if ! lsof -i :$monitor_port >/dev/null 2>&1; then
        nohup python3 "$py_script" > "/var/log/ping_server_$monitor_port.log" 2>&1 &
        echo "[+] Started local ping server on port $monitor_port"
      else
        echo "[!] Port $monitor_port already in use. Assuming ping server is running."
      fi

      # Now check the tunnel by requesting /ping on each target port
      for port in "${port_array[@]}"; do
        response=$(curl -s -o /dev/null -w "%{http_code}" "http://$target_ip:$port/ping")
        if [[ "$response" != "200" ]]; then
          echo "[FAIL] HTTP check failed on port $port (status code: $response)"
          all_ok=false
          break
        else
          echo "[OK] HTTP pong received from $target_ip:$port"
        fi
      done
      ;;


    wireguard)
      ping -c 1 -W 2 "\$target_ip" >/dev/null 2>&1
      [ \$? -ne 0 ] && echo "[FAIL] WireGuard endpoint unreachable" && all_ok=false || echo "[OK] WireGuard tunnel reachable"
      ;;

    *)
      echo "❌ Unsupported tunnel type: \$tunnel_type"
      exit 1
      ;;
  esac

  if [ "\$all_ok" = true ]; then
    fail_counter=0
  else
    ((fail_counter++))
    echo "❌ Failure count: \$fail_counter/\$fail_limit"
  fi

  if [ "\$fail_counter" -ge "\$fail_limit" ]; then
    echo "🔁 Restarting service: \$service_name"
    systemctl restart "\$service_name"
    echo "⏳ Waiting \$cooldown seconds after restart..."
    sleep "\$cooldown"
    fail_counter=0
  else
    sleep 1
  fi
done
EOF

chmod +x "$monitor_script_path"

service_file="/etc/systemd/system/tunnel-monitor.service"
cat <<EOF > "$service_file"
[Unit]
Description=Tunnel Port Monitor
After=network.target

[Service]
ExecStart=$monitor_script_path
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable tunnel-monitor.service
systemctl restart tunnel-monitor.service

echo "✅ Tunnel Monitor service installed and started successfully!"