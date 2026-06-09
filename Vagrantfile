# Vagrantfile — Projet PXE Boot Manager
# Infra de test : serveur DHCP/TFTP + client PXE
#
# Usage :
#   vagrant up          → démarre toutes les VMs
#   vagrant up pcstage  → démarre uniquement le serveur
#   vagrant ssh pcstage → accès SSH au serveur
#   vagrant halt        → arrêt propre
#   vagrant destroy     → suppression complète

Vagrant.configure("2") do |config|

  # ─── VM 1 : pcstage (serveur DHCP + TFTP + scripts) ───────────────────────
  config.vm.define "pcstage" do |s|
    s.vm.box      = "debian/bookworm64"
    s.vm.hostname = "pcstage"

    # Réseau interne simulant le réseau du labo (172.16.16.0/24)
    s.vm.network "public_network",
      ip: "172.16.16.1"

    s.vm.provider "virtualbox" do |vb|
      vb.name   = "pcstage"
      vb.memory = 1024
      vb.cpus   = 2
    end

    # Provisionnement automatique
    s.vm.provision "shell", path: "install/setup-pcstage.sh"
  end

  # ─── VM 2 : client PXE (simule un poste du labo) ──────────────────────────
  config.vm.define "client", autostart: false do |c|
    c.vm.box      = "debian/bookworm64"
    c.vm.hostname = "client-pxe"

    # Même réseau interne que pcstage
    c.vm.network "public_network",
      ip: "172.16.16.50"

    c.vm.provider "virtualbox" do |vb|
      vb.name   = "client-pxe"
      vb.memory = 512
      vb.cpus   = 1
    end
    c.vm.provision "shell", path: "install/setup-client.sh"
  end

end
