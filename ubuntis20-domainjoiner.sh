#/bin/bash
##ubuntis 20 domain joiner extraordainer

set -e

# Function to display usage
usage() {
  echo "Usage: $0 --hostname HOSTNAME --user USERNAME --realm REALM"
  echo
  echo "Options:"
  echo "  --hostname Specify the server hostname"
  echo "  --user     Specify the username"
  echo "  --realm    Specify the realm (e.g., 45drives.local)"
  exit 1
}

# If no arguments passed, show usage
[[ $# -eq 0 ]] && usage

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --user)
      USERNAME="$2"
      shift 2
      ;;
    --realm)
      REALM="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Validate required variables
if [[ -z "$HOSTNAME" || -z "$USERNAME" || -z "$REALM" ]]; then
  echo "Error: --user and --realm arguments are required."
  usage
fi

# Force the realm to uppercase
REALM="${REALM^^}"

# Now do something with $USERNAME and $REALM
echo "Username: $USERNAME"
echo "Realm:    $REALM"


echo "Installing prerequisite packages: realmd, samba, krb5-user....."
apt install realmd samba krb5-user
echo "setting hostname to:" $HOSTNAME.REALM
hostnamectl set-hostname $HOSTNAME.$REALM
currentTimestamp=`date +%y-%m-%d-%H:%M:%S`
echo "Backing up existing samba conf to:" /etc/samba/smb.conf.$currentTimestamp.bak
mv /etc/samba/smb.conf /etc/samba/smb.conf.$currentTimestamp.bak
echo "Generating kerberos ticket, please enter password at the prompt....."
kinit $USERNAME@$REALM
echo "Validating we can discover the domain....."
realm discover $REALM
echo "Joining the domain....."
realm join --user=$USERNAME --membership-software=samba --client-software=winbind --server-software=active-directory $REALM
echo "Outputting domain join validation....."
realm list
echo "Configuring smb.conf to use net registry"
echo include = registry >> /etc/samba/smb.conf
echo "Updating /etc/nsswitch.conf to use winbind"
sed -i -E '/^(passwd|group):/ s/\bsss\b/winbind/g' /etc/nsswitch.conf
echo "Configuring /etc/krb.conf"
cat <<EOF
[libdefaults]
	default_realm = $REALM
	dns_lookup_realm = false
	dns_lookup_kdc = true
EOF
#pam-auth-update --enable mkhomedir
systemctl enable --now smbd
