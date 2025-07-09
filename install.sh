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

# Prompt with validation
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
service_name=$(get_input "Enter the systemd service name to restart: ")
fail_limit=$(get_input "Enter the number of consecutive failures to trigger restart: ")
cooldown=$(get_input "Enter seconds to wait after restart before checking again: ")

# Save the monitor script
monitor_script_path="/usr/local/bin/tunnel-monitor.sh"
cat <<EOF > "$monitor_script_path"
#!/bin/bash
target_ip="$target_ip"
ports="$ports"
service_name="$service_name"
fail_limit=$fail_limit
cooldown=$cooldown

IFS=',' read -ra port_array <<< "\$ports"
fail_counter=0

echo "🟢 Tunnel Monitor started for \$target_ip ports: \$ports"

while true; do
  all_ok=true
  for port in "\${port_array[@]}"; do
    nc -z -w 3 "\$target_ip" "\$port" >/dev/null 2>&1
    if [ \$? -ne 0 ]; then
      echo "[FAIL] Port \$port on \$target_ip is unreachable"
      all_ok=false
      break
    else
      echo "[OK] Port \$port on \$target_ip is reachable"
    fi
  done

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

# Create systemd service
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

# Enable and start the service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable tunnel-monitor.service
systemctl restart tunnel-monitor.service

echo "✅ Tunnel Monitor service installed and started successfully!"