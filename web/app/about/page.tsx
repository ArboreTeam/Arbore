'use client';

import { motion } from 'framer-motion';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { Card } from '@/components/ui/card';
import { Heart, Leaf, Target } from 'lucide-react';

const team = [
  {
    name: 'Tanssime Mansour',
    role: 'Co-fondateur & CEO',
    bio: 'Passionné par l\'IA et le jardinage, Tanssime a créé Arbore pour rendre le jardinage accessible à tous.',
  },
  {
    name: 'Isaac Rahal',
    role: 'Co-fondateur & CTO',
    bio: 'Expert en intelligence artificielle et vision par ordinateur, Isaac développe les technologies qui propulsent Arbore.',
  },
];

export default function AboutPage() {
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
              Notre mission
            </h1>
            <p className="text-xl text-arbore-muted">
              Rendre le jardinage accessible à tous grâce à l&apos;intelligence artificielle
            </p>
          </motion.div>
        </div>
      </section>

      <section className="py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            viewport={{ once: true }}
            className="prose prose-lg max-w-none"
          >
            <p className="text-lg text-arbore-ink leading-relaxed mb-6">
              Arbore est née d&apos;une frustration simple : créer et entretenir un beau jardin
              ne devrait pas être si compliqué. Trop souvent, les jardiniers amateurs se retrouvent
              dépassés par la quantité d&apos;informations à assimiler, les choix à faire et les erreurs coûteuses.
            </p>
            <p className="text-lg text-arbore-ink leading-relaxed mb-6">
              Nous croyons que la technologie peut transformer cette expérience. En combinant
              intelligence artificielle, vision par ordinateur et expertise horticole, nous avons
              créé un assistant personnel qui guide chacun vers le jardin de ses rêves.
            </p>
            <p className="text-lg text-arbore-ink leading-relaxed">
              Notre objectif est simple : que chaque personne puisse créer et profiter d&apos;un jardin
              magnifique, adapté à son environnement et facile à entretenir.
            </p>
          </motion.div>
        </div>
      </section>

      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-white/50">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-4xl font-bold text-[#234632] mb-4">
              Nos valeurs
            </h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {[
              {
                icon: Heart,
                title: 'Passion',
                description: 'Nous aimons le jardinage et la nature, et cette passion anime chaque fonctionnalité que nous créons.',
              },
              {
                icon: Target,
                title: 'Simplicité',
                description: 'La technologie doit être invisible. Notre mission est de simplifier le jardinage, pas de le compliquer.',
              },
              {
                icon: Leaf,
                title: 'Écoute',
                description: 'Nous faisons évoluer Arbore à partir des besoins concrets et des retours de ses utilisateurs.',
              },
            ].map((value, index) => (
              <motion.div
                key={index}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
                viewport={{ once: true }}
              >
                <Card className="p-8 h-full text-center hover:shadow-card transition-shadow border-2 border-border rounded-card">
                  <div className="w-16 h-16 bg-[#8FAF8A]/10 rounded-full flex items-center justify-center mx-auto mb-6">
                    <value.icon className="w-8 h-8 text-[#234632]" />
                  </div>
                  <h3 className="text-xl font-bold text-arbore-ink mb-4">
                    {value.title}
                  </h3>
                  <p className="text-arbore-muted leading-relaxed">
                    {value.description}
                  </p>
                </Card>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      <section className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-12">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6 }}
              viewport={{ once: true }}
            >
              <h2 className="text-4xl font-bold text-[#234632] mb-4">
                L&apos;équipe fondatrice
              </h2>
              <p className="text-xl text-arbore-muted">
                Deux passionnés qui transforment le jardinage
              </p>
            </motion.div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            {team.map((member, index) => (
              <motion.div
                key={index}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
                viewport={{ once: true }}
              >
                <Card className="p-8 h-full hover:shadow-card transition-shadow border-2 border-border rounded-card">
                  <div className="w-24 h-24 bg-gradient-to-br from-[#234632] to-[#8FAF8A] rounded-full mx-auto mb-6 flex items-center justify-center">
                    <span className="text-4xl font-bold text-white">
                      {member.name.split(' ').map(n => n[0]).join('')}
                    </span>
                  </div>
                  <h3 className="text-2xl font-bold text-arbore-ink mb-2 text-center">
                    {member.name}
                  </h3>
                  <p className="text-[#234632] font-semibold mb-4 text-center">
                    {member.role}
                  </p>
                  <p className="text-arbore-muted leading-relaxed text-center">
                    {member.bio}
                  </p>
                </Card>
              </motion.div>
            ))}
          </div>
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
              Rejoignez l&apos;aventure
            </h2>
            <p className="text-xl text-green-100 mb-8">
              Nous sommes toujours à l&apos;écoute de vos retours.
              Ils nous aident à améliorer Arbore chaque jour.
            </p>
            <button className="bg-white text-[#234632] hover:bg-gray-100 px-8 py-4 rounded-full font-semibold text-lg transition-colors">
              Nous contacter
            </button>
          </motion.div>
        </div>
      </section>

      <Footer />
    </main>
  );
}
