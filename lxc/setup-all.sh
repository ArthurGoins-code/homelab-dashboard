#!/bin/bash
#
# Homelab Dashboard - Full Setup
# Runs both collector + dashboard LXC containers
#

set -e

# Resolve script directory regardless of where it's called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  Homelab Dashboard - Full Setup"
echo "=========================================="
echo ""

# Ensure scripts are executable
echo "Ensuring scripts are executable..."
chmod +x "$SCRIPT_DIR/setup-lxc.sh"
chmod +x "$SCRIPT_DIR/setup-dashboard.sh"

# Deploy Resource Collector (privileged)
echo ""
echo "Deploying Resource Collector LXC..."
( cd "$SCRIPT_DIR" && ./setup-lxc.sh )

# Deploy Dashboard (non-privileged)
echo ""
echo "Deploying Dashboard LXC..."
( cd "$SCRIPT_DIR" && ./setup-dashboard.sh )

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo "  Collector:   http://192.168.1.200 (LXC 100)"
echo "  Dashboard:   http://192.168.1.201 (LXC 101)"
echo "=========================================="