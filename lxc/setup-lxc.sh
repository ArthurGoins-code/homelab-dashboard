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

# Check if template already exists as a container
echo "Checking template..."
if pct status "$LXC_ID" 2>/dev/null | grep -q "running\|stopped"; then
    echo "WARNING: LXC container $LXC_ID already exists!"
    read -p "Do you want to destroy it and recreate? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
    pct destroy "$LXC_ID"
    echo "Existing container destroyed."
fi

# Try to find template using pct template command first
find_template_with_pct() {
    local template_name="$1"
    local pct_output
    pct_output=$(pct template 2>/dev/null || true)

    if [ -n "$pct_output" ]; then
        if echo "$pct_output" | grep -qi "$template_name" 2>/dev/null; then
            echo "pct"
            return 0
        fi
    fi
    return 1
}

# Find template file in common Proxmox template directories
find_template_file() {
    local template_name="$1"
    local template_file=""

    # Search common Proxmox template directories including SMB storage
    local template_dirs=(
        "/var/lib/vz/template/vztmpl"
        "/var/lib/vz/template"
        "/var/lib/vz"
        "/mnt/pve/SMB/template/vztmpl"
        "/mnt/pve/SMB/template"
        "/mnt/pve/SMB"
        "/rpool/data/SMB/template/vztmpl"
        "/rpool/data/SMB/template"
        "/rpool/data/SMB"
    )

    for dir in "${template_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # First try exact pattern match for template_name prefix
            template_file=$(find "$dir" -maxdepth 1 -name "${template_name}*" \( -name "*.tar.zst" -o -name "*.tar.gz" \) -type f 2>/dev/null | head -n 1)
            if [ -n "$template_file" ]; then
                echo "$template_file"
                return 0
            fi
            # Also try just the base name without version suffix
            template_file=$(find "$dir" -maxdepth 1 -name "${template_name}_*" \( -name "*.tar.zst" -o -name "*.tar.gz" \) -type f 2>/dev/null | head -n 1)
            if [ -n "$template_file" ]; then
                echo "$template_file"
                return 0
            fi
        fi
    done
    return 1
}

# Download template using pct download (Proxmox-native, handles all mirrors)
download_template_with_pct() {
    local template_name="$1"
    local storage="$2"
    local template_file=""

    echo "  Using pct download to fetch template..."

    # pct download handles mirror config automatically
    # Syntax: pct download <storage> <url>
    # We'll try the common proxmox CDN paths

    local download_dirs=(
        "/var/lib/vz/template/vztmpl"
        "/var/lib/vz/template"
    )

    for dir in "${download_dirs[@]}"; do
        if [ -d "$dir" ]; then
            cd "$dir"

            # Try pct download with common URL patterns
            local pct_urls=(
                "https://mirrors.proxmox.com/images/${template_name}.tar.zst"
                "https://mirrors.proxmox.com/images/dists/noble/main/binary-amd64/${template_name}_12.2-1_amd64.tar.zst"
                "https://mirrors.nju.edu.cn/proxmox/images/${template_name}.tar.zst"
                "https://mirrors.ocf.berkeley.edu/projects/openvz/template/prebuilt/${template_name}.tar.zst"
            )

            for url in "${pct_urls[@]}"; do
                echo "    Trying: $url"
                if wget --timeout=60 -q "$url" -O "${template_name}.tar.zst" 2>/dev/null; then
                    if [ -s "${template_name}.tar.zst" ]; then
                        local fsize=$(stat -f%z "${template_name}.tar.zst" 2>/dev/null || stat -c%s "${template_name}.tar.zst" 2>/dev/null)
                        if [ "$fsize" -gt 1000 ]; then
                            echo "    Downloaded: $url (${fsize} bytes)"
                            cd -
                            return 0
                        fi
                    fi
                fi
            done

            cd -
        fi
    done
    return 1
}

# Find or download template
TEMPLATE_PATH="$LXC_TEMPLATE"
TEMPLATE_FILE_PATH=""

# Method 1: Try pct template command
if find_template_with_pct "$LXC_TEMPLATE" 2>/dev/null; then
    echo "Found template via pct template command."
    TEMPLATE_PATH="$LXC_TEMPLATE"
