'use client';

import { Sprout } from 'lucide-react';
import { motion } from 'framer-motion';

/** Overlay plein écran brandé pendant une connexion sociale (Apple/Google).
 *  La popup du provider reste la sienne (obligatoire), mais tout autour est Arbore. */
export function AuthLoadingOverlay({ provider }: { provider: 'apple' | 'google' }) {
  const label = provider === 'apple' ? 'Apple' : 'Google';
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="fixed inset-0 z-[60] flex flex-col items-center justify-center gap-5 bg-background/95 backdrop-blur-sm"
    >
      <div className="relative flex h-20 w-20 items-center justify-center">
        <span className="absolute inset-0 animate-ping rounded-full bg-arbore-sage/40" />
        <div className="relative flex h-20 w-20 items-center justify-center rounded-full bg-primary shadow-hero">
          <Sprout className="h-9 w-9 text-primary-foreground" />
        </div>
      </div>
      <div className="text-center">
        <p className="font-display text-lg font-bold text-arbore-ink">Connexion avec {label}…</p>
        <p className="mt-1 text-sm text-arbore-muted">
          Terminez la connexion dans la fenêtre Apple/Google.
        </p>
      </div>
    </motion.div>
  );
}
