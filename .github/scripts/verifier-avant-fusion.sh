#!/usr/bin/env bash
# Refuse de déclarer une PR fusionnable tant que CHAQUE vérification n'a pas
# conclu en SUCCESS, SKIPPED ou NEUTRAL.
#
#   bash .github/scripts/verifier-avant-fusion.sh 787
#
# Sort 0 si tout a conclu favorablement, 1 sinon. Imprime ce qui manque.
#
# ## Pourquoi ce script existe
#
# Trois façons de lire l'état d'une PR se sont contredites le même jour (#785),
# et chacune aurait pu faire fusionner du code non vérifié.
#
# 1. **Le code de sortie de `gh pr checks` ne suffit pas.** Il rend 0 sur une
#    vérification ANNULÉE, tout en l'affichant dans la colonne « fail ». Une
#    suite annulée n'a rien éprouvé : ce n'est ni un succès ni un échec, et
#    c'est précisément le cas qu'un garde-fou doit attraper.
#
# 2. **`gh pr checks | tail` masque le code de sortie.** Dans un tube, `$?` est
#    celui de `tail`, donc toujours 0. Une PR a été fusionnée ainsi avec deux
#    vérifications encore en vol.
#
# 3. **`conclusion` est une chaîne VIDE, pas `null`, sur un job en cours.** Un
#    filtre `conclusion != null` compte donc les jobs qui tournent parmi les
#    échecs, et noie le seul échec réel au milieu.
#
# D'où la règle d'ici : on ne regarde JAMAIS un code de sortie agrégé. On
# énumère les vérifications, on exige que chacune ait un `status` COMPLETED, et
# on n'accepte que trois conclusions.
#
# `NEUTRAL` est accepté parce que CodeQL le rend normalement. `SKIPPED` l'est
# parce que le dépôt saute volontairement les jobs hors périmètre (filtre
# `changes`, et la promotion `dev` -> `main` qui ne rejoue pas les tests macOS).

set -euo pipefail

pr="${1:-}"
if [[ -z "$pr" ]]; then
  echo "usage: $(basename "$0") <numero-de-pr>" >&2
  exit 2
fi

# Le JSON passe par l'environnement, et non par l'entree standard : le
# programme Python occupe deja celle-ci via son heredoc. Deux redirections
# d'entree se concurrencent, et la derniere gagne — le script ne serait meme
# pas lu.
ROLLUP_JSON="$(gh pr view "$pr" --json statusCheckRollup,title,state)" \
PR_NUMERO="$pr" python3 - <<'PY'
import json
import os

pr = os.environ["PR_NUMERO"]
doc = json.loads(os.environ["ROLLUP_JSON"])
checks = doc.get("statusCheckRollup") or []

if doc.get("state") != "OPEN":
    print(f"PR #{pr} n'est pas ouverte (etat {doc.get('state')}).")
    raise SystemExit(1)

if not checks:
    # Cas des PR empilees : `ci.yml` filtre `pull_request` sur les bases
    # `main` et `dev`, donc une PR visant une branche de feature ne recoit
    # AUCUNE verification. Zero echec n'y est pas un succes.
    print(f"PR #{pr} : AUCUNE verification enregistree.")
    print("  Si la PR vise une branche de feature, la CI ne se declenche pas.")
    print("  Rebaser sur `dev` et forcer le push.")
    raise SystemExit(1)

ACCEPTEES = {"SUCCESS", "SKIPPED", "NEUTRAL"}
en_cours, refusees = [], []

for c in checks:
    nom = c.get("name") or c.get("context") or "(sans nom)"
    statut = c.get("status") or ""
    # `state` pour les StatusContext, `conclusion` pour les CheckRun.
    conclusion = (c.get("conclusion") or c.get("state") or "").upper()
    if statut and statut != "COMPLETED":
        en_cours.append((nom, statut))
    elif conclusion not in ACCEPTEES:
        refusees.append((nom, conclusion or "(vide)"))

for nom, statut in en_cours:
    print(f"  EN COURS   {nom} ({statut})")
for nom, conclusion in refusees:
    print(f"  REFUSEE    {nom} = {conclusion}")

if en_cours or refusees:
    total = len(en_cours) + len(refusees)
    print(f"\nPR #{pr} : {total} verification(s) non conclues favorablement "
          f"sur {len(checks)}. NE PAS FUSIONNER.")
    raise SystemExit(1)

print(f"PR #{pr} : les {len(checks)} verifications ont conclu favorablement.")
PY
