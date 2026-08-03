"""Proxmox API client for fetching node and VM/LXC data."""

import httpx
from typing import Optional
from ..models import ProxmoxNode, VirtualMachine


class ProxmoxClient:
    """Client for interacting with Proxmox API."""

    def __init__(self, url: str, user: str, password: str, token_id: Optional[str] = None, token_secret: Optional[str] = None):
        self.url = url.rstrip("/")
        self.user = user
        self.password = password
        self.token_id = token_id
        self.token_secret = token_secret
        self._ticket_token: Optional[str] = None
        self._ticket_expiry: float = 0

    async def get_ticket(self) -> str:
        """Get or refresh the Proxmox API ticket."""
        import time
        if self.token_secret:
            return f"{self.token_id}@{self.token_secret}"

        if self._ticket_token and time.time() < self._ticket_expiry:
            return self._ticket_token

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.url}/api2/json/access/ticket",
                data={
                    "username": self.user,
                    "password": self.password,
                    "path": f"/api2/json/nodes",
                },
            )
            data = response.json()
            self._ticket_token = data["data"]["ticket"]
            self._ticket_expiry = time.time() + data["data"]["expire"] / 60
        return self._ticket_token

    async def _get(self, path: str) -> dict:
        """Make a GET request to the Proxmox API."""
        ticket = await self.get_ticket()
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.url}/api2/json/{path}",
                params={"ticket": ticket},
            )
            response.raise_for_status()
            return response.json()

    async def get_nodes(self) -> list[ProxmoxNode]:
        """Get all Proxmox nodes with resource data."""
        data = await self._get("nodes")
        nodes = []
        for node_data in data.get("data", []):
            status = node_data.get("status", "online")
            node = ProxmoxNode(
                name=node_data["node"],
                status=status,
                cpu=node_data.get("cpu", 0.0),
                memory_total=node_data.get("maxmem", 0),
                memory_used=node_data.get("mem", 0),
                memory_free=node_data.get("maxmem", 0) - node_data.get("mem", 0),
                memory_percent=round((node_data.get("mem", 0) / node_data.get("maxmem", 1)) * 100, 1) if node_data.get("maxmem", 0) > 0 else 0,
                disk_total=node_data.get("maxdisk", 0),
                disk_used=node_data.get("disk", 0),
                disk_percent=round((node_data.get("disk", 0) / node_data.get("maxdisk", 1)) * 100, 1) if node_data.get("maxdisk", 0) > 0 else 0,
                uptime=node_data.get("uptime", 0),
                load_1=node_data.get("load", 0),
                load_5=node_data.get("load", 0),
                load_15=node_data.get("load", 0),
            )
            nodes.append(node)
        return nodes

    async def get_vms(self, node: Optional[str] = None) -> list[VirtualMachine]:
        """Get all VMs and LXC containers."""
        vms = []

        # Get QEMU VMs
        if node:
            vm_data = await self._get(f"nodes/{node}/qemu")
        else:
            vm_data = await self._get("nodes/all/qemu")
            
        vm_list = vm_data.get("data", [])

        if not isinstance(vm_list, list):
            vm_list = [vm_list]

        for vm in vm_list:
            # Only include running VMs
            if vm.get("status", "stopped").lower() == "running":
                vms.append(VirtualMachine(
                    name=vm.get("name", f"VM-{vm.get('vmid', 'unknown')}"),
                    vm_id=vm.get("vmid", 0),
                    type="qemu",
                    status=vm.get("status", "stopped").lower(),
                    cpu=vm.get("cpu", 0.0),
                    memory_total=vm.get("maxmem", 0),
                    memory_used=vm.get("mem", 0),
                    memory_percent=round((vm.get("mem", 0) / vm.get("maxmem", 1)) * 100, 1) if vm.get("maxmem", 0) > 0 else 0,
                    disk=vm.get("disk", 0),
                    node=vm.get("node", node or ""),
                    uptime=vm.get("uptime", 0),
                ))

        # Get LXC containers
        if not node:
            lxc_data = await self._get("nodes/all/lxc")
            lxc_list = lxc_data.get("data", [])
            
            if not isinstance(lxc_list, list):
                lxc_list = [lxc_list]

            for lxc in lxc_list:
                # Only include running containers
                if lxc.get("status", "stopped").lower() == "running":
                    vms.append(VirtualMachine(
                        name=lxc.get("name", f"LXC-{lxc.get('vid', 'unknown')}"),
                        vm_id=lxc.get("vid", 0),
                        type="lxc",
                        status=lxc.get("status", "stopped").lower(),
                        cpu=lxc.get("cpu", 0.0),
                        memory_total=lxc.get("maxmem", 0),
                        memory_used=lxc.get("mem", 0),
                        memory_percent=round((lxc.get("mem", 0) / lxc.get("maxmem", 1)) * 100, 1) if lxc.get("maxmem", 0) > 0 else 0,
                        disk=lxc.get("disk", 0),
                        node=lxc.get("node", ""),
                        uptime=lxc.get("uptime", 0),
                    ))

        return vms

    async def get_node_vms(self, node: str) -> dict:
        """Get VMs and LXCs for a specific node."""
        qemus = await self.get_vms(node)
        return {"qemus": qemus}