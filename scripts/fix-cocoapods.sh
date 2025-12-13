#!/bin/bash

# 🔧 Script de nettoyage et réinstallation CocoaPods
# Utiliser ce script si vous rencontrez des problèmes avec CocoaPods

set -e

echo "🌱 Script de nettoyage CocoaPods pour Arbore"
echo "=============================================="
echo ""

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# Vérifier qu'on est dans le bon dossier
if [ ! -d "ArboreUi" ]; then
    print_error "Ce script doit être exécuté depuis la racine du projet Arbore"
    exit 1
fi

cd ArboreUi

# 1. Nettoyage du cache CocoaPods
print_step "Nettoyage du cache CocoaPods..."
pod cache clean --all 2>/dev/null || print_warning "Impossible de nettoyer le cache"
print_success "Cache nettoyé"

# 2. Suppression des Pods existants
print_step "Suppression des Pods existants..."
if [ -d "Pods" ]; then
    rm -rf Pods
    print_success "Dossier Pods supprimé"
else
    print_warning "Pas de dossier Pods trouvé"
fi

# 3. Suppression du Podfile.lock
print_step "Suppression du Podfile.lock..."
if [ -f "Podfile.lock" ]; then
    rm -f Podfile.lock
    print_success "Podfile.lock supprimé"
else
    print_warning "Pas de Podfile.lock trouvé"
fi

# 4. Suppression du workspace généré
print_step "Suppression du workspace généré..."
if [ -f "ArboreUi.xcworkspace" ]; then
    rm -rf ArboreUi.xcworkspace
    print_success "Workspace supprimé"
else
    print_warning "Pas de workspace trouvé"
fi

# 5. Nettoyage du DerivedData Xcode
print_step "Nettoyage du DerivedData Xcode..."
if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
    rm -rf ~/Library/Developer/Xcode/DerivedData/ArboreUi-*
    print_success "DerivedData nettoyé"
fi

# 6. Mise à jour du repo CocoaPods
print_step "Mise à jour du repo CocoaPods (peut prendre quelques minutes)..."
pod repo update || {
    print_warning "Échec de la mise à jour du repo, tentative de setup..."
    pod setup
}
print_success "Repo CocoaPods mis à jour"

# 7. Vérification du Podfile
print_step "Vérification du Podfile..."
if grep -q "source 'https://cdn.cocoapods.org/'" Podfile; then
    print_success "Source CocoaPods présente dans le Podfile"
else
    print_error "Source CocoaPods manquante dans le Podfile!"
    echo ""
    echo "Ajoutez cette ligne au début de votre Podfile:"
    echo "source 'https://cdn.cocoapods.org/'"
    exit 1
fi

# 8. Installation des Pods
print_step "Installation des Pods..."
echo ""
pod install --repo-update --verbose

echo ""
echo "=============================================="
print_success "Installation terminée!"
echo ""
echo "Prochaines étapes:"
echo "1. Ouvrez ${BLUE}ArboreUi.xcworkspace${NC} (pas .xcodeproj)"
echo "2. Nettoyez le projet dans Xcode (⌘+Shift+K)"
echo "3. Buildez le projet (⌘+B)"
echo ""
