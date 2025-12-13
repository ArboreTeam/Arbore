#!/bin/bash

# Script pour installer xcpretty si nécessaire
# Utilisé dans le CI pour formatter la sortie de xcodebuild

if ! command -v xcpretty &> /dev/null; then
    echo "📦 Installation de xcpretty..."
    sudo gem install xcpretty
else
    echo "✅ xcpretty est déjà installé"
fi
