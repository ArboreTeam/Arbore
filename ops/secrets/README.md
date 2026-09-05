# `ops/secrets/` — secrets chiffrés, inventaire en clair

## Le principe

SOPS chiffre les **valeurs** et laisse les **clés** en clair :

```yaml
MONGODB_URI: ENC[AES256_GCM,data:x8Kd...,type:str]
GEMINI_API_KEY: ENC[AES256_GCM,data:9fQm...,type:str]
```

L'inventaire est donc versionné, diffable, lisible en revue de PR. Les valeurs ne le sont pas.

C'est cette propriété qui rend tenable le critère de #401 : **une machine neuve sait quoi lui fournir, sans que le dépôt révèle les valeurs.**

## Ce qui est ici, et ce qui n'y est pas

| Fichier | Versionné | Contenu |
|---|---|---|
| `env.template` | ✅ | inventaire des 24 variables, aucune valeur |
| `prod.enc.env` | ✅ | valeurs de production, **chiffrées** |
| `dev.enc.env` | ✅ | valeurs de dev, **chiffrées** |
| clé privée `age` | ❌ **jamais** | le seul secret à poser à la main |

## Mise en place — à faire une fois

### 1. Installer l'outillage

```bash
brew install sops age          # macOS
sudo dnf install -y age && \
  curl -sSL https://github.com/getsops/sops/releases/latest/download/sops-v3.x.x.linux.amd64 \
  -o /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops   # Fedora / VPS
```

### 2. Générer une paire de clés par environnement

```bash
age-keygen -o ~/.config/sops/age/arbore-prod.txt
```

La sortie affiche la clé **publique** (`age1...`). La clé **privée** est dans le fichier — elle ne doit jamais entrer dans le dépôt, ni dans un message, ni dans un presse-papier partagé.

### 3. Renseigner `.sops.yaml`

Remplacer les marqueurs `REMPLACER_PAR_LA_CLE_PUBLIQUE_AGE_*` par les clés publiques produites.

> Tant que les marqueurs sont en place, tout chiffrement échoue. C'est voulu : mieux vaut une erreur qu'un fichier chiffré vers une clé fantôme, indéchiffrable.

### 4. Chiffrer les valeurs réelles

**Depuis le VPS, sans que les valeurs transitent ailleurs :**

```bash
cd /home/fedora/Arbore
cp .env /tmp/prod.env                       # copie de travail
sops --encrypt /tmp/prod.env > ops/secrets/prod.enc.env
shred -u /tmp/prod.env                      # effacement de la copie claire
```

Puis les trois fichiers secrets :

```bash
sops --encrypt /home/fedora/arbore-data/secrets/firebase-adminsdk.json \
  > ops/secrets/prod.enc.json
sops --encrypt /home/fedora/arbore-data/secrets/apple-siwa.p8 \
  > ops/secrets/prod.enc.p8
sops --encrypt /home/fedora/arbore-data/secrets/master-encryption.key \
  > ops/secrets/prod.enc.key
```

### 5. Vérifier avant de commiter

```bash
grep -c "ENC\[" ops/secrets/prod.enc.env    # doit valoir le nombre de secrets
grep -E "mongodb\+srv|AIza|sk-" ops/secrets/prod.enc.env && echo "⚠️ FUITE" || echo "✅ propre"
```

Le second contrôle cherche des motifs de secrets en clair. **S'il trouve quelque chose, ne pas commiter.**

## Usage courant

```bash
sops ops/secrets/prod.enc.env               # éditer (déchiffre, rouvre, rechiffre)
sops --decrypt ops/secrets/prod.enc.env     # afficher en clair
```

## Le problème d'amorçage, irréductible

Il reste à poser la clé privée sur une machine neuve. **Aucun système n'y échappe** — Vault a son jeton de descellement, AWS son rôle d'instance.

Mais on passe de **24 valeurs à poser à la main à une seule**. C'est le minimum théorique.

## ⚠️ Deux pièges

**Ne jamais déchiffrer `MASTER_ENCRYPTION_KEY` vers l'environnement.** Le code préfère déjà `MASTER_ENCRYPTION_KEY_PATH` parce qu'une variable est lisible par `docker inspect` et `/proc/<pid>/environ` — or cette clé déchiffre les refresh tokens Apple (audit #338 constat 4). Le déploiement doit écrire un **fichier**.

**Un projet Firebase par environnement.** Le job de réconciliation (#393) tourne chaque dimanche avec `--apply` et compare les uid Firebase à une base Mongo. Pointé vers le mauvais couple, **il vide la mauvaise base**. Aucune de ses quatre gardes ne couvre ce cas.

## État

Le **mécanisme** est en place ; **aucune valeur réelle n'est encore chiffrée**. Les étapes 1 à 5 restent à exécuter, et l'intégration à `deploy.sh` viendra ensuite — elle ne peut pas être écrite ni testée avant qu'un fichier chiffré existe.

## Références

#401 §6 bis (choix de SOPS et alternatives écartées) · #338 constat 4 · #393
