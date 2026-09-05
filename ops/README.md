# `ops/` — configuration système déclarative

Source de vérité de tout ce qui vit **hors des conteneurs** : entrées cron, unités systemd, scripts privilégiés.

`deploy.sh` applique ce répertoire à **chaque déploiement**, de façon idempotente (étape 2/7).

## Pourquoi

Ces éléments étaient posés à la main en suivant un runbook. Ils n'existaient donc que sous deux formes — de la prose dans la documentation, et un état sur la machine — sans que rien ne puisse comparer les deux.

Résultat : `vps-bootstrap.md` a décrit **un seul cron** pendant des mois alors que la machine en avait **deux**. La dérive a été découverte par hasard (#393). Ni la CI, qui n'a pas accès au VPS, ni une relecture, qui ne lit que le dépôt, ne pouvaient la voir.

Avec ce répertoire, la dérive n'est plus détectée : elle est **impossible**.

## Conséquence à connaître

**Une modification faite à la main sur la machine est écrasée au déploiement suivant.**

C'est le comportement voulu. Pour changer une entrée cron ou une unité systemd, on modifie le fichier ici et on déploie. Le crontab précédent est sauvegardé dans `logs/crontab.bak.<horodatage>` avant tout écrasement.

## Contenu

| Chemin | Installé vers | Rôle |
|---|---|---|
| `crontab` | crontab de l'utilisateur de déploiement | 3 tâches planifiées |
| `systemd/cf-http-firewall.service` | `/etc/systemd/system/` | restreint nginx :80 aux IP Cloudflare |
| `systemd/cf-update-ranges.service` | `/etc/systemd/system/` | rafraîchit les plages IP Cloudflare |
| `systemd/cf-update-ranges.timer` | `/etc/systemd/system/` | déclenche le rafraîchissement, dimanche 04:00 UTC |
| `sbin/cf-http-firewall.sh` | `/usr/local/sbin/` | applique les règles iptables |
| `sbin/cf-update-ranges.sh` | `/usr/local/sbin/` | récupère et valide les plages Cloudflare |

## `__ARBORE_ROOT__`

`crontab` contient ce jeton, remplacé à l'installation par la racine réelle du checkout. Le fichier reste ainsi valable quel que soit l'emplacement du dépôt — condition pour qu'un second environnement puisse l'utiliser sans le modifier.

## Ce qui n'est PAS ici

- **Les secrets** — hors dépôt par conception. Voir #401 §6 bis (piste SOPS + age).
- **La configuration nginx** — pas encore déclarée, à traiter.
- **`/etc/cf-http-firewall/cf-ranges-v4.txt`** — donnée générée par `cf-update-ranges.sh`, pas une configuration.
- **Le provisionnement initial** de la machine — voir `docs/fr/operations/vps-bootstrap.md`.

## Références

#401 (objectif d'ensemble) · #400 (proposition initiale) · #393 (dérive découverte)
