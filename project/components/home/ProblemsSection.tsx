'use client';

import { motion } from 'framer-motion';
import { Card } from '@/components/ui/card';
import { AlertCircle, Skull, Frown } from 'lucide-react';
import { SectionTitle } from '@/components/shared/SectionTitle';

const problems = [
  {
    icon: AlertCircle,
    title: 'Trop de choix',
    description: 'Des milliers de plantes disponibles, mais lesquelles sont adaptées à votre jardin ?',
  },
  {
    icon: Skull,
    title: 'Plantes qui meurent',
    description: 'Vous investissez temps et argent, mais vos plantes ne survivent pas.',
  },
  {
    icon: Frown,
    title: 'Résultat décevant',
    description: 'Votre jardin ne ressemble pas à ce que vous aviez imaginé.',
  },
];

export function ProblemsSection() {
  return (
    <section className="py-20 px-4 sm:px-6 lg:px-8">
      <div className="max-w-7xl mx-auto">
        <SectionTitle subtitle="Vous reconnaissez ces situations ?">
          Les défis du jardinage
        </SectionTitle>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mt-12">
          {problems.map((problem, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5, delay: index * 0.1 }}
              viewport={{ once: true }}
            >
              <Card className="p-8 h-full hover:shadow-card transition-shadow border-2 border-border rounded-card">
                <div className="w-16 h-16 bg-red-100 rounded-card flex items-center justify-center mb-6">
                  <problem.icon className="w-8 h-8 text-red-600" />
                </div>
                <h3 className="text-xl font-bold text-arbore-ink mb-4">
                  {problem.title}
                </h3>
                <p className="text-arbore-muted leading-relaxed">
                  {problem.description}
                </p>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
