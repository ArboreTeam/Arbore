#!/bin/bash

# 🍎 Script de test CI local pour ArboreUI (iOS)
# Lance les tests iOS en local avant de push

set -e  # Arrêt en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$SCRIPT_DIR/ArboreUi"
WORKSPACE="ArboreUi.xcworkspace"
SCHEME="ArboreUi"
SIMULATOR_ID="046F5A7A-BC91-4ACF-8D48-47BDE6B2D51D"  # iPhone 17 Pro, iOS 26.2

# Vérification des dépendances
check_dependencies() {
    print_header "Vérification des dépendances iOS"

    local missing_deps=0

    # Xcode
    if command -v xcodebuild &> /dev/null; then
        print_success "Xcode installé: $(xcodebuild -version | head -1)"
    else
        print_error "Xcode n'est pas installé"
        missing_deps=1
    fi

    # Vérifier le workspace
    if [ -d "$UI_DIR/$WORKSPACE" ]; then
        print_success "Workspace trouvé: $WORKSPACE"
    else
        print_error "Workspace non trouvé: $UI_DIR/$WORKSPACE"
        missing_deps=1
    fi

    # Vérifier le simulateur
    if xcrun simctl list devices | grep -q "$SIMULATOR_ID"; then
        print_success "Simulateur trouvé: iPhone 17 Pro"
    else
        print_warning "Simulateur iPhone 17 Pro non trouvé, utilisation du simulateur par défaut"
    fi

    if [ $missing_deps -eq 1 ]; then
        print_error "Dépendances manquantes. Installation requise."
        exit 1
    fi
}

# Fonction pour lancer les tests
run_tests() {
    local test_target=$1
    local test_name=$2

    print_info "Lancement des tests: $test_name"

    cd "$UI_DIR"

    xcodebuild test \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -only-testing:"$test_target" \
        -parallel-testing-enabled NO \
        2>&1 | tee /tmp/arbore_test_output.log | \
        grep -E "(Test Suite|Test Case|passed|failed|Executed|TEST FAILED|TEST SUCCEEDED)" || true

    cd "$SCRIPT_DIR"

    # Vérifier le résultat
    if grep -q "TEST SUCCEEDED" /tmp/arbore_test_output.log; then
        print_success "$test_name: RÉUSSI"
        return 0
    else
        print_error "$test_name: ÉCHEC"
        return 1
    fi
}

# Afficher les résultats finaux
show_summary() {
    local total_tests=$1
    local failed_tests=$2

    print_header "Résumé des tests"

    echo -e "${PURPLE}Total des tests: $total_tests${NC}"
    echo -e "${GREEN}Réussis: $((total_tests - failed_tests))${NC}"

    if [ $failed_tests -eq 0 ]; then
        echo -e "${GREEN}Échecs: 0${NC}"
        echo ""
        print_success "🎉 Tous les tests sont passés!"
    else
        echo -e "${RED}Échecs: $failed_tests${NC}"
        echo ""
        print_error "Des tests ont échoué. Vérifiez les logs ci-dessus."
    fi
}

