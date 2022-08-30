#!/usr/bin/env bash

# Brett Kelly <bkelly@45drives.com>
# Josh Boudreau <jboudreau@45drives.com>
# Dawson Della Valle <ddellavalle@45drives.com>

# Ubuntu 20.04 LTS System Configuration Tweaks

interpreter=$(ps -p $$ | awk '$1 != "PID" {print $(NF)}' | tr -d '()')

if [ "$interpreter" != "bash" ]; then
	echo "Please run with bash. (\`./ubuntu-preconfig.sh\` or \`bash ubuntu-preconfig.sh\`)"
	echo "Current interpreter: $interpreter"
	exit 1
fi

euid=$(id -u)

if [[ "$euid" != 0 ]]; then 
	echo "Please run as root or with sudo."
	exit 1
fi

welcome() {
	local response
	cat <<EOF
Welcome to the

 /##   /## /#######  /#######            /##                              
| ##  | ##| ##____/ | ##__  ##          |__/                              
| ##  | ##| ##      | ##  \ ##  /######  /## /##    /## /######   /#######
| ########| ####### | ##  | ## /##__  ##| ##|  ##  /##//##__  ## /##_____/
|_____  ##|_____  ##| ##  | ##| ##  \__/| ## \  ##/##/| ########|  ###### 
      | ## /##  \ ##| ##  | ##| ##      | ##  \  ###/ | ##_____/ \____  ##
      | ##|  ######/| #######/| ##      | ##   \  #/  |  ####### /#######/
      |__/ \______/ |_______/ |__/      |__/    \_/    \_______/|_______/

                                           Ubuntu Preconfiguration Script.

    This will set up the root login password, enable root login over SSH,
add the 45Drives apt repository, replace systemd-networkd with network-manager,
remove cloud-init and snapd, and add the Houston Management UI.

    This script should *not* be run in an SSH session, as the network will be
modified and you may be disconnected. Run this script from the console or IPMI
remote console.
EOF

	read -p "Are you sure you want to continue? [y/N]: " response

	case $response in
		[yY]|[yY][eE][sS])
			echo
			;;
		*)
			echo "Exiting..."
			exit 0
			;;
	esac

	return 0
}

enable_root_user() {
	local ROOTPASSWD=""
	local ROOTPASSWD2=""
	local res
	
    echo "ENABLING ROOT LOGIN"
	
    while true; do
		read -sp "Enter password for root user: " ROOTPASSWD
		
        echo
		
        if [[ "$ROOTPASSWD" == "" ]]; then
			echo "Root password cannot be empty! Try again."
			continue
		fi
		
        read -sp "Confirm password for root user: " ROOTPASSWD2
		
        echo
		
        if [[ "$ROOTPASSWD" != "$ROOTPASSWD2" ]]; then
			echo "Passwords do not match! Try again."
			continue
		fi
		
        echo "root:$ROOTPASSWD" | chpasswd
		
        res=$?
		
        if [[ $res != 0 ]]; then
			echo "Setting password failed! Exit code: $res"
			continue
		fi

		echo "Successfully set root password."
		
        break
	done
	
    return 0
}

enable_root_ssh() {
	local res
	
    echo "ENABLING ROOT LOGIN VIA SSH"
	
    cat > /etc/ssh/sshd_config.d/45drives.conf <<EOF
PermitRootLogin yes
PasswordAuthentication yes
EOF

	# Restart sshd
	systemctl restart sshd
	res=$?
	if [[ $res != 0 ]]; then
		echo "Restarting sshd failed!"
		exit $res
	fi

	# test root login
	echo "Adding localhost's ECDSA Key Fingerprint to $HOME/.ssh/known_hosts"

	ssh-keyscan -H localhost >> $HOME/.ssh/known_hosts

	echo "Enter password to test root login to localhost:"

	ssh root@localhost exit

	res=$?

	if [[ $res != 0 ]]; then
		echo "Root ssh login failed!"
		exit $res
	fi

	echo "Successfully enabled ssh login."

	return 0
}

