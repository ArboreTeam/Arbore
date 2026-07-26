# VPS Bootstrap — Provisionnement d'un serveur Arbore

Procédure pour reconstruire le backend Arbore sur un VPS Fedora vierge.

Ce runbook est conçu pour être exécuté en condition de récupération (la VM
existante est perdue) ou de migration (passage sur un nouveau provider).
Chaque étape est idempotente — la re-jouer sur un système déjà configuré
ne casse rien.

> Hypothèses : Fedora 40 Cloud Edition, utilisateur `fedora` avec
> `sudo` NOPASSWD, accès SSH par clé publique, IP publique routable.
> Pour un autre OS (Debian/Ubuntu), adapter `dnf` en `apt` et le repo
> MongoDB.

---

## Vue d'ensemble

Composants installés à la fin de la procédure :

| Composant | Rôle |
|---|---|
| Docker + Compose | Exécute `arbore-backend` (Go/Gin, `:8080`), `arbore-ai-generator` (Python/FastAPI, `:8000`) et `arbore-web` (Next.js standalone, `:3000`) |
| Nginx | Reverse proxy `:80` + `:443` (TLS, Cloudflare Origin cert) : `api.arbore.app` → `127.0.0.1:8080` (backend) et `web.arbore.app` → `127.0.0.1:3000` (web) |
| MongoDB Atlas | DB hébergée (pas de Mongo local) ; `mongosh` et `mongodump` côté VPS pour cleanup et backups |
| cronie | Lance `cleanup-test-db.sh` chaque nuit à 04:00 UTC |
| gh CLI | Utilisé par `cleanup-test-db.sh` (optionnel, fallback curl) |

L'AI Generator écoute en interne sur `:8000`, le backend l'appelle via le
réseau Docker `arbore-net` ; le web appelle le backend sur `http://backend:8080`
(via son proxy serveur). Ces ports sont exposés sur l'hôte mais leur accès
externe direct est bloqué par le firewall (cf. annexe pare-feu) ; le trafic
public passe par Nginx sur `:80`/`:443`, eux-mêmes restreints aux IP Cloudflare.

---

## 1. Préparation système

```bash
sudo dnf -y update
sudo dnf -y install \
    git curl wget jq vim \
    cronie crontabs \
    nginx \
    gh \
    python3
sudo systemctl enable --now crond
```

Vérification :

```bash
systemctl is-active crond   # active
gh --version                # 2.x
```

---

## 2. Docker + Compose

Fedora fournit le paquet `moby-engine`, mais le projet utilise les binaires
officiels Docker (compose v2 inclus) :

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

Ajouter `fedora` au groupe `docker` est **optionnel** ; le projet appelle
`sudo docker` partout (cf. `deploy.sh`), donc on peut s'en passer si on
préfère garder la séparation de privilèges.

Vérification :

```bash
sudo docker --version            # Docker version 28.x
sudo docker compose version      # v2.35+
sudo docker run --rm hello-world # sanity check
```

---

## 3. MongoDB tools (mongosh + mongodump)

`mongodump` vient du paquet `mongodb-database-tools`. `mongosh` n'est pas
dans les dépôts Fedora — il faut ajouter le dépôt officiel MongoDB.

```bash
sudo tee /etc/yum.repos.d/mongodb-org-7.0.repo > /dev/null << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
EOF

sudo dnf -y install mongodb-database-tools mongodb-mongosh
```

Vérification :

```bash
mongosh --version       # 2.8.x
mongodump --version | head -1
```

---

## 4. Nginx reverse proxy

```bash
sudo tee /etc/nginx/conf.d/arbore.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;

    # Le diagnostic envoie une photo en base64 ; conserver une marge proxy
    # au-dessus de la limite API maximale (10 Mio côté Go).
    client_max_body_size 16m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

sudo nginx -t                # syntaxe OK ?
sudo systemctl enable --now nginx
```

> En production, deux vhosts distincts sont servis derrière Cloudflare :
> `api.arbore.app` → `127.0.0.1:8080` (backend) et `web.arbore.app` →
> `127.0.0.1:3000` (container `arbore-web`). Le bloc ci-dessus est le squelette
> backend (`:80`) ; ajouter un `server { ... server_name web.arbore.app; location / { proxy_pass http://127.0.0.1:3000; ... } }`
> équivalent pour le web, et les directives `:443 ssl` correspondantes.

