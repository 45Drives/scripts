#!/bin/bash

# Matthew Hutchinson <mhutchinson@45drives.com>

# Rocky 9 System Configuration Tweaks for Cluster Nodes

ID=$(grep -w ID= /etc/os-release | cut -d= -f2 | tr -d '"')
Platform=$(grep -w PLATFORM_ID= /etc/os-release | cut -d= -f2 | tr -d '"')

# Check if the OS is Rocky Linux 9
if [[ "$ID" != "rocky" && "$ID" != "rhel" || "$Platform" != "platform:el9" ]]; then
    echo "OS is not Rocky9 or Rhel9 Linux"
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

                                           Rocky9 Preconfiguration Script.

    This script will install cockpit and add our repos. Houston UI will be 
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



selinux_permissive() {
    echo "Setting SELinux to permissive"
    setenforce 0

    echo "Ensuring Setting Persists on Reboot"
    sed -i 's/^\(SELINUX=\).*$/\1permissive/' /etc/selinux/config
    return 0
}

houston_configuration() {
    local res

    echo "Installing Cockpit and Modules"
    dnf -y install dnf-plugins-core
    dnf config-manager --set-enabled powertools
    dnf install -y --nobest cockpit cockpit-pcp cockpit-benchmark cockpit-navigator cockpit-file-sharing cockpit-45drives-hardware cockpit-identities cockpit-storaged cockpit-scheduler 
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
    # Install Ceph Packages
    dnf install ceph ceph-radosgw ceph-mds ceph-mgr-dashboard -y
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
        ;&
    0)
        echo "################################################################################"
        selinux_permissive
        echo 3 > .rocky-preconfig.progress
        ;&
    1)
        echo "################################################################################"
        houston_configuration
        echo 4 > .rocky-preconfig.progress
        ;&
    2)
        echo "################################################################################"
        update_system
        echo 5 > .rocky-preconfig.progress
        ;&
    3)
        echo "################################################################################"
        setup_done
        echo 6 > .rocky-preconfig.progress
        ;&
    4)
        echo "Setup successfully finished the previous time running this script."
        ;;
esac

exit 0