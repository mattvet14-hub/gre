#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root"
  exit 1
fi

CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

REGISTRY_FILE="/etc/gre-tunnels/registry"
mkdir -p /etc/gre-tunnels

echo -e "${CYAN}"
echo "===================================="
echo "        GitHub: mattvet14-hub"
echo "   GRE Tunnel v4 Setup Script"
echo "===================================="
echo -e "${RESET}"

# نمایش تانل‌های قبلی
if [[ -f "$REGISTRY_FILE" ]] && [[ -s "$REGISTRY_FILE" ]]; then
  echo "[i] Existing tunnels on this server:"
  cat "$REGISTRY_FILE"
  echo ""
fi

# انتخاب اسم تانل
read -p "Enter tunnel name (e.g. tun1, iran-de): " TUN_LABEL
if [[ -z "$TUN_LABEL" ]]; then
  echo "[!] Tunnel name cannot be empty"
  exit 1
fi

TUN_NAME="gre-${TUN_LABEL}"
SCRIPT_PATH="/usr/local/bin/gre-${TUN_LABEL}.sh"
SERVICE_NAME="gre-${TUN_LABEL}"
SERVICE_PATH="/etc/systemd/system/gre-${TUN_LABEL}.service"

if [[ -f "$SERVICE_PATH" ]]; then
  echo "[!] Tunnel '$TUN_LABEL' already exists!"
  echo "    To remove it first run:"
  echo "    systemctl stop $SERVICE_NAME && systemctl disable $SERVICE_NAME"
  echo "    rm $SERVICE_PATH $SCRIPT_PATH"
  echo "    ip tunnel del $TUN_NAME 2>/dev/null"
  echo "    sed -i '/^${TUN_LABEL}:/d' $REGISTRY_FILE"
  exit 1
fi

echo "Select server location:"
echo "1 - IRAN"
echo "2 - FOREIGN"
read -p "Enter 1 or 2: " LOCATION

read -p "Enter IRAN server IP: " IP_IRAN
read -p "Enter FOREIGN server IP: " IP_FOREIGN

# کاربر شماره subnet رو وارد میکنه - باید روی هر دو سرور یکی باشه
echo ""
echo "[i] Choose a subnet ID (1-254) - use the SAME number on both servers"
echo "    Example: if you enter 5, IPs will be 10.201.5.1 and 10.201.5.2"
read -p "Enter subnet ID: " SUBNET_ID

# اعتبارسنجی
if ! [[ "$SUBNET_ID" =~ ^[0-9]+$ ]] || [[ "$SUBNET_ID" -lt 1 ]] || [[ "$SUBNET_ID" -gt 254 ]]; then
  echo "[!] Subnet ID must be a number between 1 and 254"
  exit 1
fi

# چک کردن تکراری بودن subnet ID
if grep -q "subnet_id=${SUBNET_ID}$" "$REGISTRY_FILE" 2>/dev/null; then
  echo "[!] Subnet ID $SUBNET_ID is already used by another tunnel!"
  echo "    Used IDs:"
  grep "subnet_id=" "$REGISTRY_FILE" | awk -F'subnet_id=' '{print "    ID: "$2}' | sort -t= -k2 -n
  exit 1
fi

TUN_IP_FOREIGN="10.201.${SUBNET_ID}.1"
TUN_IP_IRAN="10.201.${SUBNET_ID}.2"

echo ""
echo "[i] Tunnel internal IPs:"
echo "    IRAN side   : $TUN_IP_IRAN"
echo "    FOREIGN side: $TUN_IP_FOREIGN"
echo "    Subnet      : 10.201.${SUBNET_ID}.0/30"
echo ""

# ذخیره در رجیستری
echo "${TUN_LABEL}: iran=${TUN_IP_IRAN} | foreign=${TUN_IP_FOREIGN} | subnet_id=${SUBNET_ID}" >> "$REGISTRY_FILE"

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
echo "[✓] Subnet ID   : $SUBNET_ID"
echo "[✓] IRAN IP     : $TUN_IP_IRAN"
echo "[✓] FOREIGN IP  : $TUN_IP_FOREIGN"
echo "[✓] Auto-start enabled (systemd)"
echo "===================================="
echo ""
echo "⚠️  Use subnet ID [ $SUBNET_ID ] on the other server too!"
echo ""
echo "All tunnels: cat $REGISTRY_FILE"
echo ""
echo "To remove this tunnel:"
echo "  systemctl stop $SERVICE_NAME && systemctl disable $SERVICE_NAME"
echo "  rm $SERVICE_PATH $SCRIPT_PATH"
echo "  ip tunnel del $TUN_NAME 2>/dev/null"
echo "  sed -i '/^${TUN_LABEL}:/d' $REGISTRY_FILE"
echo "===================================="
