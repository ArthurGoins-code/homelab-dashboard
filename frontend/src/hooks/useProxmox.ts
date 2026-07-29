import { useState, useEffect, useCallback } from 'react';
import type { ProxmoxNode, VirtualMachine } from '@/types';

const API_BASE = import.meta.env.VITE_API_URL || '/api';

export function useProxmoxNodes() {
  const [nodes, setNodes] = useState<ProxmoxNode[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchNodes = useCallback(async () => {
    try {
      const response = await fetch(`${API_BASE}/proxmox/nodes`);
      if (!response.ok) throw new Error('Failed to fetch nodes');
      const data = await response.json();
      setNodes(data);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchNodes();
    const interval = setInterval(fetchNodes, 15000);
    return () => clearInterval(interval);
  }, [fetchNodes]);

  return { nodes, loading, error, refetch: fetchNodes };
}

export function useProxmoxVMs() {
  const [vms, setVMs] = useState<VirtualMachine[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchVMs = useCallback(async () => {
    try {
      const response = await fetch(`${API_BASE}/proxmox/vms`);
      if (!response.ok) throw new Error('Failed to fetch VMs');
      const data = await response.json();
      setVMs(data);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchVMs();
    const interval = setInterval(fetchVMs, 15000);
    return () => clearInterval(interval);
  }, [fetchVMs]);

  return { vms, loading, error, refetch: fetchVMs };
}

export function useNodeVMs(nodeName: string) {
  const [vms, setVMs] = useState<VirtualMachine[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchVMs = useCallback(async () => {
    try {
      const response = await fetch(`${API_BASE}/proxmox/nodes/${encodeURIComponent(nodeName)}/vms`);
      if (!response.ok) throw new Error('Failed to fetch node VMs');
      const data = await response.json();
      setVMs(Array.isArray(data) ? data : []);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, [nodeName]);

  useEffect(() => {
    fetchVMs();
    const interval = setInterval(fetchVMs, 15000);
    return () => clearInterval(interval);
  }, [fetchVMs, nodeName]);

  return { vms, loading, error, refetch: fetchVMs };
}