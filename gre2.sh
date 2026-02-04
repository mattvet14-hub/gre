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

TUN_NAME="vatan-m2"
SCRIPT_PATH="/usr/local/bin/vatan-gre.sh"
SERVICE_PATH="/etc/systemd/system/vatan-gre.service"

### -------- create tunnel script --------
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

set -e

if ip link show "$TUN_NAME" &>/dev/null; then
    exit 0
fi

if [[ "$LOCATION" == "1" ]]; then
    sudo ip tunnel add vatan-m2 mode gre local $IP_IRAN remote $IP_FOREIGN ttl 255
    sudo ip link set vatan-m2 up
    sudo ip addr add 132.168.30.2/30 dev vatan-m2
   sysctl net.ipv4.ip_forward=1
iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination 132.168.30.2
iptables -t nat -A PREROUTING -j DNAT --to-destination 132.168.30.1
iptables -t nat -A POSTROUTING -j MASQUERADE

elif [[ "$LOCATION" == "2" ]]; then
    sudo ip tunnel add vatan-m2 mode gre local $IP_FOREIGN remote $IP_IRAN ttl 255
    sudo ip link set vatan-m2 up
    sudo ip addr add 132.168.30.1/30 dev vatan-m2

    sudo iptables -A INPUT --proto icmp -j DROP
fi
EOF

chmod +x "$SCRIPT_PATH"

### -------- create systemd service --------
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=vatan GRE Tunnel
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
systemctl enable vatan-gre
systemctl start vatan-gre

echo
echo "===================================="
echo "[✓] GRE Tunnel installed successfully"
echo "[✓] Tunnel name: $TUN_NAME"
echo "[✓] Auto-start enabled (systemd)"
echo "===================================="
