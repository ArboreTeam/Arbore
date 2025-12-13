#!/bin/bash

# 🌱 Script de test CI local pour Arbore
# Ce script simule les vérifications CI en local avant de push

set -e  # Arrêt en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage
print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Vérification des dépendances
check_dependencies() {
    print_header "Vérification des dépendances"
    
    local missing_deps=0
    
    # Go
    if command -v go &> /dev/null; then
        print_success "Go installé: $(go version)"
    else
        print_error "Go n'est pas installé"
        missing_deps=1
    fi
    
    # Python
    if command -v python3 &> /dev/null; then
        print_success "Python installé: $(python3 --version)"
    else
        print_error "Python n'est pas installé"
        missing_deps=1
    fi
    
    # golangci-lint
    if command -v golangci-lint &> /dev/null; then
        print_success "golangci-lint installé"
    else
        print_warning "golangci-lint n'est pas installé (optionnel pour le backend)"
    fi
    
    # Black (Python formatter)
    if command -v black &> /dev/null; then
        print_success "Black installé"
    else
        print_warning "Black n'est pas installé (optionnel pour Python)"
    fi
    
    # Xcode (pour macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v xcodebuild &> /dev/null; then
            print_success "Xcode installé: $(xcodebuild -version | head -n 1)"
        else
            print_warning "Xcode n'est pas installé (requis pour iOS)"
        fi
        
        if command -v pod &> /dev/null; then
            print_success "CocoaPods installé: $(pod --version)"
        else
            print_warning "CocoaPods n'est pas installé (requis pour iOS)"
        fi
    fi
    
    return $missing_deps
}

# Tests Backend Go
test_backend() {
    print_header "Tests Backend (Go)"
    
    if [ ! -d "ArboreBackend" ]; then
        print_warning "Dossier ArboreBackend introuvable, skip"
        return 0
    fi
    
    cd ArboreBackend
    
    print_info "Installation des dépendances Go..."
    go mod download
    go mod verify
    
    print_info "Vérification du code Go..."
    go vet ./... || { print_error "go vet a échoué"; cd ..; return 1; }
    
    print_info "Exécution des tests Go..."
    go test -v -race -coverprofile=coverage.out ./... || { print_error "Tests Go échoués"; cd ..; return 1; }
    
    print_info "Génération du rapport de couverture..."
    go tool cover -func=coverage.out
    
    if command -v golangci-lint &> /dev/null; then
        print_info "Linting avec golangci-lint..."
        golangci-lint run ./... || { print_error "Linting Go échoué"; cd ..; return 1; }
    fi
    
    print_info "Build du backend..."
    CGO_ENABLED=0 go build -o main . || { print_error "Build Go échoué"; cd ..; return 1; }
    rm -f main
    
    cd ..
    print_success "Backend Go - Tous les tests passés!"
    return 0
}

# Tests AI Generator Python
test_ai_generator() {
    print_header "Tests AI Generator (Python)"
    
    if [ ! -d "AiGenerator" ]; then
        print_warning "Dossier AiGenerator introuvable, skip"
        return 0
    fi
    
    cd AiGenerator
    
    print_info "Installation des dépendances Python..."
    pip install -q -r requirements.txt 2>/dev/null || print_warning "Erreur lors de l'installation des dépendances"
    pip install -q pytest pytest-cov black flake8 2>/dev/null || print_warning "Erreur lors de l'installation des outils de dev"
    
    if command -v black &> /dev/null; then
        print_info "Vérification du formatage avec Black..."
        black --check . || { print_warning "Le code n'est pas formaté avec Black"; }
    fi
    
    if command -v flake8 &> /dev/null; then
        print_info "Linting avec Flake8..."
        flake8 . --max-line-length=88 --extend-ignore=E203,W503 || { print_warning "Problèmes de linting détectés"; }
    fi
    
    if [ -d "tests" ]; then
        print_info "Exécution des tests Python..."
        pytest -v || { print_error "Tests Python échoués"; cd ..; return 1; }
    else
        print_warning "Pas de dossier tests/ trouvé"
    fi
    
    cd ..
    print_success "AI Generator Python - Tous les tests passés!"
    return 0
}

# Tests iOS UI
test_ios_ui() {
    print_header "Tests iOS UI"
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_warning "Tests iOS disponibles uniquement sur macOS, skip"
        return 0
    fi
    
    if [ ! -d "ArboreUi" ]; then
        print_warning "Dossier ArboreUi introuvable, skip"
        return 0
    fi
    
    cd ArboreUi
    
    if [ -f "Podfile" ]; then
        print_info "Installation des CocoaPods..."
        pod install --repo-update || { print_error "Installation CocoaPods échouée"; cd ..; return 1; }
    fi
    
    if [ -f "ArboreUi.xcworkspace" ]; then
        print_info "Build iOS UI..."
        xcodebuild clean build \
            -workspace ArboreUi.xcworkspace \
            -scheme ArboreUi \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGN_IDENTITY="" \
            | grep -E "Build|error|warning" || { print_error "Build iOS échoué"; cd ..; return 1; }
    fi
    
    cd ..
    print_success "iOS UI - Build réussi!"
    return 0
}

# Tests iOS AR
test_ios_ar() {
    print_header "Tests iOS AR Kit"
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_warning "Tests iOS disponibles uniquement sur macOS, skip"
        return 0
    fi
    
    if [ ! -d "ArboreARkit" ]; then
        print_warning "Dossier ArboreARkit introuvable, skip"
        return 0
    fi
    
    cd ArboreARkit
    
    if [ -f "ArboreARkit.xcodeproj" ]; then
        print_info "Build iOS AR Kit..."
        xcodebuild clean build \
            -project ArboreARkit.xcodeproj \
            -scheme ArboreARkit \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGN_IDENTITY="" \
            | grep -E "Build|error|warning" || { print_error "Build iOS AR échoué"; cd ..; return 1; }
    fi
    
    cd ..
    print_success "iOS AR Kit - Build réussi!"
    return 0
}

# Fonction principale
main() {
    print_header "🌱 Arbore CI Local Check"
    
    local start_time=$(date +%s)
    local failed=0
    
    # Vérification des dépendances
    check_dependencies || failed=1
    
    # Tests
    test_backend || failed=1
    test_ai_generator || failed=1
    test_ios_ui || failed=1
    test_ios_ar || failed=1
    
    # Résumé
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "Résumé"
    
    if [ $failed -eq 0 ]; then
        print_success "Tous les tests sont passés! ✨"
        print_info "Durée totale: ${duration}s"
        echo -e "\n${GREEN}🚀 Vous pouvez push en toute confiance!${NC}\n"
        return 0
    else
        print_error "Certains tests ont échoué"
        print_info "Durée totale: ${duration}s"
        echo -e "\n${RED}🛑 Veuillez corriger les erreurs avant de push${NC}\n"
        return 1
    fi
}

# Exécution
main
