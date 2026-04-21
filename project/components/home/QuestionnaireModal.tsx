'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { X, Sprout, Leaf, TreePine, Building2, Home, Trees, Flower, Carrot, Droplet, Cherry, Package, Search, BookOpen, TrendingUp, Stethoscope, Heart, Moon, Cloud, Sun, Clock } from 'lucide-react';

interface QuestionnaireModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const questions = [
  {
    id: 1,
    title: "Quel est votre niveau d'expérience en jardinage ?",
    subtitle: "Pour adapter nos conseils à votre niveau",
    options: [
      { label: 'Débutant total', description: "C'est ma première fois", icon: Sprout },
      { label: 'Novice', description: 'J\'ai 1-2 plantes', icon: Leaf },
      { label: 'Intermédiaire', description: 'J\'ai plusieurs plantes', icon: Leaf },
      { label: 'Expert', description: 'Main verte confirmée', icon: TreePine },
    ],
  },
  {
    id: 2,
    title: 'Où souhaitez-vous cultiver vos plantes ?',
    subtitle: 'Sélectionnez tous les espaces dont vous disposez',
    options: [
      { label: 'Appartement', description: 'Plantes d\'intérieur uniquement', icon: Building2 },
      { label: 'Balcon/Terrasse', description: 'Petit espace extérieur', icon: Home },
      { label: 'Petit jardin', description: 'Moins de 50m²', icon: Trees },
      { label: 'Grand jardin', description: 'Plus de 50m²', icon: TreePine },
    ],
  },
  {
    id: 3,
    title: 'Quels types de plantes vous attirent ?',
    subtitle: 'Choisissez toutes les options qui vous intéressent',
    options: [
      { label: 'Plantes d\'intérieur', description: 'Pothos, Monstera, Ficus...', icon: Leaf },
      { label: 'Fleurs', description: 'Roses, orchidées, tulipes...', icon: Flower },
      { label: 'Légumes', description: 'Tomates, salades, courgettes...', icon: Carrot },
      { label: 'Herbes aromatiques', description: 'Basilic, menthe, persil...', icon: Sprout },
      { label: 'Succulentes', description: 'Cactus, aloé vera, echeveria...', icon: Droplet },
      { label: 'Fruits', description: 'Fraises, agrumes, arbres fruitiers...', icon: Cherry },
    ],
  },
  {
    id: 4,
    title: "Qu'espérez-vous accomplir avec Arbore ?",
    subtitle: 'Vos objectifs nous aident à personnaliser l\'application',
    options: [
      { label: 'Organiser', description: 'Calendrier d\'arrosage et rappels', icon: Package },
      { label: 'Identifier', description: 'Reconnaître mes plantes', icon: Search },
      { label: 'Apprendre', description: 'Conseils et techniques', icon: BookOpen },
      { label: 'Suivre l\'évolution', description: 'Croissance et santé', icon: TrendingUp },
      { label: 'Diagnostiquer', description: 'Détecter maladies et problèmes', icon: Stethoscope },
      { label: 'Partager', description: 'Communauté et inspiration', icon: Heart },
    ],
  },
  {
    id: 5,
    title: 'Quelle est l\'exposition de votre espace ?',
    subtitle: 'Pour vous recommander les bonnes plantes',
    options: [
      { label: 'Peu lumineux', description: 'Places sombres, peu de fenêtres', icon: Moon },
      { label: 'Lumière indirecte', description: 'Lumineux sans soleil direct', icon: Cloud },
      { label: 'Mi-ombre', description: 'Quelques heures de soleil', icon: Cloud },
      { label: 'Plein soleil', description: 'Plus de 6h de soleil direct', icon: Sun },
    ],
  },
  {
    id: 6,
    title: 'Combien de temps pouvez-vous consacrer à vos plantes ?',
    subtitle: 'Par semaine en moyenne',
    options: [
      { label: 'Moins de 30 min', description: 'Entretien minimal', icon: Clock },
      { label: '30 min - 2h', description: 'Entretien régulier', icon: Clock },
      { label: 'Plus de 2h', description: 'Passion jardinage', icon: Sprout },
    ],
  },
];

