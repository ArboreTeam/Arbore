'use client';

import { useEffect, useState } from 'react';
import { WifiOff } from 'lucide-react';

/** Bannière affichée quand le navigateur passe hors-ligne (#24). */
export function OfflineBanner() {
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    const update = () => setOffline(!navigator.onLine);
    update();
    window.addEventListener('online', update);
    window.addEventListener('offline', update);
    return () => {
      window.removeEventListener('online', update);
      window.removeEventListener('offline', update);
    };
  }, []);

  if (!offline) return null;

  return (
    <div className="fixed inset-x-0 top-0 z-[70] flex items-center justify-center gap-2 bg-arbore-danger px-4 py-2 text-sm font-semibold text-white">
      <WifiOff className="h-4 w-4 flex-shrink-0" />
      Vous êtes hors ligne — certaines fonctionnalités sont indisponibles.
    </div>
  );
}
