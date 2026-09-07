# ADOPTION DES RESSOURCES EXISTANTES
#
# Les enregistrements DNS et le bucket R2 existent et servent la production.
# Terraform doit les ADOPTER, pas les créer : un premier `apply` sans import
# tenterait de créer un bucket déjà pris (échec) et, pour le DNS, produirait un
# doublon ou un remplacement — donc une coupure.
#
# Les blocs `import` (Terraform >= 1.5) sont préférés au `terraform import` en
# ligne de commande : ils sont versionnés, relus en PR, et visibles dans le plan
# avant d'être exécutés. La CLI, elle, agit hors du dépôt et ne laisse aucune
# trace.
#
# ⚠️ Les identifiants ci-dessous NE SONT PAS RENSEIGNÉS. Ils ne s'inventent pas :
# les récupérer via le tableau de bord Cloudflare ou l'API, puis décommenter.
# Une fois le premier `apply` passé, ces blocs peuvent être supprimés — ils sont
# sans effet ensuite.
#
#   ID d'un enregistrement DNS :
#     curl -s -H "Authorization: Bearer $CF_TOKEN" \
#       "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records?name=api.arbore.app" \
#       | jq -r '.result[].id'
#
#   ID d'un bucket R2 : "<account_id>/<nom du bucket>"

# import {
#   to = cloudflare_dns_record.api
#   id = "${var.cloudflare_zone_id}/<record_id>"
# }

# import {
#   to = cloudflare_dns_record.web
#   id = "${var.cloudflare_zone_id}/<record_id>"
# }

# import {
#   to = cloudflare_r2_bucket.assets
#   id = "${var.cloudflare_account_id}/${var.r2_bucket_name}"
# }
