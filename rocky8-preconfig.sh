#!/bin/bash

# Matthew Hutchinson <mhutchinson@45drives.com>


# Rocky 8 System Configuration Tweaks


ID=$(grep -w ID= /etc/os-release | cut -d= -f2 | tr -d '"')
Platform=$(grep -w PLATFORM_ID= /etc/os-release | cut -d= -f2 | tr -d '"')

# Check if the OS is Rocky Linux 8
if [[ "$ID" != "rocky" && "$ID" != "rhel" || "$Platform" != "platform:el8" ]]; then
    echo "OS is not Rocky8 Linux"
    exit 1
fi


interpreter=$(ps -p $$ | awk '$1 != "PID" {print $(NF)}' | tr -d '()')

if [ "$interpreter" != "bash" ]; then
	echo "Please run with bash. (\`./rocky-preconfig.sh\` or \`bash rocky-preconfig.sh\`)"
	echo "Current interpreter: $interpreter"
	exit 1
fi

euid=$(id -u)

if [[ "$euid" != 0 ]]; then 
	echo "Please run as root or with sudo."
	exit 1
fi


# Check for available updates
echo "Checking for system updates..."
updates=$(dnf check-update --quiet)
exit_code=$?

if [ "$exit_code" -eq 100 ]; then
    echo "Updates are available. Please run 'dnf update' and reboot the system before proceeding."
    exit 1
elif [ "$exit_code" -eq 0 ]; then
    echo "System is up to date. Continuing with the script..."
else
    echo "There was an issue checking for updates. Exit code: $exit_code"
    exit $exit_code
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

                                           Rocky8 Preconfiguration Script.

    This script will install epel-release, zfs, cockpit and add our repos. Houston UI will be 
    configured with our latest tools and packages. 

    
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

setup_45drives_repo() {
    local res
    #Install 45Drives Repository
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
	
    return 0
}


install_epel_release() {
    local res
    echo "Installing epel-release"
    dnf install epel-release -y 

    res=$? 
    
    if [[ $res != 0 ]]; then 
        echo "epel-release install failed!"
        exit $res
    fi
    return 0
}


selinux_permissive() {
    echo "Setting SELinux to permissive"
    setenforce 0

    echo "Ensuring Setting Persists on Reboot"
    sed -i 's/^\(SELINUX=\).*$/\1permissive/' /etc/selinux/config
    return 0
}


install_zfs() {
    local res

    echo "Pulling down ZFS packages"
    source /etc/os-release

    dnf install -y https://zfsonlinux.org/epel/zfs-release-2-3$(rpm --eval "%{dist}").noarch.rpm
    
    res=$?
    if [[ $res != 0 ]]; then  
        echo "ZFS package install failed!"
        exit $res
    fi

    echo "Installing ZFS & kernel-devel"
    dnf install -y kernel-devel zfs

    res=$?
    if [[ $res != 0 ]]; then 
        echo "ZFS/kernel-devel install failed"
        exit $res
    fi

    echo "Setting ZFS to load on boot"
    echo zfs > /etc/modules-load.d/zfs.conf
    res=$?
    if [[ $res != 0 ]]; then
        echo "Step Failed"
        exit $res
    fi

    echo "Loading ZFS"
    modprobe zfs
    res=$?
    if [[ $res != 0 ]]; then 
        echo "Load ZFS Manually Failed"
        exit $res
    fi

    return 0
}


houston_configuration() {
    local res

    echo "Installing Cockpit and Modules"
    dnf -y install dnf-plugins-core
    dnf config-manager --set-enabled powertools
    dnf install -y cockpit cockpit-pcp cockpit-benchmark cockpit-navigator cockpit-file-sharing cockpit-45drives-hardware cockpit-identities \
        cockpit-sosreport cockpit-storaged cockpit-scheduler cockpit-zfs
    res=$?
    if [[ $res != 0 ]]; then
        echo "Error Installing Cockpit"
        exit $res
    fi

    echo "Configuring Firewall"
    firewall-cmd --add-service=cockpit --permanent
    res=$?
    if [[ $res != 0 ]]; then
        echo "Error Configuring Firewall"
        exit $res
    fi
    firewall-cmd --reload

    echo "Enabling Cockpit"
    systemctl enable --now cockpit.socket
    res=$?
    if [[ $res != 0 ]]; then
        echo "Error Configuring Firewall"
        exit $res
    fi
    return 0
}

update_system() {
    local res

    echo "Updating system"
    dnf update --nobest -y
    res=$?

    if [[ $res != 0 ]]; then 
        echo "Failed to update system"
        exit $res
    fi
    
    echo "Successfully Updated System"
    return 0 
}

setup_done() {
	
    echo "Installation Complete"
    echo "Access Houston UI at https://$(hostname -I | awk '{print $1}'):9090 in a browser"

	return 0
}

progress=""

if [[ -f .rocky-preconfig.progress ]]; then
	progress=$(cat .rocky-preconfig.progress)
fi

if [[ $progress != "" ]]; then
	echo "Found progress from previous time running this script. ($PWD/.rocky-preconfig.progress)"
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
		setup_45drives_repo
		echo 1 > .rocky-preconfig.progress
		;&

    1)
		echo "################################################################################"
		install_epel_release
		echo 2 > .rocky-preconfig.progress
		;&
	2)
		echo "################################################################################"
		install_zfs
		echo 3 > .rocky-preconfig.progress
		;&
    3)
		echo "################################################################################"
		selinux_permissive
		echo 4 > .rocky-preconfig.progress
		;&
    4)
		echo "################################################################################"
		houston_configuration
		echo 5 > .rocky-preconfig.progress
		;&
    5)
		echo "################################################################################"
		update_system
		echo 6 > .rocky-preconfig.progress
		;&
    6)
		echo "################################################################################"
		setup_done
		echo 7 > .rocky-preconfig.progress
		;&
    7)
		echo "Setup successfully finished the previous time running this script."
		;;
	
esac

exit 0
