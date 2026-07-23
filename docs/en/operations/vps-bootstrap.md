# VPS Bootstrap — Provisioning an Arbore server

Procedure for rebuilding the Arbore backend on a clean Fedora VPS.

This runbook is designed to be run in recovery mode (the existing VM
is lost) or migration mode (moving to a new provider).
Every step is idempotent — re-running it on an already-configured system
breaks nothing.

> Assumptions: Fedora 40 Cloud Edition, `fedora` user with
> `sudo` NOPASSWD, SSH access via public key, routable public IP.
> For a different OS (Debian/Ubuntu), adapt `dnf` to `apt` and the
> MongoDB repo.

---

## Overview

Components installed by the end of the procedure:

| Component | Role |
|---|---|
| Docker + Compose | Runs `arbore-backend` (Go/Gin, `:8080`), `arbore-ai-generator` (Python/FastAPI, `:8000`) and `arbore-web` (Next.js standalone, `:3000`) |
| Nginx | Reverse proxy `:80` + `:443` (TLS, Cloudflare Origin cert): `api.arbore.app` → `127.0.0.1:8080` (backend) and `web.arbore.app` → `127.0.0.1:3000` (web) |
| MongoDB Atlas | Hosted DB (no local Mongo); `mongosh` and `mongodump` on the VPS for cleanup and backups |
| cronie | Runs `cleanup-test-db.sh` every night at 04:00 UTC |
| gh CLI | Used by `cleanup-test-db.sh` (optional, curl fallback) |

The AI Generator listens internally on `:8000`, and the backend calls it over the
Docker network `arbore-net`; the web calls the backend on `http://backend:8080`
(via its server proxy). These ports are exposed on the host but their direct
external access is blocked by the firewall (see firewall appendix); public
traffic goes through Nginx on `:80`/`:443`, which are themselves restricted to Cloudflare IPs.

---

## 1. System preparation

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

Verification:

```bash
systemctl is-active crond   # active
gh --version                # 2.x
```

---

## 2. Docker + Compose

Fedora provides the `moby-engine` package, but the project uses the
official Docker binaries (compose v2 included):

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

Adding `fedora` to the `docker` group is **optional**; the project calls
`sudo docker` everywhere (see `deploy.sh`), so it can be skipped if you
prefer to keep privilege separation.

Verification:

```bash
sudo docker --version            # Docker version 28.x
sudo docker compose version      # v2.35+
sudo docker run --rm hello-world # sanity check
```

---

## 3. MongoDB tools (mongosh + mongodump)

`mongodump` comes from the `mongodb-database-tools` package. `mongosh` is not
in the Fedora repos — you need to add the official MongoDB repo.

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

Verification:

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

    # The diagnosis sends a base64 photo; keep proxy headroom above the
    # API maximum request size (10 MiB in Go).
    client_max_body_size 16m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

