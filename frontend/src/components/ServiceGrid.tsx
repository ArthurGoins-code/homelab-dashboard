import { ServiceCard } from './ServiceCard';
import type { ServiceStatus } from '@/types';
import { Plus, Filter } from 'lucide-react';
import { useState } from 'react';

interface Props {
  services: ServiceStatus[];
  onAddService?: () => void;
}

export function ServiceGrid({ services, onAddService }: Props) {
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);

  const categories = Array.from(new Set(services.map((s) => s.category)));
  const filtered = selectedCategory
    ? services.filter((s) => s.category === selectedCategory)
    : services;

  const onlineCount = services.filter((s) => s.online).length;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">Services</h2>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {onlineCount} of {services.length} services online
          </p>
        </div>
        {onAddService && (
          <button
            onClick={onAddService}
            className="flex items-center gap-2 px-4 py-2 bg-gradient-to-r from-blue-500 to-cyan-500 text-white rounded-lg hover:opacity-90 transition-opacity text-sm font-medium"
          >
            <Plus className="w-4 h-4" />
            Add Service
          </button>
        )}
      </div>

      {/* Category filter */}
      {categories.length > 1 && (
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => setSelectedCategory(null)}
            className={`
              px-3 py-1.5 rounded-full text-sm font-medium transition-colors
              ${selectedCategory === null
                ? 'bg-blue-500 text-white'
                : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
              }
            `}
          >
            All ({services.length})
          </button>
          {categories.map((cat) => (
            <button
              key={cat}
              onClick={() => setSelectedCategory(cat === selectedCategory ? null : cat)}
              className={`
                px-3 py-1.5 rounded-full text-sm font-medium transition-colors
                ${selectedCategory === cat
                  ? 'bg-blue-500 text-white'
                  : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
                }
              `}
            >
              {cat} ({services.filter((s) => s.category === cat).length})
            </button>
          ))}
        </div>
      )}

      {/* Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {filtered.map((service, i) => (
          <ServiceCard key={service.name} service={service} index={i} />
        ))}
      </div>

      {/* Empty state */}
      {filtered.length === 0 && (
        <div className="text-center py-12">
          <div className="text-gray-400 dark:text-gray-500 mb-2">
            <Filter className="w-12 h-12 mx-auto opacity-50" />
          </div>
          <p className="text-gray-500 dark:text-gray-400">
            {selectedCategory ? 'No services in this category' : 'No services yet'}
          </p>
          {onAddService && (
            <button
              onClick={onAddService}
              className="mt-4 text-blue-500 hover:underline text-sm"
            >
              Add your first service
            </button>
          )}
        </div>
      )}
    </div>
  );
}