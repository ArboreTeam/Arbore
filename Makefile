.PHONY: help install test build clean docker-build docker-push lint format

# Variables
BACKEND_DIR = ArboreBackend
AI_DIR = AiGenerator
IOS_UI_DIR = ArboreUi
IOS_AR_DIR = ArboreARkit

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: install-backend install-ai install-ios-ui ## Installe toutes les dépendances

install-backend: ## Installe les dépendances Go du backend
	cd $(BACKEND_DIR) && go mod download && go mod verify

install-ai: ## Installe les dépendances Python de l'AI Generator
	cd $(AI_DIR) && pip install -r requirements.txt

install-ios-ui: ## Installe les dépendances CocoaPods pour iOS UI
	cd $(IOS_UI_DIR) && pod install --repo-update

test: test-backend test-ai ## Lance tous les tests

test-backend: ## Lance les tests du backend Go
	cd $(BACKEND_DIR) && go test -v -race -coverprofile=coverage.out ./...

test-ai: ## Lance les tests de l'AI Generator
	cd $(AI_DIR) && pytest -v --cov=. --cov-report=term

build: build-backend build-ai ## Build tous les projets

build-backend: ## Build le backend Go
	cd $(BACKEND_DIR) && CGO_ENABLED=0 go build -ldflags="-w -s" -o main .

build-ai: ## Build l'image Docker de l'AI Generator
	cd $(AI_DIR) && docker build -t arbore-ai-generator:latest .

build-ios-ui: ## Build l'app iOS UI
	cd $(IOS_UI_DIR) && xcodebuild -workspace ArboreUi.xcworkspace -scheme ArboreUi -configuration Debug build

clean: ## Nettoie les fichiers de build
	cd $(BACKEND_DIR) && go clean && rm -f main main-*
	cd $(AI_DIR) && find . -type d -name __pycache__ -exec rm -rf {} + || true
	cd $(AI_DIR) && find . -type f -name "*.pyc" -delete || true
	rm -rf $(IOS_UI_DIR)/build $(IOS_AR_DIR)/build
	rm -rf $(IOS_UI_DIR)/DerivedData $(IOS_AR_DIR)/DerivedData

docker-build: ## Build toutes les images Docker
	cd $(BACKEND_DIR) && docker build -t arbore-backend:latest .
	cd $(AI_DIR) && docker build -t arbore-ai-generator:latest .

docker-push: ## Push les images Docker vers le registry
	docker push arbore-backend:latest
	docker push arbore-ai-generator:latest

lint: lint-backend lint-ai ## Lance le linting sur tous les projets

lint-backend: ## Lint le code Go
	cd $(BACKEND_DIR) && golangci-lint run ./...

lint-ai: ## Lint le code Python
	cd $(AI_DIR) && flake8 . --max-line-length=88 --extend-ignore=E203,W503
	cd $(AI_DIR) && black --check .

format: format-backend format-ai ## Formate le code

format-backend: ## Formate le code Go
	cd $(BACKEND_DIR) && gofmt -w .
	cd $(BACKEND_DIR) && goimports -w .

format-ai: ## Formate le code Python
	cd $(AI_DIR) && black .

dev-backend: ## Lance le backend en mode développement
	cd $(BACKEND_DIR) && go run main.go

dev-ai: ## Lance l'AI Generator en mode développement
	cd $(AI_DIR) && python main.py

ci-local: ## Simule la CI en local
	@echo "🔍 Running local CI checks..."
	@make lint
	@make test
	@make build
	@echo "✅ All CI checks passed!"
