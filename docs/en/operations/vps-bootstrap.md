# VPS Bootstrap — Provisioning an Arbore server

Procedure for rebuilding the Arbore backend on a clean VPS.

This runbook is designed to be run in recovery mode (the existing VM
is lost) or migration mode (moving to a new provider).
Every step is idempotent — re-running it on an already-configured system
breaks nothing.

> **Two systems are covered**, because both are in service during the
> migration (#652):
>
> | | distribution | user | home | interface |
> |---|---|---|---|---|
> | **old** | Fedora 40 Cloud | `fedora` | `/home/fedora` | `eth0` |
> | **new** | Debian 12 bookworm | `debian` | `/home/debian` | `ens3` |
>
> Install commands are given for both. The rest of the runbook is shared.
>
> In paths, **`/home/fedora` is an example that follows the user**: on Debian,
> read `/home/debian`. The code itself makes no such assumption — `deploy.sh`
> derives `arbore-data/` from the checkout directory, and the `*_HOST_PATH`
> entries in `.env` are explicit.
>
> Other assumptions: `sudo` NOPASSWD, SSH access via public key, routable
> public IP.

> ⚠️ **Fedora 40 reached end of life in May 2025** and no longer receives
> security updates. The `dnf` commands stay documented for the machine still in
> service, not as a choice to repeat.

---

## Overview

Components installed by the end of the procedure:

| Component | Role |
|---|---|
| Docker + Compose | Runs `arbore-backend` (Go/Gin, `:8080`) and `arbore-web` (Next.js standalone, `:3000`) |
| Nginx | Reverse proxy `:80` + `:443` (TLS, Cloudflare Origin cert): `api.arbore.app` → `127.0.0.1:8080` (backend) and `web.arbore.app` → `127.0.0.1:3000` (web) |
| MongoDB Atlas | Hosted DB (no local Mongo); `mongosh` and `mongodump` on the VPS for cleanup and backups |
| cronie | Runs `cleanup-test-db.sh` every night at 04:00 UTC |
| gh CLI | Used by `cleanup-test-db.sh` (optional, curl fallback) |

The web calls the backend on `http://backend:8080` over the Docker network
`arbore-net`, from its server proxy. These ports are exposed on the host but their direct
external access is blocked by the firewall (see firewall appendix); public
traffic goes through Nginx on `:80`/`:443`, which are themselves restricted to Cloudflare IPs.

---

## 1. System preparation

**Debian 12**

```bash
sudo apt-get -y update && sudo apt-get -y upgrade
sudo apt-get -y install \
    git curl wget jq vim ca-certificates gnupg \
    cron \
    nginx \
    iptables \
    rsync \
    python3
sudo systemctl enable --now cron
```

`iptables` is listed explicitly: the new machine does not ship it, and the
origin firewall depends on it. Debian 12 provides it on an nftables backend,
which suits the script.

`gh` is not in the Debian repos; it is **optional** (`cleanup-test-db.sh`
falls back to `curl`). To install it:

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get -y update && sudo apt-get -y install gh
```

**Fedora 40** — machine still in service

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
systemctl is-active cron    # Debian — "crond" on Fedora
gh --version                # 2.x, if installed

# nginx and iptables live in /usr/sbin, which is NOT on a non-root user's PATH
# on Debian — unlike Fedora. A `command -v` reports them missing when they are
# in fact installed. Check with the full path:
/usr/sbin/nginx -v          # nginx/1.22.1
/usr/sbin/iptables --version  # v1.8.9 (nf_tables)
```

The `(nf_tables)` suffix is expected: Debian 12 ships the `iptables` command
on an nftables backend, and the origin firewall works with it.

---

## 2. Docker + Compose

The project uses the official Docker binaries, compose v2 included, rather
than the distribution packages.

**Debian 12**

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get -y update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

**Fedora 40**

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

Adding the user to the `docker` group is **optional**; the project calls
`sudo docker` everywhere (see `deploy.sh`), so it can be skipped to keep the
privilege separation.

Verification:

```bash
sudo docker --version            # a version prints, not an error
sudo docker compose version      # compose v2 is wired as a subcommand
sudo docker run --rm hello-world # the daemon answers and can pull an image
```

---

## 3. MongoDB tools (mongosh + mongodump)

`mongodump` comes from the `mongodb-database-tools` package. Neither it nor
`mongosh` is in either distribution's repos — MongoDB's own must be added.

**Debian 12**

```bash
curl -fsSL https://pgp.mongodb.com/server-7.0.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list > /dev/null
sudo apt-get -y update
sudo apt-get -y install mongodb-database-tools mongodb-mongosh
```

**Fedora 40**

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

> **Nothing installs `mongod`, and that is deliberate**: the database is hosted
> on Atlas. Only the client tools are needed, for the nightly cleanup and the
> pre-deploy snapshots.

---

## 3b. sops + age — nothing starts without them

`deploy.sh` produces each `.env` by decrypting `ops/secrets/<env>.enc.env`.
**Without `sops` and `age`, no environment file is written and no container
starts.** The runbook did not install them, although they are the first
prerequisite of a deployment.

**Debian 12**

```bash
sudo apt-get -y install age

# The version is DERIVED, never hard-coded: a frozen number in a doc goes
# stale silently and returns a 404 the day you need it.
SOPS_TAG=$(curl -fsSL https://api.github.com/repos/getsops/sops/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_TAG}/sops-${SOPS_TAG}.linux.amd64" -o /tmp/sops
sudo install -m 0755 /tmp/sops /usr/local/bin/sops && rm -f /tmp/sops
```

**Fedora 40**

```bash
sudo dnf -y install age
SOPS_TAG=$(curl -fsSL https://api.github.com/repos/getsops/sops/releases/latest | jq -r .tag_name)
curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_TAG}/sops-${SOPS_TAG}.linux.amd64" -o /tmp/sops
sudo install -m 0755 /tmp/sops /usr/local/bin/sops && rm -f /tmp/sops
```

Verification:

```bash
age --version    # 1.1.1
sops --version   # 3.13.x
```

> **The private age key is not installed, it is carried over.**
> `deploy.sh` looks for it in `~/.config/sops/age/arbore-<env>.txt`. It is the
> only secret to copy from one machine to another — everything else is
> regenerated from the repository's `*.enc.*` files. See
> `ops/secrets/README.md`, and its warning about the newlines a password
> manager silently flattens.

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
| `MASTER_ENCRYPTION_KEY` | Operator secret | **Hex-encoded** 32-byte key (64 characters), used for Apple tokens. Generate with `openssl rand -hex 32`. ⚠️ Not base64: `parseMasterEncryptionKey` does a `hex.DecodeString`. Prefer the file, see `MASTER_ENCRYPTION_KEY_PATH` |
| `MASTER_ENCRYPTION_KEY_PATH` / `..._HOST_PATH` | Operator secret | **Recommended source** for the master key: a file rather than a variable, see below |
| `MONGODB_URI_PATH`, `ARBORE_API_KEY_PATH`, `GEMINI_API_KEY_PATH` (+ `..._HOST_PATH`) | Operator secret | Same file source, extended to the three remaining secrets (#338 finding 4). Leaving them empty keeps the variable: the switch happens machine by machine |
| `APPLE_TEAM_ID` / `APPLE_KEY_ID` | Apple Developer → Keys | Sign in with Apple key identifiers |
| `APPLE_SIWA_CLIENT_ID` | Bundle ID | `com.arboreteam.arbore` for the native iOS flow |
| `APPLE_SIWA_KEY_HOST_PATH` | Absolute path to the Apple `.p8` | Mode `0600`, outside Git |
| `ARBORE_ADMIN_UIDS` | Firebase Authentication | Comma-separated administrator UIDs |
| `MODELS_HOST_PATH` | Persistent VPS storage | USDZ directory, independent from the code checkout |
| `THUMBNAILS_HOST_PATH` | Persistent VPS storage | Generated thumbnails directory |
| `LEGACY_COMMUNITY_UPLOADS_HOST_PATH` | Persistent VPS storage | Retained only for GDPR deletion |
| `GEMINI_API_KEY` | Google AI Studio → API keys | Fallback AI provider |
| `MISTRAL_API_KEY` | admin.mistral.ai → API Keys | **Provider in service** for `/chat` and `/diagnose` |
| `AI_PROVIDER` | Config constant | `gemini` or `mistral`. Default `mistral`, in the code as well as in the deployment |
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
# Master key: the file is preferred over the variable (see the box below).
MASTER_ENCRYPTION_KEY=
MASTER_ENCRYPTION_KEY_PATH=/run/secrets/master-encryption.key
MASTER_ENCRYPTION_KEY_HOST_PATH=/home/fedora/arbore-data/secrets/master-encryption.key
APPLE_TEAM_ID=XXXXXXXXXX
APPLE_KEY_ID=XXXXXXXXXX
APPLE_SIWA_CLIENT_ID=com.arboreteam.arbore
APPLE_SIWA_KEY_HOST_PATH=/home/fedora/arbore-data/secrets/AuthKey_XXXXXXXXXX.p8
MODELS_HOST_PATH=/home/fedora/arbore-data/models
THUMBNAILS_HOST_PATH=/home/fedora/arbore-data/models/thumbnails
LEGACY_COMMUNITY_UPLOADS_HOST_PATH=/home/fedora/arbore-data/uploads/community
# Allowed browser origins. Empty = CORS disabled, the right setting here:
# the web app calls the API through its server-side Next.js proxy (#338 finding 5).
CORS_ALLOWED_ORIGINS=

# AI provider. Before setting mistral, check on
# admin.mistral.ai/plateforme/privacy that both "Data usage for improving our
# services" AND "Enable Labs models" are OFF: the free tier is opted in to
# training by default, and a Labs model voids the opt-out (#555).
AI_PROVIDER=mistral
MISTRAL_API_KEY=...
GEMINI_API_KEY=...

# Gin config
GIN_MODE=release
PORT=8080
EOF
chmod 600 /home/fedora/Arbore/.env
```

### Master key as a file rather than a variable

An environment variable is readable through `docker inspect` and in
`/proc/<pid>/environ`. The project already refuses, for that reason, to load the
Apple `.p8` key from the environment — yet `MASTER_ENCRYPTION_KEY` is precisely
what **decrypts** the Apple refresh tokens: it was less protected than what it
protects (#338 finding 4). Hence the file source:

```bash
mkdir -p /home/fedora/arbore-data/secrets
# From an EXISTING key, copy its value as-is (do NOT generate a new one:
# already-encrypted tokens would become undecryptable).
printf '%s' "$MASTER_ENCRYPTION_KEY" > /home/fedora/arbore-data/secrets/master-encryption.key
# First install only:
#   openssl rand -hex 32 > /home/fedora/arbore-data/secrets/master-encryption.key
chmod 600 /home/fedora/arbore-data/secrets/master-encryption.key
```

Then fill in `MASTER_ENCRYPTION_KEY_PATH` and `MASTER_ENCRYPTION_KEY_HOST_PATH`
in the `.env`, and clear `MASTER_ENCRYPTION_KEY`. The switch is reversible: as
long as `MASTER_ENCRYPTION_KEY_PATH` is empty the backend reads the variable. A
path that is set but **unreadable is an error**, not a silent fallback — under
`GIN_MODE=release`, `validateReleaseSecurityConfig` then refuses to start.

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

Images are built by CI (`.github/workflows/deploy.yml`) on every push to `main`
and published to ghcr, tagged `sha-<commit>`. The VPS pulls them instead of
rebuilding: three builds cost ~10 min of CPU and several GB of intermediate
layers on an already tight disk (#425).

Authentication uses a **classic PAT owned by a machine account**, never an App
and never a personal account.

A GitHub App does not work here: ghcr does not accept App installation tokens
and `packages: read` does not grant pull access. This is an acknowledged
platform limitation
([discussion #171423](https://github.com/orgs/community/discussions/171423)),
verified on this project on 2026-09-07 — `docker login` succeeds, reading the
manifest returns 403.

`deploy.sh` reads `GHCR_USER` / `GHCR_TOKEN` from `.env` (scoped to
`read:packages` only, see `ops/secrets/README.md`). If they are missing the
deployment does not break: the pull is attempted anonymously, then falls back to
a local build **and says so**.

```bash
cd /home/fedora/Arbore
./deploy.sh                   # pulls images, or builds as a fallback
sudo docker compose ps        # backend + web → Up (healthy)
```

For a first manual start, before `deploy.sh` is in place:

```bash
export ARBORE_IMAGE_TAG="sha-$(git rev-parse HEAD)"
sudo docker compose pull backend web
sudo -E docker compose up -d
```

The served commit is verifiable without server access — this is what makes
prod ↔ `main` drift detectable (#341):

```bash
curl -s https://api.arbore.app/health | jq -r .commit
```

End-to-end health check:

```bash
curl -fsS http://localhost:8080/health
# → {"status":"ok","service":"arbore-backend","commit":"<sha>"}
curl -fsS http://localhost:3000/   # web (Next.js)
curl -fsS http://<VPS_IP>/health   # via nginx
```

The `commit` field is the git SHA actually deployed. It is the only way to know
whether production follows `main`:

```bash
curl -s https://api.arbore.app/health | jq -r .commit   # what is running
git rev-parse origin/main                               # what should be running
```

From now on, subsequent deployments go through
`./deploy.sh` (which takes a Mongo snapshot before each rebuild).

**nginx configuration.** Versioned in `ops/nginx/` and applied by `deploy.sh`,
validated with `nginx -t` **before** reloading — a faulty configuration aborts
the deploy without cutting the running service.

⚠️ The **certificates** `/etc/ssl/cloudflare/origin.{pem,key}` stay out of the
repository: they are secrets. A fresh machine must receive them before the
`listen 443` blocks work, otherwise nginx will refuse to start.

⚠️ **MongoDB Atlas IP allowlist.** A test from an outside machine suggests the
cluster is not IP-restricted. **Confirm in the Atlas dashboard** (*Network
Access*) before any migration: if a restriction exists, a fresh machine would be
refused and the backend would fail at startup on the Mongo connection — a
symptom that does not point to its cause.

**Branch guard.** `deploy.sh` refuses to deploy when the checkout is not on the
expected branch (#384). `git pull --ff-only` follows the **current** branch: a
working branch left in place on the machine would be deployed with nothing
signalling it, and the drift would only surface downstream, in the commit exposed
by `/health`.

The expected branch defaults to `main` and is changed with
`ARBORE_DEPLOY_BRANCH` — parameterised rather than hard-coded, so a staging
environment can deploy `dev` without editing the script (#401):

```bash
ARBORE_DEPLOY_BRANCH=dev ./deploy.sh
```

**Checkout guard.** `deploy.sh` refuses to deploy when a git-**tracked** file is
modified — that is uncommitted code, hence a silent divergence. It does
however **tolerate** two things: untracked files (they cannot break a
fast-forward) and changes under `ArboreBackend/models/`, declared as
out-of-band data in `OUT_OF_BAND_PATHS`. Those 3D models are regenerated and
cleaned directly on the server; requiring them to be clean made `deploy.sh`
unusable, and deployments bypassed it — skipping the pre-deploy Mongo
snapshot, the only safety net since Atlas M0 has no automatic backups
(see #341).

USDZ files, thumbnails, legacy uploads, and secrets are meant to live under
`/home/fedora/arbore-data` through absolute `.env` paths, so a fresh release
checkout cannot overwrite or delete them.

> ✅ **Switch completed on 2026-09-05** (#341 cause 3, #401 step 2).
> `MODELS_HOST_PATH=/home/fedora/arbore-data/models` is set in the VPS `.env`,
> and the container does mount that path — verified with `docker inspect` and by
> comparing checksums between the container and a reference manifest.
>
> The 38 `.usdz` that were still tracked by git have been untracked. **A git
> operation can therefore no longer change what the app downloads**, which was
> the point of #341.

---

## 9. Scheduled jobs and system configuration

> **Nothing to install by hand.** `deploy.sh` applies `ops/` on every deploy
> (step 2/7): cron entries, systemd units, privileged scripts. A change made
> directly on the machine is **overwritten** on the next deploy — the repository
> is authoritative.
>
> To change a scheduled job: edit `ops/crontab`, then deploy.

Applied contents, detailed in [`ops/README.md`](../../../ops/README.md):

| Job | Frequency |
|---|---|
| `cleanup-test-db.sh` | daily, 04:00 UTC |
| `cleanup-test-users.sh` (#160) | Sunday 04:00 UTC |
| `reconcile-guests.sh --apply` (#393) | Sunday 05:00 UTC |
| `cf-http-firewall.service` | at boot |
| `cf-update-ranges.timer` | Sunday 04:00 UTC |

The previous crontab is saved to `logs/crontab.bak.<timestamp>` before any
overwrite.

### Verify after a deploy

```bash
crontab -l
systemctl is-enabled cf-http-firewall.service cf-update-ranges.timer
```

### Firebase ↔ Mongo reconciliation — first run

The job deletes production data on the word of an external system. **Run it in
simulation mode before trusting the cron**, which passes `--apply`:

```bash
# Deletes nothing: counts and logs.
/home/fedora/Arbore/ArboreBackend/scripts/reconcile-guests.sh
```

Four guards protect it, and it **exits with an error without deleting anything**
if any one of them is not satisfied:

| Guard | What it prevents |
|---|---|
| Fail-closed on any Firebase error | reading "I don't know" as "delete" |
| Refusing an empty Firebase enumeration | wiping the database on a bad service account |
| 7-day grace period | deleting an account created after the Firebase snapshot |
| Simulation by default | a deletion triggered by accident |

Logs contain totals only, never a `uid`: a `uid` is personal data, and the log
has its own retention period (#385).

⚠️ **No guard protects against pointing at the wrong Firebase project.** On any
environment other than production, check `FIREBASE_SERVICE_ACCOUNT_PATH` and
`MONGODB_URI` before any `--apply`.

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
- [ ] `sudo docker compose ps` → `arbore-backend` + `arbore-web` healthy
- [ ] `curl -fsS http://localhost:8080/health` → 200 OK
- [ ] `curl -fsS http://localhost:3000/` → 200 OK (web)
- [ ] `curl -fsS http://<VPS_IP>/health` → 200 OK (via nginx)
- [ ] `mongosh "$MONGODB_URI" --quiet --eval 'db.users.countDocuments()'` → integer > 0
- [ ] `crontab -l` contains all three entries, installed by `deploy.sh` from `ops/crontab` — never by hand
- [ ] `systemctl is-enabled cf-http-firewall.service cf-update-ranges.timer` → `enabled`
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

### Pointing the iOS app at dev

The Xcode project carries **three** build configurations:

| Configuration | Backend | Use |
|---|---|---|
| `Debug` | `api.arbore.app` | debugging **against production** — reproducing a beta tester's bug |
| `Dev` | `api-dev.arbore.app` | day-to-day development |
| `Release` | `api.arbore.app` | TestFlight archive |

A third configuration rather than "Debug = dev": without it we would lose the
ability to debug against production, which is the only way to faithfully
reproduce an incident reported by a user.

**One-time setup:**

```bash
cp ArboreUi/Secrets.dev.xcconfig.example ArboreUi/Secrets.dev.xcconfig
sops ops/secrets/dev.enc.env   # read ARBORE_API_KEY there
```

Fill `ARBORE_API_KEY` with that value. The file is gitignored.

> The source is **`dev.enc.env`**, not production's `ARBORE_API_KEY_TEST`. Both
> hold the same value today — dev was derived from it — but they are two
> independent settings: the day one is rotated without the other, only
> `dev.enc.env` states what the dev backend accepts.

**In use:** select the **"ArboreUi Dev"** scheme in Xcode before running on the
device. The `ArboreUi` scheme stays on production.

Sentry is left empty in dev: without a DSN it does not start, and test events do
not pollute production reports.

## Releases — deploying a fixed target rather than a branch

`main` is a **moving** target: "deploy main" does not mean the same thing at
different times. A release names a precise artefact, which makes rollback
obvious — you redeploy `v1.2.0`, you do not hunt for a SHA in a log.

### Cutting a release

```bash
git checkout main && git pull
git tag -a v1.2.0 -m "Guest access, image pulling"
git push origin v1.2.0
```

Two workflows react: `deploy.yml` publishes images tagged `1.2.0`, `1.2` and
`sha-<commit>`; `release.yml` creates the GitHub release with its notes.

### Deploying a release

```bash
cd /home/fedora/Arbore
ARBORE_DEPLOY_TAG=v1.2.0 ./deploy.sh
```

The checkout moves to a detached HEAD on the tag. No `git pull`: it is
meaningless outside a branch, and a release must not move.

### Rolling back

```bash
ARBORE_DEPLOY_TAG=v1.1.0 ./deploy.sh
```

That is all. The `v1.1.0` image still exists: retention keeps versions carrying
a `v*` tag **indefinitely**, and only purges branch `sha-` versions beyond the
ten most recent (#442).

### Returning to branch tracking

```bash
git checkout main && ./deploy.sh
```

Branch mode is the default; simply leave `ARBORE_DEPLOY_TAG` unset.

## Dev environment — a second stack on the same machine

Since #434 the machine runs two independent stacks. They share the kernel, the
disk and the Firebase project; they share **neither the deployed version, nor
the ports, nor the environment file**.

| | production | dev |
|---|---|---|
| Checkout | `/home/fedora/Arbore` | `/home/fedora/Arbore-dev` |
| Branch | `main` | `dev` |
| Compose project | `arbore-prod` | `arbore-dev` |
| Containers | `arbore-prod-*` | `arbore-dev-*` |
| Ports | 8080 / 3000 / 8000 | 8081 / 3001 / 8001 |
| Environment file | `.env` | `.env.dev` |
| Mongo database | `arbore` | `arbore_test` |
| age key | `arbore-prod.txt` | `arbore-dev.txt` |

**One checkout per environment is required, not a convenience**: `deploy.sh`
derives the image tag from `git rev-parse HEAD`. A shared checkout would deploy
the same commit on both sides, defeating the point of having two environments.

Deploying dev:

```bash
cd /home/fedora/Arbore-dev
ARBORE_ENV=dev ARBORE_DEPLOY_BRANCH=dev ./deploy.sh
```

Checking that both serve distinct commits:

```bash
curl -s http://localhost:8080/health | jq -r .commit   # prod
curl -s http://localhost:8081/health | jq -r .commit   # dev
```

**A non-primary environment does not touch host configuration** — crontab,
systemd units, nginx. The crontab is rendered with the current checkout path:
applied from `Arbore-dev` it would point production's jobs at that directory,
the reconciliation job included. Only `ARBORE_PRIMARY_ENV` (default `prod`)
applies them.

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
