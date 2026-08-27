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
echo "   GRE Tunnel v2 Setup Script"
echo "===================================="
echo -e "${RESET}"

# انتخاب اسم تانل
read -p "Enter tunnel name (e.g. tun1, myserver, iran-de): " TUN_LABEL
if [[ -z "$TUN_LABEL" ]]; then
  echo "[!] Tunnel name cannot be empty"
  exit 1
fi

# ساخت اسم‌های یونیک بر اساس اسم انتخابی
TUN_NAME="gre-${TUN_LABEL}"
SCRIPT_PATH="/usr/local/bin/gre-${TUN_LABEL}.sh"
SERVICE_NAME="gre-${TUN_LABEL}"
SERVICE_PATH="/etc/systemd/system/gre-${TUN_LABEL}.service"

# چک کردن اینکه آیا قبلاً این تانل ساخته شده
if [[ -f "$SERVICE_PATH" ]]; then
  echo "[!] Tunnel '$TUN_LABEL' already exists!"
  echo "    To remove it first run:"
  echo "    systemctl stop $SERVICE_NAME && systemctl disable $SERVICE_NAME"
  echo "    rm $SERVICE_PATH $SCRIPT_PATH"
  echo "    ip tunnel del $TUN_NAME 2>/dev/null"
  exit 1
fi

echo "Select server location:"
echo "1 - IRAN"
echo "2 - FOREIGN"
read -p "Enter 1 or 2: " LOCATION

read -p "Enter IRAN server IP: " IP_IRAN
read -p "Enter FOREIGN server IP: " IP_FOREIGN

# IP داخلی تانل - هر تانل یه subnet جدا داره
# از اسم تانل یه عدد منحصربه‌فرد می‌سازیم
TUN_HASH=$(echo "$TUN_LABEL" | cksum | awk '{print $1 % 200 + 10}')
TUN_IP_IRAN="10.200.${TUN_HASH}.2"
TUN_IP_FOREIGN="10.200.${TUN_HASH}.1"

echo ""
echo "[i] Tunnel internal IPs:"
echo "    IRAN side   : $TUN_IP_IRAN"
echo "    FOREIGN side: $TUN_IP_FOREIGN"
echo ""

### -------- create tunnel script --------
cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

if ip link show "$TUN_NAME" &>/dev/null; then
    exit 0
fi

if [[ "$LOCATION" == "1" ]]; then
    ip tunnel add $TUN_NAME mode gre local $IP_IRAN remote $IP_FOREIGN ttl 255
    ip link set $TUN_NAME up
    ip addr add ${TUN_IP_IRAN}/30 dev $TUN_NAME
    sysctl -w net.ipv4.ip_forward=1
    iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination ${TUN_IP_IRAN}
    iptables -t nat -A PREROUTING -j DNAT --to-destination ${TUN_IP_FOREIGN}
    iptables -t nat -A POSTROUTING -j MASQUERADE

elif [[ "$LOCATION" == "2" ]]; then
    ip tunnel add $TUN_NAME mode gre local $IP_FOREIGN remote $IP_IRAN ttl 255
    ip link set $TUN_NAME up
    ip addr add ${TUN_IP_FOREIGN}/30 dev $TUN_NAME
    iptables -A INPUT --proto icmp -j DROP
fi
EOF

chmod +x "$SCRIPT_PATH"

### -------- create systemd service --------
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=GRE Tunnel - ${TUN_LABEL}
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
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

echo ""
echo "===================================="
echo "[✓] GRE Tunnel installed successfully"
echo "[✓] Tunnel name : $TUN_NAME"
echo "[✓] Service name: $SERVICE_NAME"
echo "[✓] IRAN IP     : $TUN_IP_IRAN"
echo "[✓] FOREIGN IP  : $TUN_IP_FOREIGN"
echo "[✓] Auto-start enabled (systemd)"
echo "===================================="
echo ""
echo "To remove this tunnel later:"
echo "  systemctl stop $SERVICE_NAME"
echo "  systemctl disable $SERVICE_NAME"
echo "  rm $SERVICE_PATH $SCRIPT_PATH"
echo "  ip tunnel del $TUN_NAME 2>/dev/null"
echo "===================================="
