#!/bin/bash

# 🌍 Script de vérification des traductions Arbore
# Compare les fichiers Localizable.strings pour détecter les clés manquantes

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$SCRIPT_DIR/ArboreUi/ArboreUi"

# Langues supportées
LANGUAGES="en fr de es"

echo -e "${PURPLE}"
echo "╔════════════════════════════════════════╗"
echo "║  🌍 Arbore Translation Checker       ║"
echo "╔════════════════════════════════════════╗"
echo -e "${NC}"

# Fonction pour extraire les clés d'un fichier Localizable.strings
extract_keys() {
    local file=$1
    # Extrait uniquement les lignes avec "KEY" = "value";
    # Ignore les commentaires et lignes vides
    grep -E '^"[^"]+" = ' "$file" 2>/dev/null | sed -E 's/^"([^"]+)" = .*/\1/' | sort || true
}

# Créer un répertoire temporaire
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extraire les clés de chaque langue
echo -e "${BLUE}📊 Extraction des clés de traduction...${NC}"
echo ""

for lang in $LANGUAGES; do
    file="$UI_DIR/${lang}.lproj/Localizable.strings"

    if [ ! -f "$file" ]; then
        echo -e "${RED}❌ Fichier non trouvé: $file${NC}"
        continue
    fi

    extract_keys "$file" > "$TEMP_DIR/${lang}.keys"
    count=$(wc -l < "$TEMP_DIR/${lang}.keys" | tr -d ' ')
    echo -e "${GREEN}✅ $lang: $count clés${NC}"
done

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${YELLOW}🔍 Analyse des clés manquantes...${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Comparer chaque langue avec les autres
total_missing=0

for base_lang in $LANGUAGES; do
    base_file="$TEMP_DIR/${base_lang}.keys"

    if [ ! -s "$base_file" ]; then
        continue
    fi

    for compare_lang in $LANGUAGES; do
        if [ "$base_lang" = "$compare_lang" ]; then
            continue
        fi

        compare_file="$TEMP_DIR/${compare_lang}.keys"

        if [ ! -s "$compare_file" ]; then
            continue
        fi

        # Trouver les clés présentes dans base_lang mais absentes dans compare_lang
        missing_keys=$(comm -23 "$base_file" "$compare_file")

        if [ -n "$missing_keys" ]; then
            missing_count=$(echo "$missing_keys" | wc -l | tr -d ' ')
            total_missing=$((total_missing + missing_count))

            echo -e "${RED}❌ Manquant dans $compare_lang (présent dans $base_lang): $missing_count clés${NC}"
            echo "$missing_keys" | head -10 | while read -r key; do
                echo -e "   ${YELLOW}• $key${NC}"
            done

            if [ "$missing_count" -gt 10 ]; then
                echo -e "   ${YELLOW}... et $((missing_count - 10)) autres${NC}"
            fi
            echo ""
        fi
    done
done

# Résumé final
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${PURPLE}📈 Résumé${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

for lang in $LANGUAGES; do
    if [ -s "$TEMP_DIR/${lang}.keys" ]; then
        count=$(wc -l < "$TEMP_DIR/${lang}.keys" | tr -d ' ')
        echo -e "${GREEN}$lang: $count clés totales${NC}"
    fi
done

echo ""

if [ "$total_missing" -eq 0 ]; then
    echo -e "${GREEN}✅ Toutes les traductions sont synchronisées ! 🎉${NC}"
    exit_code=0
else
    echo -e "${RED}⚠️  $total_missing clés manquantes au total${NC}"
    echo -e "${YELLOW}💡 Conseil: Ajoute les clés manquantes pour compléter les traductions${NC}"
    exit_code=1
fi

echo ""
exit $exit_code
