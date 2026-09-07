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

### 3. `.sops.yaml` — déjà renseigné

Les clés publiques de `prod` et `dev` y sont inscrites depuis le 2026-09-07. Rien à faire, sauf à régénérer une paire.

> Les clés **publiques** dans le dépôt sont sans risque : c'est leur raison d'être. Les **privées** vivent dans `~/.config/sops/age/` et n'y entrent jamais.

### 4. Chiffrer les valeurs réelles

**Depuis le VPS, sans que les valeurs transitent ailleurs.**

⚠️ La copie de travail doit être **dans `ops/secrets/`**, pas dans `/tmp` :
SOPS applique ses `creation_rules` au fichier **qu'on lui donne à lire**, pas à
la redirection de sortie. Un fichier hors de ce répertoire ne correspond à
aucune règle et le chiffrement échoue avec `no matching creation rules found`.

Les fichiers en clair y sont gitignorés — le garde-fou du `.gitignore` les
exclut nommément.

```bash
cd /home/fedora/Arbore
export SOPS_AGE_KEY_FILE=~/.config/sops/age/arbore-prod.txt

cp .env ops/secrets/prod.env                          # copie de travail, ignorée par git
sops --encrypt ops/secrets/prod.env > ops/secrets/prod.enc.env
shred -u ops/secrets/prod.env                         # effacement de la copie claire
```

Puis les trois fichiers secrets, selon le même principe :

```bash
cp /home/fedora/arbore-data/secrets/firebase-adminsdk.json ops/secrets/prod.json
sops --encrypt ops/secrets/prod.json > ops/secrets/prod.enc.json
shred -u ops/secrets/prod.json

cp /home/fedora/arbore-data/secrets/apple-siwa.p8 ops/secrets/prod.p8
sops --encrypt ops/secrets/prod.p8 > ops/secrets/prod.enc.p8
shred -u ops/secrets/prod.p8

cp /home/fedora/arbore-data/secrets/master-encryption.key ops/secrets/prod.key
sops --encrypt ops/secrets/prod.key > ops/secrets/prod.enc.key
shred -u ops/secrets/prod.key
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

## État au 2026-09-07

**Le mécanisme est éprouvé de bout en bout** sur des données factices :

```
chiffrement        ✅
clés lisibles      MONGODB_URI  GEMINI_API_KEY  GIN_MODE
valeurs en clair   aucune
aller-retour       fidèle
clé dev sur prod   refusée
```

Les paires de clés `prod` et `dev` sont générées, `.sops.yaml` est renseigné.

**Aucune valeur réelle n'est encore chiffrée** : l'étape 4 reste à faire depuis le VPS. L'intégration à `deploy.sh` viendra après — elle ne peut être ni écrite ni testée avant qu'un fichier chiffré existe.

## Références

#401 §6 bis (choix de SOPS et alternatives écartées) · #338 constat 4 · #393
