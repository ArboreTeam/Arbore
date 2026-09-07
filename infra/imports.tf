# ADOPTION DES RESSOURCES EXISTANTES
#
# Tout ce que déclare ce répertoire existe déjà et sert la production.
# Terraform doit l'ADOPTER, pas le créer : sans ces blocs, un premier `apply`
# échouerait sur le bucket (nom déjà pris) et proposerait de remplacer les
# enregistrements DNS — donc une coupure, et pour la messagerie une panne
# silencieuse.
#
# Les blocs `import` (Terraform >= 1.5) sont préférés au `terraform import` en
# ligne de commande : ils sont versionnés, relus en PR, et visibles dans le plan
# avant d'être exécutés. La CLI agit hors du dépôt et ne laisse aucune trace.
#
# Identifiants relevés le 2026-09-07 sur la zone arbore.app. Une fois le premier
# `apply` passé, ces blocs peuvent être supprimés — ils sont sans effet ensuite.

# ── Enregistrements d'environnement ───────────────────────────────────────
import {
  to = cloudflare_dns_record.api
  id = "${var.cloudflare_zone_id}/c7f31e32d5d113953b8bc9723b9e0e7b"
}

import {
  to = cloudflare_dns_record.web
  id = "${var.cloudflare_zone_id}/a70033b3c86c39600e33b2ec83b6726d"
}

# ── Enregistrements de zone ───────────────────────────────────────────────
# Indexés comme les ressources correspondantes : `[0]` pour les `count`,
# `["01"]` / `["02"]` pour le `for_each` des MX.
import {
  to = cloudflare_dns_record.apex[0]
  id = "${var.cloudflare_zone_id}/9d08875953507ceb6f3f340a9afe7863"
}

import {
  to = cloudflare_dns_record.www[0]
  id = "${var.cloudflare_zone_id}/63ce9ce35a5ed0bdd5a01ebe8d1ed6b9"
}

import {
  to = cloudflare_dns_record.mx["01"]
  id = "${var.cloudflare_zone_id}/ef46d37ec4ff7a4877ae1bd16eef2cdc"
}

import {
  to = cloudflare_dns_record.mx["02"]
  id = "${var.cloudflare_zone_id}/112f4ab58b36e11002c100bf904e4570"
}

import {
  to = cloudflare_dns_record.spf[0]
  id = "${var.cloudflare_zone_id}/9bd26f1d6ff71add0a0cc9ddbd1e2559"
}

import {
  to = cloudflare_dns_record.apple_domain[0]
  id = "${var.cloudflare_zone_id}/1ec5fcab1caac12a75d93c92e2d2615f"
}

import {
  to = cloudflare_dns_record.dkim[0]
  id = "${var.cloudflare_zone_id}/b3c7423295cd885a085c7ace66a5964a"
}

# ── Bucket R2 ─────────────────────────────────────────────────────────────
import {
  to = cloudflare_r2_bucket.assets
  id = "${var.cloudflare_account_id}/${var.r2_bucket_name}"
}
