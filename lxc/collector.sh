#!/bin/bash
#
# Proxmox Resource Collector - LXC Container Script
# This script runs inside a privileged LXC container to collect
# and report system resource metrics to the Homelab Dashboard backend
#

set -e

# Configuration
BACKEND_URL="${BACKEND_URL:-http://backend:8000}"
COLLECTOR_INTERVAL="${COLLECTOR_INTERVAL:-30}"
NODE_NAME="${NODE_NAME:-$(hostname)}"
LOG_FILE="/var/log/homelab-collector.log"

# Install dependencies if not present
install_dependencies() {
    echo "Installing dependencies..."
    apt-get update
    apt-get install -y curl procps python3 python3-pip
    pip3 install psutil requests
}

# Collect system metrics
collect_metrics() {
    python3 << 'PYTHON_SCRIPT'
import psutil
import requests
import time
import json
import socket
import os

BACKEND_URL = "${BACKEND_URL}"
COLLECTOR_INTERVAL = ${COLLECTOR_INTERVAL}
NODE_NAME = "${NODE_NAME}"

def get_metrics():
    """Collect system metrics using psutil."""
    metrics = {
        "node": NODE_NAME,
        "timestamp": time.time(),
        "cpu": {
            "percent": psutil.cpu_percent(interval=1),
            "cores_logical": psutil.cpu_count(),
            "cores_physical": psutil.cpu_count(logical=False),
            "freq_current": psutil.cpu_freq().current if psutil.cpu_freq() else 0,
            "freq_min": psutil.cpu_freq().min if psutil.cpu_freq() else 0,
            "freq_max": psutil.cpu_freq().max if psutil.cpu_freq() else 0,
            "per_cpu": psutil.cpu_percent(interval=0, percpu=True),
        },
        "memory": {
            "total": psutil.virtual_memory().total,
            "available": psutil.virtual_memory().available,
            "used": psutil.virtual_memory().used,
            "percent": psutil.virtual_memory().percent,
            "swap": {
                "total": psutil.swap_memory().total,
                "used": psutil.swap_memory().used,
                "percent": psutil.swap_memory().percent,
            }
        },
        "disk": {},
        "network": {
            "bytes_sent": psutil.net_io_counters().bytes_sent,
            "bytes_recv": psutil.net_io_counters().bytes_recv,
            "packets_sent": psutil.net_io_counters().packets_sent,
            "packets_recv": psutil.net_io_counters().packets_recv,
            "interfaces": {},
        },
        "uptime_seconds": time.time() - psutil.boot_time(),
        "load_avg": os.getloadavg(),
    }

    # Get disk usage for all partitions
    for partition in psutil.disk_partitions(all=False):
        try:
            usage = psutil.disk_usage(partition.mountpoint)
            metrics["disk"][partition.mountpoint] = {
                "total": usage.total,
                "used": usage.used,
                "free": usage.free,
                "percent": usage.percent,
            }
        except PermissionError:
            pass

    # Get network interface details
    net_counters = psutil.net_io_counters(pernic=True)
    for interface, counters in net_counters.items():
        metrics["network"]["interfaces"][interface] = {
            "bytes_sent": counters.bytes_sent,
            "bytes_recv": counters.bytes_recv,
            "packets_sent": counters.packets_sent,
            "packets_recv": counters.packets_recv,
        }

    # Get IP addresses
    metrics["ip_addresses"] = {}
    for interface, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if addr.family.__name__ == 'AF_INET':
                metrics["ip_addresses"][interface] = addr.address

    return metrics

def send_metrics(metrics):
    """Send metrics to the backend API."""
    try:
        response = requests.post(
            f"{BACKEND_URL}/api/resource/collect",
            json=metrics,
            timeout=10
        )
        if response.status_code == 200:
            print(f"Metrics sent successfully: CPU={metrics['cpu']['percent']}% RAM={metrics['memory']['percent']}%")
        else:
            print(f"Failed to send metrics: {response.status_code}")
    except requests.exceptions.RequestException as e:
        print(f"Error sending metrics: {e}")

def log_message(message):
    """Log message to both stdout and log file."""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{NODE_NAME}] {message}"
    print(log_line)
    with open("${LOG_FILE}", "a") as f:
        f.write(log_line + "\n")

