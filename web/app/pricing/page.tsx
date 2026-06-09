'use client';

import { motion } from 'framer-motion';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { Card } from '@/components/ui/card';
import { Check } from 'lucide-react';

const plans = [
  {
    name: 'Gratuit',
    price: '0€',
    period: 'pour toujours',
    description: 'Parfait pour découvrir Arbore',
    features: [
      '1 projet de jardin',
      '3 scans par mois',
      'Styles de base',
      'Calendrier d\'entretien simple',
      'Accès à la communauté',
    ],
    cta: 'Commencer gratuitement',
    popular: false,
  },
  {
    name: 'Premium',
    price: '4,99€',
    period: 'par mois',
    description: 'Pour les jardiniers passionnés',
    features: [
      'Projets illimités',
      'Scans illimités',
      'Tous les styles et designs',
      'Visualisation 3D avancée',
      'Calendrier intelligent',
      'Recommandations IA personnalisées',
      'Support prioritaire',
      'Sans publicité',
      'Export haute résolution',
    ],
    cta: 'Essayer Premium',
    popular: true,
  },
];

export default function PricingPage() {
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
              Tarifs simples et transparents
            </h1>
            <p className="text-xl text-arbore-muted">
              Les tarifs qui s&apos;appliqueront après la bêta
            </p>
            <div className="mt-6 inline-flex items-center gap-2 rounded-pill bg-secondary px-5 py-2.5 text-sm font-semibold text-arbore-green">
              🌱 Pendant la bêta publique, Arbore est entièrement gratuit — aucun abonnement requis.
            </div>
          </motion.div>
        </div>
      </section>

      <section className="py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
            {plans.map((plan, index) => (
              <motion.div
                key={index}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
                viewport={{ once: true }}
                className={plan.popular ? 'lg:scale-105' : ''}
              >
                <Card
                  className={`p-8 h-full rounded-3xl ${
                    plan.popular
                      ? 'border-4 border-[#234632] shadow-2xl bg-white'
                      : 'border-2 border-border'
                  }`}
                >
                  {plan.popular && (
                    <div className="bg-[#8FAF8A] text-white text-sm font-bold px-4 py-2 rounded-full inline-block mb-4">
                      Le plus populaire
                    </div>
                  )}

                  <h3 className="text-2xl font-bold text-arbore-ink mb-2">
                    {plan.name}
                  </h3>
                  <p className="text-arbore-muted mb-6">{plan.description}</p>

                  <div className="mb-8">
                    <span className="text-5xl font-bold text-[#234632]">
                      {plan.price}
                    </span>
                    <span className="text-arbore-muted ml-2">{plan.period}</span>
                  </div>

                  <div className="mb-8 h-px w-full bg-border" />

                  <ul className="space-y-4">
                    {plan.features.map((feature, featureIndex) => (
                      <li key={featureIndex} className="flex items-start gap-3">
                        <div className="w-6 h-6 bg-[#8FAF8A]/20 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                          <Check className="w-4 h-4 text-[#234632]" />
                        </div>
                        <span className="text-arbore-ink">{feature}</span>
                      </li>
                    ))}
                  </ul>
                </Card>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-white/50">
        <div className="max-w-4xl mx-auto">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            viewport={{ once: true }}
            className="text-center"
          >
            <h2 className="text-3xl font-bold text-[#234632] mb-6">
              Questions fréquentes
            </h2>
            <div className="space-y-6 text-left">
              <div>
                <h3 className="text-xl font-semibold text-arbore-ink mb-2">
                  Puis-je changer de plan à tout moment ?
                </h3>
                <p className="text-arbore-muted">
                  Oui, vous pouvez passer à Premium ou revenir au plan gratuit à tout moment.
                  Aucun engagement, vous pouvez annuler quand vous voulez.
                </p>
              </div>
              <div>
                <h3 className="text-xl font-semibold text-arbore-ink mb-2">
                  Combien coûte Arbore pendant la bêta ?
                </h3>
                <p className="text-arbore-muted">
                  Rien : pendant la bêta publique, toutes les fonctionnalités sont gratuites.
                  Les abonnements ci-dessus ne s&apos;activeront qu&apos;après la bêta.
                </p>
              </div>
              <div>
                <h3 className="text-xl font-semibold text-arbore-ink mb-2">
                  Y a-t-il un paiement à prévoir ?
                </h3>
                <p className="text-arbore-muted">
                  Non. Arbore est une bêta étudiante gratuite et non commerciale : aucun
                  paiement, aucun abonnement, aucun moyen de paiement n&apos;est demandé. Les
                  tarifs ci-dessus sont indicatifs pour l&apos;après-bêta.
                </p>
              </div>
            </div>
          </motion.div>
        </div>
      </section>

      <Footer />
    </main>
  );
}
