# Enregistrements de ZONE — ils appartiennent au domaine, pas à un
# environnement. Un environnement de dev ne redéclare pas la messagerie ni le
# site vitrine : d'où `manage_zone_records`, vrai en production seulement.
#
# Ils étaient jusqu'ici configurés à la main, donc invisibles du dépôt et hors
# de portée de docs-drift-check.sh — exactement la colonne « volatile » du §2
# de #401. Les laisser dehors aurait fait de cette issue une demi-mesure.
#
# ⚠️ Les enregistrements de messagerie sont les plus dangereux du fichier. Une
# erreur ici ne provoque pas d'erreur visible : le courrier cesse simplement
# d'arriver, et personne ne s'en aperçoit avant des jours.

locals {
  zone_records = var.manage_zone_records ? 1 : 0
}

# ── Apex ──────────────────────────────────────────────────────────────────
# `100::` est le préfixe IPv6 de rejet (RFC 6666), utilisé ici comme cible
# fictive : il permet de proxifier l'apex par Cloudflare sans origine réelle,
# de sorte que les règles de redirection s'appliquent. Il ne route rien, et
# c'est voulu. Sans ce commentaire, la valeur passe pour une erreur.
resource "cloudflare_dns_record" "apex" {
  count   = local.zone_records
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "AAAA"
  content = "100::"
  proxied = true
  ttl     = 1
}

# ── Site vitrine ──────────────────────────────────────────────────────────
# Hébergé par GitHub Pages, dépôt Arbore_SiteVitrine. NON proxifié : Pages
# émet et renouvelle son propre certificat, ce que le proxy Cloudflare
# empêcherait.
resource "cloudflare_dns_record" "www" {
  count   = local.zone_records
  zone_id = var.cloudflare_zone_id
  name    = "www.${var.domain}"
  type    = "CNAME"
  content = "arboreteam.github.io"
  proxied = false
  ttl     = 1
}

# ── Messagerie iCloud (domaine personnalisé) ──────────────────────────────
# Jamais proxifié : le proxy Cloudflare ne traite que HTTP(S), il ne relaie
# pas SMTP.
resource "cloudflare_dns_record" "mx" {
  for_each = var.manage_zone_records ? {
    "01" = "mx01.mail.icloud.com"
    "02" = "mx02.mail.icloud.com"
  } : {}

  zone_id  = var.cloudflare_zone_id
  name     = var.domain
  type     = "MX"
  content  = each.value
  priority = 10
  proxied  = false
  ttl      = 3600
}

# SPF — autorise les serveurs iCloud à émettre pour ce domaine. Le supprimer
# fait classer le courrier sortant en indésirable.
resource "cloudflare_dns_record" "spf" {
  count   = local.zone_records
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "TXT"
  content = "\"v=spf1 include:icloud.com ~all\""
  proxied = false
  ttl     = 3600
}

# Preuve de propriété du domaine exigée par Apple. À conserver tant que la
# messagerie iCloud est active.
resource "cloudflare_dns_record" "apple_domain" {
  count   = local.zone_records
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "TXT"
  content = "\"apple-domain=mr6sfDHukeauHOre\""
  proxied = false
  ttl     = 3600
}

# DKIM — signature du courrier sortant.
resource "cloudflare_dns_record" "dkim" {
  count   = local.zone_records
  zone_id = var.cloudflare_zone_id
  name    = "sig1._domainkey.${var.domain}"
  type    = "CNAME"
  content = "sig1.dkim.arbore.app.at.icloudmailadmin.com"
  proxied = false
  ttl     = 3600
}
