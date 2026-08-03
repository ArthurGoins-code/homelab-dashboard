"""FastAPI backend for the Homelab Dashboard."""

import os
import json
import time
import asyncio
import httpx
from datetime import datetime, timezone
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from .models import (
    ServiceConfig,
    ServiceStatus,
    ProxmoxNode,
    VirtualMachine,
    DashboardData,
)
from .api.proxmox import ProxmoxClient


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

PROXMOX_URL = os.getenv("PROXMOX_URL", "https://192.168.1.1:8006")
PROXMOX_USER = os.getenv("PROXMOX_USER", "root@pam")
PROXMOX_PASSWORD = os.getenv("PROXMOX_PASSWORD", "")
PROXMOX_TOKEN_ID = os.getenv("PROXMOX_TOKEN_ID")
PROXMOX_TOKEN_SECRET = os.getenv("PROXMOX_TOKEN_SECRET")

SERVICE_CONFIG_PATH = os.getenv(
    "SERVICE_CONFIG_PATH",
    os.path.join(os.path.dirname(__file__), "..", "config", "services.json"),
)

HEALTH_CHECK_INTERVAL = int(os.getenv("HEALTH_CHECK_INTERVAL", "30"))


# ---------------------------------------------------------------------------
# Service config helpers
# ---------------------------------------------------------------------------

def load_services() -> list[ServiceConfig]:
    """Load service configurations from JSON file."""
    try:
        with open(SERVICE_CONFIG_PATH) as f:
            data = json.load(f)
        return [ServiceConfig(**s) for s in data.get("services", [])]
    except FileNotFoundError:
        # Return defaults if file not found
        return _default_services()


def save_services(services: list[ServiceConfig]) -> None:
    """Save service configurations to JSON file."""
    os.makedirs(os.path.dirname(SERVICE_CONFIG_PATH), exist_ok=True)
    with open(SERVICE_CONFIG_PATH, "w") as f:
        json.dump({"services": [s.model_dump() for s in services]}, f, indent=2)


def _default_services() -> list[ServiceConfig]:
    """Default service list."""
    return [
        ServiceConfig(name="Portainer", url="http://192.168.1.10:9000", icon="docker", category="Infrastructure"),
        ServiceConfig(name="Grafana", url="http://192.168.1.10:3000", icon="grafana", category="Monitoring", health_check={"enabled": True, "interval": 60}),
        ServiceConfig(name="Prometheus", url="http://192.168.1.10:9090", icon="prometheus", category="Monitoring", health_check={"enabled": True, "interval": 30}),
        ServiceConfig(name="Nextcloud", url="http://192.168.1.11/", icon="cloud", category="Productivity"),
        ServiceConfig(name="Pi-hole", url="http://192.168.1.12/admin", icon="shield", category="Networking"),
        ServiceConfig(name="TrueNAS", url="http://192.168.1.13", icon="database", category="Storage"),
    ]


# ---------------------------------------------------------------------------
# Health check worker
# ---------------------------------------------------------------------------

async def check_service_health(service: ServiceConfig) -> ServiceStatus:
    """Check the health of a single service."""
    health_url = service.health_check.get("url") if service.health_check else None
    check_url = health_url or service.url

    status = ServiceStatus(**service.model_dump())

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            start = time.time()
            response = await client.get(check_url)
            status.response_time = round((time.time() - start) * 1000, 1)
            status.online = response.status_code < 500
    except Exception:
        status.online = False
        status.response_time = None

    status.last_checked = datetime.now(timezone.utc).isoformat()
    return status


async def health_check_worker(services: list[ServiceConfig]) -> list[ServiceStatus]:
    """Periodically check health of all services."""
    while True:
        tasks = [check_service_health(s) for s in services if s.enabled]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        # Update the global _services with new status information
        # Note: This is a simplified approach - in a real app we might want to store 
        # status separately or use a more sophisticated caching mechanism
        await asyncio.sleep(HEALTH_CHECK_INTERVAL)


# ---------------------------------------------------------------------------
# Application lifecycle
# ---------------------------------------------------------------------------

