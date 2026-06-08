#!/bin/bash
# discover.sh V2 — Découverte automatique des machines via dhcpd.leases (SSH)

DHCP_USER="ethqn"
DHCP_HOST="172.16.16.1"
LEASES_FILE="/var/lib/dhcp/dhcpd.leases"
MACHINES_CONF="/etc/boot-manager/machines.conf"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Découverte des machines PXE ===${NC}"
echo ""

# Récupération du fichier leases via SSH
echo -e "Connexion au serveur DHCP (${DHCP_USER}@${DHCP_HOST})..."
leases_content=$(ssh "${DHCP_USER}@${DHCP_HOST}" "cat ${LEASES_FILE}" 2>/dev/null)

if [ -z "$leases_content" ]; then
    echo -e "${RED}Erreur : impossible de lire $LEASES_FILE sur le serveur DHCP.${NC}"
    exit 1
fi

# Extraction des MACs (dédupliquées)
declare -A mac_to_ip
declare -A mac_to_hostname
current_ip=""
current_mac=""
declare -A seen_macs

while IFS= read -r line; do
    if [[ "$line" =~ ^lease[[:space:]]+([0-9.]+) ]]; then
        current_ip="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ hardware[[:space:]]+ethernet[[:space:]]+([a-f0-9:]+) ]]; then
        current_mac="${BASH_REMATCH[1]}"
        mac_to_ip["$current_mac"]="$current_ip"
    elif [[ "$line" =~ client-hostname[[:space:]]+\"(.+)\" ]]; then
        mac_to_hostname["$current_mac"]="${BASH_REMATCH[1]}"
    fi
done <<< "$leases_content"

# Déduplification
declare -a unique_macs
for mac in "${!mac_to_ip[@]}"; do
    [[ -n "${seen_macs[$mac]}" ]] && continue
    seen_macs[$mac]=1
    unique_macs+=("$mac")
done

if [ ${#unique_macs[@]} -eq 0 ]; then
    echo -e "${RED}Aucune machine trouvée.${NC}"
    exit 1
fi

echo -e "${GREEN}${#unique_macs[@]} machine(s) détectée(s) :${NC}"
echo ""

i=1
declare -A index_to_mac
for mac in "${unique_macs[@]}"; do
    ip="${mac_to_ip[$mac]}"
    hostname="${mac_to_hostname[$mac]:-inconnu}"
    echo -e "  [$i] MAC: ${YELLOW}$mac${NC}  IP: $ip  Hostname: $hostname"
    index_to_mac[$i]="$mac"
    ((i++))
done

echo ""

# Création du dossier
mkdir -p "$(dirname "$MACHINES_CONF")"

# Sauvegarde ancien fichier
if [ -f "$MACHINES_CONF" ]; then
    cp "$MACHINES_CONF" "${MACHINES_CONF}.bak"
    echo -e "${YELLOW}Ancien machines.conf sauvegardé dans ${MACHINES_CONF}.bak${NC}"
    echo ""
fi

> "$MACHINES_CONF"

# Demander la salle en premier
echo -e "${CYAN}Dans quelle salle sont ces machines ?${NC}"
read -rp "Nom de la salle (ex: I209, E101) : " salle

if [ -n "$salle" ]; then
    echo "" >> "$MACHINES_CONF"
    echo "[$salle]" >> "$MACHINES_CONF"
fi

echo ""
echo -e "${CYAN}Attribution des noms aux machines${NC}"
echo "Laissez vide pour ignorer une machine."
echo ""

current_salle="$salle"

for j in $(seq 1 $((i-1))); do
    mac="${index_to_mac[$j]}"
    ip="${mac_to_ip[$mac]}"
    hostname="${mac_to_hostname[$mac]:-inconnu}"

    echo -e "  MAC: ${YELLOW}$mac${NC}  IP: $ip  Hostname: $hostname"
    read -rp "  Nom : " name

    if [ -n "$name" ]; then
        # Demander si cette machine est dans une salle différente
        read -rp "  Salle [$current_salle] (Entrée pour garder) : " new_salle
        if [ -n "$new_salle" ] && [ "$new_salle" != "$current_salle" ]; then
            current_salle="$new_salle"
            echo "" >> "$MACHINES_CONF"
            echo "[$current_salle]" >> "$MACHINES_CONF"
        fi
        echo "${name}=${mac}" >> "$MACHINES_CONF"
        echo -e "  ${GREEN}→ $name enregistré dans $current_salle${NC}"
    else
        echo -e "  ${YELLOW}→ ignorée${NC}"
    fi
    echo ""
done

echo -e "${GREEN}=== machines.conf généré ===${NC}"
echo ""
cat "$MACHINES_CONF"
