'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { SectionTitle } from '@/components/shared/SectionTitle';
import { Camera, Brain, Box, CalendarCheck, Sun } from 'lucide-react';

const features = [
  {
    icon: Camera,
    title: 'Mesure guidée de l’espace',
    description: 'Arbore vous guide pour délimiter votre pièce, balcon, terrasse ou jardin et enregistrer les dimensions utiles à votre projet.',
    image: true,
  },
  {
    icon: Brain,
    title: 'Catalogue adapté à votre environnement',
    description: 'Les plantes sont filtrées selon les informations disponibles pour votre espace, comme la lumière, la localisation approximative et vos préférences.',
    image: true,
  },
  {
    icon: Box,
    title: 'Visualisation 3D réaliste',
    description: 'Placez des modèles de plantes dans votre espace en réalité augmentée et ajustez leur disposition avant de faire votre choix.',
    image: true,
  },
  {
    icon: CalendarCheck,
    title: 'Calendrier d\'entretien personnalisé',
    description: 'Consultez les conseils de soin et programmez les rappels disponibles pour les plantes que vous souhaitez suivre.',
    image: true,
  },
  {
    icon: Sun,
    title: 'Lumière et orientation',
    description: 'Enregistrez l’orientation de la principale source de lumière afin d’affiner les informations de votre espace.',
    image: true,
  },
];

export default function FeaturesPage() {
  return (
    <main>
      <Navbar />

      <section className="pt-32 pb-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <h1 className="text-5xl md:text-6xl font-bold text-[#234632] mb-6">
              Toutes les fonctionnalités
            </h1>
            <p className="text-xl text-arbore-muted">
              Découvrez tous les outils qui font d&apos;Arbore la meilleure application de conception de jardins
            </p>
          </motion.div>
        </div>
      </section>

      <section className="py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto space-y-24">
          {features.map((feature, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6 }}
              viewport={{ once: true }}
              className={`flex flex-col ${
                index % 2 === 0 ? 'lg:flex-row' : 'lg:flex-row-reverse'
              } gap-12 items-center`}
            >
              <div className="flex-1">
                <div className="w-16 h-16 bg-[#8FAF8A]/10 rounded-card flex items-center justify-center mb-6">
                  <feature.icon className="w-8 h-8 text-[#234632]" />
                </div>
                <h2 className="text-3xl font-bold text-[#234632] mb-4">
                  {feature.title}
                </h2>
                <p className="text-lg text-arbore-muted leading-relaxed">
                  {feature.description}
                </p>
              </div>

              <div className="flex-1">
                <div className="aspect-video rounded-card bg-gradient-to-br from-[#234632]/10 to-[#8FAF8A]/10 flex items-center justify-center border-2 border-[#234632]/20">
                  <feature.icon className="w-32 h-32 text-[#234632] opacity-30" />
                </div>
              </div>
            </motion.div>
          ))}
        </div>
      </section>

      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-[#234632]">
        <div className="max-w-4xl mx-auto text-center">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            viewport={{ once: true }}
          >
            <h2 className="text-4xl font-bold text-white mb-6">
              Prêt à créer votre jardin ?
            </h2>
            <p className="text-xl text-green-100 mb-8">
              Arbore est actuellement disponible gratuitement sur iPhone.
            </p>
            <Link href="/signup" className="inline-block bg-white text-[#234632] hover:bg-gray-100 px-8 py-4 rounded-full font-semibold text-lg transition-colors">
              Créer un compte
            </Link>
          </motion.div>
        </div>
      </section>

      <Footer />
    </main>
  );
}
