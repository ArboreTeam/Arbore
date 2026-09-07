#!/usr/bin/env bash
# Durcissement reseau de l'origine Arbore (idempotent, ne touche jamais :22) :
#  - :80 et :443 -> autorise uniquement les IP Cloudflare, sur les DEUX chemins :
#      * nginx sur l'hote      -> chaine CF-HTTP accrochee a INPUT
#      * nginx en conteneur    -> chaine CF-DOCKER accrochee a DOCKER-USER
#    Le trafic destine a un conteneur ne traverse PAS INPUT (il passe par
#    FORWARD/DOCKER-USER). Ne proteger que INPUT laisserait donc l'origine
#    ouverte des que nginx passerait en conteneur -- sans aucune erreur, le
#    site continuant de fonctionner (#434).
#  - :8080 (API Go) et :8000 (AI generator) -> pas d'acces externe direct
#    (DOCKER-USER v4+v6, scope -i eth0 ; loopback + inter-conteneurs preserves)
set -euo pipefail

EXT_IF="eth0"
RANGES_FILE="/etc/cf-http-firewall/cf-ranges-v4.txt"

# Fallback code en dur : utilise si le fichier manque/est invalide, pour que
# le boot ne casse JAMAIS meme si l'update auto a foire.
CF_FALLBACK=(
173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
)

CF_RANGES=()
if [ -f "$RANGES_FILE" ]; then
  mapfile -t CF_RANGES < <(grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' "$RANGES_FILE" || true)
fi
# Garde-fou : si liste vide/trop courte, on retombe sur le fallback (jamais de DROP-all).
if [ "${#CF_RANGES[@]}" -lt 5 ]; then CF_RANGES=("${CF_FALLBACK[@]}"); fi

# --- nginx :80 : Cloudflare uniquement ---
iptables -N CF-HTTP 2>/dev/null || true
iptables -F CF-HTTP
for cidr in "${CF_RANGES[@]}"; do iptables -A CF-HTTP -s "$cidr" -j ACCEPT; done
iptables -A CF-HTTP -s 127.0.0.1 -j ACCEPT
iptables -A CF-HTTP -j DROP
iptables -C INPUT -p tcp --dport 80 -j CF-HTTP 2>/dev/null || \
  iptables -A INPUT -p tcp --dport 80 -j CF-HTTP
iptables -C INPUT -p tcp --dport 443 -j CF-HTTP 2>/dev/null || \
  iptables -A INPUT -p tcp --dport 443 -j CF-HTTP

# --- :80 / :443 vers un CONTENEUR : Cloudflare uniquement ---
#
# Chaine distincte de CF-HTTP, et ce n'est pas une duplication : dans
# DOCKER-USER il faut RETURN et non ACCEPT. Un ACCEPT serait terminal pour tout
# le hook FORWARD et court-circuiterait les propres regles de Docker (suivi de
# connexion, isolation inter-reseaux). RETURN rend la main a DOCKER-USER, qui
# poursuit normalement.
#
# Inerte tant que nginx ecoute sur l'hote : aucun trafic :80/:443 n'est alors
# forwarde vers un conteneur. La regle devient active le jour ou nginx bascule.
iptables -N CF-DOCKER 2>/dev/null || true
iptables -F CF-DOCKER
for cidr in "${CF_RANGES[@]}"; do iptables -A CF-DOCKER -s "$cidr" -j RETURN; done
iptables -A CF-DOCKER -j DROP
for port in 80 443; do
  iptables -C DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j CF-DOCKER 2>/dev/null || \
    iptables -I DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j CF-DOCKER
done

# IPv6 vers un conteneur sur :80/:443 : DROP sec. Les enregistrements DNS de
# l'origine sont des A (IPv4) -- Cloudflare joint donc l'origine en v4, et il
# n'existe aucun chemin v6 legitime. Fail-closed, coherent avec le traitement
# de :8080 et :8000 ci-dessous.
for port in 80 443; do
  ip6tables -C DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP 2>/dev/null || \
    ip6tables -I DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP
done

# --- :8080 / :8000 : pas d'acces externe direct (v4 + v6) ---
for fw in iptables ip6tables; do
  for port in 8080 8000; do
    $fw -C DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP 2>/dev/null || \
      $fw -I DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP
  done
done

echo "cf-http-firewall applied OK (${#CF_RANGES[@]} CF ranges, INPUT + DOCKER-USER)"
