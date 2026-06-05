# App Store Connect — textes de listing (#206)

Textes prêts à coller dans App Store Connect → **App Information** + **Version Information**, en 4 langues (FR / EN / ES / DE). Limites Apple respectées (sous-titre ≤ 30, mots-clés ≤ 100, description ≤ 4000, nouveautés ≤ 4000 mais on vise ~500, texte promo ≤ 170).

> Périmètre volontairement limité aux features **fonctionnelles** : design de jardin en AR, suggestions de plantes, catalogue + guides d'entretien, rappels d'arrosage, test de lumière. **Le scan/identification de plante (#11) est volontairement omis** tant qu'il n'est pas terminé (Apple reject toute feature annoncée non fonctionnelle). À rajouter une fois livré.

## Champs communs (App Information)
- **Catégorie principale** : Lifestyle — **secondaire** : Reference (optionnel)
- **Age rating** : 4+ (aucun contenu sensible)
- **Privacy Policy URL** : `https://arbore.app/privacy`
- **Marketing URL** : `https://arbore.app`
- **Support URL** : `https://arbore.app/support` (ou `mailto:contact@arbore.app`)
- **Content rights** : oui (droits sur les modèles 3D + plantes générées)

## Compte démo Apple Reviewer (App Review Information → Sign-In required)
Compte créé en prod (Firebase Auth `emailVerified=true` + record Mongo), login vérifié de bout en bout.

| Champ | Valeur |
|---|---|
| **User Name** | `appstore.review@arbore.app` |
| **Password** | _hors git_ — local : `fastlane/metadata/review_information/demo_password.txt` (gitignored) ; ou gestionnaire de mots de passe de l'équipe / `ARBORE_DEMO_PASSWORD` |

- uid : `ioBLddNo0aXcJqjJLnOz4Yjjzg83`
- Cocher **« Sign-in required »** et coller ces identifiants.
- Note de review suggérée : *"Use the demo account above to sign in. Then design a future garden: complete the questionnaire, accept the suggested plants, and place them in AR. Camera + LiDAR are used for AR plant placement on the garden creation flow."*

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
Répondez à quelques questions sur votre espace, votre style et votre lumière, et laissez Arbore vous suggérer les plantes adaptées. Placez ensuite des plantes 3D à l'échelle directement dans votre pièce ou votre jardin, et disposez-les jusqu'à ce que tout soit parfait.

DES SUGGESTIONS DE PLANTES SUR MESURE
Obtenez une sélection personnalisée selon votre exposition, votre niveau d'entretien et l'harmonie de votre espace — aucune expertise requise.

L'ENTRETIEN EN TOUTE SIMPLICITÉ
Parcourez un catalogue riche avec des guides d'entretien détaillés, et n'oubliez plus jamais d'arroser grâce aux rappels d'arrosage par plante.

MESUREZ VOTRE LUMIÈRE
Évaluez la luminosité d'un emplacement et trouvez les plantes qui s'y épanouiront.

LA CONFIDENTIALITÉ D'ABORD
Arbore est une bêta gratuite et non commerciale développée par une équipe d'étudiants. Pas de publicité, pas de tracking, pas d'achats intégrés — vos données restent les vôtres (conforme RGPD).

Cultivez en harmonie. 🌱
```

**Nouveautés / What's New** :
```
Bienvenue dans la bêta d'Arbore ! 🌱

• Concevez votre jardin en RA : placez des plantes 3D à l'échelle dans votre espace et disposez-les librement.
• Placement automatique amélioré qui agence vos plantes pour vous.
• Suggestions de plantes personnalisées via un court questionnaire.
• Catalogue de plantes avec guides d'entretien et rappels d'arrosage.
• Connexion avec Apple ou Google.

Merci de tester — vos retours façonnent la suite !
```

**Texte promotionnel** (≤170) :
```
Concevez votre futur jardin en réalité augmentée, recevez des suggestions adaptées à votre espace et gardez chaque plante en pleine forme. Bêta gratuite.
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
Answer a few questions about your space, style, and light, and let Arbore suggest the plants that fit. Then place true-to-scale 3D plants right in your room or garden with augmented reality, and arrange them until it feels just right.

SMART PLANT SUGGESTIONS
Get a personalized selection based on your exposure, maintenance level, and the harmony of your space — no green thumb required.

CARE MADE SIMPLE
Browse a rich plant catalog with detailed care guides, and never forget to water again thanks to per-plant watering reminders.

MEASURE YOUR LIGHT
Gauge the light in a spot and find the plants that will thrive there.

PRIVACY FIRST
Arbore is a free, non-commercial beta from a student team. No ads, no tracking, no in-app purchases — your data stays yours (GDPR-friendly).

Grow with harmony. 🌱
```

**What's New** :
```
Welcome to the Arbore beta! 🌱

• Design your garden in AR: place true-to-scale 3D plants in your space and arrange them freely.
• Smarter automatic placement that lays out your selected plants for you.
• Personalized plant suggestions from a quick questionnaire.
• Plant catalog with care guides and watering reminders.
• Sign in with Apple or Google.

Thanks for testing — your feedback shapes what comes next!
```

**Promotional text** (≤170) :
```
Design your future garden in augmented reality, get plant suggestions tailored to your space, and keep every plant thriving. Free beta — grow with harmony.
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
Responde unas preguntas sobre tu espacio, tu estilo y tu luz, y deja que Arbore te sugiera las plantas ideales. Luego coloca plantas 3D a escala real en tu habitación o jardín con realidad aumentada y organízalas hasta que todo encaje.

SUGERENCIAS DE PLANTAS A TU MEDIDA
Recibe una selección personalizada según tu exposición, tu nivel de mantenimiento y la armonía de tu espacio, sin necesidad de experiencia.

EL CUIDADO, MÁS FÁCIL
Explora un completo catálogo con guías de cuidado detalladas y no vuelvas a olvidar el riego gracias a los recordatorios por planta.

MIDE TU LUZ
Evalúa la luz de un lugar y encuentra las plantas que prosperarán allí.

PRIVACIDAD ANTE TODO
Arbore es una beta gratuita y sin fines comerciales creada por un equipo de estudiantes. Sin anuncios, sin seguimiento y sin compras integradas: tus datos son tuyos (conforme al RGPD).

Cultiva en armonía. 🌱
```

**Novedades** :
```
¡Bienvenido a la beta de Arbore! 🌱

• Diseña tu jardín en RA: coloca plantas 3D a escala real en tu espacio y organízalas a tu gusto.
• Colocación automática mejorada que distribuye tus plantas por ti.
• Sugerencias de plantas personalizadas con un breve cuestionario.
• Catálogo de plantas con guías de cuidado y recordatorios de riego.
• Inicia sesión con Apple o Google.

¡Gracias por probar! Tus comentarios definen lo que viene.
```

**Texto promocional** (≤170) :
```
Diseña tu futuro jardín en realidad aumentada, recibe sugerencias para tu espacio y mantén cada planta sana. Beta gratuita: cultiva en armonía.
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
Beantworte ein paar Fragen zu deinem Raum, deinem Stil und deinem Licht, und Arbore schlägt dir die passenden Pflanzen vor. Platziere anschließend maßstabsgetreue 3D-Pflanzen direkt in deinem Zimmer oder Garten und ordne sie an, bis alles stimmt.

PASSENDE PFLANZEN-VORSCHLÄGE
Erhalte eine persönliche Auswahl nach Lichtverhältnissen, Pflegeaufwand und der Harmonie deines Raums – ganz ohne Vorkenntnisse.

PFLEGE LEICHT GEMACHT
Durchstöbere einen umfangreichen Katalog mit detaillierten Pflegeanleitungen und vergiss dank Gieß-Erinnerungen pro Pflanze nie wieder das Gießen.

MISS DEIN LICHT
Bewerte das Licht an einem Ort und finde die Pflanzen, die dort gedeihen.

DATENSCHUTZ ZUERST
Arbore ist eine kostenlose, nicht-kommerzielle Beta eines Studierenden-Teams. Keine Werbung, kein Tracking, keine In-App-Käufe – deine Daten bleiben deine (DSGVO-konform).

Wachse in Harmonie. 🌱
```

**Neues** :
```
Willkommen zur Arbore-Beta! 🌱

• Gestalte deinen Garten in AR: platziere maßstabsgetreue 3D-Pflanzen in deinem Raum und ordne sie frei an.
• Verbesserte automatische Platzierung, die deine Pflanzen für dich anordnet.
• Persönliche Pflanzen-Vorschläge über einen kurzen Fragebogen.
• Pflanzenkatalog mit Pflegeanleitungen und Gieß-Erinnerungen.
• Anmeldung mit Apple oder Google.

Danke fürs Testen – dein Feedback gestaltet die Zukunft!
```

**Werbetext** (≤170) :
```
Gestalte deinen zukünftigen Garten in Augmented Reality, erhalte passende Vorschläge für deinen Raum und halte jede Pflanze gesund. Kostenlose Beta.
```

---

## Assets restants (non-texte, à fournir dans ASC)
- **App Icon 1024×1024** PNG sans alpha
- **Screenshots** 6.7" (iPhone Pro Max) — au moins 3 par langue : écran d'accueil / placement AR / détail jardin. Idéalement aussi 6.5".
- (Optionnel) App Preview vidéo
