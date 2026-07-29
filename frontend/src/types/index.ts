/** Service configuration from the backend */
export interface ServiceConfig {
  name: string;
  url: string;
  icon: string;
  category: string;
  enabled: boolean;
  health_check?: {
    enabled?: boolean;
    interval?: number;
    url?: string;
  };
}

/** Service with live health status */
export interface ServiceStatus extends ServiceConfig {
  online: boolean;
  response_time?: number;
  last_checked?: string;
}

/** Proxmox node resource data */
export interface ProxmoxNode {
  name: string;
  status: string;
  cpu: number;
  memory_total: number;
  memory_used: number;
  memory_free: number;
  memory_percent: number;
  disk_total: number;
  disk_used: number;
  disk_percent: number;
  uptime: number;
  load_1: number;
  load_5: number;
  load_15: number;
  cpu_info?: Record<string, unknown>;
}

/** VM or LXC container info */
export interface VirtualMachine {
  name: string;
  vm_id: number;
  type: 'qemu' | 'lxc';
  status: 'running' | 'stopped' | 'paused';
  cpu: number;
  memory_total: number;
  memory_used: number;
  memory_percent: number;
  disk: number;
  node: string;
  uptime: number;
}

/** Complete dashboard state from backend */
export interface DashboardData {
  services: ServiceStatus[];
  nodes: ProxmoxNode[];
  virtual_machines: VirtualMachine[];
  last_updated?: string;
}

/** UI state for the dashboard */
export interface DashboardState {
  darkMode: boolean;
  selectedCategory: string | null;
  selectedNode: string | null;
  refreshInterval: number;
}

/** Service icon mappings */
export const SERVICE_ICONS: Record<string, string> = {
  Portainer: 'docker',
  Grafana: 'activity',
  Prometheus: 'activity',
  Nextcloud: 'cloud',
  'Pi-hole': 'shield',
  TrueNAS: 'database',
  Mealie: 'book-open',
  AdGuard: 'eye',
  'Nginx Proxy Manager': 'globe',
  HomeAssistant: 'home',
  Ollama: 'cpu',
  Ubuntu: 'monitor',
  default: 'link',
};

/** Category color mappings */
export const CATEGORY_COLORS: Record<string, string> = {
  Infrastructure: 'from-blue-500 to-cyan-500',
  Monitoring: 'from-purple-500 to-pink-500',
  Productivity: 'from-green-500 to-emerald-500',
  Networking: 'from-orange-500 to-yellow-500',
  Storage: 'from-indigo-500 to-blue-500',
  AI: 'from-fuchsia-500 to-purple-500',
  default: 'from-gray-500 to-slate-500',
};

/** Format bytes to human-readable */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

/** Format uptime seconds to human-readable */
export function formatUptime(seconds: number): string {
  if (seconds === 0) return 'N/A';
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

/** Format CPU percentage */
export function formatCPU(cpu: number): string {
  return `${cpu.toFixed(1)}%`;
}