export function QuestionnaireModal({ isOpen, onClose }: QuestionnaireModalProps) {
  const [currentStep, setCurrentStep] = useState(0);
  const router = useRouter();

  const handleNext = () => {
    if (currentStep < questions.length - 1) {
      setCurrentStep(currentStep + 1);
    } else {
      // Récupérer le nom d'utilisateur depuis le localStorage
      const userName = localStorage.getItem('userName') || 'Utilisateur';
      localStorage.setItem('userName', userName);
      // Rediriger vers la page de bienvenue
      router.push('/welcome');
    }
  };

  const handlePrevious = () => {
    if (currentStep > 0) {
      setCurrentStep(currentStep - 1);
    }
  };

  const currentQuestion = questions[currentStep];
  const progress = ((currentStep + 1) / questions.length) * 100;

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50"
          onClick={onClose}
        >
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20 }}
            onClick={(e) => e.stopPropagation()}
            className="bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto"
          >
            {/* Header */}
            <div className="sticky top-0 bg-white border-b border-gray-200 p-6 flex items-center justify-between">
              <div>
                <h2 className="text-2xl font-bold text-[#2D5A27]">Parlons de votre jardin</h2>
                <p className="text-sm text-gray-600">Quelques questions pour vous proposer les meilleurs conseils</p>
              </div>
              <button
                onClick={onClose}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            {/* Progress Bar */}
            <div className="h-1 bg-gray-200">
              <motion.div
                initial={{ width: 0 }}
                animate={{ width: `${progress}%` }}
                transition={{ duration: 0.3 }}
                className="h-full bg-[#2D5A27]"
              />
            </div>

            {/* Step Indicator */}
            <div className="px-6 py-4 border-b border-gray-200">
              <div className="flex gap-2 justify-center">
                {questions.map((_, index) => (
                  <motion.div
                    key={index}
                    initial={{ opacity: 0.5 }}
                    animate={{
                      opacity: index === currentStep ? 1 : 0.5,
                      backgroundColor: index <= currentStep ? '#2D5A27' : '#e5e7eb',
                    }}
                    className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold"
                    style={{
                      color: index <= currentStep ? '#ffffff' : '#6b7280',
                    }}
                  >
                    {index + 1}
                  </motion.div>
                ))}
              </div>
            </div>

            {/* Content */}
            <motion.div
              key={currentStep}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              className="p-8"
            >
              <h3 className="text-2xl font-bold text-[#2D5A27] mb-2">
                {currentQuestion.title}
              </h3>
              <p className="text-gray-600 mb-8">{currentQuestion.subtitle}</p>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                {currentQuestion.options.map((option, index) => {
                  const IconComponent = option.icon;
                  return (
                    <motion.button
                      key={index}
                      whileHover={{ scale: 1.02 }}
                      whileTap={{ scale: 0.98 }}
                      className="p-4 border-2 border-gray-300 rounded-lg hover:border-[#2D5A27] hover:bg-[#2D5A27]/5 transition-all text-center"
                    >
                      <IconComponent className="w-12 h-12 text-[#2D5A27] mx-auto mb-3" />
                      <div className="font-semibold text-[#2D5A27]">{option.label}</div>
                      <div className="text-sm text-gray-600">{option.description}</div>
                    </motion.button>
                  );
                })}
              </div>
            </motion.div>

            {/* Footer */}
            <div className="border-t border-gray-200 p-6 flex items-center justify-between gap-4 bg-gray-50">
              <button
                onClick={onClose}
                className="text-[#2D5A27] hover:underline text-sm font-medium"
              >
                Passer le questionnaire →
              </button>
              <div className="flex gap-4">
                {currentStep > 0 && (
                  <Button
                    variant="outline"
                    onClick={handlePrevious}
                    className="border-[#2D5A27] text-[#2D5A27]"
                  >
                    ← Précédent
                  </Button>
                )}
                <Button
                  onClick={handleNext}
                  className="bg-[#2D5A27] hover:bg-[#234520] text-white"
                >
                  {currentStep === questions.length - 1 ? 'Créer mon compte ✓' : 'Suivant →'}
                </Button>
              </div>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
