# Arbore Notifications Architecture Plan

## Objectif

Mettre en place un systeme de notifications iOS moderne, robuste et scalable pour Arbore, compatible iOS 16+, couvrant:

- notifications locales on-device pour les routines d'arrosage, soins et relances de projet;
- notifications push APNs, utilisables directement ou via FCM comme transport serveur;
- alertes in-app et deep links vers les ecrans SwiftUI pertinents;
- rich notifications via Notification Service Extension.

## Principes d'architecture

- **Source of truth metier**: les routines restent dans `WateringRoutineStore`; la couche notifications observe les mutations de routines et replanifie automatiquement.
- **Separation SOLID**:
  - `ArboreNotification` decrit le contenu, la categorie, le routage et le trigger;
  - `NotificationManager` orchestre `UserNotifications`;
  - `ArboreNotificationPlanner` transforme les routines et signaux locaux en notifications planifiables;
  - `ArborePushTokenService` gere le token APNs et sa synchronisation backend;
  - `NotificationRouter` convertit les payloads/URLs en etat de navigation SwiftUI.
- **Routage unifie**: locales, push, liens `arbore://` et alertes in-app partagent le meme modele `NotificationRoute`.
- **Payload stable**: chaque notification transporte `notification_id`, `notification_category`, `route` et les identifiants metier (`plant_id`, `garden_id`, `order_id`, `routine_id`) dans `userInfo`.
- **Extensibilite serveur**: le backend peut envoyer APNs directement ou via FCM tant que le payload final APNs contient les memes cles.

## Cas d'usage locaux

### Rappels d'arrosage

Declencheur:
- creation ou mise a jour d'une `WateringRoutine`;
- completion anticipee via `markWatered`;
- report via `deferWatering`.

Calcul:
- date de base: `routine.nextWateringDate`;
- ajustement dynamique optionnel via `ArboreLocalWeatherSnapshot` et `ArborePlantCareProfile`;
- chaleur ou air sec avance le rappel;
- pluie/humidite elevee reporte legerement les plantes d'exterieur;
- gel local reporte les arrosages non urgents.

Notification:
- categorie `wateringReminder`;
- route `arbore://watering?gardenId=<id>&plantId=<id>&routineId=<id>`;
- interruption `.active`.

### Rappels d'entretien

Declencheur:
- creation/mise a jour d'une `PlantCareRoutine`;
- completion via `completeCareRoutine`;
- report via `deferCareRoutine`.

Notification:
- categorie `careReminder`;
- route `arbore://garden/<gardenId>?tab=tasks&plantId=<plantId>&routineId=<id>`;
- titre contextualise par type de soin.

### Relance de completion de projet

Declencheur:
- projet cree ou sauvegarde;
- absence de plante placee en AR apres 72h.

Notification:
- categorie `projectCompletion`;
- trigger `UNTimeIntervalNotificationTrigger(72h)`;
- route `arbore://garden/<projectId>?tab=plan`.

## Cas d'usage push

### Alertes climatiques urgentes

Payload attendu:

```json
{
  "aps": {
    "alert": {
      "title": "Risque de gelee cette nuit",
      "body": "Protegez vos plantes fragiles avant 22h."
    },
    "sound": "default",
    "interruption-level": "time-sensitive",
    "mutable-content": 1
  },
  "notification_category": "climateEmergency",
  "route": "arbore://garden/<gardenId>?tab=tasks",
  "garden_id": "<gardenId>",
  "image_url": "https://cdn.arbore.app/notifications/frost.png"
}
```

Comportement:
- foreground: banniere systeme + alerte in-app dans l'etat SwiftUI;
- background/quit: APNs affiche la notification, puis `didReceive response` route l'utilisateur;
- extension riche: telecharge `image_url` et l'attache au contenu.

### Marketplace transactionnel

Payload attendu:

```json
{
  "aps": {
    "alert": {
      "title": "Commande expediee",
      "body": "Votre pepinieriste a confie la commande au transporteur."
    },
    "sound": "default",
    "mutable-content": 1
  },
  "notification_category": "marketplaceOrder",
  "route": "arbore://marketplace/order/<orderId>",
  "order_id": "<orderId>",
  "image_url": "https://cdn.arbore.app/brand/notification-logo.png"
}
```

## Deep linking

Routes supportees:

- `arbore://home`
- `arbore://catalogue`
- `arbore://plant/<plantId>`
- `arbore://garden/<gardenId>?tab=plan|tasks|purchase&plantId=<plantId>&routineId=<routineId>`
- `arbore://watering?gardenId=<gardenId>&plantId=<plantId>&routineId=<routineId>`
- `arbore://marketplace/order/<orderId>`
- `arbore://profile/notifications`

Mapping SwiftUI:

- `home` -> onglet Accueil;
- `catalogue` et `plant` -> onglet Catalogue, puis presentation detail plante;
- `garden`, `watering` -> onglet Jardin, selection du jardin cible, onglet interne Plan/Soins/Achats;
- `marketplaceOrder` -> onglet Jardin, section Achats;
- `profile/notifications` -> onglet Profil.

## Gestion des autorisations

Etats suivis:

- `notDetermined`: bouton in-app peut lancer `requestAuthorization`;
- `authorized`, `provisional`, `ephemeral`: notifications activables;
- `denied`: l'app expose un chemin vers Settings;
- `unknown`: degrade gracefully.

Options demandees:

- `.alert`, `.badge`, `.sound`;
- `.provisional` possible via parametre dedie pour onboarding silencieux;
- `.timeSensitive` si disponible et active cote entitlement/profil.

## Token APNs

Flux:

1. L'app demande l'autorisation notification.
2. Si l'etat le permet, `UIApplication.registerForRemoteNotifications()` est appele sur main thread.
3. `didRegisterForRemoteNotificationsWithDeviceToken` convertit le token en hex.
4. `ArborePushTokenService` persiste localement le token et tente une synchro backend authentifiee.
5. En cas d'echec reseau/auth, le token reste en pending et sera renvoye au prochain lancement.

## Annulation et obsolescence

Identifiants deterministes:

- `watering.<routineId>`
- `care.<routineId>`
- `project-completion.<projectId>`
- `climate.<serverEventId>`
- `marketplace.<orderId>.<status>`

Quand l'utilisateur arrose ou termine un soin:

1. le store met a jour la prochaine date;
2. l'ancien identifiant est annule;
3. une nouvelle notification est planifiee avec le meme identifiant et la date recalculee.

## Extension riche

La Notification Service Extension:

- lit `image_url`, `image-url` ou `media-url`;
- refuse les schemas non HTTPS;
- telecharge dans un fichier temporaire avec extension MIME coherente;
- cree un `UNNotificationAttachment`;
- renvoie toujours un contenu valide, meme en cas d'echec ou timeout.

## Observabilite et securite

- Les erreurs APNs/token sont loggees sans bloquer l'UX.
- Les tokens ne sont jamais affiches en clair dans l'UI.
- Les payloads inconnus routent vers l'onglet Accueil.
- Les routes externes non `arbore://` sont ignorees par le routeur interne.
