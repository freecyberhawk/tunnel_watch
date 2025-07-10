#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root."
  exit 1
fi

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

# Check dependencies
for cmd in lsof curl python3 systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command '$cmd' not found. Please install it before running this script."
    exit 1
  fi
done

echo "Setting up Tunnel Monitor..."

get_input() {
  local prompt="$1"
  local var
  while true; do
    read -rp "$prompt" var
    if [[ -n "$var" ]]; then
      echo "$var"
      return
    else
      echo "⚠️ Input cannot be empty. Please try again."
    fi
  done
}

valid_tunnel_types=("ping" "http" "wireguard")

while true; do
  tunnel_type=$(get_input "Enter tunnel type (ping, http, wireguard): ")
  if [[ " ${valid_tunnel_types[*]} " == *" $tunnel_type "* ]]; then
    break
  else
    echo "⚠️ Invalid tunnel type. Choose one of: ping, http, wireguard."
  fi
done

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
ping_server_port=9999
ping_server_script="/usr/local/bin/ping_server_$ping_server_port.py"
ping_server_log="/var/log/ping_server_$ping_server_port.log"
monitor_log="/var/log/tunnel-monitor.log"

cat <<EOF > "$monitor_script_path"
#!/bin/bash

target_ip="$target_ip"
ports="$ports"
tunnel_type="$tunnel_type"
service_name="$service_name"
fail_limit=$fail_limit
cooldown=$cooldown
ping_server_port=$ping_server_port

IFS=',' read -ra port_array <<< "\$ports"
fail_counter=0

echo "🟢 Tunnel Monitor started for \$target_ip using tunnel type: \$tunnel_type" | tee -a "$monitor_log"

start_ping_server() {
  if ! lsof -i :\$ping_server_port >/dev/null 2>&1; then
    echo "[+] Starting local ping server on port \$ping_server_port" | tee -a "$monitor_log"
    nohup python3 "$ping_server_script" >> "$ping_server_log" 2>&1 &
    sleep 1
  else
    echo "[!] Ping server already running on port \$ping_server_port" | tee -a "$monitor_log"
  fi
}

if [[ "\$tunnel_type" == "http" ]]; then
  if [ ! -f "$ping_server_script" ]; then
    cat <<PYEOF > "$ping_server_script"
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
        pass

if __name__ == '__main__':
    server_address = ('127.0.0.1', $ping_server_port)
    httpd = HTTPServer(server_address, PingHandler)
    print(f"🟢 Ping server running on port {server_address[1]}", flush=True)
    httpd.serve_forever()
PYEOF
    chmod +x "$ping_server_script"
  fi
  start_ping_server
fi

set +e

while true; do
  case "\$tunnel_type" in
    ping)
      if ping -c 1 -W 2 "\$target_ip" >/dev/null 2>&1; then
        echo "[OK] Ping successful" | tee -a "$monitor_log"
        fail_counter=0
      else
        echo "[FAIL] Ping failed for \$target_ip" | tee -a "$monitor_log"
        ((fail_counter++))
        echo "❌ Failure count: \$fail_counter/\$fail_limit" | tee -a "$monitor_log"
      fi
      ;;

    http)
      declare -A fail_counters
      while true; do
        for port in "${port_array[@]}"; do
          response=$(curl -s -o /dev/null -w "%{http_code}" "http://$target_ip:$port/ping")

          if [[ "$response" == "200" ]]; then
            echo "[OK] Tunnel to $target_ip:$port is UP" | tee -a "$monitor_log"
            fail_counters["$port"]=0
          else
            echo "[FAIL] HTTP check failed on port $port (status code: $response)" | tee -a "$monitor_log"
            fail_counters["$port"]=$(( ${fail_counters["$port"]:-0} + 1 ))
            echo "❌ Port $port failure count: ${fail_counters["$port"]}/$fail_limit" | tee -a "$monitor_log"

            if [[ ${fail_counters["$port"]} -ge $fail_limit ]]; then
              echo "🔁 Restarting service: $service_name due to $fail_limit consecutive failures on port $port" | tee -a "$monitor_log"
              systemctl restart "$service_name"
              echo "⏳ Waiting $cooldown seconds after restart..." | tee -a "$monitor_log"
              sleep "$cooldown"

              # Reset all counters
              for p in "${port_array[@]}"; do
                fail_counters["$p"]=0
              done
              break 2  # exit both for loop and while loop
            fi
          fi
        done
        sleep 1
      done
      ;;

    wireguard)
      if ping -c 1 -W 2 "\$target_ip" >/dev/null 2>&1; then
        echo "[OK] WireGuard tunnel reachable" | tee -a "$monitor_log"
        fail_counter=0
      else
        echo "[FAIL] WireGuard endpoint unreachable" | tee -a "$monitor_log"
        ((fail_counter++))
        echo "❌ Failure count: \$fail_counter/\$fail_limit" | tee -a "$monitor_log"
      fi
      ;;

    *)
      echo "❌ Unsupported tunnel type: \$tunnel_type" | tee -a "$monitor_log"
      exit 1
      ;;
  esac

  if [ "\$fail_counter" -ge "\$fail_limit" ]; then
    echo "🔁 Restarting service: \$service_name" | tee -a "$monitor_log"
    systemctl restart "\$service_name"
    echo "⏳ Waiting \$cooldown seconds after restart..." | tee -a "$monitor_log"
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
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=tunnel-monitor
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tunnel-monitor.service
systemctl restart tunnel-monitor.service

echo "✅ Tunnel Monitor service installed and started successfully!"