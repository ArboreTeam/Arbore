'use client';

import { motion } from 'framer-motion';
import { Card } from '@/components/ui/card';
import { Scan, Brain, Box, CalendarCheck } from 'lucide-react';
import { SectionTitle } from '@/components/shared/SectionTitle';

const features = [
  {
    icon: Scan,
    title: 'Scanner intelligent',
    description: 'Analysez votre espace en quelques secondes avec votre smartphone.',
  },
  {
    icon: Brain,
    title: 'Recommandations IA',
    description: 'Obtenez des suggestions personnalisées basées sur votre climat et sol.',
  },
  {
    icon: Box,
    title: 'Visualisation 3D',
    description: 'Visualisez votre futur jardin avant de planter la moindre graine.',
  },
  {
    icon: CalendarCheck,
    title: "Guide d'entretien",
    description: 'Suivez un calendrier personnalisé pour prendre soin de vos plantes.',
  },
];

export function SolutionSection() {
  return (
    <section className="py-20 px-4 sm:px-6 lg:px-8 bg-white/50">
      <div className="max-w-7xl mx-auto">
        <SectionTitle subtitle="Arbore simplifie chaque étape de votre projet">
          La solution complète
        </SectionTitle>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mt-12">
          {features.map((feature, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5, delay: index * 0.1 }}
              viewport={{ once: true }}
            >
              <Card className="p-6 h-full hover:shadow-card transition-all hover:-translate-y-1 border-2 border-border rounded-card bg-white">
                <div className="w-14 h-14 bg-[#8FAF8A]/10 rounded-card flex items-center justify-center mb-4">
                  <feature.icon className="w-7 h-7 text-[#234632]" />
                </div>
                <h3 className="text-lg font-bold text-arbore-ink mb-3">
                  {feature.title}
                </h3>
                <p className="text-arbore-muted text-sm leading-relaxed">
                  {feature.description}
                </p>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
