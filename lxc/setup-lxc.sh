#!/bin/bash
#
# Proxmox LXC Setup Script for Homelab Dashboard Resource Collector
# Run this on your Proxmox host to create and configure the LXC container
#

set -e

# Configuration variables (with defaults)
LXC_ID="${LXC_ID:-100}"
LXC_NAME="${LXC_NAME:-homelab-collector}"
LXC_TEMPLATE="${LXC_TEMPLATE:-ubuntu-24.04-standard}"
LXC_STORAGE="${LXC_STORAGE:-local}"
LXC_CPU="${LXC_CPU:-1}"
LXC_MEMORY="${LXC_MEMORY:-256}"
LXC_DISK="${LXC_DISK:-2}"
LXC_NETWORK="${LXC_NETWORK:-vmbr0}"
LXC_IP="${LXC_IP:-192.168.1.200/24}"
LXC_GATEWAY="${LXC_GATEWAY:-192.168.1.1}"
BACKEND_URL="${BACKEND_URL:-http://192.168.1.100:8000}"
COLLECTOR_INTERVAL="${COLLECTOR_INTERVAL:-30}"
NODE_NAME="${NODE_NAME:-$(hostname)}"

echo "=========================================="
echo "  Homelab Dashboard - LXC Setup"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  LXC ID:       $LXC_ID"
echo "  LXC Name:     $LXC_NAME"
echo "  Template:     $LXC_TEMPLATE"
echo "  Storage:      $LXC_STORAGE"
echo "  CPU Cores:    $LXC_CPU"
echo "  Memory:       $LXC_MEMORY MB"
echo "  Disk Size:    $LXC_DISK GB"
echo "  Network:      $LXC_NETWORK"
echo "  IP Address:   $LXC_IP"
echo "  Gateway:      $LXC_GATEWAY"
echo "  Backend URL:  $BACKEND_URL"
echo "  Interval:     $COLLECTOR_INTERVAL s"
echo "  Node Name:    $NODE_NAME"
echo ""

# Check if template exists
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

# Resolve template path
TEMPLATE_PATH="$LXC_TEMPLATE"
if ! pct template "$LXC_TEMPLATE" 2>/dev/null; then
    # Try with storage prefix
    TEMPLATE_PATH="${LXC_STORAGE}:${LXC_TEMPLATE}"
fi

# Create the LXC container
echo ""
echo "Creating LXC container..."
pct create "$LXC_ID" \
    "$TEMPLATE_PATH" \
    --storage "$LXC_STORAGE" \
    --arch $(uname -m) \
    --cpus "$LXC_CPU" \
    --memory "$LXC_MEMORY" \
    --swap 256 \
    --disk "$LXC_DISK" \
    --net0 "name=eth0,ip=$LXC_IP,gateway=$LXC_GATEWAY,bridge=$LXC_NETWORK" \
    --hostname "$LXC_NAME" \
    --rootfs "$LXC_STORAGE,$LXC_DISK" \
    --features key=ctl,nesting=1 \
    --privileged

echo "Container created."

# Start the container
echo ""
echo "Starting container..."
pct start "$LXC_ID"

# Wait for container to be ready
echo "Waiting for container to boot..."
sleep 3

# Install dependencies inside the container
echo "Installing system dependencies..."
pct exec "$LXC_ID" -- sh -c "apt-get update && apt-get install -y python3 python3-pip curl procps"

# Install Python dependencies
echo "Installing Python dependencies..."
pct exec "$LXC_ID" -- sh -c "pip3 install psutil requests"

# Copy collector script
echo "Copying collector script..."
CURRENT_HOST=$(hostname)
scp lxc/collector.sh "root@$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}'):/usr/local/bin/collector.sh" 2>/dev/null || \
    scp lxc/collector.sh root@"$CURRENT_HOST":/usr/local/bin/collector.sh 2>/dev/null || \
    echo "Note: scp failed, collector.sh will need to be copied manually."

# Create systemd service
echo "Creating systemd service..."
pct exec "$LXC_ID" -- sh -c "cat > /etc/systemd/system/homelab-collector.service << EOF
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
EOF"

# Enable and start the service
echo "Enabling collector service..."
pct exec "$LXC_ID" -- systemctl enable homelab-collector.service
pct exec "$LXC_ID" -- systemctl start homelab-collector.service

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