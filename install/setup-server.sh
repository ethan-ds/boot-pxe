#!/bin/bash
# setup-server.sh — Installation et configuration complète du serveur PXE
# Installe : isc-dhcp-server, tftpd-hpa, grub-pc-bin, grub-efi-amd64-bin, wakeonlan
# Configure : DHCP, TFTP, GRUB PXE, scripts boot-manager

set -e

TFTP_ROOT="/srv/tftp"
GRUB_DIR="${TFTP_ROOT}/boot/grub"
MACHINES_DIR="${GRUB_DIR}/machines"
BOOT_MANAGER_CONF="/etc/boot-manager"
SCRIPTS_DIR="/usr/local/bin"
INTERFACE="eth1"   # Interface réseau du labo (172.16.16.0/24)
SERVER_IP="172.16.16.1"

echo "========================================"
echo " Installation du serveur PXE — Server"
echo "========================================"
echo ""

# ─── Mise à jour et installation des paquets ──────────────────────────────
echo "[1/6] Installation des paquets..."
apt-get update -qq
apt-get install -y -qq \
    isc-dhcp-server \
    tftpd-hpa \
    grub-pc-bin \
    grub-efi-amd64-bin \
    wakeonlan \
    openssh-server

echo "      OK"

# ─── Configuration DHCP ───────────────────────────────────────────────────
echo "[2/6] Configuration isc-dhcp-server..."

# Interface d'écoute
cat > /etc/default/isc-dhcp-server << EOF
INTERFACESv4="${INTERFACE}"
INTERFACESv6=""
EOF

# dhcpd.conf
cat > /etc/dhcp/dhcpd.conf << EOF
# dhcpd.conf — Serveur PXE labo
default-lease-time 600;
max-lease-time 7200;
authoritative;

option client-arch code 93 = unsigned integer 16;

subnet 172.16.16.0 netmask 255.255.255.0 {
    range 172.16.16.100 172.16.16.254;
    next-server ${SERVER_IP};

    if option client-arch = 00:07 {
        filename "boot/grub/grubx64.efi";
    } else {
        filename "boot/grub/i386-pc/core.0";
    }
}
EOF

echo "      OK"

# ─── Configuration TFTP ───────────────────────────────────────────────────
echo "[3/6] Configuration tftpd-hpa..."

cat > /etc/default/tftpd-hpa << EOF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="${TFTP_ROOT}"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
EOF

mkdir -p "${TFTP_ROOT}" "${GRUB_DIR}/i386-pc" "${GRUB_DIR}/x86_64-efi" "${MACHINES_DIR}"
chown -R tftp:tftp "${TFTP_ROOT}"

echo "      OK"

# ─── Génération des bootloaders GRUB PXE ──────────────────────────────────
echo "[4/6] Génération des bootloaders GRUB PXE..."

# BIOS — core.0
grub-mkimage \
    --format=i386-pc-pxe \
    --output="${GRUB_DIR}/i386-pc/core.0" \
    --prefix="(pxe)/boot/grub" \
    pxe pxechain tftp net biosdisk part_gpt part_msdos \
    ext2 ntfs fat iso9660 normal linux chain boot configfile \
    search search_fs_file echo ls reboot halt

# UEFI — grubx64.efi
grub-mkimage \
    --format=x86_64-efi \
    --output="${GRUB_DIR}/grubx64.efi" \
    --prefix="(pxe)/boot/grub" \
    efinet tftp net part_gpt part_msdos \
    ext2 ntfs fat iso9660 normal linux chain boot configfile \
    search search_fs_file echo ls reboot halt

# Copie des modules GRUB nécessaires
cp /usr/lib/grub/i386-pc/*.mod    "${GRUB_DIR}/i386-pc/"   2>/dev/null || true
cp /usr/lib/grub/x86_64-efi/*.mod "${GRUB_DIR}/x86_64-efi/" 2>/dev/null || true

chown -R tftp:tftp "${TFTP_ROOT}"
echo "      OK"

# ─── grub.cfg principal ───────────────────────────────────────────────────
echo "[5/6] Déploiement de grub.cfg et scripts..."

# ─── grub.cfg principal ───────────────────────────────────────────────────
echo "[5/6] Déploiement de grub.cfg et scripts..."

cat > "${GRUB_DIR}/grub.cfg" << 'EOF'
set timeout=5
set default=0

# Charge le fichier de config spécifique à la machine si il existe
if [ -f (pxe)/boot/grub/machines/${net_default_mac}.cfg ]; then
  configfile (pxe)/boot/grub/machines/${net_default_mac}.cfg
fi

# Menu par défaut si aucun fichier trouvé pour cette machine
menuentry "Linux (par defaut)" {
  insmod part_gpt
  insmod part_msdos
  insmod ext2
  insmod biosdisk
  insmod chain
  search --no-floppy --file --set=root /vmlinuz
  chainloader (hd0)+1
}

menuentry "Windows (par defaut)" {
  insmod part_gpt
  insmod fat
  insmod chain
  search --no-floppy --file --set=root /EFI/Microsoft/Boot/bootmgfw.efi
  chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
EOF

# Scripts
cp /vagrant/scripts/discover.sh     "${SCRIPTS_DIR}/discover.sh"
cp /vagrant/scripts/boot-manager.sh "${SCRIPTS_DIR}/boot-manager.sh"
chmod +x "${SCRIPTS_DIR}/discover.sh" "${SCRIPTS_DIR}/boot-manager.sh"

# Dossier de conf boot-manager
mkdir -p "${BOOT_MANAGER_CONF}"

echo "      OK"

# ─── Démarrage des services ───────────────────────────────────────────────
echo "[6/6] Démarrage des services..."

systemctl enable isc-dhcp-server tftpd-hpa
systemctl restart isc-dhcp-server tftpd-hpa

echo "      OK"
echo ""
echo "========================================"
echo " Serveur PXE opérationnel !"
echo " DHCP   : 172.16.16.100 – 172.16.16.254"
echo " TFTP   : ${TFTP_ROOT}"
echo " GRUB   : ${GRUB_DIR}"
echo ""
echo " Commandes disponibles :"
echo "   sudo discover.sh      → découverte des machines"
echo "   sudo boot-manager.sh  → gestion des boots"
echo "========================================"
