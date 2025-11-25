#!/bin/bash
# Script pour nettoyer le cache Xcode et les fichiers de build

echo "🧹 Nettoyage du projet Xcode..."

cd /Users/hugorath/Desktop/Arbore_tamerelapute/ArboreUi

# Nettoyer les DerivedData
echo "📦 Nettoyage des DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ArboreUi-*

# Nettoyer le dossier build
echo "🗑️  Suppression du dossier build..."
rm -rf build/

# Nettoyer les fichiers .xcuserstate
echo "🗂️  Nettoyage des fichiers utilisateur..."
find . -name "*.xcuserstate" -delete
find . -name "xcuserdata" -type d -exec rm -rf {} + 2>/dev/null

echo "✅ Nettoyage terminé!"
echo ""
echo "Maintenant, ouvrez le projet dans Xcode et:"
echo "1. Product > Clean Build Folder (⇧⌘K)"
echo "2. Product > Build (⌘B)"
echo ""
