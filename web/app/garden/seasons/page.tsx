'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { getCurrentUser } from '@/lib/authService';
import { API_URL, fetchWithAuth } from '@/lib/api';
import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import {
  ArrowLeft,
  Snowflake,
  Flower,
  Sun,
  Leaf,
  Cloud,
  Droplet,
  Wind,
  Thermometer,
  Calendar,
  AlertCircle,
  Info
} from 'lucide-react';
import { motion } from 'framer-motion';

interface SeasonTask {
  title: string;
  description: string;
  priority: 'haute' | 'moyenne' | 'basse';
}

interface SeasonInfo {
  name: string;
  months: string;
  icon: any;
  color: string;
  bgGradient: string;
  temperature: string;
  rainfall: string;
  daylight: string;
  description: string;
  tasks: SeasonTask[];
  tips: string[];
  plants: string[];
}

const seasons: SeasonInfo[] = [
  {
    name: 'Printemps',
    months: 'Mars - Mai',
    icon: Flower,
    color: 'from-pink-400 to-green-400',
    bgGradient: 'from-pink-50 to-green-50',
    temperature: '10°C - 20°C',
    rainfall: 'Modérée',
    daylight: '12h - 15h',
    description: 'La saison du renouveau, parfaite pour les semis et les plantations. La nature se réveille et c\'est le moment idéal pour préparer votre jardin.',
    tasks: [
      {
        title: 'Préparer le sol',
        description: 'Retourner la terre, enrichir avec du compost',
        priority: 'haute'
      },
      {
        title: 'Semer les légumes',
        description: 'Tomates, courgettes, salades, carottes',
        priority: 'haute'
      },
      {
        title: 'Tailler les arbustes',
        description: 'Après les gelées, tailler rosiers et arbustes',
        priority: 'moyenne'
      },
      {
        title: 'Diviser les vivaces',
        description: 'C\'est le bon moment pour multiplier vos plantes',
        priority: 'basse'
      }
    ],
    tips: [
      'Protégez les jeunes plants des gelées tardives',
      'Arrosez régulièrement mais modérément',
      'Surveillez l\'apparition des parasites',
      'Paillez pour garder l\'humidité'
    ],
    plants: ['Tomates', 'Courgettes', 'Salades', 'Radis', 'Carottes', 'Haricots', 'Roses', 'Tulipes']
  },
  {
    name: 'Été',
    months: 'Juin - Août',
    icon: Sun,
    color: 'from-yellow-400 to-orange-500',
    bgGradient: 'from-yellow-50 to-orange-50',
    temperature: '20°C - 35°C',
    rainfall: 'Faible à modérée',
    daylight: '15h - 16h',
    description: 'La saison chaude et ensoleillée. Les plantes sont en pleine croissance et nécessitent un arrosage régulier et un entretien constant.',
    tasks: [
      {
        title: 'Arroser régulièrement',
        description: 'Tôt le matin ou tard le soir, arrosage profond',
        priority: 'haute'
      },
      {
        title: 'Récolter',
        description: 'Légumes, fruits et herbes aromatiques',
        priority: 'haute'
      },
      {
        title: 'Désherber',
        description: 'Éliminer les mauvaises herbes régulièrement',
        priority: 'moyenne'
      },
      {
        title: 'Fertiliser',
        description: 'Nourrir les plantes en pleine croissance',
        priority: 'moyenne'
      }
    ],
    tips: [
      'Arrosez en profondeur plutôt que fréquemment',
      'Paillez pour conserver l\'humidité',
      'Protégez du soleil brûlant si nécessaire',
      'Récoltez régulièrement pour stimuler la production'
    ],
    plants: ['Tomates', 'Concombres', 'Poivrons', 'Aubergines', 'Melons', 'Lavande', 'Tournesols', 'Géraniums']
  },
  {
    name: 'Automne',
    months: 'Septembre - Novembre',
    icon: Leaf,
    color: 'from-orange-500 to-red-600',
    bgGradient: 'from-orange-50 to-red-50',
    temperature: '10°C - 20°C',
    rainfall: 'Modérée à forte',
    daylight: '10h - 12h',
    description: 'La saison des récoltes et des préparations pour l\'hiver. C\'est le moment de planter les bulbes et de protéger le jardin.',
    tasks: [
      {
        title: 'Récolter les derniers légumes',
        description: 'Tomates, courges, pommes de terre',
        priority: 'haute'
      },
      {
        title: 'Planter les bulbes',
        description: 'Tulipes, narcisses, jacinthes pour le printemps',
        priority: 'haute'
      },
      {
        title: 'Nettoyer le jardin',
        description: 'Enlever les feuilles mortes et les plantes fanées',
        priority: 'moyenne'
      },
      {
        title: 'Protéger les plantes fragiles',
        description: 'Installer des voiles d\'hivernage',
        priority: 'moyenne'
      }
    ],
    tips: [
      'Compostez les feuilles mortes',
      'Rentrez les plantes sensibles au froid',
      'Plantez les arbres et arbustes',
      'Préparez le sol pour l\'hiver'
    ],
    plants: ['Choux', 'Poireaux', 'Épinards', 'Mâche', 'Chrysanthèmes', 'Asters', 'Pensées', 'Cyclamens']
  },
  {
    name: 'Hiver',
    months: 'Décembre - Février',
    icon: Snowflake,
    color: 'from-blue-300 to-blue-600',
    bgGradient: 'from-blue-50 to-arbore-gold/10',
    temperature: '-5°C - 10°C',
    rainfall: 'Variable (pluie/neige)',
    daylight: '8h - 10h',
    description: 'La saison du repos pour le jardin. C\'est le moment de planifier, entretenir les outils et protéger les plantes du froid.',
    tasks: [
      {
        title: 'Protéger du gel',
        description: 'Voiles d\'hivernage, paillage épais',
        priority: 'haute'
      },
      {
        title: 'Planifier la saison',
        description: 'Commander les graines, dessiner le plan du jardin',
        priority: 'moyenne'
      },
      {
        title: 'Entretenir les outils',
        description: 'Nettoyer, affûter, huiler',
        priority: 'basse'
      },
      {
        title: 'Tailler les arbres',
        description: 'Arbres fruitiers et d\'ornement (hors gel)',
        priority: 'moyenne'
      }
    ],
    tips: [
      'Évitez de marcher sur les pelouses gelées',
      'Continuez à arroser les plantes en pot',
      'Protégez les tuyaux d\'arrosage du gel',
      'Nourrissez les oiseaux du jardin'
    ],
    plants: ['Poireaux', 'Choux', 'Perce-neige', 'Hellébores', 'Houx', 'Gui', 'Bruyère d\'hiver', 'Jasmin d\'hiver']
  }
];

