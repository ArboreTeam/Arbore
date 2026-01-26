#!/bin/bash

# 🔐 Script pour encoder les secrets en base64 pour GitHub Actions
# Usage: ./.github/encode-secrets.sh

set -e

echo "🔐 Encodage des secrets pour GitHub Actions"
echo "=========================================="
echo ""

# Couleurs pour l'output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Vérifier que nous sommes dans le bon répertoire
if [ ! -f "ArboreUi/GoogleService-Info.plist" ]; then
    echo "❌ Erreur: Lancez ce script depuis la racine du projet Arbore"
    exit 1
fi

echo -e "${BLUE}📱 1. Encodage de GoogleService-Info.plist${NC}"
echo "─────────────────────────────────────────────"

if [ -f "ArboreUi/GoogleService-Info.plist" ]; then
    GOOGLE_SERVICE=$(base64 -i ArboreUi/GoogleService-Info.plist)
    echo -e "${GREEN}✅ GoogleService-Info.plist encodé${NC}"
    echo ""
    echo -e "Secret Name: ${YELLOW}GOOGLE_SERVICE_INFO_PLIST_BASE64${NC}"
    echo "Secret Value (copié dans le presse-papier):"
    echo ""
    echo "$GOOGLE_SERVICE" | pbcopy
    echo -e "→ ${GREEN}Copié dans le presse-papier !${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠️  GoogleService-Info.plist non trouvé${NC}"
    echo ""
fi

echo -e "${BLUE}🔑 2. Secrets du backend${NC}"
echo "─────────────────────────────────────────────"

if [ -f "ArboreUi/Secrets.xcconfig" ]; then
    echo -e "${GREEN}✅ Lecture de Secrets.xcconfig${NC}"
    echo ""

    # Extraire les valeurs du fichier
    API_KEY=$(grep "ARBORE_API_KEY" ArboreUi/Secrets.xcconfig | cut -d'=' -f2 | xargs)
    BACKEND_PROTOCOL=$(grep "ARBORE_BACKEND_PROTOCOL" ArboreUi/Secrets.xcconfig | cut -d'=' -f2 | xargs)
    BACKEND_HOST=$(grep "ARBORE_BACKEND_HOST" ArboreUi/Secrets.xcconfig | cut -d'=' -f2 | xargs)

    echo -e "Secret Name: ${YELLOW}ARBORE_API_KEY${NC}"
    echo -e "Secret Value: ${GREEN}$API_KEY${NC}"
    echo ""

    echo -e "Secret Name: ${YELLOW}ARBORE_BACKEND_PROTOCOL${NC}"
    echo -e "Secret Value: ${GREEN}$BACKEND_PROTOCOL${NC}"
    echo ""

    echo -e "Secret Name: ${YELLOW}ARBORE_BACKEND_HOST${NC}"
    echo -e "Secret Value: ${GREEN}$BACKEND_HOST${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠️  Secrets.xcconfig non trouvé${NC}"
    echo ""
fi

echo "=========================================="
echo -e "${GREEN}✅ Encodage terminé !${NC}"
echo ""
echo -e "${BLUE}📝 Prochaines étapes:${NC}"
echo "1. Allez sur: https://github.com/YOUR_USERNAME/Arbore/settings/secrets/actions"
echo "2. Cliquez sur 'New repository secret'"
echo "3. Pour chaque secret ci-dessus:"
echo "   - Copiez le Secret Name"
echo "   - Collez le Secret Value"
echo "   - Cliquez sur 'Add secret'"
echo ""
echo -e "${BLUE}📖 Documentation complète:${NC}"
echo "→ .github/SECRETS_SETUP.md"
echo ""
