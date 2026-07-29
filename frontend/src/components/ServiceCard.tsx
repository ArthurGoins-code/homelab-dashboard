import { Link } from 'react-router-dom';
import type { ServiceStatus } from '@/types';
import { SERVICE_ICONS } from '@/types';
import {
  Globe,
  Activity,
  Cloud,
  Shield,
  Database,
  BookOpen,
  Home,
  Cpu,
  Monitor,
  Link as LinkIcon,
} from 'lucide-react';

const ICON_MAP: Record<string, typeof Globe> = {
  docker: Activity,
  grafana: Activity,
  prometheus: Activity,
  cloud: Cloud,
  shield: Shield,
  database: Database,
  'book-open': BookOpen,
  eye: Activity,
  globe: Globe,
  home: Home,
  cpu: Cpu,
  monitor: Monitor,
  link: LinkIcon,
};

interface Props {
  service: ServiceStatus;
  index?: number;
}

export function ServiceCard({ service, index = 0 }: Props) {
  const IconComponent = ICON_MAP[service.icon.toLowerCase()] || ICON_MAP[service.icon] || LinkIcon;
  const isOnline = service.online;
  const isSlow = service.response_time !== undefined && service.response_time > 500;

  return (
    <Link
      to={service.url}
      target="_blank"
      rel="noopener noreferrer"
      className={`
        service-card card rounded-xl border p-5 cursor-pointer
        flex flex-col gap-3
        ${isOnline ? 'border-green-200 dark:border-green-900' : 'border-red-200 dark:border-red-900'}
      `}
      style={{ animationDelay: `${index * 0.05}s` }}
    >
      {/* Header row */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div
            className={`
              flex items-center justify-center w-10 h-10 rounded-lg
              ${isOnline
                ? 'bg-gradient-to-br from-blue-500 to-cyan-500 text-white'
                : 'bg-gray-100 dark:bg-gray-800 text-gray-400'
              }
            `}
          >
            <IconComponent className="w-5 h-5" />
          </div>
          <div>
            <h3 className="font-semibold text-sm">{service.name}</h3>
            <span
              className={`text-xs ${isOnline ? 'status-online' : 'status-offline'}`}
            >
              {isOnline ? 'Online' : 'Offline'}
            </span>
          </div>
        </div>
        <span className="text-xs text-gray-400 dark:text-gray-500">
          {service.category}
        </span>
      </div>

      {/* URL */}
      <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
        {service.url}
      </p>

      {/* Footer: response time */}
      {isOnline && service.response_time !== undefined && (
        <div className="flex items-center justify-between mt-auto">
          <span className="text-xs text-gray-400">
            {service.response_time < 100
              ? `${service.response_time}ms`
              : `${(service.response_time / 1000).toFixed(1)}s`}
          </span>
          {isSlow && (
            <span className="text-xs text-amber-500 bg-amber-50 dark:bg-amber-900/30 px-2 py-0.5 rounded">
              Slow
            </span>
          )}
        </div>
      )}

      {/* Offline indicator */}
      {!isOnline && (
        <span className="text-xs text-red-400 bg-red-50 dark:bg-red-900/30 px-2 py-0.5 rounded self-start">
          Last checked: {service.last_checked ? new Date(service.last_checked).toLocaleTimeString() : 'N/A'}
        </span>
      )}
    </Link>
  );
}