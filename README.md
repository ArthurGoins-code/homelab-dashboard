# Homelab Dashboard

A sleek, modern dashboard for monitoring and managing your homelab services and Proxmox infrastructure.

## Features

- **Service Monitoring**: Real-time health checks for all your services with visual status indicators
- **Proxmox Integration**: Monitor node resource usage (CPU, RAM, Disk) in real-time
- **VM/Container Management**: View all VMs and LXC containers across your Proxmox cluster
- **Dark/Light Mode**: Automatically detected or manually toggled
- **Responsive Design**: Works on desktop, tablet, and mobile
- **Docker Deployment**: Easy deployment with docker-compose

## Project Structure

```
homelab-dashboard/
├── backend/                    # FastAPI backend
│   ├── api/
│   │   ├── proxmox.py         # Proxmox API client
│   │   └── __init__.py
│   ├── main.py                # FastAPI application
│   ├── models.py              # Pydantic models
│   ├── requirements.txt       # Python dependencies
│   ├── Dockerfile             # Backend Docker image
│   └── .env                   # Environment configuration
├── frontend/                   # React + TypeScript frontend
│   ├── src/
│   │   ├── components/
│   │   │   ├── ServiceCard.tsx
│   │   │   ├── ServiceGrid.tsx
│   │   │   ├── NodeCard.tsx
│   │   │   └── VmList.tsx
│   │   ├── hooks/
│   │   │   ├── useServices.ts
│   │   │   └── useProxmox.ts
│   │   ├── types/
│   │   │   └── index.ts
│   │   ├── config/
│   │   │   └── services.json
│   │   ├── App.tsx
│   │   ├── main.tsx
│   │   └── index.css
│   ├── nginx.conf             # Nginx configuration
│   ├── index.html
│   ├── package.json
│   ├── vite.config.ts
│   ├── tailwind.config.js
│   └── tsconfig.json
├── docker-compose.yml          # Docker orchestration
└── README.md
```

## Services (Pre-configured)

The dashboard comes with these services pre-configured. Edit `frontend/src/config/services.json` to customize:

| Service | URL | Category |
|---------|-----|----------|
| Mealie | http://mealie.local:8080 | Productivity |
| AdGuard DNS | http://adguard.local:3000 | Networking |
| Nginx Proxy Manager | http://npm.local:81 | Networking |
| Home Assistant | http://hass.local:8123 | Productivity |
| Ubuntu VM | http://ubuntu.local:3000 | Infrastructure |
| Ollama | http://ollama.local:11434 | AI |
| Grafana | http://grafana.local:3000 | Monitoring |
| Prometheus | http://prometheus.local:9090 | Monitoring |
| Sonarr | http://sonarr.local:8989 | Media |
| Radarr | http://radarr.local:7878 | Media |
| Plex | http://plex.local:32400 | Media |
| Cloudflare Tunnel | https://tunnel.cloudflare.com | Networking |
| Database | http://db.local:5432 | Infrastructure |
| Eye of Provision | http://eye.local:8080 | Monitoring |

## Proxmox Integration

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Homelab Dashboard                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │   Frontend   │    │   Backend API    │    │  Services  │ │
│  │  (React)     │◄──►│   (FastAPI)      │    │  (External)│ │
│  │  :80/:443    │    │   :8000          │    │            │ │
│  └─────────────┘    └────────┬─────────┘    └────────────┘ │
│                               │                              │
│                       ┌───────▼────────┐                    │
│                       │  Proxmox API   │                    │
│                       │   Client       │                    │
│                       └───────┬────────┘                    │
├───────────────────────────────┼─────────────────────────────┤
│                         Proxmox Cluster                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │  Primary  │  │Secondary │  │ Ollama   │                  │
│  │  (Node)   │  │  (Node)  │  │  (Node)  │                  │
│  │          │  │          │  │          │                    │
│  │  ┌─────┐ │  │  ┌─────┐ │  │  ┌─────┐ │                  │
│  │  │ LXC │ │  │  │ LXC │ │  │  │ VM  │ │                  │
│  │  └─────┘ │  │  └─────┘ │  │  └─────┘ │                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Resource Collection

Resource data is collected via multiple methods:

1. **Proxmox API** - Direct API calls to Proxmox nodes for VM/container metadata
2. **Privileged LXC Container** - A dedicated LXC container with access to host metrics via mounted `/proc` and `/sys`
3. **psutil** - Python library for cross-platform system monitoring

### LXC Resource Collector

The resource collector runs as a **privileged LXC container** directly on your Proxmox host. This provides:

- **Native host access** - Direct access to `/proc`, `/sys`, and `/dev` for accurate metrics
- **Low overhead** - No Docker runtime layer, runs as a native Proxmox container
- **Automatic startup** - Configured as a systemd service that starts with the container
- **Per-node deployment** - Deploy one collector per Proxmox node to monitor all VMs/LXCs on that host

