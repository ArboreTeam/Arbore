#!/bin/bash

# 🔍 Script de validation de la configuration CI/CD
# Vérifie que tous les fichiers de configuration sont corrects

set -e

echo "🔍 Validation de la configuration CI/CD Arbore"
echo "=============================================="
echo ""

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

errors=0
warnings=0

check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅${NC} $1"
    else
        echo -e "${RED}❌${NC} $1"
        ((errors++))
    fi
}

warn() {
    echo -e "${YELLOW}⚠️${NC} $1"
    ((warnings++))
}

info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

# Vérification des workflows GitHub Actions
echo "📋 Vérification des workflows GitHub Actions..."

if [ -f ".github/workflows/ci.yml" ]; then
    check "ci.yml existe"
    
    # Vérifier la syntaxe YAML (si yq est installé)
    if command -v yq &> /dev/null; then
        yq eval '.jobs' .github/workflows/ci.yml > /dev/null 2>&1
        check "ci.yml est un YAML valide"
    else
        warn "yq non installé, impossible de valider la syntaxe YAML"
    fi
else
    echo -e "${RED}❌${NC} ci.yml n'existe pas"
    ((errors++))
fi

if [ -f ".github/workflows/codeql.yml" ]; then
    check "codeql.yml existe"
else
    warn "codeql.yml n'existe pas"
fi

if [ -f ".github/workflows/docker-publish.yml" ]; then
    check "docker-publish.yml existe"
else
    warn "docker-publish.yml n'existe pas"
fi

echo ""
echo "📦 Vérification Dependabot..."

if [ -f ".github/dependabot.yml" ]; then
    check "dependabot.yml existe"
    
    # Vérifier qu'il n'y a pas cocoapods (non supporté)
    if grep -q "cocoapods" .github/dependabot.yml; then
        echo -e "${RED}❌${NC} dependabot.yml contient 'cocoapods' (non supporté)"
        ((errors++))
    else
        check "dependabot.yml ne contient pas 'cocoapods'"
    fi
else
    warn "dependabot.yml n'existe pas"
fi

echo ""
echo "🍎 Vérification Podfile (iOS)..."

if [ -f "ArboreUi/Podfile" ]; then
    check "Podfile existe"
    
    # Vérifier la source CocoaPods
    if grep -q "source 'https://cdn.cocoapods.org/'" ArboreUi/Podfile; then
        check "Source CocoaPods configurée"
    else
        echo -e "${RED}❌${NC} Source CocoaPods manquante dans le Podfile"
        ((errors++))
    fi
    
    # Vérifier qu'on n'utilise pas FacebookLogin v18 (n'existe pas)
    if grep -q "FacebookLogin" ArboreUi/Podfile; then
        echo -e "${RED}❌${NC} FacebookLogin trouvé (utiliser FBSDKLoginKit à la place)"
        ((errors++))
    else
        check "Pas de FacebookLogin obsolète"
    fi
    
    # Vérifier FBSDKLoginKit
    if grep -q "FBSDKLoginKit" ArboreUi/Podfile; then
        check "FBSDKLoginKit configuré"
    else
        warn "FBSDKLoginKit non trouvé"
    fi
else
    echo -e "${RED}❌${NC} Podfile n'existe pas"
    ((errors++))
fi

echo ""
echo "🐹 Vérification Backend Go..."

if [ -f "ArboreBackend/go.mod" ]; then
    check "go.mod existe"
    
    cd ArboreBackend
    if go mod verify > /dev/null 2>&1; then
        check "go.mod est valide"
    else
        warn "go.mod nécessite une vérification (go mod tidy)"
    fi
    cd ..
else
    echo -e "${RED}❌${NC} go.mod n'existe pas"
    ((errors++))
fi

if [ -f ".golangci.yml" ]; then
    check "Configuration golangci-lint existe"
else
    warn "Configuration golangci-lint manquante"
fi

echo ""
echo "🐍 Vérification AI Generator Python..."

if [ -f "AiGenerator/requirements.txt" ]; then
    check "requirements.txt existe"
else
    echo -e "${RED}❌${NC} requirements.txt n'existe pas"
    ((errors++))
fi

if [ -f "AiGenerator/setup.cfg" ]; then
    check "setup.cfg existe"
else
    warn "setup.cfg manquant"
fi

if [ -f "AiGenerator/pyproject.toml" ]; then
    check "pyproject.toml existe"
else
    warn "pyproject.toml manquant"
fi

# Vérifier le formatage Black
if [ -d "AiGenerator" ]; then
    cd AiGenerator
    if command -v black &> /dev/null; then
        if black --check . > /dev/null 2>&1; then
            check "Code Python formaté avec Black"
        else
            echo -e "${RED}❌${NC} Code Python non formaté (run: black .)"
            ((errors++))
        fi
    else
        warn "Black non installé, impossible de vérifier le formatage"
    fi
    cd ..
fi

echo ""
echo "📝 Vérification documentation..."

if [ -f "docs/CI-CD.md" ]; then
    check "Documentation CI/CD existe"
else
    warn "Documentation CI/CD manquante"
fi

if [ -f "docs/TROUBLESHOOTING.md" ]; then
    check "Guide de dépannage existe"
else
    warn "Guide de dépannage manquant"
fi

if [ -f ".github/pull_request_template.md" ]; then
    check "Template PR existe"
else
    warn "Template PR manquant"
fi

if [ -f ".github/CODEOWNERS" ]; then
    check "CODEOWNERS existe"
else
    warn "CODEOWNERS manquant"
fi

echo ""
echo "🛠️ Vérification outils..."

if [ -f "Makefile" ]; then
    check "Makefile existe"
else
    warn "Makefile manquant"
fi

if [ -f "ci-local.sh" ]; then
    check "Script CI local existe"
    if [ -x "ci-local.sh" ]; then
        check "Script CI local est exécutable"
    else
        warn "Script CI local n'est pas exécutable (chmod +x ci-local.sh)"
    fi
else
    warn "Script CI local manquant"
fi

if [ -f ".editorconfig" ]; then
    check ".editorconfig existe"
else
    warn ".editorconfig manquant"
fi

if [ -f ".gitignore" ]; then
    check ".gitignore existe"
else
    warn ".gitignore manquant"
fi

echo ""
echo "=============================================="
echo "📊 Résumé de la validation"
echo "=============================================="
echo ""

if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✅ Parfait ! Aucun problème détecté.${NC}"
    echo ""
    echo "Votre configuration CI/CD est prête ! 🚀"
    exit 0
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠️  $warnings avertissements${NC}"
    echo ""
    echo "La configuration est fonctionnelle mais pourrait être améliorée."
    exit 0
else
    echo -e "${RED}❌ $errors erreurs${NC}"
    if [ $warnings -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $warnings avertissements${NC}"
    fi
    echo ""
    echo "Veuillez corriger les erreurs avant de push."
    exit 1
fi
