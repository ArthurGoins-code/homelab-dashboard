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

# Create the LXC container
echo ""
echo "Creating LXC container..."
pct create "$LXC_ID" \
    "$LXC_TEMPLATE" \
    -storage "$LXC_STORAGE" \
    -arch $(uname -m) \
    -cpus "$LXC_CPU" \
    -memory "$LXC_MEMORY" \
    -swap 256 \
    -disk "$LXC_DISK" \
    -net0 "name=eth0,ip=$LXC_IP,gateway=$LXC_GATEWAY,bridge=$LXC_NETWORK" \
    -hostname "$LXC_NAME" \
    -rootfs "$LXC_STORAGE,$LXC_DISK" \
    -features key=ctl \
    --privileged 1

echo "Container created."

# Configure mounts for host access
echo ""
echo "Configuring host mounts..."
pct set "$LXC_ID" \
    -mount "host-proc=$LXC_STORAGE:/proc:bind" \
    -mount "host-sys=$LXC_STORAGE:/sys:bind" \
    -mount "host-dev=$LXC_STORAGE:/dev:bind"

echo "Host mounts configured."

# Set unprivileged to 0 for privileged access
echo "Setting privileged mode..."
pct set "$LXC_ID" --features nesting=1

# Start the container
echo ""
echo "Starting container..."
pct start "$LXC_ID"

# Wait for container to be ready
echo "Waiting for container to boot..."
pct exec "$LXC_ID" -- sh -c "apt-get update && apt-get install -y python3 python3-pip curl procps"

# Install Python dependencies
echo "Installing Python dependencies..."
pct exec "$LXC_ID" -- sh -c "pip3 install psutil requests"

# Copy collector script
echo "Copying collector script..."
scp lxc/collector.sh "$LXC_NAME":/usr/local/bin/collector.sh 2>/dev/null || \
    scp lxc/collector.sh root@$(pct exec "$LXC_ID" -- hostname):/usr/local/bin/collector.sh

# Create systemd service
echo "Creating systemd service..."
pct exec "$LXC_ID" -- sh -c 'cat > /etc/systemd/system/homelab-collector.service << EOF
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
EOF'

# Enable and start the service
pct exec "$LXC_ID" -- systemctl enable homelab-collector.service
pct exec "$LXC_ID" -- systemctl start homelab-collector.service

echo ""
echo "=========================================="
echo "  LXC Container Setup Complete!"
echo "=========================================="
echo ""
echo "  Container ID:  $LXC_ID"
echo "  Container Name: $LXC_NAME"
echo "  IP Address:    $LXC_IP"
echo "  Backend URL:   $BACKEND_URL"
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