#!/usr/bin/env bash
# Rafraichit la liste des plages IPv4 Cloudflare utilisee par le firewall
# d'origine. Refuse toute liste suspecte (fetch KO, page d'erreur, compte
# anormal) et rollback automatiquement si l'API ne repond plus apres apply.
set -euo pipefail

RANGES_FILE="/etc/cf-http-firewall/cf-ranges-v4.txt"
URL="https://www.cloudflare.com/ips-v4"
TMP="$(mktemp)"; trap 'rm -f "$TMP" "$TMP.norm"' EXIT

# Le repertoire n'etait cree par PERSONNE. (#652)
#
# Les deux scripts du pare-feu nomment ce chemin, `ops/README.md` le decrit
# comme « donnee generee par cf-update-ranges.sh », et aucun ne le creait : il
# existait sur la premiere machine parce qu'il y avait ete pose a la main lors
# de l'installation initiale, en juin.
#
# Sur la machine de migration, il manquait. Le service echouait donc a CHAQUE
# declenchement depuis le 2026-10-25 :
#
#     cf-update-ranges.sh: line 31: /etc/cf-http-firewall/cf-ranges-v4.txt:
#     No such file or directory
#
# Sans consequence visible, et c'est bien le probleme. `cf-http-firewall.sh`
# porte un repli code en dur, utilise des que le fichier manque ou compte
# moins de cinq entrees : le pare-feu reste donc CORRECT, mais FIGE a la liste
# du depot. Le jour ou Cloudflare ajoute une plage, le trafic legitime qui en
# vient serait rejete en silence — une panne partielle, intermittente selon le
# point de presence, et qui ne ressemblerait pas a un pare-feu.
#
# C'est l'ecrivain du fichier qui doit garantir son repertoire.
mkdir -p "$(dirname "$RANGES_FILE")"

# 1. Fetch (echec => on garde l'existant, pas d'erreur bloquante).
if ! curl -fsS -m 20 "$URL" -o "$TMP"; then
  echo "cf-update: fetch KO, on garde les plages actuelles" >&2; exit 0
fi

# 2. Validation stricte : que des CIDR IPv4, aucune ligne parasite, compte sain.
mapfile -t NEW < <(grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' "$TMP" || true)
TOTAL=$(grep -cve '^[[:space:]]*$' "$TMP" || true)
if [ "${#NEW[@]}" -lt 5 ] || [ "${#NEW[@]}" -gt 50 ] || [ "$TOTAL" -ne "${#NEW[@]}" ]; then
  echo "cf-update: reponse suspecte (valides=${#NEW[@]}, total=$TOTAL), abort" >&2; exit 0
fi

# 3. Pas de changement => rien a faire.
printf '%s\n' "${NEW[@]}" | sort > "$TMP.norm"
if [ -f "$RANGES_FILE" ] && diff -q <(sort "$RANGES_FILE") "$TMP.norm" >/dev/null 2>&1; then
  echo "cf-update: aucune evolution des plages"; exit 0
fi

# 4. Backup + ecriture + application.
[ -f "$RANGES_FILE" ] && cp -f "$RANGES_FILE" "$RANGES_FILE.bak"
printf '%s\n' "${NEW[@]}" > "$RANGES_FILE"
systemctl restart cf-http-firewall.service
sleep 2

# 5. Health-check via Cloudflare ; rollback si l'API ne repond plus.
code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' https://api.arbore.app/health || echo 000)
if [ "$code" != "200" ]; then
  echo "cf-update: health-check KO ($code) -> ROLLBACK" >&2
  if [ -f "$RANGES_FILE.bak" ]; then mv -f "$RANGES_FILE.bak" "$RANGES_FILE"; else rm -f "$RANGES_FILE"; fi
  systemctl restart cf-http-firewall.service
  exit 1
fi
echo "cf-update: plages mises a jour (${#NEW[@]} CIDR), health OK"
