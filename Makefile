.PHONY: help install test build clean docker-build docker-push lint format

# Variables
BACKEND_DIR = ArboreBackend
IOS_UI_DIR = ArboreUi
IOS_AR_DIR = ArboreARkit

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: install-backend install-ios-ui ## Installe toutes les dépendances

install-backend: ## Installe les dépendances Go du backend
	cd $(BACKEND_DIR) && go mod download && go mod verify

install-ios-ui: ## Installe les dépendances CocoaPods pour iOS UI
	cd $(IOS_UI_DIR) && pod install --repo-update

test: test-backend ## Lance tous les tests

test-backend: ## Lance les tests du backend Go
	cd $(BACKEND_DIR) && go test -v -race -coverprofile=coverage.out ./...

build: build-backend ## Build tous les projets

build-backend: ## Build le backend Go
	cd $(BACKEND_DIR) && CGO_ENABLED=0 go build -ldflags="-w -s" -o main .

build-ios-ui: ## Build l'app iOS UI
	cd $(IOS_UI_DIR) && xcodebuild -workspace ArboreUi.xcworkspace -scheme ArboreUi -configuration Debug build

clean: ## Nettoie les fichiers de build
	cd $(BACKEND_DIR) && go clean && rm -f main main-*
	rm -rf $(IOS_UI_DIR)/build $(IOS_AR_DIR)/build
	rm -rf $(IOS_UI_DIR)/DerivedData $(IOS_AR_DIR)/DerivedData

docker-build: ## Build toutes les images Docker
	cd $(BACKEND_DIR) && docker build -t arbore-backend:latest .

docker-push: ## Push les images Docker vers le registry
	docker push arbore-backend:latest

lint: lint-backend ## Lance le linting sur tous les projets

lint-backend: ## Lint le code Go (même config que la CI)
	cd $(BACKEND_DIR) && golangci-lint run --config=../.golangci.yml --timeout=5m ./...

format: format-backend ## Formate le code

format-backend: ## Formate le code Go
	cd $(BACKEND_DIR) && gofmt -w .
	cd $(BACKEND_DIR) && goimports -w .

dev-backend: ## Lance le backend en mode développement
	cd $(BACKEND_DIR) && go run .

ci-local: ## Simule la CI en local
	@echo "🔍 Running local CI checks..."
	@make lint
	@make test
	@make build
	@echo "✅ All CI checks passed!"
