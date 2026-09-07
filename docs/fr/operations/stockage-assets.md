# Stockage des assets 3D

Où vivent les 372 fichiers du catalogue — 124 modèles légers, 124 haute
définition, 124 vignettes — et comment en changer sans interrompre le service.

## Pourquoi ce document existe

L'accès au VPS actuel est coupé **fin février**. Les assets n'y existent
aujourd'hui qu'en un seul exemplaire : sans migration, ils disparaissent avec la
machine. Ce document décrit la manœuvre, pour qu'elle ne dépende pas de la
mémoire de qui l'a préparée.

## Les trois supports

Un seul jeu de variables les configure tous : R2, S3 et MinIO parlent le même
protocole. Changer de fournisseur, c'est changer des **valeurs**, pas des
champs — c'est ce qu'achète l'abstraction `StorageProvider`
(`ArboreBackend/storageprovider.go`).

| `STORAGE_PROVIDER` | Usage | Particularité |
|---|---|---|
| `filesystem` | défaut, et état actuel de la production | sert depuis `MODELS_HOST_PATH` |
| `r2` / `s3` | production visée | aucun frais de sortie chez R2 |
| `minio` | développement local | `STORAGE_S3_USE_SSL=false` |

L'inventaire complet des variables, avec un exemple par support, est dans
[`ops/secrets/env.template`](../../../ops/secrets/env.template).

## Pourquoi Cloudflare R2

**R2 ne facture jamais la sortie.** Une app mobile qui télécharge des modèles de
121 Mo rend ce poste imprévisible chez un fournisseur qui le tarife — c'est le
seul risque financier réel du projet.

S'y ajoute le fait que Cloudflare est déjà dans la chaîne : pas de fournisseur
supplémentaire à opérer, et un palier gratuit de 10 Go qui ne s'éteint pas.

> ⚠️ **Ne pas choisir la classe de stockage *Infrequent Access*.** Elle réduit
> le prix du stockage mais **facture la récupération** — ce qui réintroduit
> exactement le coût par téléchargement que R2 permet d'éviter.

## Créer le seau

Tableau de bord Cloudflare → **R2 Object Storage** → *Create bucket*.

```
Nom              arbore-assets      (permanent)
Location         Automatic
Storage class    Standard           ← surtout pas Infrequent Access
```

Un moyen de paiement est exigé à l'activation, même sous les 10 Go gratuits.
Poser une **alerte de facturation** basse dans les notifications du compte.

### Le jeton d'API

R2 → **Manage R2 API Tokens** → *Create **Account** API Token*.

| Réglage | Valeur | Pourquoi |
|---|---|---|
| Type | **Account**, pas User | un jeton utilisateur meurt avec l'accès de son créateur ; la production ne doit pas en dépendre |
| Permissions | **Object Read & Write** | *Admin* permettrait de supprimer le seau lui-même |
| Portée | **ce seau uniquement** | « tous les seaux, y compris futurs » annule l'intérêt du cadrage |
| TTL | illimité | une expiration oubliée casserait le service en silence ; à faire tourner manuellement |
| Filtre IP | vide | un filtre transformerait chaque changement de machine en panne difficile à diagnostiquer |

⚠️ **La clé secrète n'est affichée qu'une fois.**

### L'endpoint

À relever dans les **paramètres du seau, section S3 API** — ne pas le
reconstruire de mémoire. Un seau en juridiction UE s'adresse en
`<account-id>.eu.r2.cloudflarestorage.com`, avec un `.eu.` que l'on oublie.

Retirer le `https://` et tout ce qui suit l'hôte : la bibliothèque veut l'hôte
seul.

## Migrer vers R2 — l'ordre importe

L'ordre inverse ferait servir la production depuis un seau vide : tous les
modèles en 404, immédiatement.

```
1. ajouter les identifiants dans ops/secrets/prod.enc.env,
   en laissant STORAGE_PROVIDER=filesystem        ← la prod ne bouge pas
2. déployer                                        ← le VPS reçoit les identifiants
3. téléverser les 372 fichiers depuis le VPS
4. vérifier les empreintes
5. passer STORAGE_PROVIDER=r2 et redéployer
```

Les identifiants s'ajoutent sans jamais transiter en clair :

```bash
EDITOR=nano SOPS_AGE_KEY_FILE=~/.config/sops/age/arbore-prod.txt \
  sops ops/secrets/prod.enc.env
```

## Revenir en arrière

**Ne rien supprimer du disque tant que la bascule n'est pas éprouvée.** Le
retour arrière tient alors en une variable :

```
STORAGE_PROVIDER=filesystem
```

puis un déploiement. Les fichiers étant toujours dans `arbore-data/models`, le
service repart comme avant.

Ce n'est qu'après avoir vu l'app télécharger réellement depuis R2 que le disque
peut être nettoyé — et une copie hors machine doit exister d'ici là.

## Le garde-fou

`guardedStorage` encapsule **tous** les supports, disque compris, et refuse
au-delà de seuils configurés. Un emballement sur disque n'est pas gratuit non
plus : il sature les entrées-sorties et masque le défaut qui le provoque.

```
STORAGE_MAX_OPS_PER_MINUTE   défaut 600 ; 0 = illimité
STORAGE_MAX_OBJECT_BYTES     défaut 200 Mio
```

Un refus rend **503 avec `Retry-After`**, pas 404 : le fichier existe, c'est le
backend qui refuse de le servir. Les refus sont journalisés par fenêtre, en
nommant la variable à relever — un seuil trop bas ne dégradera pas le service en
silence.

Sur un MinIO local, relever largement : l'opération n'y coûte rien.

> La garde protège d'un emballement **aigu**, pas d'une surconsommation modérée
> mais soutenue. Le compteur est en mémoire, par processus, remis à zéro au
> redémarrage. Une alerte de facturation côté fournisseur reste utile.

## Références

#401 étape 5 (abstraction et quotas) · #341 (assets hors du checkout git) ·
[`ops/secrets/README.md`](../../../ops/secrets/README.md) (procédure SOPS)
