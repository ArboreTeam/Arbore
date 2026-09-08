# Enregistrements PROPRES À UN ENVIRONNEMENT (#401 §3 : « Domaine, TLS, DNS »
# varie). Chaque environnement a ses propres noms d'hôte pointant vers sa
# machine ; les enregistrements de zone, eux, sont dans dns_zone.tf.
#
# Ils existent déjà et servent la production : imports.tf les fait ADOPTER.
# Un plan qui proposerait de les détruire coupe le service.
#
# `proxied = true` n'est pas un réglage de confort. Le pare-feu d'origine
# (ops/systemd/cf-http-firewall.service) verrouille :80 sur les seules plages
# Cloudflare. Dé-proxifier rend l'origine injoignable.
#
# `ttl = 1` signifie « automatique », obligatoire quand proxied vaut true.

resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_hostname
  type    = "A"
  content = var.origin_ip
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "web" {
  zone_id = var.cloudflare_zone_id
  name    = var.web_hostname
  type    = "A"
  content = var.origin_ip
  proxied = true
  ttl     = 1
}

# ── Environnements secondaires ────────────────────────────────────────────
#
# Déclarés dans CE state, pas dans un state par environnement.
#
# #401 prévoyait l'inverse. Pour deux enregistrements dans la MÊME zone, la
# séparation coûterait plus qu'elle ne protège : un `init -reconfigure` oublié
# ferait appliquer les variables de dev contre le state de prod, et Terraform
# proposerait de détruire les dix ressources de production. Le mode d'échec est
# sans commune mesure avec le bénéfice.
#
# Le raisonnement de fond : un enregistrement DNS appartient à la ZONE, qui est
# partagée, pas à un environnement. C'est la même logique que
# `manage_zone_records`.
#
# Ce qui appartient VRAIMENT à un environnement — son bucket, son cluster —
# justifiera un state séparé le jour où il existera.
resource "cloudflare_dns_record" "api_dev" {
  count   = var.enable_dev_hostnames ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "api-dev.${var.domain}"
  type    = "A"
  content = var.origin_ip
  proxied = true
  ttl     = 1
}
