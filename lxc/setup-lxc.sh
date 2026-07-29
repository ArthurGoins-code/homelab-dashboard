#!/bin/bash
#
# Proxmox LXC Setup Script for Homelab Dashboard Resource Collector
# Run this on your Proxmox host to create and configure the LXC container
#

set -e

# Configuration variables (with defaults)
LXC_ID="${LXC_ID:-100}"
LXC_NAME="${LXC_NAME:-homelab-collector}"
LXC_TEMPLATE="${LXC_TEMPLATE:-debian-12-standard}"
LXC_TEMPLATE_URL="${LXC_TEMPLATE_URL:-https://mirrors.zlib.cc/proxmox/images/${LXC_TEMPLATE}.tar.zst}"
LXC_STORAGE="${LXC_STORAGE:-local}"
LXC_CORES="${LXC_CORES:-1}"
LXC_MEMORY="${LXC_MEMORY:-256}"
LXC_SWAP="${LXC_SWAP:-256}"
LXC_ROOTFS_DISK="${LXC_ROOTFS_DISK:-2}"
LXC_NETWORK="${LXC_NETWORK:-vmbr0}"
LXC_IP="${LXC_IP:-192.168.1.200/24}"
LXC_GATEWAY="${LXC_GATEWAY:-192.168.1.1}"
BACKEND_URL="${BACKEND_URL:-http://192.168.1.100:8000}"
COLLECTOR_INTERVAL="${COLLECTOR_INTERVAL:-30}"
NODE_NAME="${NODE_NAME:-$(hostname)}"
LXC_PRIVILEGED="${LXC_PRIVILEGED:-1}"

echo "=========================================="
echo "  Homelab Dashboard - LXC Setup"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  LXC ID:         $LXC_ID"
echo "  LXC Name:       $LXC_NAME"
echo "  Template:       $LXC_TEMPLATE"
echo "  Template URL:   $LXC_TEMPLATE_URL"
echo "  Storage:        $LXC_STORAGE"
echo "  Cores:          $LXC_CORES"
echo "  Memory:         $LXC_MEMORY MB"
echo "  Swap:           $LXC_SWAP MB"
echo "  RootFS Disk:    $LXC_ROOTFS_DISK GB"
echo "  Network:        $LXC_NETWORK"
echo "  IP Address:     $LXC_IP"
echo "  Gateway:        $LXC_GATEWAY"
echo "  Backend URL:    $BACKEND_URL"
echo "  Interval:       $COLLECTOR_INTERVAL s"
echo "  Node Name:      $NODE_NAME"
echo "  Privileged:     $LXC_PRIVILEGED"
echo ""

# Check if template exists in Proxmox
check_template() {
    local template_name="$1"
    local template_file=""

    # Check in template directory
    if [ -f "/var/lib/vz/template/vztmpl/${template_name}.tar.zst" ]; then
        template_file="/var/lib/vz/template/vztmpl/${template_name}.tar.zst"
    elif [ -f "/var/lib/vz/template/vztmpl/${template_name}" ]; then
        template_file="/var/lib/vz/template/vztmpl/${template_name}"
    elif [ -f "/var/lib/vz/template/vztmpl/${template_name}.tar.gz" ]; then
        template_file="/var/lib/vz/template/vztmpl/${template_name}.tar.gz"
    fi

    if [ -n "$template_file" ]; then
        echo "$template_file"
        return 0
    fi
    return 1
}

# Check if template already exists as a container
echo "Checking template..."
if pct status "$LXC_ID" 2>/dev/null; then
    echo "WARNING: LXC container $LXC_ID already exists!"
    read -p "Do you want to destroy it and recreate? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
    pct destroy "$LXC_ID"
    echo "Existing container destroyed."
fi

# Find or download template
TEMPLATE_PATH="$LXC_TEMPLATE"
TEMPLATE_FILE=$(check_template "$LXC_TEMPLATE" 2>/dev/null || true)

if [ -n "$TEMPLATE_FILE" ]; then
    echo "Found template: $TEMPLATE_FILE"
    TEMPLATE_PATH="$LXC_STORAGE:vztmpl/$(basename "$TEMPLATE_FILE")"
else
    echo "Template not found. Downloading..."
    mkdir -p /var/lib/vz/template/vztmpl
    cd /var/lib/vz/template/vztmpl
    wget -q "$LXC_TEMPLATE_URL" -O "${LXC_TEMPLATE}.tar.zst" 2>/dev/null || \
    wget -q "${LXC_TEMPLATE_URL%.tar.zst}.tar.gz" -O "${LXC_TEMPLATE}.tar.gz" 2>/dev/null || \
    echo "WARNING: Download failed, will try using template name directly"
    cd -
    TEMPLATE_PATH="${LXC_STORAGE}:vztmpl/$(basename "$LXC_TEMPLATE")"
fi

echo "Template path: $TEMPLATE_PATH"

# Create the LXC container
echo ""
echo "Creating LXC container..."

pct create $LXC_ID \
  $TEMPLATE_PATH \
  -cores $LXC_CORES \
  -memory $LXC_MEMORY \
  -swap $LXC_SWAP \
  -rootfs ${LXC_STORAGE}-lvm:${LXC_ROOTFS_DISK} \
  -ostype debian \
  -hostname $LXC_NAME \
  -unprivileged $((1 - LXC_PRIVILEGED)) \
  -net0 name=eth0,bridge=$LXC_NETWORK,firewall=1,ip=$LXC_IP,gw=$LXC_GATEWAY \
  -start 1

echo "Container created and started."

# Wait for container to be ready
echo "Waiting for container to boot..."
sleep 3

# Install dependencies inside the container
echo "Installing system dependencies..."
pct exec $LXC_ID -- sh -c "apt-get update && apt-get install -y python3 python3-pip curl procps"

# Install Python dependencies
echo "Installing Python dependencies..."
pct exec $LXC_ID -- sh -c "pip3 install psutil requests"

# Create systemd service
echo "Creating systemd service..."
pct exec $LXC_ID -- sh -c "cat > /etc/systemd/system/homelab-collector.service << SERVEOF
[Unit]
Description=Homelab Dashboard Resource Collector
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/collector.sh
Restart=always
RestartSec=10
Environment=BACKEND_URL=$BACKEND_URL
Environment=COLLECTOR_INTERVAL=$COLLECTOR_INTERVAL
Environment=NODE_NAME=$NODE_NAME
Environment=LOG_FILE=/var/log/homelab-collector.log

[Install]
WantedBy=multi-user.target
SERVEOF"

# Enable and start the service
echo "Enabling collector service..."
pct exec $LXC_ID -- systemctl enable homelab-collector.service
pct exec $LXC_ID -- systemctl start homelab-collector.service

echo ""
echo "=========================================="
echo "  LXC Container Setup Complete!"
echo "=========================================="
echo ""
echo "  Container ID:    $LXC_ID"
echo "  Container Name:  $LXC_NAME"
echo "  IP Address:      $LXC_IP"
echo "  Backend URL:     $BACKEND_URL"
echo ""
echo "  Management commands:"
echo "    pct start $LXC_ID"
echo "    pct stop $LXC_ID"
echo "    pct console $LXC_ID"
echo "    pct exec $LXC_ID -- bash"
echo ""
echo "  View logs:"
echo "    journalctl -u homelab-collector.service"
echo "    tail -f /var/log/homelab-collector.log"
echo ""