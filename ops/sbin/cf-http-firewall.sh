#!/usr/bin/env bash
# Durcissement reseau de l'origine Arbore (idempotent, ne touche jamais :22) :
#  - :80 et :443 -> autorise uniquement les IP Cloudflare, sur les DEUX chemins :
#      * nginx sur l'hote      -> chaine CF-HTTP accrochee a INPUT
#      * nginx en conteneur    -> chaine CF-DOCKER accrochee a DOCKER-USER
#    Le trafic destine a un conteneur ne traverse PAS INPUT (il passe par
#    FORWARD/DOCKER-USER). Ne proteger que INPUT laisserait donc l'origine
#    ouverte des que nginx passerait en conteneur -- sans aucune erreur, le
#    site continuant de fonctionner (#434).
#  - AUCUN port de conteneur joignable depuis eth0, hors :80/:443 Cloudflare.
#    Liste blanche et non enumeration : enumerer les ports se perime a chaque
#    environnement ajoute. Constate le 2026-09-08 -- les ports de dev (8081,
#    3001, 8001) et le web de prod (3000) n'avaient AUCUNE regle. Ce qui les
#    protegeait n'etait pas le pare-feu mais une valeur par defaut dans
#    docker-compose.yml (BIND_ADDRESS=127.0.0.1). Un `.env` posant 0.0.0.0 pour
#    « acceder a dev depuis son poste » aurait expose six services a Internet,
#    sans erreur ni avertissement (#456).
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

# --- Trafic EXTERNE vers un CONTENEUR : liste blanche ---
#
# Un seul saut depuis DOCKER-USER vers une chaine qu'on maitrise entierement,
# videe et reconstruite a chaque passage. C'est ce qui rend l'ordre des regles
# DETERMINISTE : avec des `-I` successifs, l'ordre depend de ce qui existait
# deja, donc d'un historique qu'on ne controle pas.
#
# RETURN et non ACCEPT : un ACCEPT est terminal pour tout le hook FORWARD et
# court-circuiterait les regles propres de Docker (suivi de connexion,
# isolation inter-reseaux). RETURN rend la main a DOCKER-USER, qui poursuit.
#
# Portee `-i eth0` : le trafic inter-conteneurs passe par le bridge, pas par
# eth0, et le trafic sortant porte `-o eth0`. Ni l'un ni l'autre n'est touche.
iptables -N ARBORE-EXT 2>/dev/null || true
iptables -F ARBORE-EXT

# EN PREMIER, et c'est vital : le trafic de RETOUR des connexions sortantes.
#
# `-i eth0` matche les paquets ARRIVANT sur eth0. Un conteneur qui joint
# MongoDB Atlas envoie en `-o eth0`, mais la reponse ARRIVE en `-i eth0` et est
# forwardee vers lui -- elle tombait donc dans le DROP final.
#
# Sans cette regle, les conteneurs sont coupes d'Internet. Constate en
# production le 2026-09-08 : le backend ne pouvait plus joindre Atlas, son
# healthcheck echouait, et `web` -- qui depend de sa sante -- n'a jamais
# demarre. Le service est reste indisponible jusqu'a l'insertion de cette ligne.
#
# La regle avait ete annoncee « inerte car tout est sur la loopback ». C'etait
# faux : elle ne l'etait que pour le trafic ENTRANT vers un port publie, pas
# pour le retour du trafic sortant.
iptables -A ARBORE-EXT -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN

for cidr in "${CF_RANGES[@]}"; do
  iptables -A ARBORE-EXT -p tcp -m multiport --dports 80,443 -s "$cidr" -j RETURN
done
iptables -A ARBORE-EXT -j DROP

iptables -C DOCKER-USER -i "$EXT_IF" -j ARBORE-EXT 2>/dev/null || \
  iptables -I DOCKER-USER -i "$EXT_IF" -j ARBORE-EXT

# Les regles par port de la version precedente deviennent redondantes : la
# liste blanche les couvre toutes. On les retire pour qu'il ne reste qu'une
# seule source de verite -- deux mecanismes concurrents finissent par diverger.
for port in 80 443; do
  while iptables -C DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j CF-DOCKER 2>/dev/null; do
    iptables -D DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j CF-DOCKER
  done
done
for port in 8080 8000; do
  while iptables -C DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP 2>/dev/null; do
    iptables -D DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP
  done
done
iptables -F CF-DOCKER 2>/dev/null || true
iptables -X CF-DOCKER 2>/dev/null || true

# IPv6 : DROP sec sur tout trafic externe vers un conteneur. Les enregistrements
# de l'origine sont des A (IPv4), Cloudflare joint donc l'origine en v4 et aucun
# chemin v6 legitime n'existe.
ip6tables -N ARBORE-EXT6 2>/dev/null || true
ip6tables -F ARBORE-EXT6
ip6tables -A ARBORE-EXT6 -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
ip6tables -A ARBORE-EXT6 -j DROP
ip6tables -C DOCKER-USER -i "$EXT_IF" -j ARBORE-EXT6 2>/dev/null || \
  ip6tables -I DOCKER-USER -i "$EXT_IF" -j ARBORE-EXT6
while ip6tables -C DOCKER-USER -i "$EXT_IF" -j DROP 2>/dev/null; do
  ip6tables -D DOCKER-USER -i "$EXT_IF" -j DROP
done
for port in 80 443 8080 8000; do
  while ip6tables -C DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP 2>/dev/null; do
    ip6tables -D DOCKER-USER -i "$EXT_IF" -p tcp --dport "$port" -j DROP
  done
done

echo "cf-http-firewall applied OK (${#CF_RANGES[@]} plages CF ; INPUT + liste blanche DOCKER-USER)"
