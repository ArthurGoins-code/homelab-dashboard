#!/bin/bash
#
# Proxmox LXC Setup Script for Homelab Dashboard Resource Collector
# Run this on your Proxmox host to create and configure the LXC container
# Inspired by https://github.com/community-scripts/ProxmoxVE
#

# ─── Interactive Storage Selection ───
# Get available storage from Proxmox (like mealie.sh does)
get_available_storage() {
    local storage="$1"
    local found=false

    # If storage is set and available, use it
    if [ -n "$storage" ]; then
        if pvesm status | grep -q "^${storage} "; then
            echo "$storage"
            return 0
        fi
    fi

    # Auto-detect available storage (priority: local > local-lvm > SMB/NFS > first available)
    local storages=("local" "local-lvm" "SMB" "nfs" "ceph")
    for s in "${storages[@]}"; do
        if pvesm status 2>/dev/null | grep -q "^${s} "; then
            echo "$s"
            return 0
        fi
    done

    # Fallback: get first storage from pvesm
    local first_storage
    first_storage=$(pvesm status 2>/dev/null | grep -v "type\|storage" | head -n 1 | awk '{print $1}')
    if [ -n "$first_storage" ]; then
        echo "$first_storage"
        return 0
    fi

    echo "local"
}

# ─── Interactive Template Selection ───
# Find and list available templates (like mealie.sh does)
find_available_templates() {
    local storage="$1"
    local template_dir=""

    case "$storage" in
        local)
            template_dir="/var/lib/vz/template/cache"
            ;;
        local-lvm)
            template_dir="/var/lib/vz/template/cache"
            ;;
        *)
            template_dir="/var/lib/vz/template/cache"
            ;;
    esac

    # Search for templates in common locations
    local template_dirs=(
        "/var/lib/vz/template/cache"
        "/var/lib/vz/template/vztmpl"
        "/var/lib/vz/template"
    )

    local templates=()
    for dir in "${template_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r t; do
                templates+=("$t")
            done < <(find "$dir" -maxdepth 1 \( -name "*.tar.zst" -o -name "*.tar.gz" \) -type f 2>/dev/null | sort)
        fi
    done

    # If SMB storage, also check there
    if [ -d "/mnt/pve/SMB/template" ]; then
        while IFS= read -r t; do
            templates+=("$t")
        done < <(find "/mnt/pve/SMB/template" -maxdepth 1 \( -name "*.tar.zst" -o -name "*.tar.gz" \) -type f 2>/dev/null | sort)
    fi

    echo "${templates[@]}"
}

# ─── Download template using Proxmox's native pveam ───
download_template_via_pveam() {
    local template_name="$1"
    local storage="$2"

    echo "  Downloading template via pveam..."

    # pveam download downloads to /var/lib/vz/template/cache/
    pveam download "$storage" "$template_name" 2>&1 | tail -n 1

    if [ -f "/var/lib/vz/template/cache/${template_name}" ]; then
        local fsize
        fsize=$(stat -c%s "/var/lib/vz/template/cache/${template_name}" 2>/dev/null || echo "0")
        echo "  Downloaded: /var/lib/vz/template/cache/${template_name} ($fsize bytes)"
        return 0
    fi

    return 1
}

# ─── Interactive prompt for numeric selection ───
prompt_selection() {
    local prompt_text="$1"
    local default="$2"

    if [ -z "$default" ]; then
        read -p "${prompt_text}: " choice
    else
        read -p "${prompt_text} [default: $default]: " choice
        [ -z "$choice" ] && choice="$default"
    fi
    echo "$choice"
}

# ─── Interactive prompt for yes/no ───
prompt_yes_no() {
    local prompt_text="$1"
    local default="$2"

    local default_str=""
    if [ "$default" = "y" ]; then
        default_str="Y"
    elif [ "$default" = "n" ]; then
        default_str="N"
    fi

    if [ -z "$default_str" ]; then
        read -p "${prompt_text} (y/N): " choice
    else
        read -p "${prompt_text} ($default_str): " choice
        [ -z "$choice" ] && choice="$default_str"
    fi

    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        return 0
    else
        return 1
    fi
}

# ─── Main Setup ───
echo "=========================================="
echo "  Homelab Dashboard - LXC Setup"
echo "=========================================="
echo ""

# ─── Interactive Configuration ───
echo "Configuration mode: Interactive"
echo ""

# LXC ID
LXC_ID=$(prompt_selection "Container ID" "$LXC_ID")

# LXC Name
LXC_NAME=$(prompt_selection "Container name" "$LXC_NAME")

