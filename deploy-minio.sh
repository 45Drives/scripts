#!/bin/bash

# Matthew Hutchinson <mhutchinson@45drives.com>

if [ $EUID -ne 0 ]; then echo "Must be run as root!" >&2 exit 2 fi

set -e

echo "=== MinIO ZFS Setup Script ==="

# Prompt for required inputs
read -p "Enter ZFS pool name (e.g., tank): " POOL_NAME
read -p "Enter MINIO Access Key: " ACCESS_KEY
read -p "Enter MINIO Secret Key: " SECRET_KEY
read -p "Enter MINIO UI ADMIN Username: " MINIO_USER
read -p "Enter MINIO UI ADMIN Password: " MINIO_PASSWORD

# Detect package manager and OS

OS=$(cat /etc/os-release | grep -w NAME)

# Update system
echo "[1/10] Updating system..."
if [ "$OS" == 'NAME="Ubuntu"' ]; then
    apt update && apt upgrade -y
    PM=apt
elif [ "$OS" == 'NAME="Rocky Linux"' ]; then
    dnf update -y
    PM=dnf
else
    echo "Unsupported package manager. Please use a system with DNF or APT."
    exit 1
fi

echo "[2/10] Creating minio user..."
useradd -r minio-user -s /sbin/nologin || echo "User already exists."

echo "[3/10] Installing wget..."
$PM install -y wget

echo "[4/10] Downloading and setting up MinIO binary..."
wget https://dl.min.io/community/server/minio/release/linux-amd64/archive/minio.RELEASE.2025-04-22T22-12-26Z -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

echo "[5/10] Creating ZFS filesystem ${POOL_NAME}/minio..."

# Ensure pool exists
if ! zpool list -H -o name | grep -qx "${POOL_NAME}"; then
  echo "ERROR: ZFS pool '${POOL_NAME}' not found. Pools available:"
  zpool list
  exit 1
fi

DATASET="${POOL_NAME}/minio"

# Existence check with timeout so it cannot "stick"
if timeout 10s zfs list -H -o name "$DATASET" >/dev/null 2>&1; then
  echo "WARNING: The ZFS dataset $DATASET already exists."
  read -p "Do you want to delete and recreate it? This will erase all data in it. (y/n): " RECREATE
  if [[ "$RECREATE" == "y" ]]; then
    echo "Destroying existing dataset $DATASET..."
    zfs destroy -r "$DATASET"
    echo "Creating new dataset $DATASET..."
    zfs create -o recordsize=1M -o atime=off -o xattr=sa -o compression=lz4 "$DATASET"
  elif [[ "$RECREATE" == "n" ]]; then
    read -p "Do you want to deploy on top of existing data? (y/n): " REUSE
    if [[ "$REUSE" != "y" ]]; then
      echo "Exiting"
      exit 1
    fi
  else
    echo "Invalid option. Exiting."
    exit 1
  fi
else
  rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "ERROR: ZFS command timed out. ZFS may be unhealthy or blocked."
    echo "Try: zpool status ; dmesg -T | tail -n 200 | grep -i zfs"
    exit 1
  fi
  echo "Creating new dataset $DATASET..."
  zfs create -o recordsize=1M -o atime=off -o xattr=sa -o compression=lz4 "$DATASET"
fi


echo "[6/10] Setting ownership for ZFS mount..."
chown -R minio-user:minio-user /${POOL_NAME}/minio/

echo "[7/10] Creating and setting permissions for config directories..."
mkdir -p /etc/minio/certs
touch /etc/minio/credentials
chown -R minio-user:minio-user /etc/minio/
chmod 600 /etc/minio/credentials

echo "[8/10] Creating default config at /etc/default/minio..."
bash -c "cat > /etc/default/minio" <<EOF
# MinIO Configuration
MINIO_VOLUMES="/${POOL_NAME}/minio/"
MINIO_ACCESS_KEY="${ACCESS_KEY}"
MINIO_SECRET_KEY="${SECRET_KEY}"
MINIO_CERTS_DIR="/etc/minio/certs"
EOF

echo "[9/10] Creating credentials file..."
bash -c "cat > /etc/minio/credentials" <<EOF
MINIO_ROOT_USER=${MINIO_USER}
MINIO_ROOT_PASSWORD=${MINIO_PASSWORD}
EOF

echo "[10/10] Setting firewall rule for port 7575..."
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --zone=public --add-port=7575/tcp --permanent || true
    firewall-cmd --reload || true
else
    echo "firewalld not found, skipping firewall configuration."
fi

read -p "Do you want to create self-signed HTTPS certs? (y/n): " USE_SSL
if [[ "$USE_SSL" == "y" ]]; then
    echo "Installing OpenSSL and generating certs..."
    $PM install -y openssl
    openssl genrsa -out /etc/minio/certs/private.key 2048
    openssl req -new -x509 -key /etc/minio/certs/private.key -out /etc/minio/certs/public.crt -days 3650
    chown -R minio-user:minio-user /etc/minio/certs
    chmod 600 /etc/minio/certs/private.key
else 
echo -e "\033[1;36mPlace SSL certs in \"/etc/minio/certs\" for custom certificates\033[0m"
fi

echo "Creating systemd service for MinIO..."
bash -c "cat > /etc/systemd/system/minio.service" <<'EOF'
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
ExecStart=/usr/local/bin/minio server --console-address :7575 --certs-dir ${MINIO_CERTS_DIR} \$MINIO_VOLUMES

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
systemctl daemon-reload
systemctl enable --now minio

echo "Installing MinIO client (mc)..."
$PM install -y curl
curl -fL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc

MC_BIN="/usr/local/bin/mc"
if [[ ! -x "$MC_BIN" ]]; then
  echo "ERROR: mc not found or not executable at $MC_BIN"
  ls -l "$MC_BIN" || true
  exit 1
fi


# Determine scheme: https if cert exists, else http
SCHEME="http"
if [[ -f /etc/minio/certs/public.crt ]]; then
  SCHEME="https"

  echo "Trusting MinIO certificate (self-signed)..."
  if [[ "$OS" == 'NAME="Rocky Linux"' ]]; then
    cp /etc/minio/certs/public.crt /etc/pki/ca-trust/source/anchors/minio.crt
    update-ca-trust
  elif [[ "$OS" == 'NAME="Ubuntu"' ]]; then
    cp /etc/minio/certs/public.crt /usr/local/share/ca-certificates/minio.crt
    update-ca-certificates
  fi
fi

echo "Waiting for MinIO to become ready..."
for i in {1..60}; do
  if curl -fsS -k "${SCHEME}://127.0.0.1:9000/minio/health/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "Creating mc alias houston (for root)..."
 "$MC_BIN" alias set houston "${SCHEME}://127.0.0.1:9000" "${MINIO_USER}" "${MINIO_PASSWORD}"

echo "Verifying MinIO admin access via mc..."
 "$MC_BIN" --json admin info houston >/dev/null

echo "mc alias houston created and verified."


echo "=== Setup Complete ==="
echo "Visit https://YOUR_SERVER_IP:7575 to access the MinIO console."