# Initialize global state
_services: list[ServiceConfig] = load_services()
_proxmox_client = ProxmoxClient(
    url=PROXMOX_URL,
    user=PROXMOX_USER,
    password=PROXMOX_PASSWORD,
    token_id=PROXMOX_TOKEN_ID,
    token_secret=PROXMOX_TOKEN_SECRET,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start background tasks."""
    task = asyncio.create_task(health_check_worker(_services))
    yield
    task.cancel()


app = FastAPI(title="Homelab Dashboard", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# API schemas
# ---------------------------------------------------------------------------

class ServiceUpdate(BaseModel):
    """Schema for updating a service."""
    name: str
    url: str
    icon: str = "link"
    category: str = "General"
    enabled: bool = True
    health_check: Optional[dict] = None


class ProxmoxConfig(BaseModel):
    """Proxmox connection config."""
    url: str
    user: str
    password: str = ""
    token_id: Optional[str] = None
    token_secret: Optional[str] = None


# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------

@app.get("/api/services")
async def get_services() -> list[ServiceStatus]:
    """Get all services with their current health status."""
    return await get_services_status()


@app.get("/api/services/status")
async def get_services_status() -> list[ServiceStatus]:
    """Get all services with their current health status."""
    tasks = [check_service_health(s) for s in _services]
    return await asyncio.gather(*tasks)


@app.post("/api/services")
async def add_service(service: ServiceUpdate) -> ServiceConfig:
    """Add a new service."""
    new_service = ServiceConfig(
        name=service.name,
        url=service.url,
        icon=service.icon,
        category=service.category,
        enabled=service.enabled,
        health_check=service.health_check,
    )
    _services.append(new_service)
    save_services(_services)
    return new_service


@app.put("/api/services/{name}")
async def update_service(name: str, service: ServiceUpdate) -> ServiceConfig:
    """Update an existing service."""
    for i, s in enumerate(_services):
        if s.name.lower() == name.lower():
            _services[i] = ServiceConfig(
                name=service.name,
                url=service.url,
                icon=service.icon,
                category=service.category,
                enabled=service.enabled,
                health_check=service.health_check,
            )
            save_services(_services)
            return _services[i]
    raise HTTPException(status_code=404, detail=f"Service '{name}' not found")


@app.delete("/api/services/{name}")
async def delete_service(name: str) -> dict:
    """Delete a service."""
    for i, s in enumerate(_services):
        if s.name.lower() == name.lower():
            _services.pop(i)
            save_services(_services)
            return {"message": f"Service '{name}' deleted"}
    raise HTTPException(status_code=404, detail=f"Service '{name}' not found")


@app.get("/api/proxmox/nodes")
async def get_proxmox_nodes() -> list[ProxmoxNode]:
    """Get all Proxmox nodes."""
    return await _proxmox_client.get_nodes()


@app.get("/api/proxmox/vms")
async def get_proxmox_vms() -> list[VirtualMachine]:
    """Get all VMs and LXC containers."""
    return await _proxmox_client.get_vms()


@app.get("/api/proxmox/nodes/{node}/vms")
async def get_node_vms(node: str) -> list[VirtualMachine]:
    """Get VMs and LXCs for a specific node."""
    vms = await _proxmox_client.get_vms(node)
    return vms


@app.get("/api/dashboard")
async def get_dashboard() -> DashboardData:
    """Get complete dashboard state."""
    services_status = await get_services_status()
    nodes = await get_proxmox_nodes()
    vms = await get_proxmox_vms()

    return DashboardData(
        services=services_status,
        nodes=nodes,
        virtual_machines=vms,
        last_updated=datetime.now(timezone.utc).isoformat(),
    )


@app.post("/api/proxmox/config")
async def update_proxmox_config(config: ProxmoxConfig) -> dict:
    """Update Proxmox connection configuration."""
    global _proxmox_client
    _proxmox_client = ProxmoxClient(
        url=config.url,
        user=config.user,
        password=config.password,
        token_id=config.token_id,
        token_secret=config.token_secret,
    )
    return {"message": "Proxmox configuration updated"}


# ---------------------------------------------------------------------------
# Dev mode
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)