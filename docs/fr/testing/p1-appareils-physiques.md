# Validation P1 sur appareils physiques

Cette recette couvre ce qu'un simulateur ne peut pas valider : caméra, LiDAR,
RoomPlan, ARKit, localisation réelle et chauffe. Une ligne vide dans le tableau
de résultats signifie « non validé » ; elle ne doit jamais être présentée comme
un succès.

## Parc minimal d'appareils

Tester au minimum deux iPhone sous une version iOS supportée par l'app (cible
minimale actuelle : iOS 18.2) :

| Profil | Exemple | Raison |
|---|---|---|
| iPhone avec LiDAR | iPhone 12 Pro ou Pro plus récent | RoomPlan, profondeur, scan d'une pièce |
| iPhone sans LiDAR | iPhone 12/13/14/15/16 standard ou 16e | tracé guidé, détection de plans, performances de base |
| Appareil ancien supporté, recommandé | le plus ancien iPhone réellement disponible dans le parc | mémoire, batterie et chauffe dans le pire cas réaliste |

Utiliser une build Release/TestFlight propre. Noter le modèle, la version iOS,
la version Arbore et le numéro de build avant chaque session.

## Scénarios obligatoires

### 1. Autorisations et localisation

1. Installer l'app sans permissions préexistantes.
2. Créer successivement une pièce, un balcon/une terrasse et un jardin.
3. Vérifier que la caméra est demandée au moment du scan, pas au lancement.
4. Après le scan, vérifier que chaque nouveau jardin redemande une localisation
   ou permet de saisir une ville ; tester aussi la localisation approximative.
5. Refuser caméra puis localisation, revenir depuis Réglages et reprendre le
   parcours sans écran bloqué ni perte du brouillon.

Critère : aucune adresse exacte n'est affichée ou conservée ; la ville,
l'orientation et l'ensoleillement atteignent bien le plan 2D.

### 2. Pièce avec LiDAR / RoomPlan

1. Mesurer au ruban une pièce simple et une pièce contenant porte, fenêtre et
   mobilier.
2. Effectuer le scan RoomPlan, puis orienter le téléphone vers la source de
   lumière demandée.
3. Comparer largeur, longueur et surface au relevé manuel.
4. Ouvrir l'AR, placer, déplacer et supprimer trois plantes, quitter puis rouvrir
   le jardin.

Cible : erreur de dimension inférieure à 5 % ou 10 cm sur une longueur simple ;
aucun crash ; objets toujours dans la zone attendue après réouverture. Toute
erreur supérieure à 10 % doit être considérée bloquante ou clairement proposée
à la correction manuelle.

### 3. Espace sans LiDAR

1. Tracer quatre coins dans un ordre normal, puis tenter volontairement un ordre
   susceptible de croiser les diagonales.
2. Tester un balcon étroit, une terrasse et un contour de jardin non rectangulaire.
3. Refaire les dimensions depuis le plan 2D.

Critère : points faciles à poser et annuler, contour jamais auto-croisé, fermeture
compréhensible et modification reflétée dans le plan 2D.

### 4. Catalogue et réseau

1. Vider le cache de vignettes, lancer le catalogue en Wi-Fi puis en 4G/5G.
2. Faire défiler les 124 plantes, rechercher et appliquer plusieurs filtres.
3. Ouvrir dix plantes et placer au moins cinq modèles AR.

Critère : les cartes téléchargent des PNG serveur sans reconstruction USDZ locale,
pas de pic thermique lors du simple défilement, aucune vignette blanche ou hors
cadre, et un échec réseau affiche un repli puis permet de réessayer.

### 5. Session thermique

Sur chaque profil d'appareil, exécuter 20 minutes continues : 5 minutes de scan,
10 minutes de placement/déplacement AR et 5 minutes de catalogue. Relever toutes
les 5 minutes : état thermique observé dans les logs, batterie, fluidité et
éventuel avertissement Arbore.

Critère : aucun crash ou blocage ; en état `.serious`/`.critical`, la qualité AR
se réduit conformément au contrôleur adaptatif ; le téléphone ne reconstruit pas
les vignettes pendant le catalogue. Un arrêt iOS pour pression mémoire ou chauffe
est bloquant.

## Feuille de résultats

| Date | Appareil / iOS | Build | Pièce LiDAR | Sans LiDAR | Localisation | Catalogue | 20 min thermique | Anomalies |
|---|---|---|---|---|---|---|---|---|
| À remplir |  |  |  |  |  |  |  |  |

Joindre les captures, vidéos et logs Sentry à chaque anomalie. Une publication
App Store ne peut être déclarée validée que lorsque les deux profils minimaux ont
toutes les colonnes obligatoires renseignées sans anomalie bloquante.
