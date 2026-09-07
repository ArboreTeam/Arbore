# Les deux enregistrements existent déjà et sont servis en production. Ils sont
# ADOPTÉS par les blocs `import` de imports.tf, jamais recréés : un plan qui
# proposerait de les détruire coupe le service.
#
# `proxied = true` n'est pas un réglage de confort. Le pare-feu d'origine
# (#401 §2, ops/systemd/cf-http-firewall.service) verrouille :80 sur les seules
# plages Cloudflare. Dé-proxifier rend l'origine injoignable.

resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_hostname
  type    = "A"
  content = var.origin_ip
  proxied = true
  # 1 = automatique. Obligatoire quand proxied vaut true.
  ttl     = 1
  comment = "Backend Go — géré par Terraform (infra/dns.tf), env ${var.environment}"
}

resource "cloudflare_dns_record" "web" {
  zone_id = var.cloudflare_zone_id
  name    = var.web_hostname
  type    = "A"
  content = var.origin_ip
  proxied = true
  ttl     = 1
  comment = "App Next.js — géré par Terraform (infra/dns.tf), env ${var.environment}"
}
