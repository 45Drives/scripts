#!/bin/bash
## Ubuntu domain join

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
  echo "Error: --hostname, --user, and --realm arguments are required."
  usage
fi

# Force the realm to uppercase for Kerberos
REALM_UPPER="${REALM^^}"

echo "Username: $USERNAME"
echo "Realm:    $REALM_UPPER"

echo "Installing prerequisite packages: realmd, samba, krb5-user..."
apt install -y realmd samba krb5-user

# Normalize case for comparison
HOSTNAME_LOWER=$(echo "$HOSTNAME" | tr '[:upper:]' '[:lower:]')
REALM_LOWER=$(echo "$REALM" | tr '[:upper:]' '[:lower:]')

# Only append the realm if it is not already part of the hostname
if [[ "$HOSTNAME_LOWER" == *"$REALM_LOWER"* ]]; then
  echo "Hostname already contains the realm. Leaving it as: $HOSTNAME"
  FINAL_HOSTNAME="$HOSTNAME"
else
  FINAL_HOSTNAME="$HOSTNAME.$REALM_LOWER"
  echo "Setting hostname to: $FINAL_HOSTNAME"
  hostnamectl set-hostname "$FINAL_HOSTNAME"
fi

currentTimestamp=$(date +%y-%m-%d-%H:%M:%S)
if [ -f /etc/samba/smb.conf ]; then
  echo "Backing up existing samba conf to /etc/samba/smb.conf.$currentTimestamp.bak"
  mv /etc/samba/smb.conf /etc/samba/smb.conf.$currentTimestamp.bak
else
  echo "File /etc/samba/smb.conf does not exist. Skipping."
fi

echo "Generating kerberos ticket, please enter password at the prompt..."
kinit "$USERNAME@$REALM_UPPER"

echo "Validating we can discover the domain..."
realm discover "$REALM_UPPER"

echo "Joining the domain..."
realm join --user="$USERNAME" --membership-software=samba --client-software=winbind --server-software=active-directory "$REALM_UPPER"

echo "Outputting domain join validation..."
realm list

echo "Configuring smb.conf to use net registry"
echo "include = registry" >> /etc/samba/smb.conf

echo "Updating /etc/nsswitch.conf to use winbind"
sed -i -E '/^(passwd|group):/ s/\bsss\b/winbind/g' /etc/nsswitch.conf

echo "Configuring /etc/krb5.conf"
cat <<EOF >/etc/krb5.conf
[libdefaults]
	default_realm = $REALM_UPPER
	dns_lookup_realm = false
	dns_lookup_kdc = true
EOF

# pam-auth-update --enable mkhomedir
systemctl enable --now smbd
