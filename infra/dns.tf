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