update_system() {
	local res
	## Update system
	# Install 45drives repository
	echo "UPDATING SYSTEM"

	echo "Downloading 45Drives Repo Setup Script"
	curl -sSL https://repo.45drives.com/setup -o setup-repo.sh

	res=$?
	if [[ $res != 0 ]]; then
		echo "Failed to download repo setup script! (https://repo.45drives.com/setup)"
		exit $res
	fi

	echo "Running 45Drives Repo Setup Script"

	bash setup-repo.sh
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Failed to run the setup script! (https://repo.45drives.com/setup)"
		exit $res
	fi

	# apt upgrade
	echo "Upgrading packages"
	
    apt upgrade -y
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "apt upgrade failed!"
		exit $res
	fi

	echo "Successfully updated system."
	
    return 0
}

init_network() {
	local res
	
    echo "SETTING UP NETWORK MANAGER"
	# Install network packages
	
    apt update
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "apt update failed!"
		exit $res
	fi
	
	apt install -y network-manager firewalld
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Installing network manager and/or firewalld failed!"
		exit $res
	fi
	
	systemctl enable --now network-manager
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Enabling network manager failed!"
		exit $res
	fi
	
	# Disable ufw and enable firewalld
	systemctl enable --now firewalld
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Enabling firewalld failed!"
		exit $res
	fi
	
	ufw disable
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Disabling ufw failed!"
		exit $res
	fi
	
	echo "Successfully set up network manager."
	
	return 0
}

remove_garbage() {
	local res
	
    echo "REMOVING CLOUD-INIT AND SNAPD"
	
    # Disable cloud-init
    touch /etc/cloud/cloud-init.disabled
	
	# Remove snapd
	apt autoremove --purge -y snapd
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Disabling snapd failed!"
		exit $res
	fi
	
	echo "Successfully removed cloud-init and snapd."
	
	return 0
}

add_cockpit() {
	local res
	
    echo "INITIALIZING HOUSTON"
	
    # Install cockpit and cockpit related things
	
    echo "Installing dependencies"
	
    apt update
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "apt update failed!"
		exit $res
	fi
	
	apt install -y cockpit cockpit-zfs-manager cockpit-benchmark cockpit-navigator cockpit-file-sharing cockpit-45drives-hardware cockpit-identities cockpit-machines cockpit-sosreport realmd tuned udisks2-lvm2 zfs-dkms samba winbind nfs-kernel-server nfs-client 45drives-tools
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Installing Houston dependencies failed!"
		exit $res
	fi
	
	# Open firewall for cockpit
	echo "Opening firewall for cockpit"
	
    firewall-cmd --permanent --add-service=cockpit
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Adding cockpit to firewall failed!"
		exit $res
	fi
	
	firewall-cmd --reload
	
    res=$?
	
    if [[ $res != 0 ]]; then
		echo "Reloading firewall failed!"
		exit $res
	fi
	
	# Install cockpit override manifests for 45ddrives-hardware and apps
	
    cat >> /usr/share/cockpit/45drives-disks/override.json <<EOF
{
	"menu": {
		"45drives-disks": {
			"order": 110
		}
	}
}
EOF

	cat >> /usr/share/cockpit/45drives-motherboard/override.json <<EOF
{
	"menu": {
		"45drives-motherboard": {
			"order": 111
		}
	}
}
EOF

	cat >> /usr/share/cockpit/45drives-system/override.json <<EOF
{
	"menu": {
		"45drives-system": {
			"order": 112
		}
	}
}
EOF

	cat >> /usr/share/cockpit/apps/override.json <<EOF
{
	"tools": {
		"index": null
		}
}
EOF

	systemctl enable --now cockpit.socket

	res=$?

	if [[ $res != 0 ]]; then
		echo "Enabling cockpit.socket failed!"
		exit $res
	fi
	
	echo "Successfully initialized Houston."
	
	return 0
}

use_nm_not_systemd-networkd() {
	local res

	echo "ENABLING NETWORK MANAGER"
	# Use Network Manager instead of systemd-networkd

	cat > /etc/netplan/00-networkmanager.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF

	[[ -f /etc/netplan/00-installer-config.yaml ]] && mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.backup

	netplan try

	res=$?

	if [[ $res != 0 ]]; then
		echo "netplan try failed."
		exit $res
	fi
	
	ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

	mv /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf  /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf.backup

	sed -i '/^managed/s/false/true/' /etc/NetworkManager/NetworkManager.conf
	
	systemctl restart network-manager

	res=$?

	if [[ $res != 0 ]]; then
		echo "Reloading network-manager failed."
		exit $res
	fi
	
	echo "Successfully enabled network manager."
	
	return 0
}

setup_done() {
	local response=""

	echo "SETUP COMPLETE"

	read -p "Reboot system now? [y/N]: " response

	case $response in
		[yY]|[yY][eE][sS])
			reboot now
			;;
		*)
			echo "Reboot soon to finish configuration."
			;;
	esac

	return 0
}

progress=""

if [[ -f .ubuntu-preconfig.progress ]]; then
	progress=$(cat .ubuntu-preconfig.progress)
fi

if [[ $progress != "" ]]; then
	echo "Found progress from previous time running this script. ($PWD/.ubuntu-preconfig.progress)"
	echo "1. Continue from last successful step."
	echo "2. Start from beginning."
	echo "3. Exit. (default)"
	read -p "[1-3]: " response
	case $response in
		1)
			echo "Starting from last successful step."
			;;
		2)
			echo "Starting from beginning."
			progress=""
			;;
		*)
			echo "Exiting..."
			exit 0
			;;
	esac
fi

case $progress in
	"")
		welcome
		;& # fallthrough
	0)
		echo "################################################################################"
		enable_root_user
		echo 1 > .ubuntu-preconfig.progress
		;&
	1)
		echo "################################################################################"
		enable_root_ssh
		echo 2 > .ubuntu-preconfig.progress
		;&
	2)
		echo "################################################################################"
		update_system
		echo 3 > .ubuntu-preconfig.progress
		;&
	3)
		echo "################################################################################"
		init_network
		echo 4 > .ubuntu-preconfig.progress
		;&
	4)
		echo "################################################################################"
		remove_garbage
		echo 5 > .ubuntu-preconfig.progress
		;&
	5)
		echo "################################################################################"
		add_cockpit
		echo 6 > .ubuntu-preconfig.progress
		;&
	6)
		echo "################################################################################"
		use_nm_not_systemd-networkd
		echo 7 > .ubuntu-preconfig.progress
		;&
	7)
		echo "################################################################################"
		setup_done
		echo 8 > .ubuntu-preconfig.progress
		;;
	8)
		echo "Setup successfully finished the previous time running this script."
		;;
esac

exit 0