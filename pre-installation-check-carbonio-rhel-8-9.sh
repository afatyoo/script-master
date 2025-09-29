#!/bin/bash
echo "================================================"
echo "= Initial Setup Carbonio Script for RHEL 8/9   ="
echo "= by: TYO-CHAN                                 ="
echo "================================================"
set -e
sleep 3

# ==== Detect RHEL version ====
if [ -f /etc/redhat-release ]; then
    OS="rhel"
    RHEL_VERSION=$(rpm -E %{rhel})
    echo "✅ Detected RHEL $RHEL_VERSION"
else
    echo "❌ This script is only for RHEL 8/9"
    exit 1
fi

# ==== Check Static IP or DHCP ====
echo
echo "[0/9] Checking network configuration..."
IFACE=$(nmcli -t -f DEVICE,STATE d | grep ":connected" | cut -d: -f1 | head -n1)
BOOTPROTO=$(nmcli -g ipv4.method con show $IFACE)
if [ "$BOOTPROTO" == "auto" ]; then
    echo "❌ Server masih pakai DHCP (dynamic IP)."
    echo "👉 Disarankan ganti ke static IP sebelum lanjut."
    exit 1
else
    echo "✅ Server sudah pakai static IP."
fi

sleep 3
# ==== Update system ====
echo
echo "[1/9] Updating system..."
sudo dnf clean all
sudo dnf update -y

sleep 3
# ==== Enable EPEL repo ====
echo
echo "[2/9] Installing EPEL repository..."
if [ "$RHEL_VERSION" -eq 8 ]; then
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms
    subscription-manager repos --enable=rhel-8-for-x86_64-appstream-rpms
    subscription-manager repos --enable=codeready-builder-for-rhel-8-x86_64-rpms
elif [ "$RHEL_VERSION" -eq 9 ]; then
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms
    subscription-manager repos --enable=rhel-9-for-x86_64-appstream-rpms
    subscription-manager repos --enable=codeready-builder-for-rhel-9-x86_64-rpms
else
    echo "⚠️ EPEL untuk RHEL $RHEL_VERSION tidak tersedia otomatis, cek manual."
fi
echo "✅ EPEL & repos tambahan sudah diaktifkan."

sleep 3
# ==== Configure Carbonio Repository ====
echo
echo "[3/9] Configuring Carbonio repository..."
cat > /etc/yum.repos.d/zextras.repo <<EOF
[zextras]
name=zextras
baseurl=https://repo.zextras.io/release/rhel$RHEL_VERSION
enabled=1
repo_gpgcheck=1
gpgcheck=0
gpgkey=https://repo.zextras.io/repomd.xml.key
EOF
echo "✅ Carbonio repository ditambahkan ke /etc/yum.repos.d/zextras.repo"

sleep 3
# ==== Install required packages ====
echo
echo "[4/9] Installing required packages..."
sudo dnf install -y \
    dnsmasq chrony net-tools curl vim perl python3 \
    tar unzip bzip2

sleep 3
# ==== Setup /etc/hosts & hostname ====
echo
echo "[5/9] Configuring /etc/hosts and hostname..."
read -p "Masukkan IP Address server: " IPADDRESS
read -p "Masukkan Hostname server: " HOSTNAME
read -p "Masukkan Domain server: " DOMAIN

# Backup hosts & resolv.conf
cp /etc/hosts /etc/hosts.backup
[ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf.backup

# Overwrite resolv.conf dengan DNS lokal + Google
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
EOF

# Tulis ulang hosts
cat > /etc/hosts <<EOF
127.0.0.1       localhost
$IPADDRESS   $HOSTNAME.$DOMAIN       $HOSTNAME
EOF

# Set hostname
hostnamectl set-hostname $HOSTNAME.$DOMAIN

sleep 3
# ==== Setup chrony ====
echo
echo "[6/9] Configuring Chrony..."
systemctl disable --now ntpd 2>/dev/null || true
systemctl enable --now chronyd

# Set timezone ke Asia/Jakarta
timedatectl set-timezone Asia/Jakarta
timedatectl set-ntp true

sleep 3
# ==== Disable SELinux ====
echo
echo "[7/9] Disabling SELinux..."
if [ -f /etc/selinux/config ]; then
    sed -i s/'SELINUX='/'#SELINUX='/g /etc/selinux/config
    echo 'SELINUX=disabled' >> /etc/selinux/config
fi
setenforce 0 || true
echo "❌ SELinux dimatikan."

sleep 3
# ==== Disable Firewall (firewalld, iptables, ip6tables) ====
echo
echo "[8/9] Disabling Firewall..."
systemctl stop firewalld iptables ip6tables 2>/dev/null || true
systemctl disable firewalld iptables ip6tables 2>/dev/null || true
echo "🔥 Firewall (firewalld, iptables, ip6tables) sudah dimatikan."

sleep 3
# ==== Install PostgreSQL 16 ====
echo
echo "[9/9] Installing PostgreSQL 16..."
if [ "$RHEL_VERSION" -eq 8 ]; then
    dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
elif [ "$RHEL_VERSION" -eq 9 ]; then
    dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
fi

# Disable default PostgreSQL module, lalu install pgsql 16
dnf -qy module disable postgresql
dnf install -y postgresql16 postgresql16-server

# Init database
/usr/pgsql-16/bin/postgresql-16-setup initdb

# Enable & start service
systemctl enable --now postgresql-16

echo "✅ PostgreSQL 16 terinstall & berjalan."

sleep 3
echo
echo "===================================================================="
echo "= Setup selesai! Detail:                                           "
echo "= - Hostname  : $(hostname)                                        "
echo "= - Domain    : $DOMAIN                                            "
echo "= - Repo      : /etc/yum.repos.d/zextras.repo                      "
echo "= - PostgreSQL: version 16 (running)                               "
echo "= - Catatan   : DNS server (dnsmasq) belum di setup, lakukan manual"
echo "===================================================================="