# LXC Template
echo ""
echo "Available templates:"
available_templates=$(find_available_templates "$LXC_STORAGE")
if [ -n "$available_templates" ]; then
    idx=1
    template_list=()
    for t in $available_templates; do
        template_list+=("$t")
        echo "  $idx. $(basename "$t")"
        idx=$((idx + 1))
    done

    if [ ${#template_list[@]} -gt 0 ]; then
        echo "  0. Use custom name"
        tpl_choice=$(prompt_selection "Select template" "1")

        if [ "$tpl_choice" = "0" ]; then
            LXC_TEMPLATE=$(prompt_selection "Custom template name (e.g., debian-12-standard)" "$LXC_TEMPLATE")
        else
            LXC_TEMPLATE=$(basename "${template_list[$((tpl_choice - 1))]}")
        fi
    else
        LXC_TEMPLATE=$(prompt_selection "No templates found. Enter template name" "$LXC_TEMPLATE")
    fi
else
    LXC_TEMPLATE=$(prompt_selection "No templates found. Enter template name" "$LXC_TEMPLATE")
fi

# Storage
echo ""
echo "Available storage:"
pvesm status 2>/dev/null | grep -v "^type" | while read -r line; do
    echo "  $line"
done
LXC_STORAGE=$(prompt_selection "Template storage" "$(get_available_storage)")

# Cores
LXC_CORES=$(prompt_selection "Number of cores" "$LXC_CORES")

# Memory
LXC_MEMORY=$(prompt_selection "Memory (MB)" "$LXC_MEMORY")

# Swap
LXC_SWAP=$(prompt_selection "Swap (MB)" "$LXC_SWAP")

# RootFS Disk
LXC_ROOTFS_DISK=$(prompt_selection "RootFS disk size (GB)" "$LXC_ROOTFS_DISK")

# Network
LXC_NETWORK=$(prompt_selection "Network bridge" "$LXC_NETWORK")

# IP Address
LXC_IP=$(prompt_selection "IP address (CIDR)" "$LXC_IP")

# Gateway
LXC_GATEWAY=$(prompt_selection "Gateway" "$LXC_GATEWAY")

# Backend URL
BACKEND_URL=$(prompt_selection "Backend URL" "$BACKEND_URL")

# Collector Interval
COLLECTOR_INTERVAL=$(prompt_selection "Collection interval (seconds)" "$COLLECTOR_INTERVAL")

# Node Name
NODE_NAME=$(prompt_selection "Node name" "$NODE_NAME")

# Privileged
if prompt_yes_no "Privileged container?" "y"; then
    LXC_PRIVILEGED=1
else
    LXC_PRIVILEGED=0
fi

echo ""
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
echo "Checking for existing container..."
if pct status "$LXC_ID" 2>/dev/null | grep -q "running\|stopped"; then
    echo "WARNING: LXC container $LXC_ID already exists!"
    if prompt_yes_no "Do you want to destroy it and recreate?"; then
        pct destroy "$LXC_ID" 2>/dev/null || true
        pct destroydisk "$LXC_ID" 2>/dev/null || true
        echo "Existing container destroyed."
    else
        echo "Aborted."
        exit 1
    fi
fi

# ─── Template Resolution ───
# Find the template file and determine the correct path for pct create
echo ""
echo "Resolving template..."

TEMPLATE_NAME="$LXC_TEMPLATE"
TEMPLATE_FILE_PATH=""
TEMPLATE_PATH="${LXC_STORAGE}:vztmpl/${TEMPLATE_NAME}"

# Step 1: Check if template is a .tar.zst/.tar.gz file that exists on disk
check_template_file() {
    local name="$1"
    local storage="$2"

    # Try common template file locations
    local template_dirs=(
        "/var/lib/vz/template/cache"
        "/var/lib/vz/template/vztmpl"
        "/var/lib/vz/template"
        "/var/lib/vz/vztmpl"
    )

    # Also check SMB storage
    if [ -d "/mnt/pve/SMB/template" ]; then
        template_dirs+=("/mnt/pve/SMB/template")
    fi

    for dir in "${template_dirs[@]}"; do
        # Try exact name
        if [ -f "${dir}/${name}" ]; then
            local fsize
            fsize=$(stat -c%s "${dir}/${name}" 2>/dev/null || echo "0")
            echo "  Found: ${dir}/${name} ($fsize bytes)" >&2
            printf '%s' "${dir}/${name}"
            return 0
        fi

        # Try with .tar.zst extension
        if [ -f "${dir}/${name}.tar.zst" ]; then
            local fsize
            fsize=$(stat -c%s "${dir}/${name}.tar.zst" 2>/dev/null || echo "0")
            echo "  Found: ${dir}/${name}.tar.zst ($fsize bytes)" >&2
            printf '%s' "${dir}/${name}.tar.zst"
            return 0
        fi

        # Try with .tar.gz extension
        if [ -f "${dir}/${name}.tar.gz" ]; then
            local fsize
            fsize=$(stat -c%s "${dir}/${name}.tar.gz" 2>/dev/null || echo "0")
            echo "  Found: ${dir}/${name}.tar.gz ($fsize bytes)" >&2
            printf '%s' "${dir}/${name}.tar.gz"
            return 0
        fi

        # Try pattern match (e.g., debian-12-standard -> debian-12-standard-*.tar.zst)
        local found
        found=$(find "$dir" -maxdepth 1 -name "${name}*" \( -name "*.tar.zst" -o -name "*.tar.gz" \) -type f 2>/dev/null | head -n 1)
        if [ -n "$found" ]; then
            local fsize
            fsize=$(stat -c%s "$found" 2>/dev/null || echo "0")
            echo "  Found: $found ($fsize bytes)" >&2
            printf '%s' "$found"
            return 0
        fi
    done

    return 1
}

# Check if we have a valid template file
TEMPLATE_FILE=$(check_template_file "$LXC_TEMPLATE" "$LXC_STORAGE")

if [ -n "$TEMPLATE_FILE" ]; then
    TEMPLATE_NAME=$(basename "$TEMPLATE_FILE")
    TEMPLATE_FILE_PATH="$TEMPLATE_FILE"

    # Check file size - must be > 1MB for pct create
    tpl_size=$(stat -c%s "$TEMPLATE_FILE" 2>/dev/null || echo "0")
    if [ "$tpl_size" -lt 1000000 ]; then
        echo "  WARNING: Template file is only $tpl_size bytes (expected >= 1MB)"
        echo "  Will try to download if pct create fails."
    else
        echo "  Template size OK: $tpl_size bytes"
    fi

    # Determine TEMPLATE_PATH based on storage and file location
    case "$TEMPLATE_FILE" in
        /var/lib/vz/*)
            TEMPLATE_PATH="local:vztmpl/${TEMPLATE_NAME}"
            LXC_STORAGE="local"
            ;;
        /mnt/pve/*)
            # Extract storage name from path (e.g., /mnt/pve/SMB -> SMB)
            TEMPLATE_STORAGE=$(echo "$TEMPLATE_FILE" | cut -d'/' -f 4)
            TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}"
            LXC_STORAGE="$TEMPLATE_STORAGE"
            ;;
        *)
            TEMPLATE_PATH="${LXC_STORAGE}:vztmpl/${TEMPLATE_NAME}"
            ;;
    esac
else
    # No template file found on disk - download it
    echo "  No existing template found. Downloading..."

    # Try pveam download first
    if download_template_via_pveam "$LXC_TEMPLATE" "$LXC_STORAGE"; then
        TEMPLATE_NAME="${LXC_TEMPLATE}.tar.zst"
        TEMPLATE_PATH="${LXC_STORAGE}:vztmpl/${TEMPLATE_NAME}"
        TEMPLATE_FILE_PATH="/var/lib/vz/template/cache/${TEMPLATE_NAME}"
    else
        echo "  ERROR: Could not find or download template: $LXC_TEMPLATE"
        echo ""
        echo "  Options:"
        echo "    1. Check your template name (try: pct list-contents <storage>)"
        echo "    2. Download a template manually: pveam download local debian-12-standard"
        echo "    3. Set LXC_TEMPLATE env var and re-run"
        echo ""
        exit 1
    fi
fi

echo "  Template name: $TEMPLATE_NAME"
echo "  Template path: $TEMPLATE_PATH"
echo "  Template file: $TEMPLATE_FILE_PATH"

# Validate template exists for pct create
if ! pct status "$LXC_ID" 2>/dev/null | grep -q "running\|stopped"; then
    # Check if template file actually exists for pct create
    if [ -n "$TEMPLATE_FILE_PATH" ]; then
        if [ ! -f "$TEMPLATE_FILE_PATH" ]; then
            echo "  ERROR: Template file does not exist: $TEMPLATE_FILE_PATH"
            exit 1
        fi

        # Validate file size
        tpl_size=$(stat -c%s "$TEMPLATE_FILE_PATH" 2>/dev/null || echo "0")
        if [ "$tpl_size" -lt 1000000 ]; then
            echo "  WARNING: Template file is only $tpl_size bytes (expected >= 1MB)"
            echo "  Attempting to proceed anyway..."
        fi
    fi
fi

# Create the LXC container
echo ""
echo "Creating LXC container..."

pct create "$LXC_ID" \
  "$TEMPLATE_PATH" \
  -cores "$LXC_CORES" \
  -memory "$LXC_MEMORY" \
  -swap "$LXC_SWAP" \
  -rootfs "${LXC_STORAGE}:${LXC_ROOTFS_DISK}" \
  -ostype debian \
  -hostname "$LXC_NAME" \
  -unprivileged "$((1 - LXC_PRIVILEGED))" \
  -net0 "name=eth0,bridge=${LXC_NETWORK},firewall=1,ip=${LXC_IP},gw=${LXC_GATEWAY}" \
  -start 1

echo "Container created and started."

# Wait for container to be ready
echo "Waiting for container to boot..."
sleep 3

# Install dependencies inside the container
echo "Installing system dependencies..."
pct exec "$LXC_ID" -- sh -c "apt-get update && apt-get install -y python3 python3-pip curl procps"

# Install Python dependencies
echo "Installing Python dependencies..."
pct exec "$LXC_ID" -- sh -c "pip3 install psutil requests"

# Create collector script inside container
echo "Installing collector script..."
pct exec "$LXC_ID" -- sh -c "cat > /usr/local/bin/collector.sh << 'COLLECTOREOF'
#!/bin/bash
#
# Homelab Dashboard Resource Collector
# Collects system metrics and sends to the dashboard backend
#

BACKEND_URL=\"\${BACKEND_URL:-http://192.168.1.100:8000}\"
COLLECTOR_INTERVAL=\"\${COLLECTOR_INTERVAL:-30}\"
NODE_NAME=\"\${NODE_NAME:-\$(hostname)}\"
LOG_FILE=\"\${LOG_FILE:-/var/log/homelab-collector.log}\"

log() {
    echo \"\$(date '+%Y-%m-%d %H:%M:%S') - \$1\" | tee -a \"\$LOG_FILE\"
}

collect_metrics() {
    # Get system metrics
    local cpu_usage
    cpu_usage=\$(top -bn1 | grep \"Cpu(s)\" | awk '{print \$2}' | cut -d'%' -f1)
    [ -z \"$cpu_usage\" ] && cpu_usage=0

    local mem_info
    mem_info=\$(free | grep Mem)
    local mem_total=\$(echo \"$mem_info\" | awk '{print \$2}')
    local mem_used=\$(echo \"$mem_info\" | awk '{print \$3}')
    local mem_percent=\$(echo \"scale=2; $mem_used * 100 / $mem_total\" | bc)

    local disk_info
    disk_info=\$(df -h / | tail -1)
    local disk_total=\$(echo \"$disk_info\" | awk '{print \$2}')
    local disk_used=\$(echo \"$disk_info\" | awk '{print \$3}')
    local disk_percent=\$(echo \"$disk_info\" | awk '{print \$5}' | tr -d '%')

    # Get process count
    local process_count
    process_count=\$(ps aux | wc -l)

    # Get uptime
    local uptime_str
    uptime_str=\$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')

    log \"Collecting metrics for node: $NODE_NAME\"

    # Send metrics to backend
    curl -s -X POST \"\$BACKEND_URL/api/resources/proxmox/nodes/$NODE_NAME/metrics\" \
        -H \"Content-Type: application/json\" \
        -d '{
            \"node_name\": \"$NODE_NAME\",
            \"cpu_usage\": $cpu_usage,
            \"memory_total\": $mem_total,
            \"memory_used\": $mem_used,
            \"memory_percent\": $mem_percent,
            \"disk_total\": \"$disk_total\",
            \"disk_used\": \"$disk_used\",
            \"disk_percent\": $disk_percent,
            \"process_count\": $process_count,
            \"uptime\": \"$uptime_str\"
        }' 2>/dev/null
}

log \"Collector started for node: $NODE_NAME\"
log \"Backend URL: $BACKEND_URL\"
log \"Collection interval: $COLLECTOR_INTERVAL seconds\"

# Run initial collection
collect_metrics

# Loop forever
while true; do
    sleep \"$COLLECTOR_INTERVAL\"
    collect_metrics
done
COLLECTOREOF"

# Make collector script executable
pct exec "$LXC_ID" -- chmod +x /usr/local/bin/collector.sh

# Create systemd service
echo "Creating systemd service..."
pct exec "$LXC_ID" -- sh -c "cat > /etc/systemd/system/homelab-collector.service << SERVEOF
[Unit]
Description=Homelab Dashboard Resource Collector
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/bash /usr/local/bin/collector.sh
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
pct exec "$LXC_ID" -- systemctl daemon-reload
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