sudo nginx -t                # syntax OK?
sudo systemctl enable --now nginx
```

> In production, two distinct vhosts are served behind Cloudflare:
> `api.arbore.app` → `127.0.0.1:8080` (backend) and `web.arbore.app` →
> `127.0.0.1:3000` (`arbore-web` container). The block above is the backend
> skeleton (`:80`); add an equivalent `server { ... server_name web.arbore.app; location / { proxy_pass http://127.0.0.1:3000; ... } }`
> for the web, along with the corresponding `:443 ssl` directives.

> HTTPS (issue #121): **done**. Public traffic goes through Cloudflare in
> `Full (strict)` mode. The origin serves a `:443 ssl http2` vhost with a
> **Cloudflare Origin Certificate** (`/etc/ssl/cloudflare/origin.{pem,key}`,
> see `arbore.conf`); nginx listens on `:80` **and** `:443`, both
> restricted to Cloudflare IPs (see firewall appendix). The iOS-side HTTP ATS
> exception has been removed — the app now only talks to `api.arbore.app` over HTTPS.

---

## 5. Clone the repository and configure the environment

```bash
cd ~                                                      # /home/fedora
git clone git@github.com:ArboreTeam/Arbore.git
cd Arbore
```

If the SSH key is not yet registered on the machine's GitHub account,
use the HTTPS clone then replace the remote:

```bash
git clone https://github.com/ArboreTeam/Arbore.git
cd Arbore && git remote set-url origin git@github.com:ArboreTeam/Arbore.git
```

---

## 6. Rebuild the `.env`

The file `/home/fedora/Arbore/.env` is **never committed**. Expected
variables (sources of truth indicated):

| Variable | Source of truth | Notes |
|---|---|---|
| `MONGODB_URI` | Atlas → Database → Connect → Drivers | Prod URI with user `arbore_backend_user` |
| `MONGODB_URI_TEST` | Atlas → same, `arbore_test` database, user `arbore_test_user` | Optional, only enables the test DB if present |
| `ARBORE_API_KEY` | GitHub Settings → Secrets → `ARBORE_API_KEY` | Application key for prod traffic |
| `ARBORE_API_KEY_TEST` | GitHub Settings → Secrets → `ARBORE_API_KEY_TEST` | Key that routes to `arbore_test` |
| `FIREBASE_SERVICE_ACCOUNT_HOST_PATH` | Absolute path to the Firebase JSON | See step 7; mounted read-only |
| `MASTER_ENCRYPTION_KEY` | Operator secret | Base64-encoded 32-byte key used for Apple tokens |
| `APPLE_TEAM_ID` / `APPLE_KEY_ID` | Apple Developer → Keys | Sign in with Apple key identifiers |
| `APPLE_SIWA_CLIENT_ID` | Bundle ID | `com.arboreteam.arbore` for the native iOS flow |
| `APPLE_SIWA_KEY_HOST_PATH` | Absolute path to the Apple `.p8` | Mode `0600`, outside Git |
| `ARBORE_ADMIN_UIDS` | Firebase Authentication | Comma-separated administrator UIDs |
| `MODELS_HOST_PATH` | Persistent VPS storage | USDZ directory, independent from the code checkout |
| `THUMBNAILS_HOST_PATH` | Persistent VPS storage | Generated thumbnails directory |
| `LEGACY_COMMUNITY_UPLOADS_HOST_PATH` | Persistent VPS storage | Retained only for GDPR deletion |
| `OPENAI_API_KEY` | OpenAI Platform → API keys | For the AI Generator |
| `UNSPLASH_ACCESS_KEY` | Unsplash Developers → Application | Plant photos |
| `MISTRAL_API_KEY` | console.mistral.ai → API keys | Alternative backend AI provider |
| `AI_PROVIDER` | Config constant | `openai` or `mistral` |
| `GIN_MODE` | Config constant | `release` in prod |
| `PORT` | Config constant | `8080` |

Template to copy:

```bash
cat > /home/fedora/Arbore/.env << 'EOF'
# Mongo
MONGODB_URI=mongodb+srv://arbore_backend_user:PASSWORD@arbore.cew6l.mongodb.net/arbore?retryWrites=true&w=majority&appName=Arbore
MONGODB_URI_TEST=mongodb+srv://arbore_test_user:PASSWORD@arbore.cew6l.mongodb.net/arbore_test?retryWrites=true&w=majority&appName=Arbore

# Application API keys
ARBORE_API_KEY=arbore_ios_v1_xxxxxxxxxxxxxxxxxxxx
ARBORE_API_KEY_TEST=arbore_test_v1_xxxxxxxxxxxxxxxxxxxx
ARBORE_ADMIN_UIDS=firebase_admin_uid

# Secrets and persistent data (absolute host paths)
FIREBASE_SERVICE_ACCOUNT_HOST_PATH=/home/fedora/arbore-data/secrets/firebase-adminsdk.json
MASTER_ENCRYPTION_KEY=base64_32_bytes
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

# Gin config
GIN_MODE=release
PORT=8080
EOF
chmod 600 /home/fedora/Arbore/.env
```

---

## 7. Firebase service account

1. Firebase Console → Project settings → Service accounts → **Generate new
   private key**. Download the JSON.
2. Rename it to `arbore-firebase-adminsdk.json`.
3. Upload it to the repository root:

```bash
scp arbore-firebase-adminsdk.json fedora@<VPS>:/home/fedora/Arbore/
chmod 600 /home/fedora/Arbore/arbore-firebase-adminsdk.json
```

The bind mount in `docker-compose.yml` mounts this file read-only as
`/run/secrets/firebase-adminsdk.json`. Its host path is supplied through
`FIREBASE_SERVICE_ACCOUNT_HOST_PATH`.

---

## 8. First deployment

```bash
cd /home/fedora/Arbore
sudo docker compose build
sudo docker compose up -d
sudo docker compose ps        # backend + ai-generator + web → Up (healthy)
```

End-to-end health check:

```bash
curl -fsS http://localhost:8080/health
# → {"status":"ok","service":"arbore-backend","version":"..."}
curl -fsS http://localhost:3000/   # web (Next.js)
curl -fsS http://<VPS_IP>/health   # via nginx
```

From now on, subsequent deployments go through
`./deploy.sh` (which takes a Mongo snapshot before each rebuild). The checkout
must be clean. USDZ files, thumbnails, legacy uploads, and secrets remain under
`/home/fedora/arbore-data` through absolute `.env` paths, so a fresh release
checkout cannot overwrite or delete them.

---

## 9. Test DB cleanup cron

```bash
mkdir -p /home/fedora/Arbore/logs
touch /home/fedora/Arbore/logs/cleanup-test-db.log
chmod +x /home/fedora/Arbore/scripts/cleanup-test-db.sh

(crontab -l 2>/dev/null; echo "0 4 * * * /home/fedora/Arbore/scripts/cleanup-test-db.sh >> /home/fedora/Arbore/logs/cleanup-test-db.log 2>&1") | crontab -
crontab -l
```

Manual validation (may print "skip" if a CI run is in progress, that's OK):

```bash
/home/fedora/Arbore/scripts/cleanup-test-db.sh
```

The script checks that no GitHub Actions CI run is in progress before
dropping the DB. It uses `gh` if authenticated, otherwise `curl` without a token (since
the repo is public, the Actions API is readable without auth).

---

## 10. Restore from a Mongo backup

`deploy.sh` produces a snapshot in `backups/daily/` before each
rebuild. To restore a specific backup (disaster, rollback):

```bash
cd /home/fedora/Arbore/backups/daily
ls -lt | head -5                                   # locate the desired snapshot
SNAPSHOT="arbore-predeploy-2026-05-13T22-15-06Z"
tar -xzf "${SNAPSHOT}.tar.gz"

source /home/fedora/Arbore/.env
mongorestore --uri="$MONGODB_URI" --drop --nsInclude="arbore.*" "$SNAPSHOT/arbore"
```

> `--drop` replaces the **prod** DB. To restore into `arbore_test`,
> add `--nsFrom='arbore.*' --nsTo='arbore_test.*'` and use
> `MONGODB_URI_TEST`.

---

## 11. Post-bootstrap sanity checklist

Check off these items before considering the VPS operational:

- [ ] `systemctl is-active docker crond nginx` → all `active`
- [ ] `sudo docker compose ps` → `arbore-backend` + `arbore-ai-generator` + `arbore-web` healthy
- [ ] `curl -fsS http://localhost:8080/health` → 200 OK
- [ ] `curl -fsS http://localhost:3000/` → 200 OK (web)
- [ ] `curl -fsS http://<VPS_IP>/health` → 200 OK (via nginx)
- [ ] `mongosh "$MONGODB_URI" --quiet --eval 'db.users.countDocuments()'` → integer > 0
- [ ] `crontab -l` contains the `cleanup-test-db.sh` entry
- [ ] `/home/fedora/Arbore/scripts/cleanup-test-db.sh` finishes with exit 0
- [ ] `ls /home/fedora/Arbore/backups/daily/` does not crash (the folder is created on the first `deploy.sh`)
- [ ] A test PR on GitHub triggers the CI; the tests pass while
      pointing to `arbore_test`

---

## Appendix — Firewall / cloud provider

Depending on the provider, the VM-level firewall may be managed by:

- **`cf-http-firewall.service`** (in place on the current VM): `iptables`
  rules that restrict `:80` **and** `:443` to **Cloudflare IPs** only
  (chain `CF-HTTP`, ranges auto-refreshed every week by
  `cf-update-ranges.timer` with validation + rollback) and **block direct
  external access** to `:8080`/`:8000` (chain `DOCKER-USER`, v4 + v6, scope
  `eth0`). Script: `/usr/local/sbin/cf-http-firewall.sh`.
- The cloud dashboard's "Network" rules (Oracle Cloud, OVH, etc.), where applicable.

Public ports: **22** (SSH), **80** and **443** (via nginx, **Cloudflare-only**).
**Do NOT expose** `:8080`, `:8000` or `:3000`: reachable only on
localhost (via nginx for `:8080` and `:3000`) and between containers — direct
external access is blocked by the firewall above.

---

## Appendix — Secret rotation

In case of a leak (see issue history #117, #119):

1. **Application API key**: generate a new value, update
   `ARBORE_API_KEY` in `.env`, redeploy (`sudo docker compose up -d
   backend`). Update `Secrets.xcconfig` on the iOS side and the GitHub
   Actions secrets.
2. **MongoDB user**: Atlas → Database Access → Edit → new password.
   Update `MONGODB_URI` in `.env`, redeploy.
3. **Firebase service account**: Firebase Console → revoke the
   compromised key, generate a new one, replace the JSON on the VPS,
   redeploy.
4. **Re-scan the git history** with `gitleaks detect --config
   .gitleaks.toml` to make sure the new value is not, in turn,
   in a commit.
