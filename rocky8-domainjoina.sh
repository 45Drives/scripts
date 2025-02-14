#/bin/bash
#rocky 8 domain join

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
dnf install realmd oddjob-mkhomedir oddjob samba-winbind-clients samba-winbind samba-common-tools samba-winbind-krb5-locator samba
echo "setting hostname to:" $HOSTNAME.$REALM
hostnamectl set-hostname $HOSTNAME.$REALM
echo "Backing up existing samba conf to:" /etc/samba/smb.conf.$currentTimestamp.bak
currentTimestamp=`date +%y-%m-%d-%H:%M:%S`
mv /etc/samba/smb.conf /etc/samba/smb.conf.$currentTimestamp.bak
echo "Validating we can discover the domain....."
realm discover $REALM
echo "Joining the domain....."
realm join --user=ballison --membership-software=samba --client-software=winbind --server-software=active-directory 45SERVICE.LOCAL
echo "Outputting domain join validation....."
realm list
echo "Configuring smb.conf to use net registry"
echo include = registry >> smb.conf
systemctl enable --now smb
