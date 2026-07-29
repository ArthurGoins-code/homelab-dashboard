import { useState, useEffect } from 'react';
import { ServiceGrid } from './components/ServiceGrid';
import { NodeCard } from './components/NodeCard';
import { VmList } from './components/VmList';
import { useServices } from './hooks/useServices';
import { useProxmoxNodes, useProxmoxVMs } from './hooks/useProxmox';
import { Sun, Moon, Activity, Layers, Settings as SettingsIcon } from 'lucide-react';

type Tab = 'services' | 'nodes' | 'vms' | 'settings';

function App() {
  const [darkMode, setDarkMode] = useState(() => {
    const saved = localStorage.getItem('homelab-dark-mode');
    return saved ? saved === 'true' : window.matchMedia('(prefers-color-scheme: dark)').matches;
  });
  const [activeTab, setActiveTab] = useState<Tab>('services');
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  const { services, loading: servicesLoading } = useServices();
  const { nodes, loading: nodesLoading } = useProxmoxNodes();
  const { vms, loading: vmsLoading } = useProxmoxVMs();

  useEffect(() => {
    document.documentElement.classList.toggle('dark', darkMode);
    localStorage.setItem('homelab-dark-mode', String(darkMode));
  }, [darkMode]);

  const tabs: { id: Tab; label: string; icon: typeof Activity }[] = [
    { id: 'services', label: 'Services', icon: Layers },
    { id: 'nodes', label: 'Nodes', icon: Activity },
    { id: 'vms', label: 'VMs & Containers', icon: Layers },
    { id: 'settings', label: 'Settings', icon: SettingsIcon },
  ];

  const totalOnline = services.filter((s) => s.online).length;
  const totalNodesOnline = nodes.filter((n) => n.status === 'online').length;
  const totalVmsOnline = vms.filter((v) => v.status === 'running').length;

  return (
    <div className="min-h-screen flex bg-gray-50 dark:bg-gray-950 transition-colors">
      {/* Sidebar */}
      <aside
        className={`
          ${sidebarCollapsed ? 'w-16' : 'w-56'}
          flex flex-col bg-white dark:bg-gray-900 border-r border-gray-200 dark:border-gray-800
          transition-all duration-300
        `}
      >
        {/* Logo */}
        <div className="p-4 border-b border-gray-200 dark:border-gray-800">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-blue-500 to-cyan-500 flex items-center justify-center flex-shrink-0">
              <Activity className="w-5 h-5 text-white" />
            </div>
            {!sidebarCollapsed && (
              <div className="overflow-hidden">
                <h1 className="font-bold text-sm">Homelab</h1>
                <p className="text-xs text-gray-500 dark:text-gray-400">Dashboard</p>
              </div>
            )}
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 p-2 space-y-1">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`
                  w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors
                  ${isActive
                    ? 'bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400'
                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
                  }
                `}
              >
                <Icon className="w-5 h-5 flex-shrink-0" />
                {!sidebarCollapsed && <span>{tab.label}</span>}
              </button>
            );
          })}
        </nav>

        {/* Summary */}
        <div className="p-3 border-t border-gray-200 dark:border-gray-800">
          <div className={`${sidebarCollapsed ? 'text-center' : ''}`}>
            {!sidebarCollapsed && <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-2">Overview</p>}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-xs">
                {!sidebarCollapsed && <span className="text-gray-500 dark:text-gray-400">Services</span>}
                <span className="font-medium text-green-600 dark:text-green-400">
                  {totalOnline}/{services.length}
                </span>
              </div>
              <div className="flex items-center justify-between text-xs">
                {!sidebarCollapsed && <span className="text-gray-500 dark:text-gray-400">Nodes</span>}
                <span className="font-medium text-green-600 dark:text-green-400">
                  {totalNodesOnline}/{nodes.length}
                </span>
              </div>
              <div className="flex items-center justify-between text-xs">
                {!sidebarCollapsed && <span className="text-gray-500 dark:text-gray-400">VMs</span>}
                <span className="font-medium text-green-600 dark:text-green-400">
                  {totalVmsOnline}/{vms.length}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Bottom controls */}
        <div className="p-3 border-t border-gray-200 dark:border-gray-800 flex items-center justify-between">
          <button
            onClick={() => setDarkMode(!darkMode)}
            className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
          >
            {darkMode ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
          </button>
          <button
            onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
            className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors text-gray-500"
          >
            <Layers className="w-4 h-4" />
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-auto">
        {/* Top bar */}
        <header className="sticky top-0 z-10 bg-white/80 dark:bg-gray-900/80 backdrop-blur-sm border-b border-gray-200 dark:border-gray-800 px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-xl font-bold capitalize">{activeTab}</h2>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                {activeTab === 'services' && 'Monitor and access your homelab services'}
                {activeTab === 'nodes' && 'Real-time resource usage for your Proxmox nodes'}
                {activeTab === 'vms' && 'Virtual machines and LXC containers'}
                {activeTab === 'settings' && 'Configure your dashboard'}
              </p>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-xs text-gray-500 dark:text-gray-400">
                {activeTab === 'services' && servicesLoading ? 'Loading...' : `Updated ${new Date().toLocaleTimeString()}`}
                {activeTab === 'nodes' && nodesLoading ? ' Loading...' : ''}
                {activeTab === 'vms' && vmsLoading ? ' Loading...' : ''}
              </span>
            </div>
          </div>
        </header>

        {/* Content */}
        <div className="p-6">
          {activeTab === 'services' && (
            <ServiceGrid services={services} />
          )}

          {activeTab === 'nodes' && (
            <div className="space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
                {nodes.map((node, i) => (
                  <NodeCard key={node.name} node={node} index={i} />
                ))}
              </div>
              {nodes.length === 0 && (
                <div className="text-center py-12">
                  <Activity className="w-12 h-12 mx-auto text-gray-400 dark:text-gray-500 mb-4" />
                  <p className="text-gray-500 dark:text-gray-400">No Proxmox nodes detected</p>
                  <p className="text-sm text-gray-400 dark:text-gray-500 mt-1">
                    Check your Proxmox API configuration
                  </p>
                </div>
              )}
            </div>
          )}

          {activeTab === 'vms' && (
            <VmList vms={vms} nodes={nodes} />
          )}

          {activeTab === 'settings' && <SettingsPanel />}
        </div>
      </main>
    </div>
  );
}

function SettingsPanel() {
  return (
    <div className="max-w-2xl space-y-6">
      <div className="card rounded-xl border p-6">
        <h3 className="font-semibold mb-4">Dashboard Settings</h3>
        <div className="space-y-4">
          <div className="flex items-center justify-between py-3 border-b border-gray-100 dark:border-gray-800">
            <div>
              <p className="text-sm font-medium">Refresh Interval</p>
              <p className="text-xs text-gray-500 dark:text-gray-400">How often to check service health</p>
            </div>
            <select className="px-3 py-1.5 rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 text-sm">
              <option>30 seconds</option>
              <option>60 seconds</option>
              <option>120 seconds</option>
            </select>
          </div>
          <div className="flex items-center justify-between py-3 border-b border-gray-100 dark:border-gray-800">
            <div>
              <p className="text-sm font-medium">Dark Mode</p>
              <p className="text-xs text-gray-500 dark:text-gray-400">Toggle dark/light theme</p>
            </div>
            <div className="w-11 h-6 rounded-full bg-blue-500 relative cursor-pointer">
              <div className="w-5 h-5 rounded-full bg-white shadow-sm absolute top-0.5 right-0.5" />
            </div>
          </div>
          <div className="flex items-center justify-between py-3 border-b border-gray-100 dark:border-gray-800">
            <div>
              <p className="text-sm font-medium">Proxmox API</p>
              <p className="text-xs text-gray-500 dark:text-gray-400">https://proxmox:8006/api2/json</p>
            </div>
            <span className="text-xs text-green-500 font-medium">Connected</span>
          </div>
        </div>
      </div>

      <div className="card rounded-xl border p-6">
        <h3 className="font-semibold mb-4">Services Configuration</h3>
        <pre className="text-xs bg-gray-50 dark:bg-gray-800 rounded-lg p-4 overflow-x-auto">
          {JSON.stringify({
            services: [
              { name: 'Mealie', category: 'Productivity', online: true },
              { name: 'AdGuard DNS', category: 'Networking', online: true },
              { name: 'Nginx Proxy Manager', category: 'Networking', online: true },
              { name: 'Home Assistant', category: 'Productivity', online: true },
              { name: 'Ubuntu VM', category: 'Infrastructure', online: true },
              { name: 'Ollama', category: 'AI', online: true },
            ],
            nodes: ['primary', 'secondary', 'ollama-node'],
          }, null, 2)}
        </pre>
      </div>
    </div>
  );
}

export default App;