#!/bin/bash

# 🌱 Arbore - Script de développement local
# Utilisation: ./dev.sh [command]

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[Arbore]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Installation des dépendances
install() {
    log "🔧 Installation des dépendances Arbore..."
    
    # Backend Go
    if [ -d "ArboreBackend" ]; then
        log "📦 Installation dépendances Go..."
        cd ArboreBackend
        go mod tidy
        cd ..
    fi
    
    # AI Generator Python
    if [ -d "AiGenerator" ]; then
        log "🐍 Installation dépendances Python..."
        cd AiGenerator
        if [ ! -f "requirements.txt" ]; then
            cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
openai==1.3.0
pydantic==2.5.0
EOF
        fi
        pip install -r requirements.txt
        cd ..
    fi
    
    # iOS CocoaPods
    if [ -d "ArboreUi" ] && [ -f "ArboreUi/Podfile" ]; then
        log "🍎 Installation CocoaPods..."
        cd ArboreUi
        pod install
        cd ..
    fi
    
    log "✅ Installation terminée !"
}

# Tests
test() {
    log "🧪 Exécution des tests Arbore..."
    
    # Tests Go
    if [ -d "ArboreBackend" ]; then
        log "🔧 Tests Backend Go..."
        cd ArboreBackend
        go test ./... -v
        cd ..
    fi
    
    # Tests Python
    if [ -d "AiGenerator" ]; then
        log "🐍 Tests AI Generator..."
        cd AiGenerator
        if [ -d "tests" ]; then
            python -m pytest -v
        else
            log "Aucun test Python trouvé"
        fi
        cd ..
    fi
    
    log "✅ Tests terminés !"
}

# Lint/Format
lint() {
    log "🎨 Formatage et linting du code..."
    
    # Go
    if [ -d "ArboreBackend" ]; then
        log "🔧 Formatage Go..."
        cd ArboreBackend
        go fmt ./...
        if command -v golangci-lint &> /dev/null; then
            golangci-lint run
        else
            warn "golangci-lint non installé, install: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
        fi
        cd ..
    fi
    
    # Python
    if [ -d "AiGenerator" ]; then
        log "🐍 Formatage Python..."
        cd AiGenerator
        if command -v black &> /dev/null; then
            black .
        else
            warn "black non installé, install: pip install black"
        fi
        if command -v flake8 &> /dev/null; then
            flake8 . --max-line-length=88 --extend-ignore=E203,W503
        else
            warn "flake8 non installé, install: pip install flake8"
        fi
        cd ..
    fi
    
    log "✅ Formatage terminé !"
}

# Démarrage des services en développement
dev() {
    log "🚀 Démarrage en mode développement..."
    
    # Vérifier les ports
    check_port() {
        if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null ; then
            warn "Port $1 déjà utilisé"
            return 1
        fi
        return 0
    }
    
    # Backend Go
    if [ -d "ArboreBackend" ]; then
        if check_port 8080; then
            log "🔧 Démarrage Backend sur :8080..."
            cd ArboreBackend
            go run . &
            BACKEND_PID=$!
            cd ..
        fi
    fi
    
    # AI Generator Python
    if [ -d "AiGenerator" ]; then
        if check_port 8000; then
            log "🤖 Démarrage AI Generator sur :8000..."
            cd AiGenerator
            uvicorn main:app --reload --host 0.0.0.0 --port 8000 &
            AI_PID=$!
            cd ..
        fi
    fi
    
    log "✅ Services démarrés !"
    log "🌐 URLs :"
    log "  Backend: http://localhost:8080"
    log "  AI Generator: http://localhost:8000"
    log ""
    log "💡 Pour arrêter: Ctrl+C ou ./dev.sh stop"
    
    # Attendre Ctrl+C
    trap 'log "🛑 Arrêt des services..."; kill $BACKEND_PID $AI_PID 2>/dev/null; exit' INT
    wait
}

# Arrêt des services
stop() {
    log "🛑 Arrêt des services..."
    pkill -f "go run" 2>/dev/null || true
    pkill -f "uvicorn" 2>/dev/null || true
    log "✅ Services arrêtés !"
}

# Nettoyage
clean() {
    log "🧹 Nettoyage..."
    
    # Go
    if [ -d "ArboreBackend" ]; then
        cd ArboreBackend
        go clean
        cd ..
    fi
    
    # Python
    if [ -d "AiGenerator" ]; then
        find AiGenerator -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        find AiGenerator -name "*.pyc" -delete 2>/dev/null || true
    fi
    
    log "✅ Nettoyage terminé !"
}

# Menu principal
case "${1:-help}" in
    "install"|"i")
        install
        ;;
    "test"|"t")
        test
        ;;
    "lint"|"l")
        lint
        ;;
    "dev"|"d")
        dev
        ;;
    "stop"|"s")
        stop
        ;;
    "clean"|"c")
        clean
        ;;
    "help"|"h"|*)
        echo "🌱 Arbore - Script de développement"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  install, i    - Installe toutes les dépendances"
        echo "  test, t       - Lance tous les tests"
        echo "  lint, l       - Formate et lint le code"
        echo "  dev, d        - Démarre en mode développement"
        echo "  stop, s       - Arrête tous les services"
        echo "  clean, c      - Nettoie les fichiers temporaires"
        echo "  help, h       - Affiche cette aide"
        echo ""
        echo "Exemples:"
        echo "  $0 install   # Installe tout"
        echo "  $0 dev       # Lance en dev"
        echo "  $0 test      # Lance les tests"
        ;;
esac