export default function SeasonsPage() {
  const [user, setUser] = useState<any>(null);
  const [allPlants, setAllPlants] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedSeason, setSelectedSeason] = useState<SeasonInfo | null>(null);
  const router = useRouter();

  useEffect(() => {
    const currentUser = getCurrentUser();
    if (!currentUser) {
      router.push('/login');
    } else {
      setUser(currentUser);
      setLoading(false);
      // Charger les vraies plantes du catalogue (pour la section "Plantes de saison").
      (async () => {
        try {
          const res = await fetchWithAuth(`${API_URL}/plants`);
          if (res.ok) setAllPlants((await res.json()) || []);
        } catch {
          /* catalogue indisponible -> fallback sur les suggestions */
        }
      })();
    }
  }, [router]);

  // Déterminer la saison actuelle
  useEffect(() => {
    const month = new Date().getMonth(); // 0-11
    let currentSeasonIndex = 0;

    if (month >= 2 && month <= 4) currentSeasonIndex = 0; // Printemps
    else if (month >= 5 && month <= 7) currentSeasonIndex = 1; // Été
    else if (month >= 8 && month <= 10) currentSeasonIndex = 2; // Automne
    else currentSeasonIndex = 3; // Hiver

    setSelectedSeason(seasons[currentSeasonIndex]);
  }, []);

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center pt-24">
          <div className="text-center">
            <div className="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-[#234632]"></div>
          </div>
        </div>
        <Footer />
      </>
    );
  }

  const getPriorityColor = (priority: string) => {
    switch(priority) {
      case 'haute': return 'bg-red-100 text-red-700 border-red-300';
      case 'moyenne': return 'bg-yellow-100 text-yellow-700 border-yellow-300';
      case 'basse': return 'bg-secondary text-green-700 border-green-300';
      default: return 'bg-gray-100 text-arbore-ink border-border';
    }
  };

  const getPriorityLabel = (priority: string) => {
    switch(priority) {
      case 'haute': return 'Priorité haute';
      case 'moyenne': return 'Priorité moyenne';
      case 'basse': return 'Priorité basse';
      default: return priority;
    }
  };

  // Vraies plantes du catalogue correspondant à la saison (matching par nom, accents/pluriel tolérés).
  const seasonRealPlants = (season: SeasonInfo) => {
    const norm = (s: string) =>
      s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/s$/, '');
    const roots = season.plants.map(norm);
    return allPlants
      .filter((p: any) => {
        const n = norm(p.name || '');
        return n.length > 1 && roots.some((r) => r.length > 1 && (n.includes(r) || r.includes(n)));
      })
      .slice(0, 8);
  };

  return (
    <>
      <Navbar />
      <main id="main-content" className="min-h-screen bg-arbore-beige pt-24 pb-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {/* Header */}
          <motion.div
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            className="mb-8"
          >
            <div className="flex items-center gap-4 mb-4">
              <button
                onClick={() => router.push('/garden')}
                className="flex items-center gap-2 text-arbore-muted hover:text-[#234632] transition-colors"
              >
                <ArrowLeft className="w-5 h-5" />
                <span>Retour au jardin</span>
              </button>
            </div>
            <h1 className="text-4xl md:text-5xl font-bold text-[#234632] mb-2">Guide des Saisons</h1>
            <p className="text-lg text-arbore-muted">Découvrez les tâches et conseils pour chaque saison</p>
          </motion.div>

          {/* Season Selector */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-12"
          >
            {seasons.map((season, index) => {
              const Icon = season.icon;
              const isSelected = selectedSeason?.name === season.name;

              return (
                <motion.button
                  key={season.name}
                  onClick={() => setSelectedSeason(season)}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className={`relative overflow-hidden rounded-card p-6 text-left transition-all ${
                    isSelected
                      ? 'shadow-2xl ring-4 ring-[#234632] ring-opacity-50'
                      : 'shadow-lg hover:shadow-card'
                  }`}
                >
                  <div className={`absolute inset-0 bg-gradient-to-br ${season.color} opacity-90`}></div>
                  <div className="relative z-10 text-white">
                    <Icon className="w-10 h-10 mb-3" />
                    <h3 className="text-2xl font-bold mb-1">{season.name}</h3>
                    <p className="text-sm opacity-90">{season.months}</p>
                  </div>
                  {isSelected && (
                    <motion.div
                      initial={{ scale: 0 }}
                      animate={{ scale: 1 }}
                      className="absolute top-3 right-3 z-20 bg-white rounded-full p-1"
                    >
                      <Calendar className="w-5 h-5 text-[#234632]" />
                    </motion.div>
                  )}
                </motion.button>
              );
            })}
          </motion.div>

          {/* Season Details */}
          {selectedSeason && (
            <motion.div
              key={selectedSeason.name}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5 }}
            >
              {/* Overview Card */}
              <div className={`bg-gradient-to-br ${selectedSeason.bgGradient} rounded-card shadow-xl p-8 mb-8 border-2 border-opacity-20`}>
                <div className="flex items-start gap-6 mb-6">
                  <div className={`bg-gradient-to-br ${selectedSeason.color} p-4 rounded-card`}>
                    {(() => {
                      const Icon = selectedSeason.icon;
                      return <Icon className="w-12 h-12 text-white" />;
                    })()}
                  </div>
                  <div className="flex-1">
                    <h2 className="text-4xl font-bold text-arbore-ink mb-2">
                      {selectedSeason.name}
                    </h2>
                    <p className="text-xl text-arbore-muted mb-4">{selectedSeason.months}</p>
                    <p className="text-lg text-arbore-ink leading-relaxed">
                      {selectedSeason.description}
                    </p>
                  </div>
                </div>

                {/* Weather Info */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div className="bg-white bg-opacity-60 rounded-card p-4 flex items-center gap-3">
                    <Thermometer className="w-8 h-8 text-red-500" />
                    <div>
                      <p className="text-sm text-arbore-muted font-medium">Température</p>
                      <p className="text-lg font-bold text-arbore-ink">{selectedSeason.temperature}</p>
                    </div>
                  </div>
                  <div className="bg-white bg-opacity-60 rounded-card p-4 flex items-center gap-3">
                    <Droplet className="w-8 h-8 text-blue-500" />
                    <div>
                      <p className="text-sm text-arbore-muted font-medium">Précipitations</p>
                      <p className="text-lg font-bold text-arbore-ink">{selectedSeason.rainfall}</p>
                    </div>
                  </div>
                  <div className="bg-white bg-opacity-60 rounded-card p-4 flex items-center gap-3">
                    <Sun className="w-8 h-8 text-yellow-500" />
                    <div>
                      <p className="text-sm text-arbore-muted font-medium">Ensoleillement</p>
                      <p className="text-lg font-bold text-arbore-ink">{selectedSeason.daylight}</p>
                    </div>
                  </div>
                </div>
              </div>

              <div className="grid lg:grid-cols-2 gap-8">
                {/* Tasks */}
                <div className="bg-white rounded-card shadow-lg p-8">
                  <div className="flex items-center gap-3 mb-6">
                    <div className="bg-[#234632] p-2 rounded-lg">
                      <AlertCircle className="w-6 h-6 text-white" />
                    </div>
                    <h3 className="text-2xl font-bold text-arbore-ink">Tâches principales</h3>
                  </div>
                  <div className="space-y-4">
                    {selectedSeason.tasks.map((task, index) => (
                      <motion.div
                        key={index}
                        initial={{ opacity: 0, x: -20 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: index * 0.1 }}
                        className="border-2 border-border rounded-card p-4 hover:border-[#234632] transition-all"
                      >
                        <div className="flex items-start justify-between mb-2">
                          <h4 className="font-bold text-arbore-ink text-lg">{task.title}</h4>
                          <span className={`text-xs px-2 py-1 rounded-full border font-semibold ${getPriorityColor(task.priority)}`}>
                            {getPriorityLabel(task.priority)}
                          </span>
                        </div>
                        <p className="text-arbore-muted">{task.description}</p>
                      </motion.div>
                    ))}
                  </div>
                </div>

                {/* Tips and Plants */}
                <div className="space-y-8">
                  {/* Tips */}
                  <div className="bg-white rounded-card shadow-lg p-8">
                    <div className="flex items-center gap-3 mb-6">
                      <div className="bg-blue-500 p-2 rounded-lg">
                        <Info className="w-6 h-6 text-white" />
                      </div>
                      <h3 className="text-2xl font-bold text-arbore-ink">Conseils</h3>
                    </div>
                    <ul className="space-y-3">
                      {selectedSeason.tips.map((tip, index) => (
                        <motion.li
                          key={index}
                          initial={{ opacity: 0, x: 20 }}
                          animate={{ opacity: 1, x: 0 }}
                          transition={{ delay: index * 0.1 }}
                          className="flex items-start gap-3 text-arbore-ink"
                        >
                          <span className="text-[#234632] mt-1">✓</span>
                          <span>{tip}</span>
                        </motion.li>
                      ))}
                    </ul>
                  </div>

                  {/* Plants */}
                  <div className="bg-white rounded-card shadow-lg p-8">
                    <div className="flex items-center gap-3 mb-6">
                      <div className="bg-green-500 p-2 rounded-lg">
                        <Leaf className="w-6 h-6 text-white" />
                      </div>
                      <h3 className="text-2xl font-bold text-arbore-ink">Plantes de saison</h3>
                    </div>
                    {(() => {
                      const real = seasonRealPlants(selectedSeason);
                      if (real.length > 0) {
                        return (
                          <>
                            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                              {real.map((p: any) => (
                                <button
                                  key={p.id}
                                  onClick={() => router.push(`/garden/plant/${p.id}?from=seasons`)}
                                  className="group overflow-hidden rounded-card border border-border bg-card text-left shadow-soft transition hover:shadow-card"
                                >
                                  <div className="h-24 overflow-hidden bg-arbore-soft">
                                    {p.imageURLs?.[0] ? (
                                      // eslint-disable-next-line @next/next/no-img-element
                                      <img loading="lazy" decoding="async" src={p.imageURLs[0]} alt={p.name} className="h-full w-full object-cover transition-transform group-hover:scale-105" />
                                    ) : (
                                      <div className="flex h-full items-center justify-center"><Leaf className="h-8 w-8 text-arbore-sage" /></div>
                                    )}
                                  </div>
                                  <p className="truncate px-2.5 py-2 text-sm font-semibold text-arbore-ink">{p.name}</p>
                                </button>
                              ))}
                            </div>
                            <Link href="/garden/catalogue" className="mt-4 inline-block text-sm font-semibold text-arbore-green hover:underline">
                              Voir tout le catalogue →
                            </Link>
                          </>
                        );
                      }
                      return (
                        <>
                          <p className="mb-3 text-sm text-arbore-muted">Suggestions pour cette saison :</p>
                          <div className="flex flex-wrap gap-2">
                            {selectedSeason.plants.map((plant, index) => (
                              <span key={index} className="rounded-pill bg-secondary px-4 py-2 text-sm font-semibold text-arbore-green">
                                {plant}
                              </span>
                            ))}
                          </div>
                          <Link href="/garden/catalogue" className="mt-4 inline-block text-sm font-semibold text-arbore-green hover:underline">
                            Explorer le catalogue →
                          </Link>
                        </>
                      );
                    })()}
                  </div>
                </div>
              </div>
            </motion.div>
          )}
        </div>
      </main>
      <Footer />
    </>
  );
}
