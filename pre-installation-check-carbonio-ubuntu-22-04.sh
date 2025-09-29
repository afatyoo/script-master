#!/bin/bash
echo "================================================"
echo "= Initial Setup Carbonio Script for Ubuntu 22/24="
echo "= by: TYO-CHAN                                 ="
echo "================================================" 
set -e
sleep 3
# ==== Check Static IP or DHCP ====
echo
echo
echo "[0/6] Checking network configuration..."
if [ -f /etc/redhat-release ]; then
    # RHEL based check
    IFACE=$(nmcli -t -f DEVICE,STATE d | grep ":connected" | cut -d: -f1 | head -n1)
    BOOTPROTO=$(nmcli -g ipv4.method con show $IFACE)
    if [ "$BOOTPROTO" == "auto" ]; then
        echo "❌ Server masih pakai DHCP (dynamic IP)."
        echo "👉 Disarankan ganti ke static IP sebelum lanjut."
        exit 1
    else
        echo "✅ Server sudah pakai static IP."
    fi
elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
    # Ubuntu/Debian check via Netplan
    if grep -q "dhcp4: true" /etc/netplan/*.yaml 2>/dev/null; then
        echo "❌ Server masih pakai DHCP (dynamic IP)."
        echo "👉 Edit /etc/netplan/*.yaml untuk set static IP lalu apply dengan:"
        echo "   sudo netplan apply"
        exit 1
    else
        echo "✅ Server sudah pakai static IP."
    fi
else
    echo "Unsupported OS"
    exit 1
fi

sleep 3
# ==== Update system ====
echo
echo
echo "[1/6] Updating system..." 
if [ -f /etc/redhat-release ]; then
    sudo dnf update -y
    sudo dnf install -y epel-release
    PKG="dnf"
    OS="rhel"
elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
    sudo apt update -y
    sudo apt upgrade -y
    PKG="apt"
    OS="ubuntu"
else
    echo "Unsupported OS"
    exit 1
fi

sleep 3
# ==== Install required packages ====
echo
echo
echo "[2/6] Installing required packages..."
if [ "$OS" == "rhel" ]; then
    sudo $PKG install -y dnsmasq chrony net-tools curl vim perl python3
else
    sudo $PKG install -y dnsmasq chrony net-tools curl vim resolvconf perl python3 wget gnupg lsb-release
fi

sleep 3
# ==== Setup /etc/hosts & hostname ====
echo
echo
echo "[3/6] Configuring /etc/hosts and hostname..."
read -p "Masukkan IP Address server: " IPADDRESS
read -p "Masukkan Hostname server: " HOSTNAME
read -p "Masukkan Domain server: " DOMAIN

# Backup resolv.conf & hosts
cp /etc/resolv.conf /etc/resolv.conf.backup
cp /etc/hosts /etc/hosts.backup

# ==== Disable systemd-resolved (Ubuntu/Debian only) ====
if [ "$OS" == "ubuntu" ]; then
    echo "Menonaktifkan systemd-resolved..."
    systemctl disable --now systemd-resolved 2>/dev/null || true
    rm -f /etc/resolv.conf
    touch /etc/resolv.conf
fi

# Insert localhost sebagai resolver pertama
sed -i '1 s/^/nameserver 127.0.0.1\n/' /etc/resolv.conf
sed -i '2 s/^/nameserver 8.8.8.8\n/' /etc/resolv.conf

# Tulis ulang hosts
echo "127.0.0.1       localhost" > /etc/hosts
echo "$IPADDRESS   $HOSTNAME.$DOMAIN       $HOSTNAME" >> /etc/hosts

# Set hostname
hostnamectl set-hostname $HOSTNAME.$DOMAIN

sleep 3
# ==== Setup chrony ====
echo
echo
echo "[4/6] Configuring Chrony..."
if [ "$OS" == "rhel" ]; then
    systemctl disable --now ntpd 2>/dev/null || true
    systemctl enable --now chronyd
else
    systemctl disable --now systemd-timesyncd 2>/dev/null || true
    systemctl enable --now chrony
fi

# Set timezone ke Asia/Jakarta
timedatectl set-timezone Asia/Jakarta
timedatectl set-ntp true

sleep 3
# ==== Disable Firewall ====
echo
echo
echo "[5/6] Disabling Firewall..."
if [ "$OS" == "rhel" ]; then
    systemctl disable --now firewalld 2>/dev/null || true
    echo "🔥 Firewalld sudah dimatikan."
else
    systemctl disable --now ufw 2>/dev/null || true
    echo "🔥 UFW sudah dimatikan."
fi

sleep 3
# ==== Install PostgreSQL 16 ====
echo
echo
echo "[6/6] Installing PostgreSQL 16..."
if [ "$OS" == "ubuntu" ]; then
    UBUNTU_VER=$(grep VERSION_ID /etc/os-release | cut -d\" -f2)
    if [ "$UBUNTU_VER" == "22.04" ]; then
        echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        | sudo tee /etc/apt/sources.list.d/pgdg.list
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    elif [ "$UBUNTU_VER" == "24.04" ]; then
        echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        | sudo tee /etc/apt/sources.list.d/pgdg.list
        wget -O- "https://www.postgresql.org/media/keys/ACCC4CF8.asc" | \
        gpg --dearmor | sudo tee /usr/share/keyrings/postgres.gpg >/dev/null
        chmod 644 /usr/share/keyrings/postgres.gpg
        sed -i 's|deb |deb [signed-by=/usr/share/keyrings/postgres.gpg] |' \
        /etc/apt/sources.list.d/pgdg.list
    fi
    sudo apt update -y
    sudo apt install -y postgresql-16 postgresql-client-16
    systemctl enable --now postgresql
    echo "✅ PostgreSQL 16 terinstall & berjalan."
fi

sleep 3
echo 
echo 
echo "===================================================================="
echo "= Setup selesai! Detail:                                           "
echo "= - Hostname  : $(hostname)                                        "
echo "= - Domain    : $DOMAIN                                            "
echo "= - PostgreSQL: version 16 (running)                               "
echo "= - Catatan   : DNS server belum di setup silahkan di setup manual " 
echo "===================================================================="
