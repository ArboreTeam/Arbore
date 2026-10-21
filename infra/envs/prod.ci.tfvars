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

# Machine servant la production.
origin_ip = "79.137.92.154"

# Vide = dev suit la production. Renseignée pendant une migration pour
# éprouver une machine neuve derrière Cloudflare sans déplacer le trafic (#652).
#
# RENSEIGNÉE le 2026-10-21 : `api-dev.arbore.app` passe sur la machine de
# migration. `api` et `web` restent sur celle en service. À remettre vide une
# fois la bascule complète faite, pour que dev retourne suivre la production.
dev_origin_ip = "162.19.13.82"

# L'atelier 3D suit les modèles qu'il produit, donc la machine de migration.
# Ce n'est pas une surface d'utilisateur : l'app mobile ne l'appelle pas, et
# son état est un fichier sur disque, pas une base (#652).
generator_origin_ip = "162.19.13.82"

r2_bucket_name  = "arbore-assets"
r2_jurisdiction = "eu"

manage_zone_records  = true
enable_dev_hostnames = true
