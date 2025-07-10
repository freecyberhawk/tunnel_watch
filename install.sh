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

target_ip=$(get_input "Enter the destination IP to check tunnel (e.g. 1.2.3.4): ")
ports=$(get_input "Enter comma-separated ports to monitor (e.g. 443,8443): ")
tunnel_type=$(get_input "Enter tunnel type (ping, http, ssh, frp, wireguard): ")
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
      if [ \$? -ne 0 ]; then
        echo "[FAIL] Ping failed for \$target_ip"
        all_ok=false
      else
        echo "[OK] Ping successful"
      fi
      ;;

    http)
      for port in "\${port_array[@]}"; do
        response=\$(curl -s --max-time 3 "http://\$target_ip:\$port/ping.php")
        if [[ "\$response" != "pong" ]]; then
          echo "[FAIL] No valid HTTP response on port \$port"
          all_ok=false
          break
        else
          echo "[OK] HTTP pong received from port \$port"
        fi
      done
      ;;

    ssh)
      ssh -q -o ConnectTimeout=5 -o BatchMode=yes "\$target_ip" exit
      if [ \$? -ne 0 ]; then
        echo "[FAIL] SSH connection failed to \$target_ip"
        all_ok=false
      else
        echo "[OK] SSH tunnel is up"
      fi
      ;;

    frp)
      for port in "\${port_array[@]}"; do
        nc -z -w 2 "\$target_ip" "\$port"
        if [ \$? -ne 0 ]; then
          echo "[FAIL] FRP port \$port unreachable"
          all_ok=false
          break
        else
          echo "[OK] FRP port \$port reachable"
        fi
      done
      ;;

    wireguard)
      ping -c 1 -W 2 "\$target_ip" >/dev/null 2>&1
      if [ \$? -ne 0 ]; then
        echo "[FAIL] WireGuard endpoint unreachable"
        all_ok=false
      else
        echo "[OK] WireGuard tunnel reachable"
      fi
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