# Menu principal
main() {
    clear
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════╗"
    echo "║   🍎 Arbore UI - Tests iOS Locaux   ║"
    echo "╔════════════════════════════════════════╗"
    echo -e "${NC}"

    # Vérifier les dépendances
    check_dependencies

    # Choix du type de tests
    echo -e "\n${BLUE}Choisissez les tests à lancer:${NC}"
    echo "1) Tests Privacy Settings (Unit + Integration)"
    echo "2) Tests Privacy Settings - Unit uniquement"
    echo "3) Tests Privacy Settings - Integration uniquement"
    echo "4) Tests NetworkManager (Unit + Integration)"
    echo "5) Tests NetworkManager - Unit uniquement"
    echo "6) Tests NetworkManager - Integration uniquement"
    echo "7) Tests API Key Protection"
    echo "8) Tous les tests de l'app"
    echo "9) Quitter"
    echo ""
    read -p "Votre choix (1-9): " choice

    local failed=0
    local total=0

    case $choice in
        1)
            print_header "Tests Privacy Settings Complets"
            run_tests "ArboreUiTests/PrivacySettingsViewTests" "Unit Tests"
            failed=$((failed + $?))
            total=$((total + 1))

            run_tests "ArboreUiTests/PrivacySettingsIntegrationTests" "Integration Tests"
            failed=$((failed + $?))
            total=$((total + 1))
            ;;
        2)
            print_header "Tests Privacy Settings - Unit Tests"
            run_tests "ArboreUiTests/PrivacySettingsViewTests" "Unit Tests"
            failed=$?
            total=1
            ;;
        3)
            print_header "Tests Privacy Settings - Integration Tests"
            run_tests "ArboreUiTests/PrivacySettingsIntegrationTests" "Integration Tests"
            failed=$?
            total=1
            ;;
        4)
            print_header "Tests NetworkManager Complets"
            run_tests "ArboreUiTests/NetworkManagerTests" "NetworkManager Unit Tests"
            failed=$((failed + $?))
            total=$((total + 1))

            run_tests "ArboreUiTests/NetworkManagerIntegrationTests" "NetworkManager Integration Tests"
            failed=$((failed + $?))
            total=$((total + 1))
            ;;
        5)
            print_header "Tests NetworkManager - Unit Tests"
            run_tests "ArboreUiTests/NetworkManagerTests" "Unit Tests"
            failed=$?
            total=1
            ;;
        6)
            print_header "Tests NetworkManager - Integration Tests"
            run_tests "ArboreUiTests/NetworkManagerIntegrationTests" "Integration Tests"
            failed=$?
            total=1
            ;;
        7)
            print_header "Tests API Key Protection"
            run_tests "ArboreUiTests/PrivacySettingsIntegrationTests/testAPIKey_PlantsEndpoint_ShouldRequireFirebaseToken" "Firebase Token requis"
            failed=$((failed + $?))
            total=$((total + 1))

            run_tests "ArboreUiTests/PrivacySettingsIntegrationTests/testAPIKey_WithoutKey_ShouldReturn401" "API Key sans clé"
            failed=$((failed + $?))
            total=$((total + 1))
            ;;
        8)
            print_header "Tous les tests de l'app"
            cd "$UI_DIR"
            xcodebuild test \
                -workspace "$WORKSPACE" \
                -scheme "$SCHEME" \
                -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
                -parallel-testing-enabled NO \
                2>&1 | tee /tmp/arbore_test_output.log | \
                grep -E "(Test Suite|Test Case|passed|failed|Executed|TEST FAILED|TEST SUCCEEDED)" || true
            cd "$SCRIPT_DIR"

            # Parser le résultat "Executed X tests, with Y failures"
            if grep -q "Executed.*tests" /tmp/arbore_test_output.log; then
                total=$(grep "Executed.*tests" /tmp/arbore_test_output.log | tail -1 | sed -E 's/.*Executed ([0-9]+) tests.*/\1/')
                failed=$(grep "Executed.*tests" /tmp/arbore_test_output.log | tail -1 | sed -E 's/.*with ([0-9]+) failure(s)?.*/\1/')

                # Si pas de failures dans la sortie, c'est que tous ont réussi
                if ! grep -q "failure" /tmp/arbore_test_output.log; then
                    failed=0
                fi
            else
                # Fallback si le format n'est pas trouvé
                if grep -q "TEST SUCCEEDED" /tmp/arbore_test_output.log; then
                    failed=0
                else
                    failed=1
                fi
                total=1
            fi
            ;;
        9)
            print_info "Annulé par l'utilisateur"
            exit 0
            ;;
        *)
            print_error "Choix invalide"
            exit 1
            ;;
    esac

    # Afficher le résumé
    show_summary $total $failed

    # Code de sortie
    if [ "$failed" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Lancer le script
main
