#!/bin/bash
#
# Homelab Dashboard - LXC Setup Script
# Creates a non-privileged LXC container that runs the backend (FastAPI) + frontend (Nginx)
# Pulls code from GitHub and sets up everything automatically
#

set -e

# Configuration variables (with defaults)
LXC_ID="${LXC_ID:-105}"
LXC_NAME="${LXC_NAME:-homelab-dashboard}"
LXC_TEMPLATE="${LXC_TEMPLATE:-ubuntu-24.04-standard}"
LXC_STORAGE="${LXC_STORAGE:-local}"
LXC_CPU="${LXC_CPU:-2}"
LXC_MEMORY="${LXC_MEMORY:-512}"
LXC_DISK="${LXC_DISK:-4}"
LXC_NETWORK="${LXC_NETWORK:-vmbr0}"
LXC_IP="${LXC_IP:-192.168.1.201/24}"
LXC_GATEWAY="${LXC_GATEWAY:-192.168.1.1}"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/ArthurGoins-code/homelab-dashboard}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
COLLECTOR_LXC_ID="${COLLECTOR_LXC_ID:-100}"

# ─── Get available storage from Proxmox ───
get_available_storage() {
    local storage="$1"
    if [ -n "$storage" ]; then
        if pvesm status | grep -q "^${storage} "; then
            echo "$storage"
            return 0
        fi
    fi
    local storages=("local" "local-lvm" "SMB" "nfs" "ceph")
    for s in "${storages[@]}"; do
        if pvesm status 2>/dev/null | grep -q "^${s} "; then
            echo "$s"
            return 0
        fi
    done
    local first_storage
    first_storage=$(pvesm status 2>/dev/null | grep -v "type\|storage" | head -n 1 | awk '{print $1}')
    if [ -n "$first_storage" ]; then
        echo "$first_storage"
        return 0
    fi
    echo "local"
}

# ─── Download template using pveam ───
download_template_via_pveam() {
    local template_name="$1"
    local storage="$2"
    echo "  Downloading template via pveam..."
    pveam download "$storage" "$template_name" 2>&1 | tail -n 1
    if [ -f "/var/lib/vz/template/cache/${template_name}" ]; then
        local fsize
        fsize=$(stat -c%s "/var/lib/vz/template/cache/${template_name}" 2>/dev/null || echo "0")
        echo "  Downloaded: /var/lib/vz/template/cache/${template_name} ($fsize bytes)"
        return 0
    fi
    return 1
}

