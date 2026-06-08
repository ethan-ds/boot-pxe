#!/bin/bash
# boot-manager.sh V2 — Gestion par salle + Wake-on-LAN

MACHINES_CONF="/etc/boot-manager/machines.conf"
GRUB_MACHINES_DIR="/srv/tftp/boot/grub/machines"
BROADCAST="172.16.16.255"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Génération du grub.cfg ---
generate_cfg() {
    local mac="$1"
    local os="$2"
    local filepath="${GRUB_MACHINES_DIR}/${mac}.cfg"
    mkdir -p "$GRUB_MACHINES_DIR"

    if [ "$os" == "linux" ]; then
        cat > "$filepath" << GRUBEOF
set default=0
set timeout=0

menuentry "Linux" {
  insmod part_gpt
  insmod part_msdos
  insmod ext2
  insmod biosdisk
  insmod chain
  search --no-floppy --file --set=root /vmlinuz
  chainloader (hd0)+1
}
GRUBEOF
    elif [ "$os" == "windows" ]; then
        cat > "$filepath" << GRUBEOF
set default=0
set timeout=0

menuentry "Windows" {
  insmod part_gpt
  insmod fat
  insmod chain
  search --no-floppy --file --set=root /EFI/Microsoft/Boot/bootmgfw.efi
  chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
GRUBEOF
    fi
}

# --- Wake-on-LAN ---
wakeup_machine() {
    local name="$1"
    local mac="$2"
    echo -e "  Envoi WoL à ${YELLOW}$name${NC} ($mac)..."
    if wakeonlan -i "$BROADCAST" "$mac" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Paquet WoL envoyé${NC}"
    else
        echo -e "  ${RED}✗ Echec WoL${NC}"
    fi
}

# --- Ajouter une machine manuellement ---
add_machine() {
    echo ""
    echo -e "${CYAN}=== Ajouter une machine ===${NC}"
    echo ""

    read -rp "Nom de la machine : " name
    read -rp "Adresse MAC (format aa:bb:cc:dd:ee:ff) : " mac

    # Vérification format MAC
    if [[ ! "$mac" =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]]; then
        echo -e "${RED}Format MAC invalide.${NC}"
        return
    fi

    # Vérifier si MAC déjà enregistrée
    if grep -q "=$mac$" "$MACHINES_CONF" 2>/dev/null; then
        echo -e "${YELLOW}Cette MAC est déjà enregistrée.${NC}"
        return
    fi

    # Afficher les salles existantes
    echo ""
    echo -e "${CYAN}Salles existantes :${NC}"
    i=1
    declare -A idx_to_salle
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            echo -e "  [$i] ${BASH_REMATCH[1]}"
            idx_to_salle[$i]="${BASH_REMATCH[1]}"
            ((i++))
        fi
    done < "$MACHINES_CONF"
    echo -e "  [N] Nouvelle salle"
    echo ""

    read -rp "Choisissez une salle : " salle_choice

    if [[ "$salle_choice" =~ ^[Nn]$ ]]; then
        read -rp "Nom de la nouvelle salle : " salle
        echo "" >> "$MACHINES_CONF"
        echo "[$salle]" >> "$MACHINES_CONF"
    else
        salle="${idx_to_salle[$salle_choice]}"
        if [ -z "$salle" ]; then
            echo -e "${RED}Choix invalide.${NC}"
            return
        fi
    fi

    # Insérer après la section de la salle
    # On ajoute à la fin de la section correspondante
    local tmp=$(mktemp)
    local in_section=0
    local added=0
    while IFS= read -r line; do
        echo "$line" >> "$tmp"
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            if [ "${BASH_REMATCH[1]}" == "$salle" ]; then
                in_section=1
            else
                if [ $in_section -eq 1 ] && [ $added -eq 0 ]; then
                    echo "${name}=${mac}" >> "$tmp"
                    added=1
                fi
                in_section=0
            fi
        fi
    done < "$MACHINES_CONF"

    # Si la salle était la dernière
    if [ $added -eq 0 ]; then
        echo "${name}=${mac}" >> "$tmp"
    fi

    mv "$tmp" "$MACHINES_CONF"
    echo -e "${GREEN}✓ $name ($mac) ajouté dans $salle${NC}"
    echo ""
}

# --- Parsing machines.conf ---
parse_conf() {
    unset mac_list name_list salle_list all_salles
    declare -ag mac_list
    declare -ag name_list
    declare -ag salle_list
    declare -ag all_salles
    declare -Ag salle_seen

    local current_salle=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_salle="${BASH_REMATCH[1]}"
            if [ -z "${salle_seen[$current_salle]}" ]; then
                all_salles+=("$current_salle")
                salle_seen[$current_salle]=1
            fi
        elif [[ "$line" =~ ^([^=]+)=([a-fA-F0-9:]+)$ ]]; then
            name_list+=("${BASH_REMATCH[1]}")
            mac_list+=("${BASH_REMATCH[2]}")
            salle_list+=("$current_salle")
        fi
    done < "$MACHINES_CONF"
}

# --- Obtenir l'OS actuel d'une machine ---
get_current_os() {
    local mac="$1"
    local cfg="${GRUB_MACHINES_DIR}/${mac}.cfg"
    if [ -f "$cfg" ]; then
        grep -o 'menuentry "[^"]*"' "$cfg" | head -1 | cut -d'"' -f2
    else
        echo "non défini"
    fi
}

# --- Appliquer OS sur une liste de machines ---
apply_os() {
    local os="$1"
    local os_label="$2"
    local wol_choice="$3"
    shift 3
    local indices=("$@")

    echo ""
    echo -e "${CYAN}Application de $os_label...${NC}"
    echo ""
    for idx in "${indices[@]}"; do
        local name="${name_list[$idx]}"
        local mac="${mac_list[$idx]}"
        generate_cfg "$mac" "$os"
        echo -e "  ${GREEN}✓${NC} $name ($mac) → $os_label"
        [ "$wol_choice" == "1" ] && wakeup_machine "$name" "$mac"
    done
    echo ""
    if [ "$wol_choice" == "1" ]; then
        echo -e "${YELLOW}Les machines vont démarrer dans quelques secondes...${NC}"
    else
        echo -e "${YELLOW}Configuration appliquée au prochain démarrage PXE.${NC}"
    fi
    echo ""
}

# --- Choix OS + WoL ---
choose_os_and_wol() {
    echo ""
    echo -e "${CYAN}Quel OS ?${NC}"
    echo "  [1] Linux"
    echo "  [2] Windows"
    echo ""
    read -rp "Votre choix : " os_choice

    case "$os_choice" in
        1) os="linux"   ; os_label="Linux"   ;;
        2) os="windows" ; os_label="Windows" ;;
        *)
            echo -e "${RED}Choix invalide.${NC}"
            return 1
            ;;
    esac

    echo ""
    echo -e "${CYAN}Allumer via Wake-on-LAN ?${NC}"
    echo "  [1] Oui"
    echo "  [2] Non"
    echo ""
    read -rp "Votre choix : " wol_choice
    return 0
}

