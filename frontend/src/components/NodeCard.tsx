import type { ProxmoxNode } from '@/types';
import { formatBytes, formatUptime, formatCPU } from '@/types';
import { Cpu, MemoryStick, HardDrive, Clock } from 'lucide-react';

interface Props {
  node: ProxmoxNode;
  index?: number;
}

function getProgressClass(percent: number): string {
  if (percent < 60) return 'low';
  if (percent < 85) return 'medium';
  return 'high';
}

export function NodeCard({ node, index = 0 }: Props) {
  const isOnline = node.status === 'online';
  const uptimeHours = node.uptime > 0 ? node.uptime / 3600 : 0;

  return (
    <div
      className={`node-card card rounded-xl border p-5 fade-in ${isOnline ? 'border-blue-200 dark:border-blue-900' : 'border-red-200 dark:border-red-900'}`}
      style={{ animationDelay: `${index * 0.1}s` }}
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className={`w-3 h-3 rounded-full ${isOnline ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`} />
          <div>
            <h3 className="font-bold text-lg">{node.name}</h3>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              Uptime: {formatUptime(node.uptime)}
            </p>
          </div>
        </div>
        <span className={`text-xs font-medium px-2 py-1 rounded-full ${isOnline ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400' : 'bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400'}`}>
          {node.status}
        </span>
      </div>

      {/* Metrics */}
      <div className="space-y-3">
        {/* CPU */}
        <div>
          <div className="flex items-center justify-between text-xs mb-1">
            <span className="flex items-center gap-1 text-gray-500 dark:text-gray-400">
              <Cpu className="w-3 h-3" />
              CPU
            </span>
            <span className="font-medium">{formatCPU(node.cpu)}</span>
          </div>
          <div className="progress-bar">
            <div
              className={`progress-bar-fill ${getProgressClass(node.cpu)}`}
              style={{ width: `${Math.min(node.cpu, 100)}%` }}
            />
          </div>
        </div>

        {/* Memory */}
        <div>
          <div className="flex items-center justify-between text-xs mb-1">
            <span className="flex items-center gap-1 text-gray-500 dark:text-gray-400">
              <MemoryStick className="w-3 h-3" />
              Memory
            </span>
            <span className="font-medium">
              {formatBytes(node.memory_used)} / {formatBytes(node.memory_total)}
            </span>
          </div>
          <div className="progress-bar">
            <div
              className={`progress-bar-fill ${getProgressClass(node.memory_percent)}`}
              style={{ width: `${Math.min(node.memory_percent, 100)}%` }}
            />
          </div>
        </div>

        {/* Disk */}
        <div>
          <div className="flex items-center justify-between text-xs mb-1">
            <span className="flex items-center gap-1 text-gray-500 dark:text-gray-400">
              <HardDrive className="w-3 h-3" />
              Disk
            </span>
            <span className="font-medium">
              {formatBytes(node.disk_used)} / {formatBytes(node.disk_total)}
            </span>
          </div>
          <div className="progress-bar">
            <div
              className={`progress-bar-fill ${getProgressClass(node.disk_percent)}`}
              style={{ width: `${Math.min(node.disk_percent, 100)}%` }}
            />
          </div>
        </div>

        {/* Load average */}
        <div className="flex items-center gap-4 pt-2 border-t border-gray-100 dark:border-gray-800">
          <span className="text-xs text-gray-500 dark:text-gray-400 flex items-center gap-1">
            <Clock className="w-3 h-3" />
            Load: {node.load_1.toFixed(2)}
          </span>
          <span className="text-xs text-gray-400 dark:text-gray-500">
            1m: {node.load_1.toFixed(2)}
          </span>
          <span className="text-xs text-gray-400 dark:text-gray-500">
            5m: {node.load_5.toFixed(2)}
          </span>
          <span className="text-xs text-gray-400 dark:text-gray-500">
            15m: {node.load_15.toFixed(2)}
          </span>
        </div>
      </div>
    </div>
  );
}