# Method 2: Try finding template file on disk (including SMB storage)
elif TEMPLATE_FILE=$(find_template_file "$LXC_TEMPLATE" 2>/dev/null); then
    TEMPLATE_NAME=$(basename "$TEMPLATE_FILE")
    TEMPLATE_FILE_PATH="$TEMPLATE_FILE"
    # Detect which storage the file is on
    case "$TEMPLATE_FILE" in
        /mnt/pve/SMB*) LXC_STORAGE="SMB" ;;
        /rpool/data/SMB*) LXC_STORAGE="SMB" ;;
        /var/lib/vz*) LXC_STORAGE="local" ;;
        *) LXC_STORAGE="$LXC_STORAGE" ;;
    esac
    # Use vztmpl content path format for pct create
    # The vztmpl content directory is at /var/lib/vz/vztmpl/ in Proxmox storage
    # First check if the file is already at the right location
    TEMPLATE_PATH="${LXC_STORAGE}:vztmpl/${TEMPLATE_NAME}"
    
    # Check if template exists at the pct-expected location
    if [ -f "/var/lib/vz/vztmpl/${TEMPLATE_NAME}" ]; then
        echo "Template found at /var/lib/vz/vztmpl/"
    elif [ -f "/var/lib/vz/template/vztmpl/${TEMPLATE_NAME}" ]; then
        echo "Template found at /var/lib/vz/template/vztmpl/"
        # Copy to the expected location for pct create
        cp "/var/lib/vz/template/vztmpl/${TEMPLATE_NAME}" "/var/lib/vz/vztmpl/${TEMPLATE_NAME}" 2>/dev/null || true
        echo "Copied template to /var/lib/vz/vztmpl/"
    else
        # File was found by find but may be in a different subdir
        echo "Template file found at: $TEMPLATE_FILE"
        echo "Copying to /var/lib/vz/vztmpl/ for pct create..."
        cp "$TEMPLATE_FILE" "/var/lib/vz/vztmpl/${TEMPLATE_NAME}" 2>/dev/null || true
    fi
    
    echo "Found template file: $TEMPLATE_FILE"
    echo "Template name: $TEMPLATE_NAME"
    echo "Template storage: $LXC_STORAGE"
    echo "Template path: $TEMPLATE_PATH"
    echo "Template file exists: $(test -f "$TEMPLATE_FILE" && echo 'yes' || echo 'no')"
    echo "Template at vztmpl: $(test -f "/var/lib/vz/vztmpl/${TEMPLATE_NAME}" && echo 'yes' || echo 'no')"
# Method 3: Use pct download if pct is available
elif command -v pct &>/dev/null; then
    echo "Template not found on disk. Using pct download..."
    download_template_with_pct "$LXC_TEMPLATE" "$LXC_STORAGE" && \
    TEMPLATE_PATH="${LXC_STORAGE}:vztmpl/${LXC_TEMPLATE}.tar.zst"
# Method 4: Manual download
else
    echo "Template not found. Downloading manually..."
    mkdir -p /var/lib/vz/template/vztmpl
    cd /var/lib/vz/template/vztmpl

    DOWNLOAD_SUCCESS=false
    URL_PATTERNS=(
        "https://mirrors.proxmox.com/images/${LXC_TEMPLATE}.tar.zst"
        "https://mirrors.nju.edu.cn/proxmox/images/${LXC_TEMPLATE}.tar.zst"
        "https://mirrors.ocf.berkeley.edu/projects/openvz/template/prebuilt/${LXC_TEMPLATE}.tar.zst"
        "https://download.proxmox.com/images/system/${LXC_TEMPLATE}.tar.zst"
    )

    for url in "${URL_PATTERNS[@]}"; do
        echo "  Trying: $url"
        if wget --timeout=60 -q "$url" -O "${LXC_TEMPLATE}.tar.zst" 2>/dev/null; then
            if [ -s "${LXC_TEMPLATE}.tar.zst" ]; then
                local fsize=$(stat -c%s "${LXC_TEMPLATE}.tar.zst" 2>/dev/null || echo "0")
                if [ "$fsize" -gt 1000 ]; then
                    echo "  Successfully downloaded: $url ($fsize bytes)"
                    DOWNLOAD_SUCCESS=true
                    break
                fi
            fi
        fi
    done

    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        echo "  WARNING: Could not download template from mirrors."
        echo "  Continuing with template name: $LXC_TEMPLATE"
        echo "  Make sure the template is available on your Proxmox host."
    fi

    cd -
    TEMPLATE_PATH="${LXC_STORAGE}:vztmpl/${LXC_TEMPLATE}.tar.zst"
fi

echo "Using template path: $TEMPLATE_PATH"

# Create the LXC container
echo ""
echo "Creating LXC container..."

pct create $LXC_ID \
  $TEMPLATE_PATH \
  -cores $LXC_CORES \
  -memory $LXC_MEMORY \
  -swap $LXC_SWAP \
  -rootfs ${LXC_STORAGE}:${LXC_ROOTFS_DISK} \
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