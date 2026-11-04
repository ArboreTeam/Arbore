# Variables NON SENSIBLES de la production, pour la CI.
#
# `envs/prod.tfvars` est gitignoré — à raison, il porte les identifiants de
# compte et de zone. Mais la CI ne peut pas lire un fichier absent du dépôt,
# et un `plan` a besoin de toutes les variables.
#
# D'où ce fichier, qui ne contient QUE ce qui est déjà public ou sans valeur
# pour un attaquant. Les quatre valeurs sensibles arrivent par
# `TF_VAR_*` depuis les secrets du dépôt, jamais par ici :
#
#   TF_VAR_cloudflare_api_token
#   TF_VAR_cloudflare_account_id
#   TF_VAR_cloudflare_zone_id
#
# Le fait que `origin_ip` soit ici est délibéré. L'adresse de l'origine n'est
# pas le contrôle de sécurité — le pare-feu l'est : `cf-http-firewall.service`
# n'accepte que les plages Cloudflare, et les enregistrements restent
# proxifiés. La connaître ne donne rien. En échange, la poser ici rend toute
# bascule de machine VISIBLE comme un diff relu en PR, au lieu d'une valeur
# changée dans un fichier que personne ne voit.

environment = "prod"
domain      = "arbore.app"

api_hostname = "api.arbore.app"
web_hostname = "web.arbore.app"

# Machine servant la production : VPS Debian 12, GRA11, depuis le 2026-11-04.
# L'ancienne (Fedora 40) reste allumée jusqu'au 2026-11-06 comme repli — y
# revenir est un changement de cette seule ligne, suivi d'un apply.
origin_ip = "162.19.13.82"

# Vide = suit `origin_ip`. Renseignées pendant une migration pour éprouver une
# machine neuve derrière Cloudflare sans déplacer le trafic (#652).
#
# Renseignées le 2026-10-21, REVIDÉES le 2026-11-04 : la bascule est faite, les
# quatre noms vivent sur la même machine, et laisser une valeur dupliquée ici
# se désynchroniserait à la prochaine migration — on corrigerait `origin_ip` en
# croyant avoir tout fait.
#
# Le piège reste entier dans l'autre sens : changer `origin_ip` SEUL pendant une
# migration déplace `api` et `web` en laissant `generator` et `api-dev`
# derrière, et le plan ne signale qu'un changement d'adresse. C'est ce que
# `dns.tf` décrit pour `generator`.
dev_origin_ip       = ""
generator_origin_ip = ""

r2_bucket_name  = "arbore-assets"
r2_jurisdiction = "eu"

manage_zone_records  = true
enable_dev_hostnames = true