### Deploying the LXC Collector

**Option 1: Automated Setup (Recommended)**

```bash
# From the project root, run the setup script on your Proxmox host
chmod +x lxc/setup-lxc.sh
./lxc/setup-lxc.sh

# Custom configuration
LXC_ID=200 LXC_CPU=2 LXC_MEMORY=512 BACKEND_URL=http://192.168.1.100:8000 ./lxc/setup-lxc.sh
```

**Option 2: Manual LXC Creation**

```bash
# Create a privileged LXC container
pct create 100 \
  ubuntu-24.04-standard \
  -storage local \
  -cpus 1 \
  -memory 256 \
  -swap 256 \
  -disk 2 \
  -net0 "name=eth0,ip=192.168.1.200/24,gateway=192.168.1.1,bridge=vmbr0" \
  -hostname homelab-collector \
  -rootfs local:2 \
  -features key=ctl,nesting=1 \
  --privileged 1

# Configure host mounts
pct set 100 \
  -mount "host-proc=local:/proc:bind" \
  -mount "host-sys=local:/sys:bind" \
  -mount "host-dev=local:/dev:bind"

# Start and install dependencies
pct start 100
pct exec 100 -- sh -c "apt-get update && apt-get install -y python3 python3-pip curl procps"
pct exec 100 -- pip3 install psutil requests

# Copy collector script and create systemd service
scp lxc/collector.sh root@192.168.1.200:/usr/local/bin/collector.sh
pct exec 100 -- sh -c "systemctl enable --now homelab-collector.service"
```

**Option 3: Docker (Alternative)**

```bash
# Run as a Docker container on the Proxmox host
docker run -d \
  --name homelab-collector \
  --privileged \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -e BACKEND_URL=http://192.168.1.100:8000 \
  homelab-collector:latest
```

## Setup & Installation

### Prerequisites

- Docker & Docker Compose
- Access to your Proxmox cluster (for node monitoring)
- Network access to all services

### Quick Start

1. **Clone the repository**
   ```bash
   cd homelab-dashboard
   ```

2. **Configure environment**
   ```bash
   cp backend/.env.example backend/.env
   # Edit backend/.env with your Proxmox credentials
   ```

3. **Start the services**
   ```bash
   docker-compose up -d
   ```

4. **Access the dashboard**
   - Frontend: http://localhost
   - Backend API: http://localhost:8000
   - API Docs: http://localhost:8000/docs

### Development Setup

```bash
# Backend
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000

# Frontend
cd frontend
npm install
npm run dev
```

## Configuration

### Backend Configuration (`backend/.env`)

```env
# Proxmox nodes
PROXMOX_HOSTS=primary,secondary,ollama-node
PROXMOX_PRIMARY_HOST=192.168.1.100
PROXMOX_PRIMARY_PORT=8006
PROXMOX_PRIMARY_USER=root@pam
PROXMOX_PRIMARY_PASSWORD=your_password

# Dashboard settings
DASHBOARD_PORT=8000
REFRESH_INTERVAL=30
```

### Services Configuration (`frontend/src/config/services.json`)

```json
{
  "name": "Service Name",
  "url": "http://service.local:port",
  "icon": "icon-name",
  "category": "Category"
}
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/services` | List all services with health status |
| GET | `/api/services/{name}` | Get specific service status |
| GET | `/api/nodes` | List all Proxmox nodes with resource usage |
| GET | `/api/vms` | List all VMs and containers |
| GET | `/api/resource/{node}` | Get detailed resource metrics for a node |
| POST | `/api/resource/collect` | Receive resource metrics from collector |
| GET | `/api/health` | Health check endpoint |

## Customization

### Adding New Services

Edit `frontend/src/config/services.json` and add your service:

```json
{
  "name": "Your Service",
  "url": "http://your-service.local:port",
  "icon": "globe",
  "category": "Custom"
}
```

### Custom Icons

Supported icon categories: `globe`, `docker`, `database`, `monitor`, `cpu`, `cloud`, `home`, `shield`, `book-open`, `grafana`, `prometheus`, `eye`

## Troubleshooting

### Services showing as offline

- Verify the service URLs in `services.json`
- Check that the backend can reach the services
- Ensure DNS resolution is working

### Proxmox nodes not connecting

- Verify `PROXMOX_*_HOST` and `PROXMOX_*_PASSWORD` in `.env`
- Check SSL certificate settings (`PROXMOX_*_VERIFY_SSL`)
- Test the Proxmox API directly: `curl https://<host>:8006/api2/json/nodes`

### Resource metrics not updating

- Check the `proxmox-collector` container logs: `docker logs homelab-collector`
- Verify the collector can reach the backend: `http://backend:8000/api/resource/collect`

## License

MIT