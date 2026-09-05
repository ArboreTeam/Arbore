#!/usr/bin/env bash
# Durcissement reseau de l'origine Arbore (idempotent, ne touche jamais :22) :
#  - nginx :80  -> autorise uniquement les IP Cloudflare (chaine CF-HTTP)
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

# --- :8080 / :8000 : pas d'acces externe direct (v4 + v6) ---
for fw in iptables ip6tables; do
  for port in 8080 8000; do
    $fw -C DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP 2>/dev/null || \
      $fw -I DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP
  done
done

echo "cf-http-firewall applied OK (${#CF_RANGES[@]} CF ranges)"
