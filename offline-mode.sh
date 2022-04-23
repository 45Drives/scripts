#!/bin/bash
usage() { # Help
cat << EOF
    Usage: ./offline-mode.sh -m <enable|disable> -i <interface_name>
        [-m] Mode. Required. Enable turns internet access OFF, Disable turns internet ON
        [-i] Interface. Required. Active interface name
        [-g] Gateway Address. Optional. Defaults to 192.168.0.1
        [-h] Displays this message
EOF
    exit 1
}

GATEWAY="192.168.0.1"
INTERFACES=( $(ls /sys/class/net | grep -v lo) )

while getopts 'm:i:g:h' OPTION; do
    case ${OPTION} in
    m)
        MODE="${OPTARG}"
        ;;
    i)
        INTERFACE="${OPTARG}"
        ;;
    g)
        GATEWAY="${OPTARG}"
        ;;
    h)
        usage
        ;;
    esac
done

if [ -z $MODE ] ; then
    usage
elif [ "$MODE" != "enable" ] && [ "$MODE" != "disable" ]; then
    usage
fi
if [ -z $INTERFACE ] ; then
    usage
elif [[ ! " ${INTERFACES[*]} " =~ " $INTERFACE " ]];then
    echo "Network interface does not exist on server"
    exit 1
fi

case $MODE in
enable)
    echo "removing gateway on $INTERFACE"
    nmcli connection modify "$INTERFACE" ipv4.gateway "0.0.0.0"
    ;;
disable)
    echo "adding gateway address $GATEWAY on $INTERFACE "
    nmcli connection modify "$INTERFACE" ipv4.gateway "$GATEWAY"
    ;;
*)
    echo "input options are: enable or disable"
    exit 1
    ;;
esac
echo "Reloading $INTERFACE" 
nmcli connection up "$INTERFACE"
