'use client';

import { motion } from 'framer-motion';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
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
    price: '3,99€',
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
            <h1 className="text-5xl md:text-6xl font-bold text-[#2D5A27] mb-6">
              Tarifs simples et transparents
            </h1>
            <p className="text-xl text-gray-600">
              Choisissez le plan qui correspond à vos besoins
            </p>
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
                      ? 'border-4 border-[#2D5A27] shadow-2xl bg-white'
                      : 'border-2 border-gray-200'
                  }`}
                >
                  {plan.popular && (
                    <div className="bg-[#84CC16] text-white text-sm font-bold px-4 py-2 rounded-full inline-block mb-4">
                      Le plus populaire
                    </div>
                  )}

                  <h3 className="text-2xl font-bold text-gray-900 mb-2">
                    {plan.name}
                  </h3>
                  <p className="text-gray-600 mb-6">{plan.description}</p>

                  <div className="mb-8">
                    <span className="text-5xl font-bold text-[#2D5A27]">
                      {plan.price}
                    </span>
                    <span className="text-gray-600 ml-2">{plan.period}</span>
                  </div>

                  <Button
                    className={`w-full py-6 text-lg rounded-full mb-8 ${
                      plan.popular
                        ? 'bg-[#2D5A27] hover:bg-[#234520] text-white'
                        : 'bg-white border-2 border-[#2D5A27] text-[#2D5A27] hover:bg-[#2D5A27] hover:text-white'
                    }`}
                  >
                    {plan.cta}
                  </Button>

                  <ul className="space-y-4">
                    {plan.features.map((feature, featureIndex) => (
                      <li key={featureIndex} className="flex items-start gap-3">
                        <div className="w-6 h-6 bg-[#84CC16]/20 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                          <Check className="w-4 h-4 text-[#2D5A27]" />
                        </div>
                        <span className="text-gray-700">{feature}</span>
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
            <h2 className="text-3xl font-bold text-[#2D5A27] mb-6">
              Questions fréquentes
            </h2>
            <div className="space-y-6 text-left">
              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">
                  Puis-je changer de plan à tout moment ?
                </h3>
                <p className="text-gray-600">
                  Oui, vous pouvez passer à Premium ou revenir au plan gratuit à tout moment.
                  Aucun engagement, vous pouvez annuler quand vous voulez.
                </p>
              </div>
              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">
                  Y a-t-il une période d&apos;essai ?
                </h3>
                <p className="text-gray-600">
                  Oui, vous bénéficiez de 7 jours d&apos;essai gratuit sur le plan Premium pour tester toutes les fonctionnalités.
                </p>
              </div>
              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">
                  Quels moyens de paiement acceptez-vous ?
                </h3>
                <p className="text-gray-600">
                  Nous acceptons toutes les cartes bancaires (Visa, Mastercard, American Express) ainsi que PayPal.
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
