#!/bin/bash

# Matthew Hutchinson <mhutchinson@45drives.com>


set -e

echo "=== MinIO ZFS Setup Script ==="

# Prompt for required inputs
read -p "Enter ZFS pool name (e.g., tank): " POOL_NAME
read -p "Enter MINIO Access Key: " ACCESS_KEY
read -p "Enter MINIO Secret Key: " SECRET_KEY
read -p "Enter MINIO ADMIN Username: " MINIO_USER
read -p "Enter MINIO ADMIN Password: " MINIO_PASSWORD

# Detect package manager and OS

OS=$(cat /etc/os-release | grep -w NAME)

# Update system
echo "[1/10] Updating system..."
if [ "$OS" == 'NAME="Ubuntu"' ]; then
    sudo apt update && sudo apt upgrade -y
    PM=apt
elif [ "$OS" == 'NAME="Rocky Linux"' ]; then
    sudo dnf update -y
    PM=dnf
else
    echo "Unsupported package manager. Please use a system with DNF or APT."
    exit 1
fi

echo "[2/10] Creating minio user..."
sudo useradd -r minio-user -s /sbin/nologin || echo "User already exists."

echo "[3/10] Installing wget..."
sudo $PM install -y wget

echo "[4/10] Downloading and setting up MinIO binary..."
sudo wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
sudo chmod +x /usr/local/bin/minio

echo "[5/10] Creating ZFS filesystem ${POOL_NAME}/minio..."
sudo zfs create -o recordsize=1M -o atime=off -o xattr=sa -o compression=lz4 ${POOL_NAME}/minio

echo "[6/10] Setting ownership for ZFS mount..."
sudo chown -R minio-user:minio-user /${POOL_NAME}/minio/

echo "[7/10] Creating and setting permissions for config directories..."
sudo mkdir -p /etc/minio/certs
sudo touch /etc/minio/credentials
sudo chown -R minio-user:minio-user /etc/minio/
sudo chmod 600 /etc/minio/credentials

echo "[8/10] Creating default config at /etc/default/minio..."
sudo bash -c "cat > /etc/default/minio" <<EOF
# MinIO Configuration
MINIO_VOLUMES="/${POOL_NAME}/minio/"
MINIO_OPTS="--console-address :7575"
MINIO_ACCESS_KEY="${ACCESS_KEY}"
MINIO_SECRET_KEY="${SECRET_KEY}"
MINIO_CERTS_DIR="/etc/minio/certs"
EOF

echo "[9/10] Creating credentials file..."
sudo bash -c "cat > /etc/minio/credentials" <<EOF
MINIO_ROOT_USER=${MINIO_USER}
MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}
EOF

echo "[10/10] Setting firewall rule for port 7575..."
if command -v firewall-cmd &>/dev/null; then
    sudo firewall-cmd --zone=public --add-port=7575/tcp --permanent || true
    sudo firewall-cmd --reload || true
else
    echo "firewalld not found, skipping firewall configuration."
fi

read -p "Do you want to create self-signed HTTPS certs? (y/n): " USE_SSL
if [[ "$USE_SSL" == "y" ]]; then
    echo "Installing OpenSSL and generating certs..."
    sudo $PM install -y openssl
    sudo openssl genrsa -out /etc/minio/certs/private.key 2048
    sudo openssl req -new -x509 -key /etc/minio/certs/private.key -out /etc/minio/certs/public.crt -days 3650
    sudo chown -R minio-user:minio-user /etc/minio/certs
    sudo chmod 600 /etc/minio/certs/private.key
fi

echo "Creating systemd service for MinIO..."
sudo bash -c "cat > /etc/systemd/system/minio.service" <<'EOF'
[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target

[Service]
User=minio-user
Group=minio-user
ProtectProc=invisible
EnvironmentFile=/etc/default/minio
EnvironmentFile=/etc/minio/credentials
ExecStartPre=/bin/bash -c "if [ -z \"${MINIO_VOLUMES}\" ]; then echo \"Variable MINIO_VOLUMES not set in /etc/default/minio\"; exit 1; fi"
ExecStart=/usr/local/bin/minio server --certs-dir ${MINIO_CERTS_DIR} \$MINIO_OPTS \$MINIO_VOLUMES

# Let systemd restart this service always
Restart=always

# Specifies the maximum file descriptor number that can be opened by this process
LimitNOFILE=65536

# Specifies the maximum number of threads this process can create
TasksMax=infinity

# Disable timeout logic and wait until process is stopped
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF


echo "Enabling and starting MinIO service..."
sudo systemctl daemon-reload
sudo systemctl enable --now minio

echo "=== Setup Complete ==="
echo "Visit https://YOUR_SERVER_IP:7575 to access the MinIO console."
