#!/bin/bash

set -e

# install needed packages
source /etc/os-release

echo "Installing prerequisite packages: realmd, samba, krb5-user....."
case "$ID" in
    rocky|rhel|centos) dnf install -y samba realmd oddjob-mkhomedir oddjob samba-winbind-clients samba-winbind samba-common-tools samba-winbind-krb5-locator krb5-workstation sssd-winbind-idmap ;;
    ubuntu|debian) apt install -y samba realmd oddjob-mkhomedir oddjob winbind libnss-winbind libpam-winbind krb5-user krb5-config ;;
    *)
        echo "Unsupported distro: $PRETTY_NAME"
        exit 1
        ;;
esac

# backing up smb.conf
echo "Backing up existing samba conf to:" /etc/samba/smb.conf.$currentTimestamp.bak
currentTimestamp=`date +%y-%m-%d-%H:%M:%S`
if [ -f /etc/samba/smb.conf ]; then
    mv /etc/samba/smb.conf /etc/samba/smb.conf.$currentTimestamp.bak
    echo "Moved /etc/samba/smb.conf to /etc/samba/smb.conf.$currentTimestamp.bak"
else
    echo "File /etc/samba/smb.conf does not exist. Skipping."
fi

# discover the realm
read -rp "Enter Active Directory Realm (e.g. CONTOSO.LOCAL): " REALM
realm discover ${REALM^^}

# set the full hostname
HOSTNAME=$(hostname -s)

if [[ "${HOSTNAME,,}" == *"${REALM,,}"* ]]; then
  echo "Hostname already contains the realm. Leaving it as: $HOSTNAME"
else
  HOSTNAME="$HOSTNAME.${REALM,,}"
  echo "Setting hostname to: $HOSTNAME"
  hostnamectl set-hostname "$HOSTNAME"
fi

# domain join
read -rp "Enter AD username: " USERNAME
echo "Joining the domain....."
realm join --user=$USERNAME --membership-software=samba --client-software=winbind --server-software=active-directory "${REALM^^}"
echo "Outputting domain join validation....."
realm list
echo "Configuring smb.conf to use net registry"
echo "include = registry" >> /etc/samba/smb.conf

# start services
case "$ID" in
    rocky|rhel|centos) SMB_SVC=smb; NMB_SVC=nmb ;;
    ubuntu|debian) SMB_SVC=smbd; NMB_SVC=nmbd ;;
esac
systemctl enable --now "$SMB_SVC" "$NMB_SVC"
systemctl disable --now sssd
