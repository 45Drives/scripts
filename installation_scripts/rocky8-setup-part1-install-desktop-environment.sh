#!/bin/bash

# For fresh installs of Rocky (8)
# Installs desktop environment + sets up distros

get_base_distro() {
    local base_distro
    base_distro=$(grep '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | awk '{print $1}')

    if [ -z "$base_distro" ]; then
        # fallback to ID if ID_LIKE is not found
        base_distro=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | awk '{print $1}')
    fi

    echo "$base_distro"
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

backup_existing_repo() {
    if [[ -f /etc/yum.repos.d/45drives.repo ]]; then
        mkdir -p /opt/45drives/archives/repos
        mv /etc/yum.repos.d/45drives.repo /opt/45drives/archives/repos/45drives-$(date +%F).repo
        echo "Existing 45Drives repo backed up."
    fi
    if [[ -f /etc/apt/sources.list.d/45drives.list ]]; then
        mkdir -p /opt/45drives/archives/repos
        mv /etc/apt/sources.list.d/45drives.list /opt/45drives/archives/repos/45drives-$(date +%F).list
        echo "Existing 45Drives APT repo backed up."
    fi
}

install_desktop_env() {
    if [[ $distro == "rhel" || $distro == "fedora" ]]; then
        echo "Installing XFCE Desktop Environment for Rocky/RHEL..."
        dnf update -y
        dnf install -y epel-release kernel-headers
        dnf groupinstall -y "Xfce" "base-x"
        echo "exec /usr/bin/xfce4-session" >> ~/.xinitrc
        systemctl set-default graphical
    fi
}

add_cockpit_overrides() {
    echo "Adding Cockpit override configurations..."
    cat > /usr/share/cockpit/45drives-system/override.json <<EOF
{
  "menu": {
    "45drives-system": {
      "order": 112
    }
  }
}
EOF
}

allow_root_in_cockpit() {
    echo "Ensuring root is allowed in Cockpit..."
    local disallowed_file="/etc/cockpit/disallowed-users"

    if [[ -f "$disallowed_file" ]]; then
        grep -q "^root$" "$disallowed_file" && {
            sed -i '/^root$/d' "$disallowed_file"
            echo "Removed root from $disallowed_file"
        } || echo "Root not present in disallowed-users"
    else
        echo "$disallowed_file does not exist. Skipping."
    fi
}

run_preconfig_inline() {
    echo "Running integrated preconfiguration for $distro_id $distro_version..."
    backup_existing_repo

    if [[ "$distro" == "rhel" || "$distro" == "fedora" ]]; then
        setenforce 0
        sed -i 's/SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
        curl -sSL https://repo.45drives.com/setup | bash
        dnf install -y cockpit cockpit-pcp cockpit-benchmark cockpit-navigator cockpit-file-sharing cockpit-45drives-hardware cockpit-identities cockpit-sosreport cockpit-storaged cockpit-scheduler
        firewall-cmd --add-service=cockpit --permanent && firewall-cmd --reload
        systemctl enable --now cockpit.socket
        dnf update -y
    fi

    allow_root_in_cockpit

    echo "Preconfiguration complete. Houston UI available at: https://$(hostname -I | awk '{print $1}'):9090"
}

# Start Execution
require_root
distro=$(get_base_distro)
distro_id=$(get_distro)
distro_version=$(get_version_id)

echo "Detected distro: $distro_id (base: $distro), version: $distro_version"

if [[ "$distro" != "rhel" && "$distro" != "fedora" && "$distro" != "rocky" ]]; then
    echo "This is an unsupported distro. Please run on a Rocky, RHEL, or Fedora system."
    exit 1
fi

install_desktop_env
run_preconfig_inline

echo "Finished initial setup.... Reboot required."
echo "Run ZFS-setup.sh after reboot to install zfs and cockpit zfs modules"

read -n 1 -s -r -p "Press any key to reboot..."
echo

sudo reboot