def main():
    log_message("Resource collector started")
    log_message(f"Backend URL: {BACKEND_URL}")
    log_message(f"Collection interval: {COLLECTOR_INTERVAL}s")

    # Send initial metrics
    metrics = get_metrics()
    send_metrics(metrics)

    # Continuously collect and send metrics
    while True:
        time.sleep(COLLECTOR_INTERVAL)
        metrics = get_metrics()
        send_metrics(metrics)

if __name__ == "__main__":
    main()
PYTHON_SCRIPT
}

# Main execution
echo "=== Homelab Resource Collector (LXC) ==="
echo "Node: ${NODE_NAME}"
echo "Backend: ${BACKEND_URL}"
echo "Interval: ${COLLECTOR_INTERVAL}s"

# Install dependencies if needed
if ! command -v python3 &> /dev/null || ! pip3 list 2>/dev/null | grep -q psutil; then
    install_dependencies
fi

# Start collection
exec python3 << 'PYTHON_MAIN'
import psutil
import requests
import time
import json
import socket
import os
import signal
import sys

BACKEND_URL = "${BACKEND_URL}"
COLLECTOR_INTERVAL = ${COLLECTOR_INTERVAL}
NODE_NAME = "${NODE_NAME}"
LOG_FILE = "${LOG_FILE}"

running = True

def signal_handler(sig, frame):
    global running
    log_message("Received shutdown signal, stopping...")
    running = False

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def get_metrics():
    metrics = {
        "node": NODE_NAME,
        "timestamp": time.time(),
        "cpu": {
            "percent": psutil.cpu_percent(interval=1),
            "cores_logical": psutil.cpu_count(),
            "cores_physical": psutil.cpu_count(logical=False),
            "freq_current": psutil.cpu_freq().current if psutil.cpu_freq() else 0,
        },
        "memory": {
            "total": psutil.virtual_memory().total,
            "available": psutil.virtual_memory().available,
            "used": psutil.virtual_memory().used,
            "percent": psutil.virtual_memory().percent,
            "swap": {
                "total": psutil.swap_memory().total,
                "used": psutil.swap_memory().used,
                "percent": psutil.swap_memory().percent,
            }
        },
        "disk": {},
        "network": {
            "bytes_sent": psutil.net_io_counters().bytes_sent,
            "bytes_recv": psutil.net_io_counters().bytes_recv,
            "interfaces": {},
        },
        "uptime_seconds": time.time() - psutil.boot_time(),
        "load_avg": os.getloadavg(),
    }

    for partition in psutil.disk_partitions(all=False):
        try:
            usage = psutil.disk_usage(partition.mountpoint)
            metrics["disk"][partition.mountpoint] = {
                "total": usage.total,
                "used": usage.used,
                "free": usage.free,
                "percent": usage.percent,
            }
        except PermissionError:
            pass

    for interface, counters in psutil.net_io_counters(pernic=True).items():
        metrics["network"]["interfaces"][interface] = {
            "bytes_sent": counters.bytes_sent,
            "bytes_recv": counters.bytes_recv,
        }

    metrics["ip_addresses"] = {}
    for interface, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if addr.family.__name__ == 'AF_INET':
                metrics["ip_addresses"][interface] = addr.address

    return metrics

def send_metrics(metrics):
    try:
        response = requests.post(
            f"{BACKEND_URL}/api/resource/collect",
            json=metrics,
            timeout=10
        )
        if response.status_code == 200:
            print(f"OK: CPU={metrics['cpu']['percent']}% RAM={metrics['memory']['percent']}%")
        else:
            print(f"ERR: Status {response.status_code}")
    except Exception as e:
        print(f"ERR: {e}")

def log_message(message):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] [{NODE_NAME}] {message}"
    print(log_line)
    with open(LOG_FILE, "a") as f:
        f.write(log_line + "\n")

log_message("Resource collector started")
log_message(f"Backend URL: {BACKEND_URL}")
log_message(f"Collection interval: {COLLECTOR_INTERVAL}s")

metrics = get_metrics()
send_metrics(metrics)

while running:
    time.sleep(COLLECTOR_INTERVAL)
    metrics = get_metrics()
    send_metrics(metrics)
PYTHON_MAIN