# ===== PROGRAMME PRINCIPAL =====

if [ ! -f "$MACHINES_CONF" ]; then
    echo -e "${RED}Erreur : $MACHINES_CONF introuvable.${NC}"
    exit 1
fi

while true; do
    parse_conf

    if [ ${#mac_list[@]} -eq 0 ]; then
        echo -e "${RED}Aucune machine dans $MACHINES_CONF.${NC}"
        exit 1
    fi

    # --- Menu principal ---
    echo -e "${CYAN}=== Gestionnaire de boot PXE ===${NC}"
    echo ""
    echo -e "${YELLOW}Salles disponibles :${NC}"
    echo ""

    for idx in "${!all_salles[@]}"; do
        salle="${all_salles[$idx]}"
        count=0
        for s in "${salle_list[@]}"; do
            [ "$s" == "$salle" ] && ((count++))
        done
        echo -e "  [$((idx+1))] ${GREEN}$salle${NC}  ($count machine(s))"
    done

    echo ""
    echo -e "  [T] Toutes les salles"
    echo -e "  [L] Lister tous les PCs"
    echo -e "  [A] Ajouter une machine"
    echo -e "  [Q] Quitter"
    echo ""
    read -rp "Votre choix : " main_choice

    case "$main_choice" in

        [Qq])
            echo "Au revoir."
            exit 0
            ;;

        [Aa])
            add_machine
            continue
            ;;

        [Ll])
            echo ""
            echo -e "${CYAN}=== Tous les PCs enregistrés ===${NC}"
            for salle in "${all_salles[@]}"; do
                echo ""
                echo -e "${BLUE}--- $salle ---${NC}"
                for idx in "${!mac_list[@]}"; do
                    if [ "${salle_list[$idx]}" == "$salle" ]; then
                        name="${name_list[$idx]}"
                        mac="${mac_list[$idx]}"
                        current_os=$(get_current_os "$mac")
                        echo -e "  ${GREEN}$name${NC}  MAC: $mac  →  ${YELLOW}$current_os${NC}"
                    fi
                done
            done
            echo ""
            read -rp "Appuyez sur Entrée pour continuer..."
            echo ""
            continue
            ;;

        [Tt])
            choose_os_and_wol || continue
            all_indices=("${!mac_list[@]}")
            apply_os "$os" "$os_label" "$wol_choice" "${all_indices[@]}"
            ;;

        *)
            # Sélection d'une salle
            salle_idx=$(( main_choice - 1 ))
            if [ -z "${all_salles[$salle_idx]}" ]; then
                echo -e "${RED}Choix invalide.${NC}"
                echo ""
                continue
            fi
            selected_salle="${all_salles[$salle_idx]}"

            # --- Menu machines de la salle ---
            while true; do
                echo ""
                echo -e "${CYAN}=== $selected_salle ===${NC}"
                echo ""

                declare -a salle_indices
                for idx in "${!mac_list[@]}"; do
                    [ "${salle_list[$idx]}" == "$selected_salle" ] && salle_indices+=("$idx")
                done

                for j in "${!salle_indices[@]}"; do
                    idx="${salle_indices[$j]}"
                    name="${name_list[$idx]}"
                    mac="${mac_list[$idx]}"
                    current_os=$(get_current_os "$mac")
                    echo -e "  [$((j+1))] ${GREEN}$name${NC}  MAC: $mac  →  ${YELLOW}$current_os${NC}"
                done

                echo ""
                echo -e "  [T] Toute la salle $selected_salle"
                echo -e "  [R] Retour"
                echo ""
                read -rp "Sélectionnez une machine ou [T/R] : " machine_choice

                if [[ "$machine_choice" =~ ^[Rr]$ ]]; then
                    unset salle_indices
                    declare -a salle_indices
                    break
                fi

                if [[ "$machine_choice" =~ ^[Tt]$ ]]; then
                    choose_os_and_wol || { unset salle_indices; declare -a salle_indices; continue; }
                    apply_os "$os" "$os_label" "$wol_choice" "${salle_indices[@]}"
                else
                    m_idx=$(( machine_choice - 1 ))
                    if [ -z "${salle_indices[$m_idx]}" ]; then
                        echo -e "${RED}Choix invalide.${NC}"
                        unset salle_indices
                        declare -a salle_indices
                        continue
                    fi
                    target_idx="${salle_indices[$m_idx]}"
                    choose_os_and_wol || { unset salle_indices; declare -a salle_indices; continue; }
                    apply_os "$os" "$os_label" "$wol_choice" "$target_idx"
                fi

                unset salle_indices
                declare -a salle_indices
            done
            ;;
    esac
done
