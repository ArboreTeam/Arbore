'use client';

import { motion } from 'framer-motion';
import { Camera, MapPin, Palette, Eye, Rocket } from 'lucide-react';
import { SectionTitle } from '@/components/shared/SectionTitle';

const steps = [
  {
    number: 1,
    icon: Camera,
    title: 'Scannez votre espace',
    description: 'Prenez une photo de votre jardin avec votre smartphone.',
  },
  {
    number: 2,
    icon: MapPin,
    title: 'Définissez vos préférences',
    description: 'Indiquez votre localisation, type de sol et style souhaité.',
  },
  {
    number: 3,
    icon: Palette,
    title: 'Choisissez un design',
    description: 'Explorez les propositions générées par notre IA.',
  },
  {
    number: 4,
    icon: Eye,
    title: 'Visualisez en 3D',
    description: 'Admirez votre futur jardin dans tous les angles.',
  },
  {
    number: 5,
    icon: Rocket,
    title: "Passez à l'action",
    description: 'Suivez le guide étape par étape pour concrétiser votre projet.',
  },
];

export function HowItWorksSection() {
  return (
    <section className="py-20 px-4 sm:px-6 lg:px-8">
      <div className="max-w-7xl mx-auto">
        <SectionTitle subtitle="Un processus simple en 5 étapes">
          Comment ça marche ?
        </SectionTitle>

        <div className="mt-16 space-y-12">
          {steps.map((step, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, x: index % 2 === 0 ? -20 : 20 }}
              whileInView={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.5 }}
              viewport={{ once: true }}
              className="flex flex-col md:flex-row items-center gap-8"
            >
              <div className={`flex-1 ${index % 2 === 0 ? 'md:order-1' : 'md:order-2'}`}>
                <div className="flex items-center gap-4 mb-4">
                  <div className="w-12 h-12 bg-[#234632] text-white rounded-full flex items-center justify-center text-xl font-bold">
                    {step.number}
                  </div>
                  <h3 className="text-2xl font-bold text-[#234632]">
                    {step.title}
                  </h3>
                </div>
                <p className="text-lg text-arbore-muted leading-relaxed">
                  {step.description}
                </p>
              </div>

              <div className={`flex-1 ${index % 2 === 0 ? 'md:order-2' : 'md:order-1'}`}>
                <div className="aspect-video rounded-card bg-gradient-to-br from-[#234632]/10 to-[#8FAF8A]/10 flex items-center justify-center border-2 border-[#234632]/20">
                  <step.icon className="w-24 h-24 text-[#234632]" />
                </div>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
