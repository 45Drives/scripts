#!/bin/bash

# For use after initial setup script
# Installs ZFS and Cockpit-ZFS

get_base_distro() {
    grep '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | awk '{print $1}'
}

get_distro() {
    grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"'
}

get_version_id() {
    grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d '.' -f1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi
}

require_root
distro=$(get_base_distro)
distro_id=$(get_distro)
distro_version=$(get_version_id)

echo "Detected distro: $distro_id (base: $distro), version: $distro_version"

if [[ "$distro" != "rhel" && "$distro" != "fedora" && "$distro" != "rocky" ]]; then
    echo "This is an unsupported distro. Please run on a Rocky, RHEL, or Fedora system."
    exit 1
fi

if ! command -v zfs &>/dev/null; then
    echo "ZFS not detected. Installing ZFS..."
    dnf install -y https://zfsonlinux.org/epel/zfs-release-2-3$(rpm --eval "%{dist}").noarch.rpm
    dnf install -y kernel-devel dkms zfs
    echo "zfs" > /etc/modules-load.d/zfs.conf
    modprobe zfs
    systemctl enable zfs-import-cache zfs-import-scan zfs-mount zfs.target zfs-zed
else
    echo "ZFS already installed."
fi

# Make sure SELinux is permissive
setenforce 0
sed -i 's/SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

# Re-run repo setup to ensure 45Drives repo is present
curl -sSL https://repo.45drives.com/setup | bash

echo "Installing Cockpit ZFS module..."
dnf install -y cockpit-zfs

# Ensure cockpit.socket is active
systemctl enable --now cockpit.socket

echo "ZFS and Cockpit-ZFS installation complete."
echo "Access Cockpit at: https://$(hostname -I | awk '{print $1}'):9090"

read -n 1 -s -r -p "Press any key to reboot and load ZFS modules..."
echo

sudo reboot