> HTTPS (issue #121) : **fait**. Le trafic public passe par Cloudflare en
> mode `Full (strict)`. L'origine sert un vhost `:443 ssl http2` avec un
> **Cloudflare Origin Certificate** (`/etc/ssl/cloudflare/origin.{pem,key}`,
> cf. `arbore.conf`) ; nginx écoute en `:80` **et** `:443`, tous deux
> restreints aux IP Cloudflare (cf. annexe pare-feu). L'exception ATS HTTP
> côté iOS a été retirée — l'app ne parle plus qu'en HTTPS à `api.arbore.app`.

---

## 5. Cloner le dépôt et configurer l'environnement

```bash
cd ~                                                      # /home/fedora
git clone git@github.com:ArboreTeam/Arbore.git
cd Arbore
```

Si la clé SSH n'est pas encore enregistrée sur le compte GitHub de la
machine, utiliser le clone HTTPS puis remplacer le remote :

```bash
git clone https://github.com/ArboreTeam/Arbore.git
cd Arbore && git remote set-url origin git@github.com:ArboreTeam/Arbore.git
```

---

## 6. Reconstruire le `.env`

Le fichier `/home/fedora/Arbore/.env` n'est **jamais commité**. Variables
attendues (sources de vérité indiquées) :

| Variable | Source de vérité | Notes |
|---|---|---|
| `MONGODB_URI` | Atlas → Database → Connect → Drivers | URI prod avec user `arbore_backend_user` |
| `MONGODB_URI_TEST` | Atlas → idem, base `arbore_test`, user `arbore_test_user` | Optionnelle, n'active la DB test que si présente |
| `ARBORE_API_KEY` | GitHub Settings → Secrets → `ARBORE_API_KEY` | Clé applicative trafic prod |
| `ARBORE_API_KEY_TEST` | GitHub Settings → Secrets → `ARBORE_API_KEY_TEST` | Clé qui route vers `arbore_test` |
| `FIREBASE_SERVICE_ACCOUNT_HOST_PATH` | Chemin absolu du JSON Firebase | Voir étape 7 ; monté en lecture seule |
| `MASTER_ENCRYPTION_KEY` | Secret opérateur | Clé 32 octets encodée en base64, utilisée pour les jetons Apple |
| `APPLE_TEAM_ID` / `APPLE_KEY_ID` | Apple Developer → Keys | Identifiants de la clé Sign in with Apple |
| `APPLE_SIWA_CLIENT_ID` | Bundle ID | `com.arboreteam.arbore` pour le flux iOS natif |
| `APPLE_SIWA_KEY_HOST_PATH` | Chemin absolu du `.p8` Apple | Fichier `0600`, hors Git |
| `ARBORE_ADMIN_UIDS` | Firebase Authentication | UIDs administrateurs séparés par des virgules |
| `MODELS_HOST_PATH` | Stockage persistant du VPS | Dossier USDZ, indépendant du checkout de code |
| `THUMBNAILS_HOST_PATH` | Stockage persistant du VPS | Dossier de miniatures générées |
| `LEGACY_COMMUNITY_UPLOADS_HOST_PATH` | Stockage persistant du VPS | Conservé uniquement pour l'effacement RGPD |
| `OPENAI_API_KEY` | OpenAI Platform → API keys | Pour l'AI Generator |
| `UNSPLASH_ACCESS_KEY` | Unsplash Developers → Application | Photos de plantes |
| `MISTRAL_API_KEY` | console.mistral.ai → API keys | Backend AI provider alternatif |
| `AI_PROVIDER` | Constante config | `openai` ou `mistral` |
| `GIN_MODE` | Constante config | `release` en prod |
| `PORT` | Constante config | `8080` |

Template à recopier :

```bash
cat > /home/fedora/Arbore/.env << 'EOF'
# Mongo
MONGODB_URI=mongodb+srv://arbore_backend_user:PASSWORD@arbore.cew6l.mongodb.net/arbore?retryWrites=true&w=majority&appName=Arbore
MONGODB_URI_TEST=mongodb+srv://arbore_test_user:PASSWORD@arbore.cew6l.mongodb.net/arbore_test?retryWrites=true&w=majority&appName=Arbore

# API keys applicatives
ARBORE_API_KEY=arbore_ios_v1_xxxxxxxxxxxxxxxxxxxx
ARBORE_API_KEY_TEST=arbore_test_v1_xxxxxxxxxxxxxxxxxxxx
ARBORE_ADMIN_UIDS=uid_firebase_admin

# Secrets et données persistantes (chemins hôte absolus)
FIREBASE_SERVICE_ACCOUNT_HOST_PATH=/home/fedora/arbore-data/secrets/firebase-adminsdk.json
MASTER_ENCRYPTION_KEY=base64_32_octets
APPLE_TEAM_ID=XXXXXXXXXX
APPLE_KEY_ID=XXXXXXXXXX
APPLE_SIWA_CLIENT_ID=com.arboreteam.arbore
APPLE_SIWA_KEY_HOST_PATH=/home/fedora/arbore-data/secrets/AuthKey_XXXXXXXXXX.p8
MODELS_HOST_PATH=/home/fedora/arbore-data/models
THUMBNAILS_HOST_PATH=/home/fedora/arbore-data/models/thumbnails
LEGACY_COMMUNITY_UPLOADS_HOST_PATH=/home/fedora/arbore-data/uploads/community

# AI providers
AI_PROVIDER=openai
OPENAI_API_KEY=sk-...
MISTRAL_API_KEY=...

# Unsplash
UNSPLASH_ACCESS_KEY=...

# Config Gin
GIN_MODE=release
PORT=8080
EOF
chmod 600 /home/fedora/Arbore/.env
```

---

## 7. Firebase service account

1. Console Firebase → Project settings → Service accounts → **Generate new
   private key**. Télécharger le JSON.
2. Renommer en `arbore-firebase-adminsdk.json`.
3. Uploader à la racine du dépôt :

```bash
scp arbore-firebase-adminsdk.json fedora@<VPS>:/home/fedora/Arbore/
chmod 600 /home/fedora/Arbore/arbore-firebase-adminsdk.json
```

Le bind mount dans `docker-compose.yml` monte ce fichier en lecture seule dans
`/run/secrets/firebase-adminsdk.json`. Le chemin hôte est fourni par
`FIREBASE_SERVICE_ACCOUNT_HOST_PATH`.

---

## 8. Premier déploiement

```bash
cd /home/fedora/Arbore
sudo docker compose build
sudo docker compose up -d
sudo docker compose ps        # backend + ai-generator + web → Up (healthy)
```

Health check end-to-end :

```bash
curl -fsS http://localhost:8080/health
# → {"status":"ok","service":"arbore-backend","commit":"<sha>"}
curl -fsS http://localhost:3000/   # web (Next.js)
curl -fsS http://<VPS_IP>/health   # via nginx
```

Le champ `commit` est le SHA git réellement déployé. C'est le seul moyen de
savoir si la production suit `main` :

```bash
curl -s https://api.arbore.app/health | jq -r .commit   # ce qui tourne
git rev-parse origin/main                               # ce qui devrait tourner
```

À partir de maintenant, les déploiements suivants passent par
`./deploy.sh` (qui prend un snapshot Mongo avant chaque rebuild).

**Garde-fou du checkout.** `deploy.sh` refuse de déployer si un fichier **suivi**
par git est modifié — c'est du code non committé, donc une divergence
silencieuse. En revanche il **tolère** deux choses : les fichiers non suivis (ils
ne peuvent pas faire échouer un fast-forward) et les modifications sous
`ArboreBackend/models/`, déclarées comme données hors bande dans
`OUT_OF_BAND_PATHS`. Ces modèles 3D sont regénérés et nettoyés directement sur le
serveur ; les exiger propres rendait `deploy.sh` inutilisable, et les
déploiements le contournaient — en sautant le snapshot Mongo pre-deploy, seul
filet de sécurité puisque Atlas M0 n'a aucun backup automatique (cf. #341).

Les USDZ, miniatures, anciens uploads et secrets sont censés vivre dans
`/home/fedora/arbore-data` grâce aux chemins absolus du `.env`, pour qu'un
nouveau checkout de release ne puisse ni les écraser ni les supprimer.

> ⚠️ **État réel au 26/07/2026** : `/home/fedora/arbore-data/models` existe et
> contient bien les 124 modèles, mais **aucun `MODELS_HOST_PATH` n'est défini
> dans le `.env` du VPS**. `docker-compose.yml` retombe donc sur son défaut
> `./ArboreBackend/models`, et la production sert les modèles **depuis le
> checkout git**. Cette bascule reste à faire (#341) ; d'ici là, toute opération
> git sur ces fichiers change ce que l'app télécharge.

---

## 9. Cron de cleanup de la DB de test

```bash
mkdir -p /home/fedora/Arbore/logs
touch /home/fedora/Arbore/logs/cleanup-test-db.log
chmod +x /home/fedora/Arbore/scripts/cleanup-test-db.sh

(crontab -l 2>/dev/null; echo "0 4 * * * /home/fedora/Arbore/scripts/cleanup-test-db.sh >> /home/fedora/Arbore/logs/cleanup-test-db.log 2>&1") | crontab -
crontab -l
```

Validation manuelle (peut afficher "skip" si une CI tourne, c'est OK) :

```bash
/home/fedora/Arbore/scripts/cleanup-test-db.sh
```

Le script vérifie qu'aucune CI GitHub Actions n'est en cours avant de
droper la DB. Il utilise `gh` si authentifié, sinon `curl` sans token (le
dépôt étant public, l'API Actions est lisible sans auth).

---

## 10. Restauration depuis un backup Mongo

`deploy.sh` produit un snapshot dans `backups/daily/` avant chaque
rebuild. Pour restaurer un backup précis (catastrophe, rollback) :

```bash
cd /home/fedora/Arbore/backups/daily
ls -lt | head -5                                   # repérer le snapshot voulu
SNAPSHOT="arbore-predeploy-2026-05-13T22-15-06Z"
tar -xzf "${SNAPSHOT}.tar.gz"

source /home/fedora/Arbore/.env
mongorestore --uri="$MONGODB_URI" --drop --nsInclude="arbore.*" "$SNAPSHOT/arbore"
```

> `--drop` remplace la DB **prod**. Pour restaurer en `arbore_test`,
> ajouter `--nsFrom='arbore.*' --nsTo='arbore_test.*'` et utiliser
> `MONGODB_URI_TEST`.

---

## 11. Sanity checklist post-bootstrap

Cocher ces points avant de considérer le VPS opérationnel :

- [ ] `systemctl is-active docker crond nginx` → tous `active`
- [ ] `sudo docker compose ps` → `arbore-backend` + `arbore-ai-generator` + `arbore-web` healthy
- [ ] `curl -fsS http://localhost:8080/health` → 200 OK
- [ ] `curl -fsS http://localhost:3000/` → 200 OK (web)
- [ ] `curl -fsS http://<VPS_IP>/health` → 200 OK (via nginx)
- [ ] `mongosh "$MONGODB_URI" --quiet --eval 'db.users.countDocuments()'` → entier > 0
- [ ] `crontab -l` contient l'entrée `cleanup-test-db.sh`
- [ ] `/home/fedora/Arbore/scripts/cleanup-test-db.sh` finit en exit 0
- [ ] `ls /home/fedora/Arbore/backups/daily/` ne plante pas (le dossier est créé au 1er `deploy.sh`)
- [ ] Une PR de test sur GitHub déclenche la CI ; les tests passent en
      pointant vers `arbore_test`

---

## Annexe — Pare-feu / cloud provider

Selon le provider, le pare-feu au niveau de la VM peut être géré par :

- **`cf-http-firewall.service`** (en place sur la VM actuelle) : règles
  `iptables` qui restreignent `:80` **et** `:443` aux seules **IP Cloudflare**
  (chaîne `CF-HTTP`, plages auto-rafraîchies chaque semaine par
  `cf-update-ranges.timer` avec validation + rollback) et **bloquent l'accès
  externe direct** à `:8080`/`:8000` (chaîne `DOCKER-USER`, v4 + v6, scope
  `eth0`). Script : `/usr/local/sbin/cf-http-firewall.sh`.
- Les règles "Network" du dashboard cloud (Oracle Cloud, OVH, etc.), le cas échéant.

Ports publics : **22** (SSH), **80** et **443** (via nginx, **Cloudflare-only**).
**Ne PAS exposer** `:8080`, `:8000` ni `:3000` : joignables uniquement en
localhost (via nginx pour `:8080` et `:3000`) et en inter-conteneurs — l'accès
externe direct est bloqué par le firewall ci-dessus.

---

## Annexe — Rotation des secrets

En cas de fuite (cf. historique des issues #117, #119) :

1. **API key applicative** : générer une nouvelle valeur, mettre à jour
   `ARBORE_API_KEY` dans `.env`, redéployer (`sudo docker compose up -d
   backend`). Mettre à jour `Secrets.xcconfig` côté iOS et les secrets
   GitHub Actions.
2. **MongoDB user** : Atlas → Database Access → Edit → nouveau password.
   Mettre à jour `MONGODB_URI` dans `.env`, redéployer.
3. **Firebase service account** : Console Firebase → révoquer la clé
   compromise, en générer une nouvelle, remplacer le JSON sur le VPS,
   redéployer.
4. **Re-scanner l'historique git** avec `gitleaks detect --config
   .gitleaks.toml` pour s'assurer que la nouvelle valeur n'est pas, à son
   tour, dans un commit.
