'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { motion } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Sparkles } from 'lucide-react';
import { QuestionnaireModal } from './QuestionnaireModal';

export function HeroSection() {
  const [isQuestionnaireOpen, setIsQuestionnaireOpen] = useState(false);
  const router = useRouter();

  return (
    <section className="pt-32 pb-20 px-4 sm:px-6 lg:px-8">
      <div className="max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <div className="inline-flex items-center gap-2 bg-[#84CC16]/10 text-[#2D5A27] px-4 py-2 rounded-full mb-6">
              <Sparkles className="w-4 h-4" />
              <span className="text-sm font-medium">Grow with harmony</span>
            </div>
            <h1 className="text-5xl md:text-6xl lg:text-7xl font-bold text-[#2D5A27] mb-6 leading-tight">
              Créez le jardin de vos rêves
            </h1>
            <p className="text-xl text-gray-600 mb-8 leading-relaxed">
              Transformez votre espace extérieur avec l&apos;intelligence artificielle.
              Arbore vous guide pas à pas pour créer un jardin harmonieux et adapté à votre environnement.
            </p>
            <div className="flex flex-col sm:flex-row gap-4">
              <Button
                size="lg"
                onClick={() => setIsQuestionnaireOpen(true)}
                className="bg-[#2D5A27] hover:bg-[#234520] text-white rounded-full text-lg px-8 py-6"
              >
                Commencer gratuitement
              </Button>
              <Button
                size="lg"
                variant="outline"
                onClick={() => router.push('/login')}
                className="border-[#2D5A27] text-[#2D5A27] hover:bg-[#2D5A27] hover:text-white rounded-full text-lg px-8 py-6"
              >
                Se connecter
              </Button>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.6, delay: 0.2 }}
            className="relative"
          >
            <div className="aspect-square rounded-3xl bg-gradient-to-br from-[#2D5A27] to-[#84CC16] p-8 shadow-2xl">
              <div className="w-full h-full rounded-2xl bg-white/10 backdrop-blur-sm flex items-center justify-center">
                <div className="text-center text-white">
                  <div className="w-32 h-32 mx-auto mb-4 bg-white/20 rounded-full flex items-center justify-center">
                    <Sparkles className="w-16 h-16" />
                  </div>
                  <p className="text-2xl font-semibold">Votre jardin parfait</p>
                  <p className="text-lg opacity-90">vous attend</p>
                </div>
              </div>
            </div>
            <div className="absolute -bottom-6 -right-6 w-32 h-32 bg-[#84CC16] rounded-full opacity-20 blur-3xl"></div>
            <div className="absolute -top-6 -left-6 w-32 h-32 bg-[#2D5A27] rounded-full opacity-20 blur-3xl"></div>
          </motion.div>
        </div>
      </div>
      <QuestionnaireModal isOpen={isQuestionnaireOpen} onClose={() => setIsQuestionnaireOpen(false)} />
    </section>
  );
}
