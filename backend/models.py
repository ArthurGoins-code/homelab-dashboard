"""Pydantic models for the homelab dashboard."""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class ServiceConfig(BaseModel):
    """Configuration for a dashboard service."""
    name: str
    url: str
    icon: str = "link"
    category: str = "General"
    enabled: bool = True
    health_check: Optional[dict] = Field(default_factory=dict)


class ServiceStatus(ServiceConfig):
    """Service config with live status."""
    online: bool = False
    response_time: Optional[float] = None
    last_checked: Optional[str] = None


class ProxmoxNode(BaseModel):
    """Proxmox node information."""
    name: str
    status: str = "online"
    cpu: float = 0.0
    memory_total: float = 0.0
    memory_used: float = 0.0
    memory_free: float = 0.0
    memory_percent: float = 0.0
    disk_total: float = 0.0
    disk_used: float = 0.0
    disk_percent: float = 0.0
    uptime: float = 0.0
    load_1: float = 0.0
    load_5: float = 0.0
    load_15: float = 0.0
    cpu_info: Optional[dict] = None


class VirtualMachine(BaseModel):
    """VM or LXC container information."""
    name: str
    vm_id: int
    type: str = "qemu"  # qemu or lxc
    status: str = "stopped"  # running, stopped, paused
    cpu: float = 0.0
    memory_total: float = 0.0
    memory_used: float = 0.0
    memory_percent: float = 0.0
    disk: float = 0.0
    node: str = ""
    uptime: float = 0.0


class DashboardData(BaseModel):
    """Complete dashboard state."""
    services: list[ServiceStatus] = []
    nodes: list[ProxmoxNode] = []
    virtual_machines: list[VirtualMachine] = []
    last_updated: Optional[str] = None