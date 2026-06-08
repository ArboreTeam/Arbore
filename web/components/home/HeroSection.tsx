'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { motion } from 'framer-motion';
import { Leaf, Sprout } from 'lucide-react';
import { QuestionnaireModal } from './QuestionnaireModal';

export function HeroSection() {
  const [isQuestionnaireOpen, setIsQuestionnaireOpen] = useState(false);
  const router = useRouter();

  return (
    <section className="px-4 pb-20 pt-32 sm:px-6 lg:px-8">
      <div className="mx-auto max-w-7xl">
        <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <div className="arbore-chip mb-6">
              <Leaf className="h-4 w-4" />
              <span>Cultivez en harmonie</span>
            </div>
            <h1 className="mb-6 font-display text-5xl font-extrabold leading-[1.05] text-arbore-green md:text-6xl lg:text-7xl">
              Composez le jardin de vos rêves
            </h1>
            <p className="mb-8 max-w-xl text-lg leading-relaxed text-arbore-muted">
              Concevez votre espace en réalité augmentée, recevez des suggestions de plantes
              adaptées à votre lumière, et gardez chaque plante en pleine forme — sans avoir la main verte.
            </p>
            <div className="flex flex-col gap-3 sm:flex-row">
              <button onClick={() => setIsQuestionnaireOpen(true)} className="btn-arbore px-8 py-4 text-base">
                Commencer gratuitement
              </button>
              <button onClick={() => router.push('/login')} className="btn-arbore-ghost px-8 py-4 text-base">
                Se connecter
              </button>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.6, delay: 0.2 }}
            className="relative"
          >
            {/* Halo organique */}
            <div className="absolute -right-10 -top-10 h-48 w-48 rounded-full bg-arbore-sage opacity-25 blur-3xl" />
            <div className="absolute -bottom-10 -left-10 h-48 w-48 rounded-full bg-primary opacity-15 blur-3xl" />

            <div className="arbore-hero relative aspect-square overflow-hidden p-8">
              {/* lueur radiale */}
              <div className="pointer-events-none absolute -top-1/3 left-1/2 h-2/3 w-[120%] -translate-x-1/2 rounded-full bg-white/10 blur-3xl" />
              <div className="flex h-full w-full flex-col items-center justify-center text-center">
                <div className="mb-6 flex h-28 w-28 items-center justify-center rounded-full bg-white/15 backdrop-blur-sm">
                  <Sprout className="h-14 w-14 text-primary-foreground" />
                </div>
                <p className="font-display text-3xl font-bold text-primary-foreground">Votre jardin parfait</p>
                <p className="mt-1 text-lg text-primary-foreground/80">prend racine ici</p>
              </div>
            </div>
          </motion.div>
        </div>
      </div>
      <QuestionnaireModal isOpen={isQuestionnaireOpen} onClose={() => setIsQuestionnaireOpen(false)} />
    </section>
  );
}
