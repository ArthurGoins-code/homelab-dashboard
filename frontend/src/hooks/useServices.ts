import { useState, useEffect, useCallback } from 'react';
import type { ServiceStatus } from '@/types';

const API_BASE = import.meta.env.VITE_API_URL || '/api';

export function useServices() {
  const [services, setServices] = useState<ServiceStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchServices = useCallback(async () => {
    try {
      const response = await fetch(`${API_BASE}/services`);
      if (!response.ok) throw new Error('Failed to fetch services');
      const data = await response.json();
      setServices(Array.isArray(data) ? data : []);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchServices();
    const interval = setInterval(fetchServices, 30000);
    return () => clearInterval(interval);
  }, [fetchServices]);

  const addService = useCallback(async (service: Omit<ServiceStatus, 'online' | 'response_time' | 'last_checked'>) => {
    const response = await fetch(`${API_BASE}/services`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(service),
    });
    if (response.ok) {
      await fetchServices();
    }
  }, []);

  const removeService = useCallback(async (name: string) => {
    const response = await fetch(`${API_BASE}/services/${encodeURIComponent(name)}`, {
      method: 'DELETE',
    });
    if (response.ok) {
      await fetchServices();
    }
  }, []);

  const updateService = useCallback(async (name: string, updates: Partial<ServiceStatus>) => {
    const response = await fetch(`${API_BASE}/services/${encodeURIComponent(name)}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updates),
    });
    if (response.ok) {
      await fetchServices();
    }
  }, []);

  return {
    services,
    loading,
    error,
    refetch: fetchServices,
    addService,
    removeService,
    updateService,
  };
}