import type { VirtualMachine, ProxmoxNode } from '@/types';
import { formatBytes, formatUptime, formatCPU } from '@/types';
import { Cpu, MemoryStick, HardDrive, Monitor, Box } from 'lucide-react';

interface Props {
  vms: VirtualMachine[];
  nodes: ProxmoxNode[];
}

function getStatusColor(status: string): string {
  switch (status) {
    case 'running':
      return 'text-green-500 bg-green-50 dark:bg-green-900/30';
    case 'stopped':
      return 'text-red-500 bg-red-50 dark:bg-red-900/30';
    case 'paused':
      return 'text-amber-500 bg-amber-50 dark:bg-amber-900/30';
    default:
      return 'text-gray-500 bg-gray-50 dark:bg-gray-800';
  }
}

function getTypeIcon(type: string) {
  return type === 'qemu' ? (
    <Monitor className="w-4 h-4" />
  ) : (
    <Box className="w-4 h-4" />
  );
}

function getProgressClass(percent: number): string {
  if (percent < 60) return 'low';
  if (percent < 85) return 'medium';
  return 'high';
}

export function VmList({ vms, nodes }: Props) {
  // Group VMs by node
  const vmsByNode = vms.reduce<Record<string, VirtualMachine[]>>((acc, vm) => {
    if (!acc[vm.node]) {
      acc[vm.node] = [];
    }
    acc[vm.node].push(vm);
    return acc;
  }, {});

  // Get node info for a node name
  const getNodeInfo = (nodeName: string) => {
    return nodes.find((n) => n.name === nodeName);
  };

  return (
    <div className="space-y-6">
      {/* Summary */}
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2 px-4 py-2 bg-green-50 dark:bg-green-900/30 rounded-lg">
          <div className="w-2 h-2 rounded-full bg-green-500" />
          <span className="text-sm font-medium text-green-700 dark:text-green-400">
            {vms.filter((v) => v.status === 'running').length} running
          </span>
        </div>
        <div className="flex items-center gap-2 px-4 py-2 bg-red-50 dark:bg-red-900/30 rounded-lg">
          <div className="w-2 h-2 rounded-full bg-red-500" />
          <span className="text-sm font-medium text-red-700 dark:text-red-400">
            {vms.filter((v) => v.status === 'stopped').length} stopped
          </span>
        </div>
        <div className="flex items-center gap-2 px-4 py-2 bg-amber-50 dark:bg-amber-900/30 rounded-lg">
          <div className="w-2 h-2 rounded-full bg-amber-500" />
          <span className="text-sm font-medium text-amber-700 dark:text-amber-400">
            {vms.filter((v) => v.status === 'paused').length} paused
          </span>
        </div>
      </div>

      {/* VMs by node */}
      {Object.entries(vmsByNode).map(([nodeName, nodeVms]) => {
        const nodeInfo = getNodeInfo(nodeName);
        return (
          <div key={nodeName} className="card rounded-xl border p-5">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className={`w-3 h-3 rounded-full ${nodeInfo?.status === 'online' ? 'bg-green-500' : 'bg-red-500'}`} />
                <h3 className="font-bold text-lg">{nodeName}</h3>
                {nodeInfo && (
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    CPU: {formatCPU(nodeInfo.cpu)} | RAM: {formatBytes(nodeInfo.memory_used)} / {formatBytes(nodeInfo.memory_total)}
                  </span>
                )}
              </div>
              <span className="text-sm text-gray-500 dark:text-gray-400">
                {nodeVms.filter((v) => v.status === 'running').length}/{nodeVms.length} running
              </span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              {nodeVms.map((vm) => (
                <div
                  key={vm.vm_id}
                  className={`
                    p-4 rounded-lg border transition-colors
                    ${vm.status === 'running'
                      ? 'border-green-200 dark:border-green-900 bg-green-50/50 dark:bg-green-900/10'
                      : 'border-gray-200 dark:border-gray-800'
                    }
                  `}
                >
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-2">
                      {getTypeIcon(vm.type)}
                      <span className="font-medium text-sm">{vm.name}</span>
                    </div>
                    <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${getStatusColor(vm.status)}`}>
                      {vm.status}
                    </span>
                  </div>

                  <div className="space-y-2">
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-gray-500 dark:text-gray-400 flex items-center gap-1">
                        <Cpu className="w-3 h-3" />
                        CPU
                      </span>
                      <span className="font-medium">{formatCPU(vm.cpu)}</span>
                    </div>
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-gray-500 dark:text-gray-400 flex items-center gap-1">
                        <MemoryStick className="w-3 h-3" />
                        RAM
                      </span>
                      <span className="font-medium">{formatBytes(vm.memory_used)}</span>
                    </div>
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-gray-500 dark:text-gray-400 flex items-center gap-1">
                        <HardDrive className="w-3 h-3" />
                        Disk
                      </span>
                      <span className="font-medium">{formatBytes(vm.disk)}</span>
                    </div>
                    <div className="text-xs text-gray-400 dark:text-gray-500 pt-1">
                      ID: {vm.vm_id} | Uptime: {formatUptime(vm.uptime)}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        );
      })}

      {/* Empty state */}
      {vms.length === 0 && (
        <div className="text-center py-12">
          <Monitor className="w-12 h-12 mx-auto text-gray-400 dark:text-gray-500 mb-4" />
          <p className="text-gray-500 dark:text-gray-400">No VMs or containers detected</p>
          <p className="text-sm text-gray-400 dark:text-gray-500 mt-1">
            VMs will appear here when Proxmox data is available
          </p>
        </div>
      )}
    </div>
  );
}