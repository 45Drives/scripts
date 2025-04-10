#/bin/bash
#rocky 8 domain join

set -e

# Function to display usage
usage() {
  echo "Usage: $0 --user USERNAME --realm REALM"
  echo
  echo "Options:"
  echo "  --user     Specify the username"
  echo "  --realm    Specify the realm (e.g., 45drives.local)"
  exit 1
}

# If no arguments passed, show usage
[[ $# -eq 0 ]] && usage

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
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
if [[ -z "$USERNAME" || -z "$REALM" ]]; then
  echo "Error: --user and --realm arguments are required."
  usage
fi

# Uppercase the realm
REALM="${REALM^^}"

# Set the full hostname
HOSTNAME="$(hostname -s)"
FQDN="${HOSTNAME}.${REALM}"
echo "Setting hostname to: $FQDN"
hostnamectl set-hostname $FQDN


#  Now do something with $USERNAME and $REALM
echo "Username: $USERNAME"
echo "Realm:    $REALM"
echo "Hostname: $FQDN"

# Install needed packages 
echo "Installing prerequisite packages: realmd, samba, krb5-user....."
dnf install realmd oddjob-mkhomedir oddjob samba-winbind-clients samba-winbind samba-common-tools samba-winbind-krb5-locator samba -y

#Backing up smb.conf
currentTimestamp=`date +%y-%m-%d-%H:%M:%S`
echo "Backing up existing samba conf to:" /etc/samba/smb.conf.$currentTimestamp.bak
if [ -f /etc/samba/smb.conf ]; then
    mv /etc/samba/smb.conf /etc/samba/smb.conf.$currentTimestamp.bak
    echo "Moved /etc/samba/smb.conf to /etc/samba/smb.conf.$currentTimestamp.bak"
else
    echo "File /etc/samba/smb.conf does not exist. Skipping."
fi

# Domain Join
echo "Validating we can discover the domain....."
realm discover $REALM
echo "Joining the domain....."
realm join --user=$USERNAME --membership-software=samba --client-software=winbind --server-software=active-directory $REALM
echo "Outputting domain join validation....."
realm list
echo "Configuring smb.conf to use net registry"
echo "include = registry" >> /etc/samba/smb.conf
systemctl enable --now smb