# Projet PXE Boot Manager

Infrastructure de boot PXE pour salles informatiques, permettant de sélectionner l'OS de démarrage (Windows ou Linux) par machine ou par salle, avec Wake-on-LAN.

Développé dans le cadre d'un stage au C.C.R.I — IUT Paris-Saclay (Orsay).

---

## Architecture

```
DHCP (isc-dhcp-server)
  └→ TFTP (tftpd-hpa)
       └→ GRUB PXE (core.0 / grubx64.efi)
            └→ grub.cfg  ← lit le MAC de la machine
                 └→ machines/<mac>.cfg  ← Linux ou Windows
```

## Structure du projet

```
projet-pxe/
├── Vagrantfile                  ← environnement de test (2 VMs)
├── config/
│   └── grub.cfg                 ← menu GRUB principal (routage par MAC)
├── install/
│   └── setup-server.sh         ← installation complète du serveur
└── scripts/
    ├── discover.sh              ← découverte des machines via dhcpd.leases
    └── boot-manager.sh          ← gestion des boots par salle/machine
```

---

## Prérequis

- Debian 12 (Bookworm)
- VirtualBox
- Vagrant

```bash
sudo apt install -y virtualbox vagrant
```

---

## Démarrage rapide

```bash
git clone <repo>
cd projet-pxe

# Démarrer le serveur (provisionne automatiquement)
vagrant up server

# Accéder au serveur
vagrant ssh server

# Démarrer le client PXE (optionnel)
vagrant up client
```

---

## Utilisation des scripts

### discover.sh
Connexion SSH au serveur DHCP, lecture de `dhcpd.leases`, enregistrement des machines dans `/etc/boot-manager/machines.conf`.

```bash
sudo discover.sh
```

### boot-manager.sh
Interface de gestion : sélection de l'OS (Linux/Windows) par machine ou par salle entière, avec Wake-on-LAN optionnel.

```bash
sudo boot-manager.sh
```

---

## Réseau de test (Vagrant)

| Machine   | IP           | Rôle                     |
|-----------|--------------|--------------------------|
| server    | 172.16.16.1  | Serveur DHCP + TFTP      |
| client    | 172.16.16.50 | Client PXE (test)        |
| pool DHCP | 172.16.16.100–254 | Machines du labo    |

---

## Stack technique

- `isc-dhcp-server` — DHCP avec détection BIOS/UEFI
- `tftpd-hpa` — serveur TFTP
- `grub-mkimage` — génération des bootloaders PXE
- `wakeonlan` — réveil réseau des machines
- Bash — scripts d'administration
