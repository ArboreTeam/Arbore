# App Store Connect — textes de listing (#206)

Textes prêts à coller dans App Store Connect → **App Information** + **Version Information**, en 4 langues (FR / EN / ES / DE). Limites Apple respectées (sous-titre ≤ 30, mots-clés ≤ 100, description ≤ 4000, nouveautés ≤ 4000 mais on vise ~500, texte promo ≤ 170).

> Périmètre volontairement limité aux features **fonctionnelles** : design de jardin en AR, suggestions de plantes, catalogue + guides d'entretien, rappels d'arrosage, test de lumière. **Le scan/identification de plante (#11) est volontairement omis** tant qu'il n'est pas terminé (Apple reject toute feature annoncée non fonctionnelle). À rajouter une fois livré.

## Champs communs (App Information)
- **Catégorie principale** : Lifestyle — **secondaire** : Reference (optionnel)
- **Age rating** : 4+ (aucun contenu sensible)
- **Privacy Policy URL** : `https://arbore.app/privacy`
- **Marketing URL** : `https://arbore.app`
- **Support URL** : `https://arbore.app` tant que la page `/support` n'est pas publiée. Ajouter aussi `contact@arbore.app` dans les notes de review.
- **Content rights** : oui (droits sur les modèles 3D + plantes générées)

## App Privacy — réponses à reporter dans App Store Connect

Arbore ne pratique aucun suivi inter-apps et n'utilise aucune donnée pour la publicité. Déclarer les catégories suivantes comme liées à l'identité et utilisées pour les fonctionnalités de l'app :

- coordonnées : adresse e-mail ;
- informations de contact : nom ;
- identifiants : identifiant utilisateur Firebase ;
- localisation : localisation approximative ;
- contenu utilisateur : photos ou vidéos et autre contenu utilisateur (jardins, réponses, messages IA) ;
- diagnostics : données de crash et autres données de diagnostic, uniquement lorsque le consentement Sentry est activé.

Répondre « non » au tracking. La caméra/LiDAR brute, le mouvement et les WorldMaps restant sur l'appareil ne sont pas des données collectées. Cette section, `PrivacyInfo.xcprivacy`, la politique publique version 2.2 et le texte in-app doivent évoluer ensemble.

## Compte démo Apple Reviewer (App Review Information → Sign-In required)
Compte créé en prod (Firebase Auth `emailVerified=true` + record Mongo), login vérifié de bout en bout.

| Champ | Valeur |
|---|---|
| **User Name** | `appstore.review@arbore.app` |
| **Password** | _hors git_ — local : `fastlane/metadata/review_information/demo_password.txt` (gitignored) ; ou gestionnaire de mots de passe de l'équipe / `ARBORE_DEMO_PASSWORD` |

- uid : `ioBLddNo0aXcJqjJLnOz4Yjjzg83`
- Cocher **« Sign-in required »** et coller ces identifiants.
- Note de review suggérée : *"Use the demo account above to sign in. Create a garden, choose the space type, measure its boundary, capture the main light direction when requested, and provide an approximate location or city. Answer the three short environment questions, open the catalog (adapted plants are enabled by default), then place a plant in AR. The camera is required for measurement and AR; LiDAR is used only on compatible devices. Approximate location is optional because a city can be entered manually."*

---

## 🇫🇷 Français (fr-FR)

**Sous-titre** (≤30) :
```
Composez votre jardin en RA
```

**Mots-clés** (≤100) :
```
jardin,plantes,RA,jardinage,entretien,arrosage,3D,design,plante,paysage,rappel,botanique,LiDAR
```

**Description** :
```
Arbore est votre compagnon de jardinage intelligent — concevez, faites pousser et entretenez vos plantes en toute simplicité, que vous ayez la main verte ou que vous débutiez.

CONCEVEZ VOTRE FUTUR JARDIN EN RÉALITÉ AUGMENTÉE
Mesurez votre espace, indiquez sa lumière et quelques contraintes essentielles, puis laissez Arbore mettre en avant les plantes adaptées. Placez ensuite des plantes 3D à l'échelle directement dans votre pièce ou votre jardin, et disposez-les jusqu'à ce que tout soit parfait.

DES SUGGESTIONS DE PLANTES SUR MESURE
Obtenez une sélection personnalisée selon votre exposition, votre niveau d'entretien et l'harmonie de votre espace — aucune expertise requise.

L'ENTRETIEN EN TOUTE SIMPLICITÉ
Parcourez un catalogue riche avec des guides d'entretien détaillés, et n'oubliez plus jamais d'arroser grâce aux rappels d'arrosage par plante.

MESUREZ VOTRE LUMIÈRE
Évaluez la luminosité d'un emplacement et trouvez les plantes qui s'y épanouiront.

LA CONFIDENTIALITÉ D'ABORD
Arbore ne diffuse aucune publicité, ne suit pas votre activité entre applications et ne propose aucun achat intégré. La localisation approximative n'est enregistrée que pour adapter un jardin. Les diagnostics techniques sont facultatifs.

Cultivez en harmonie. 🌱
```

**Nouveautés / What's New** :
```
Bienvenue dans Arbore ! 🌱

• Concevez votre jardin en RA : placez des plantes 3D à l'échelle dans votre espace et disposez-les librement.
• Placement automatique amélioré qui agence vos plantes pour vous.
• Suggestions de plantes personnalisées via un court questionnaire.
• Catalogue de plantes avec guides d'entretien et rappels d'arrosage.
• Connexion avec Apple ou Google.

Merci de tester — vos retours façonnent la suite !
```

**Texte promotionnel** (≤170) :
```
Concevez votre futur jardin en réalité augmentée, recevez des suggestions adaptées à votre espace et gardez chaque plante en pleine forme.
```

---

## 🇬🇧 English (en-US)

**Subtitle** (≤30) :
```
Design your garden in AR
```

**Keywords** (≤100) :
```
garden,plants,AR,gardening,care,watering,3D,design,houseplant,landscape,reminder,botany,LiDAR
```

**Description** :
```
Arbore is your smart gardening companion — design, grow, and care for your plants with ease, whether you're a seasoned gardener or just starting out.

DESIGN YOUR FUTURE GARDEN IN AR
Measure your space, record its light, and answer a few essential questions so Arbore can highlight suitable plants. Then place true-to-scale 3D plants right in your room or garden with augmented reality, and arrange them until it feels just right.

SMART PLANT SUGGESTIONS
Get a personalized selection based on your exposure, maintenance level, and the harmony of your space — no green thumb required.

CARE MADE SIMPLE
Browse a rich plant catalog with detailed care guides, and never forget to water again thanks to per-plant watering reminders.

MEASURE YOUR LIGHT
Gauge the light in a spot and find the plants that will thrive there.

PRIVACY FIRST
Arbore has no ads, no cross-app tracking and no in-app purchases. Approximate location is stored only to adapt a garden. Technical diagnostics are optional.

Grow with harmony. 🌱
```

**What's New** :
```
Welcome to Arbore! 🌱

• Design your garden in AR: place true-to-scale 3D plants in your space and arrange them freely.
• Smarter automatic placement that lays out your selected plants for you.
• Personalized plant suggestions from a quick questionnaire.
• Plant catalog with care guides and watering reminders.
• Sign in with Apple or Google.

Thanks for testing — your feedback shapes what comes next!
```

**Promotional text** (≤170) :
```
Design your future garden in augmented reality, get plant suggestions tailored to your space, and keep every plant thriving.
```

---

## 🇪🇸 Español (es-ES)

**Subtítulo** (≤30) :
```
Diseña tu jardín en RA
```

**Palabras clave** (≤100) :
```
jardín,plantas,RA,jardinería,cuidado,riego,3D,diseño,planta,paisaje,recordatorio,botánica,LiDAR
```

**Descripción** :
```
Arbore es tu compañero de jardinería inteligente: diseña, cultiva y cuida tus plantas con facilidad, tengas o no mano para las plantas.

DISEÑA TU FUTURO JARDÍN EN REALIDAD AUMENTADA
Mide tu espacio, registra su luz y responde unas preguntas esenciales para que Arbore destaque las plantas adecuadas. Luego coloca plantas 3D a escala real en tu habitación o jardín con realidad aumentada y organízalas hasta que todo encaje.

SUGERENCIAS DE PLANTAS A TU MEDIDA
Recibe una selección personalizada según tu exposición, tu nivel de mantenimiento y la armonía de tu espacio, sin necesidad de experiencia.

EL CUIDADO, MÁS FÁCIL
Explora un completo catálogo con guías de cuidado detalladas y no vuelvas a olvidar el riego gracias a los recordatorios por planta.

MIDE TU LUZ
Evalúa la luz de un lugar y encuentra las plantas que prosperarán allí.

PRIVACIDAD ANTE TODO
Arbore no contiene publicidad, seguimiento entre aplicaciones ni compras integradas. La ubicación aproximada solo se guarda para adaptar un jardín. Los diagnósticos técnicos son opcionales.

Cultiva en armonía. 🌱
```

**Novedades** :
```
¡Te damos la bienvenida a Arbore! 🌱

• Diseña tu jardín en RA: coloca plantas 3D a escala real en tu espacio y organízalas a tu gusto.
• Colocación automática mejorada que distribuye tus plantas por ti.
• Sugerencias de plantas personalizadas con un breve cuestionario.
• Catálogo de plantas con guías de cuidado y recordatorios de riego.
• Inicia sesión con Apple o Google.

¡Gracias por probar! Tus comentarios definen lo que viene.
```

**Texto promocional** (≤170) :
```
Diseña tu futuro jardín en realidad aumentada, recibe sugerencias para tu espacio y mantén cada planta sana.
```

---

## 🇩🇪 Deutsch (de-DE)

**Untertitel** (≤30) :
```
Gestalte deinen Garten in AR
```

**Schlüsselwörter** (≤100) :
```
Garten,Pflanzen,AR,Gärtnern,Pflege,Gießen,3D,Design,Zimmerpflanze,Landschaft,Erinnerung,Botanik
```

**Beschreibung** :
```
Arbore ist dein smarter Garten-Begleiter: Gestalte, ziehe und pflege deine Pflanzen ganz einfach – egal ob mit grünem Daumen oder als Anfänger.

GESTALTE DEINEN ZUKÜNFTIGEN GARTEN IN AUGMENTED REALITY
Vermesse deinen Raum, erfasse das Licht und beantworte einige wichtige Fragen, damit Arbore geeignete Pflanzen hervorheben kann. Platziere anschließend maßstabsgetreue 3D-Pflanzen direkt in deinem Zimmer oder Garten und ordne sie an, bis alles stimmt.

PASSENDE PFLANZEN-VORSCHLÄGE
Erhalte eine persönliche Auswahl nach Lichtverhältnissen, Pflegeaufwand und der Harmonie deines Raums – ganz ohne Vorkenntnisse.

PFLEGE LEICHT GEMACHT
Durchstöbere einen umfangreichen Katalog mit detaillierten Pflegeanleitungen und vergiss dank Gieß-Erinnerungen pro Pflanze nie wieder das Gießen.

MISS DEIN LICHT
Bewerte das Licht an einem Ort und finde die Pflanzen, die dort gedeihen.

DATENSCHUTZ ZUERST
Arbore enthält keine Werbung, kein app-übergreifendes Tracking und keine In-App-Käufe. Der ungefähre Standort wird nur zur Anpassung eines Gartens gespeichert. Technische Diagnosen sind optional.

Wachse in Harmonie. 🌱
```

**Neues** :
```
Willkommen bei Arbore! 🌱

• Gestalte deinen Garten in AR: platziere maßstabsgetreue 3D-Pflanzen in deinem Raum und ordne sie frei an.
• Verbesserte automatische Platzierung, die deine Pflanzen für dich anordnet.
• Persönliche Pflanzen-Vorschläge über einen kurzen Fragebogen.
• Pflanzenkatalog mit Pflegeanleitungen und Gieß-Erinnerungen.
• Anmeldung mit Apple oder Google.

Danke fürs Testen – dein Feedback gestaltet die Zukunft!
```

**Werbetext** (≤170) :
```
Gestalte deinen zukünftigen Garten in Augmented Reality, erhalte passende Vorschläge für deinen Raum und halte jede Pflanze gesund.
```

---

## Assets restants (non-texte, à fournir dans ASC)
- **App Icon 1024×1024** PNG sans alpha
- **Screenshots** 6.7" (iPhone Pro Max) — au moins 3 par langue : écran d'accueil / placement AR / détail jardin. Idéalement aussi 6.5".
- (Optionnel) App Preview vidéo
