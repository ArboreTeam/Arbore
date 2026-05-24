#!/usr/bin/env bash
# Issue #160 — wrapper d'exécution du script Mongo de cleanup des
# comptes de test. Conçu pour le cron hebdomadaire :
#
#   0 4 * * 0 /home/fedora/Arbore/ArboreBackend/scripts/cleanup-test-users.sh \
#     >> /home/fedora/Arbore/logs/cleanup-test-users.log 2>&1
#
# Lit `MONGODB_URI` depuis le `.env` de la racine du repo (priorité 1)
# ou du backend (fallback). Sort en erreur si introuvable.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
JS_SCRIPT="$SCRIPT_DIR/cleanup-test-users.js"

if [[ ! -f "$JS_SCRIPT" ]]; then
    echo "[cleanup-test-users] missing $JS_SCRIPT" >&2
    exit 2
fi

# Localise un .env utilisable : root du repo en priorité, backend en fallback.
ENV_CANDIDATES=(
    "$SCRIPT_DIR/../../.env"
    "$SCRIPT_DIR/../.env"
)

ENV_FILE=""
for candidate in "${ENV_CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
        ENV_FILE="$candidate"
        break
    fi
done

if [[ -z "$ENV_FILE" ]]; then
    echo "[cleanup-test-users] no .env found in any of: ${ENV_CANDIDATES[*]}" >&2
    exit 3
fi

# Extrait MONGODB_URI (tolère guillemets simples ou doubles autour de la valeur).
MONGODB_URI="$(grep -E '^MONGODB_URI=' "$ENV_FILE" | head -1 | sed -E 's/^MONGODB_URI=//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')"

if [[ -z "$MONGODB_URI" ]]; then
    echo "[cleanup-test-users] MONGODB_URI not set in $ENV_FILE" >&2
    exit 4
fi

printf '[cleanup-test-users] %s UTC — starting cleanup against %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(echo "$MONGODB_URI" | sed -E 's|mongodb[^@]*@||; s|/.*||')"

mongosh "$MONGODB_URI" --quiet --file "$JS_SCRIPT"
