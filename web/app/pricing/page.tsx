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
      'Sans publicité',
    ],
    cta: 'Commencer gratuitement',
    popular: false,
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
              Arbore ne propose actuellement ni abonnement ni achat intégré.
            </p>
            <div className="mt-6 inline-flex items-center gap-2 rounded-pill bg-secondary px-5 py-2.5 text-sm font-semibold text-arbore-green">
              🌱 Toutes les fonctionnalités actuellement disponibles sont gratuites.
            </div>
          </motion.div>
        </div>
      </section>

      <section className="py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto">
          <div className="mx-auto grid max-w-xl grid-cols-1 gap-8">
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
                  Arbore propose-t-il un abonnement ?
                </h3>
                <p className="text-arbore-muted">
                  Non. Aucun abonnement ni achat intégré n&apos;est actuellement proposé.
                </p>
              </div>
              <div>
                <h3 className="text-xl font-semibold text-arbore-ink mb-2">
                  Combien coûte Arbore actuellement ?
                </h3>
                <p className="text-arbore-muted">
                  L&apos;application et ses fonctionnalités disponibles sont gratuites.
                </p>
              </div>
              <div>
                <h3 className="text-xl font-semibold text-arbore-ink mb-2">
                  Y a-t-il un paiement à prévoir ?
                </h3>
                <p className="text-arbore-muted">
                  Non. Aucun paiement, abonnement ou moyen de paiement n&apos;est demandé.
                  Toute évolution de cette politique sera annoncée avant son entrée en vigueur.
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