# ─── Resolve template name to template path ───
resolve_template() {
    local template_name="$1"
    local storage="$2"
    local TEMPLATE_PATH=""
    local TEMPLATE_FILE=""

    # Check if template is a .tar.zst/.tar.gz file that exists on disk
    local template_dirs=(
        "/var/lib/vz/template/cache"
        "/var/lib/vz/template/vztmpl"
        "/var/lib/vz/template"
    )

    # Also check SMB storage
    if [ -d "/mnt/pve/SMB/template" ]; then
        template_dirs+=("/mnt/pve/SMB/template")
    fi

    for dir in "${template_dirs[@]}"; do
        # Try exact name
        if [ -f "${dir}/${template_name}" ]; then
            TEMPLATE_FILE="${dir}/${template_name}"
            break
        fi
        # Try with .tar.zst extension
        if [ -f "${dir}/${template_name}.tar.zst" ]; then
            TEMPLATE_FILE="${dir}/${template_name}.tar.zst"
            break
        fi
        # Try with .tar.gz extension
        if [ -f "${dir}/${template_name}.tar.gz" ]; then
            TEMPLATE_FILE="${dir}/${template_name}.tar.gz"
            break
        fi
        # Try pattern match (e.g., ubuntu-24.04-standard -> ubuntu-24.04-standard-*.tar.zst)
        local found
        found=$(find "$dir" -maxdepth 1 -name "${template_name}*" \( -name "*.tar.zst" -o -name "*.tar.gz" \) -type f 2>/dev/null | head -n 1)
        if [ -n "$found" ]; then
            TEMPLATE_FILE="$found"
            break
        fi
    done

    if [ -n "$TEMPLATE_FILE" ]; then
        local tname
        tname=$(basename "$TEMPLATE_FILE")
        local tpl_size
        tpl_size=$(stat -c%s "$TEMPLATE_FILE" 2>/dev/null || echo "0")
        echo "  Found template: $TEMPLATE_FILE ($tpl_size bytes)" >&2

        # Determine TEMPLATE_PATH based on storage and file location
        case "$TEMPLATE_FILE" in
            /var/lib/vz/*)
                TEMPLATE_PATH="local:vztmpl/${tname}"
                ;;
            /mnt/pve/*)
                local tmpl_storage
                tmpl_storage=$(echo "$TEMPLATE_FILE" | cut -d'/' -f 4)
                TEMPLATE_PATH="${tmpl_storage}:vztmpl/${tname}"
                ;;
            *)
                TEMPLATE_PATH="${storage}:vztmpl/${tname}"
                ;;
        esac
    else
        # No template file found - use pveam download
        echo "  No existing template found. Using pveam to resolve..." >&2
        TEMPLATE_PATH="${storage}:${template_name}"
    fi

    echo "$TEMPLATE_PATH"
}

# Resolve storage if needed
LXC_STORAGE=$(get_available_storage "$LXC_STORAGE")

# Resolve template path
echo "Resolving template..."
TEMPLATE_PATH=$(resolve_template "$LXC_TEMPLATE" "$LXC_STORAGE")
echo "  Template path: $TEMPLATE_PATH"

echo "=========================================="
echo "  Homelab Dashboard - LXC Setup"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  LXC ID:         $LXC_ID"
echo "  LXC Name:       $LXC_NAME"
echo "  Template:       $LXC_TEMPLATE"
echo "  Storage:        $LXC_STORAGE"
echo "  CPU Cores:      $LXC_CPU"
echo "  Memory:         $LXC_MEMORY MB"
echo "  Disk Size:      $LXC_DISK GB"
echo "  Network:        $LXC_NETWORK"
echo "  IP Address:     $LXC_IP"
echo "  Gateway:        $LXC_GATEWAY"
echo "  GitHub Repo:    $GITHUB_REPO"
echo "  GitHub Branch:  $GITHUB_BRANCH"
echo "  Collector LXC:  $COLLECTOR_LXC_ID"
echo ""

# Check if LXC already exists
echo "Checking for existing LXC..."
if pct status "$LXC_ID" 2>/dev/null; then
    echo "WARNING: LXC container $LXC_ID already exists!"
    read -p "Do you want to destroy it and recreate? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
    pct stop "$LXC_ID" 2>/dev/null || true
    pct destroy "$LXC_ID"
    echo "Existing container destroyed."
fi

# Create the LXC container (non-privileged)
echo ""
echo "Creating LXC container..."

# Convert uname architecture to Proxmox format (x86_64 -> amd64)
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
esac

pct create "$LXC_ID" \
    "$TEMPLATE_PATH" \
    -storage "$LXC_STORAGE" \
    -arch "$ARCH" \
    -cores "$LXC_CPU" \
    -memory "$LXC_MEMORY" \
    -swap 256 \
    -rootfs "${LXC_STORAGE}:${LXC_DISK}" \
    -net0 "name=eth0,bridge=$LXC_NETWORK,ip=$LXC_IP,gw=$LXC_GATEWAY" \
    -hostname "$LXC_NAME" \
    -unprivileged 1

echo "Container created."

# Start the container
echo ""
echo "Starting container..."
pct start "$LXC_ID"

# Wait for container to boot
echo "Waiting for container to boot..."
sleep 5

# Get container info
CONTAINER_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
echo "Container IP: $CONTAINER_IP"

# Install dependencies inside the container
echo ""
echo "Installing dependencies..."
pct exec "$LXC_ID" -- sh -c '
    apt-get update && apt-get install -y \
        git \
        curl \
        wget \
        python3 \
        python3-pip \
        python3-venv \
        nginx \
        nginx-extras \
        sqlite3 \
        procps \
        net-tools \
        iputils-ping \
        ca-certificates \
        curl \
        gnupg \
        && rm -rf /var/lib/apt/lists/*
'

echo "System dependencies installed."

# Clone the repository
echo ""
echo "Cloning repository from $GITHUB_REPO..."
pct exec "$LXC_ID" -- sh -c "
    cd /opt && \
    git clone $GITHUB_REPO homelab-dashboard 2>/dev/null || true
"

echo "Repository cloned."

# Setup Python backend
echo ""
echo "Setting up Python backend..."
pct exec "$LXC_ID" -- sh -c '
    cd /opt/homelab-dashboard/backend && \
    python3 -m venv venv && \
    source venv/bin/activate && \
    pip install --upgrade pip && \
    pip install -r requirements.txt
'

echo "Python backend configured."

# Setup Node.js frontend
echo ""
echo "Setting up Node.js frontend..."
pct exec "$LXC_ID" -- sh -c '
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    cd /opt/homelab-dashboard/frontend && \
    npm install
'

echo "Node.js frontend configured."

# Build the frontend
echo ""
echo "Building frontend..."
pct exec "$LXC_ID" -- sh -c '
    cd /opt/homelab-dashboard/frontend && \
    npm run build
'

echo "Frontend built."

# Configure Nginx
echo ""
echo "Configuring Nginx..."
pct exec "$LXC_ID" -- sh -c '
    # Copy the custom nginx config
    cp /opt/homelab-dashboard/frontend/nginx.conf /etc/nginx/conf.d/default.conf && \
    
    # Enable nginx modules
    ln -sf /etc/nginx/modules-enabled/* /etc/nginx/modules/ 2>/dev/null || true
    
    # Test nginx config
    nginx -t
'

echo "Nginx configured."

# Create systemd service for the dashboard
echo ""
echo "Creating systemd service..."
pct exec "$LXC_ID" -- sh -c '
    cat > /etc/systemd/system/homelab-dashboard.service << EOF
[Unit]
Description=Homelab Dashboard (Backend + Frontend)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/homelab-dashboard
Environment=PATH=/opt/homelab-dashboard/backend/venv/bin:/usr/bin:/bin
ExecStart=/opt/homelab-dashboard/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/homelab-frontend.service << EOF
[Unit]
Description=Homelab Frontend Builder
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=/opt/homelab-dashboard/frontend
ExecStart=/usr/bin/npm run build
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
'

# Enable and start services
echo ""
echo "Enabling services..."
pct exec "$LXC_ID" -- systemctl enable homelab-dashboard.service
pct exec "$LXC_ID" -- systemctl enable homelab-frontend.service
pct exec "$LXC_ID" -- systemctl start homelab-dashboard.service
pct exec "$LXC_ID" -- systemctl start homelab-frontend.service

# Update backend .env with collector info
echo ""
echo "Configuring backend environment..."
pct exec "$LXC_ID" -- sh -c "
    BACKEND_URL=\$(hostname -f)
    
    # Create .env file if it doesn't exist
    if [ ! -f /opt/homelab-dashboard/backend/.env ]; then
        cat > /opt/homelab-dashboard/backend/.env << ENVEOF
# Proxmox Configuration
PROXMOX_HOSTS=primary,secondary,ollama-node
PROXMOX_PRIMARY_HOST=\${BACKEND_URL}
PROXMOX_PRIMARY_PORT=8006
PROXMOX_PRIMARY_USER=root@pam
PROXMOX_PRIMARY_PASSWORD=your_password
PROXMOX_SECONDARY_HOST=
PROXMOX_SECONDARY_PORT=8006
PROXMOX_SECONDARY_USER=root@pam
PROXMOX_SECONDARY_PASSWORD=
PROXMOX_OLLAMA_HOST=
PROXMOX_OLLAMA_PORT=8006
PROXMOX_OLLAMA_USER=root@pam
PROXMOX_OLLAMA_PASSWORD=
PROXMOX_VERIFY_SSL=true

# Dashboard Settings
DASHBOARD_PORT=8000
REFRESH_INTERVAL=30
BACKEND_URL=http://\${BACKEND_URL}:8000
COLLECTOR_LXC_ID=$COLLECTOR_LXC_ID
ENVEOF
    fi
"

echo ""
echo "=========================================="
echo "  Dashboard LXC Setup Complete!"
echo "=========================================="
echo ""
echo "  Container ID:    $LXC_ID"
echo "  Container Name:  $LXC_NAME"
echo "  IP Address:      $LXC_IP"
echo "  Dashboard URL:   http://$LXC_IP"
echo "  Backend API:     http://$LXC_IP:8000"
echo "  API Docs:        http://$LXC_IP:8000/docs"
echo ""
echo "  Management commands:"
echo "    pct start $LXC_ID"
echo "    pct stop $LXC_ID"
echo "    pct console $LXC_ID"
echo "    pct exec $LXC_ID -- bash"
echo ""
echo "  View logs:"
echo "    journalctl -u homelab-dashboard.service -f"
echo "    journalctl -u homelab-frontend.service -f"
echo ""
echo "  Update code:"
echo "    pct exec $LXC_ID -- bash -c 'cd /opt/homelab-dashboard && git pull'"
echo "    pct exec $LXC_ID -- systemctl restart homelab-dashboard"
echo ""