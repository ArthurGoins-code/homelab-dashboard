#!/bin/bash
#
# Homelab Dashboard - One-Line Setup
# Pulls code from GitHub and runs both collector + dashboard LXC containers
#

set -e

echo "=========================================="
echo "  Homelab Dashboard - Full Setup"
echo "=========================================="
echo ""

# Pull latest code
echo "Pulling latest code from GitHub..."
cd "$(dirname "$0")/.."
git pull origin main 2>/dev/null || git clone https://github.com/ArthurGoins-code/homelab-dashboard.git /tmp/homelab-dashboard && cd /tmp/homelab-dashboard

# Deploy Resource Collector (privileged)
echo ""
echo "Deploying Resource Collector LXC..."
chmod +x lxc/setup-lxc.sh
cd lxc && ./setup-lxc.sh && cd ..

# Deploy Dashboard (non-privileged)
echo ""
echo "Deploying Dashboard LXC..."
chmod +x lxc/setup-dashboard.sh
cd lxc && ./setup-dashboard.sh && cd ..

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo "  Collector:   http://192.168.1.200 (LXC 100)"
echo "  Dashboard:   http://192.168.1.201 (LXC 101)"
echo "=========================================="