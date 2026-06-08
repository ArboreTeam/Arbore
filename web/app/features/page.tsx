'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { SectionTitle } from '@/components/shared/SectionTitle';
import { Camera, Brain, Box, CalendarCheck, Cloud, Users } from 'lucide-react';

const features = [
  {
    icon: Camera,
    title: 'Scanner 3D intelligent',
    description: 'Notre technologie de scan avancée analyse votre espace en 3D pour créer un modèle précis de votre jardin. Capturez les dimensions, l\'exposition au soleil et les caractéristiques uniques de votre terrain en quelques secondes.',
    image: true,
  },
  {
    icon: Brain,
    title: 'Recommandations personnalisées par IA',
    description: 'Notre intelligence artificielle prend en compte votre climat, la qualité de votre sol, l\'exposition au soleil et vos préférences esthétiques pour vous suggérer les plantes parfaites. Chaque recommandation est unique et adaptée à votre situation.',
    image: true,
  },
  {
    icon: Box,
    title: 'Visualisation 3D réaliste',
    description: 'Explorez votre futur jardin sous tous les angles avant de planter la moindre graine. Visualisez la croissance des plantes au fil des saisons et ajustez votre design en temps réel.',
    image: true,
  },
  {
    icon: CalendarCheck,
    title: 'Calendrier d\'entretien personnalisé',
    description: 'Recevez des rappels pour l\'arrosage, la taille, la fertilisation et toutes les tâches d\'entretien. Notre système s\'adapte à la météo locale et aux besoins spécifiques de chaque plante.',
    image: true,
  },
  {
    icon: Cloud,
    title: 'Synchronisation cloud',
    description: 'Accédez à vos projets depuis n\'importe quel appareil. Vos designs, notes et calendriers sont automatiquement sauvegardés et synchronisés dans le cloud.',
    image: true,
  },
  {
    icon: Users,
    title: 'Communauté de jardiniers',
    description: 'Partagez vos créations, découvrez l\'inspiration des autres jardiniers et bénéficiez des conseils d\'experts. Rejoignez une communauté passionnée qui grandit chaque jour.',
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
              Rejoignez la bêta publique dès aujourd&apos;hui
            </p>
            <Link href="/signup" className="inline-block bg-white text-[#234632] hover:bg-gray-100 px-8 py-4 rounded-full font-semibold text-lg transition-colors">
              Rejoindre la bêta
            </Link>
          </motion.div>
        </div>
      </section>

      <Footer />
    </main>
  );
}
