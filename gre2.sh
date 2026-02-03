#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root"
  exit 1
fi

CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

echo -e "${CYAN}"
echo "===================================="
echo "        GitHub: mattvet14-hub"
echo "   GRE Tunnel v1 Setup Script"
echo "===================================="
echo -e "${RESET}"

echo "Select server location:"
echo "1 - IRAN"
echo "2 - FOREIGN"
read -p "Enter 1 or 2: " LOCATION

read -p "Enter IRAN server IP: " IP_IRAN
read -p "Enter FOREIGN server IP: " IP_FOREIGN

TUN_NAME="peaknet-m2"
SCRIPT_PATH="/usr/local/bin/peaknet-gre.sh"
SERVICE_PATH="/etc/systemd/system/peaknet-gre.service"

### -------- create tunnel script --------
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

set -e

if ip link show "$TUN_NAME" &>/dev/null; then
    exit 0
fi

if [[ "$LOCATION" == "1" ]]; then
    ip tunnel add $TUN_NAME mode gre local $IP_IRAN remote $IP_FOREIGN ttl 255
    ip link set $TUN_NAME up
    ip addr add 132.168.30.2/30 dev $TUN_NAME

    sysctl -w net.ipv4.ip_forward=1

    iptables -A FORWARD -i eth0 -o $TUN_NAME -j ACCEPT
    iptables -A FORWARD -i $TUN_NAME -o eth0 -j ACCEPT
    iptables -t nat -A POSTROUTING -o $TUN_NAME -j MASQUERADE

elif [[ "$LOCATION" == "2" ]]; then
    ip tunnel add $TUN_NAME mode gre local $IP_FOREIGN remote $IP_IRAN ttl 255
    ip link set $TUN_NAME up
    ip addr add 132.168.30.1/30 dev $TUN_NAME

    sysctl -w net.ipv4.ip_forward=1
fi
EOF

chmod +x "$SCRIPT_PATH"

### -------- create systemd service --------
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=peaknet GRE Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

### -------- enable service --------
systemctl daemon-reload
systemctl enable peaknet-gre
systemctl start peaknet-gre

echo
echo "===================================="
echo "[✓] GRE Tunnel installed successfully"
echo "[✓] Tunnel name: $TUN_NAME"
echo "[✓] Auto-start enabled (systemd)"
echo "===================================="
