#!/usr/bin/env python3
"""
Script pour ajouter les nouveaux fichiers de la page Jardin au projet Xcode.
Ce script liste les fichiers à ajouter manuellement.
"""

import os

# Couleurs pour le terminal
GREEN = '\033[92m'
BLUE = '\033[94m'
YELLOW = '\033[93m'
RESET = '\033[0m'

def print_header(text):
    print(f"\n{BLUE}{'='*60}{RESET}")
    print(f"{BLUE}{text.center(60)}{RESET}")
    print(f"{BLUE}{'='*60}{RESET}\n")

def print_section(text):
    print(f"\n{GREEN}▶ {text}{RESET}")

def print_file(path):
    print(f"  {YELLOW}✓{RESET} {path}")

def main():
    print_header("NOUVEAUX FICHIERS - PAGE JARDIN")
    
    base_path = "ArboreUi/ArboreUi"
    
    # Models
    print_section("1. Modèles (à ajouter dans le dossier Models/)")
    models = [
        f"{base_path}/Models/GardenProject.swift",
        f"{base_path}/Models/GardenProjectService.swift"
    ]
    for model in models:
        if os.path.exists(model):
            print_file(model)
        else:
            print(f"  ⚠️  {model} - FICHIER NON TROUVÉ")
    
    # Views principales
    print_section("2. Vues principales (à ajouter dans le dossier Views/)")
    main_views = [
        f"{base_path}/Views/NewMyGardenView.swift",
        f"{base_path}/Views/GardenProjectDetailView.swift"
    ]
    for view in main_views:
        if os.path.exists(view):
            print_file(view)
        else:
            print(f"  ⚠️  {view} - FICHIER NON TROUVÉ")
    
    # Vues des étapes
    print_section("3. Vues des étapes (à ajouter dans Views/GardenSteps/)")
    step_views = [
        f"{base_path}/Views/GardenSteps/ScanStepView.swift",
        f"{base_path}/Views/GardenSteps/MediaStepView.swift",
        f"{base_path}/Views/GardenSteps/InfoStepView.swift",
        f"{base_path}/Views/GardenSteps/LocationStepView.swift",
        f"{base_path}/Views/GardenSteps/PreferencesStepView.swift",
        f"{base_path}/Views/GardenSteps/ZonesStepView.swift",
        f"{base_path}/Views/GardenSteps/SummaryStepView.swift"
    ]
    for view in step_views:
        if os.path.exists(view):
            print_file(view)
        else:
            print(f"  ⚠️  {view} - FICHIER NON TROUVÉ")
    
    # Instructions
    print_header("INSTRUCTIONS D'INTÉGRATION")
    
    print("""
1. Ouvrez le projet dans Xcode:
   $ open ArboreUi/ArboreUi.xcodeproj

2. Dans le navigateur de projet (à gauche), faites un clic droit sur le dossier 
   "Models" et sélectionnez "Add Files to ArboreUi..."

3. Ajoutez les 2 fichiers Models:
   - GardenProject.swift
   - GardenProjectService.swift

4. Faites un clic droit sur le dossier "Views" et ajoutez:
   - NewMyGardenView.swift
   - GardenProjectDetailView.swift

5. Créez un nouveau groupe "GardenSteps" dans Views:
   - Clic droit sur Views → New Group → "GardenSteps"

6. Dans GardenSteps, ajoutez les 7 fichiers d'étapes:
   - ScanStepView.swift
   - MediaStepView.swift
   - InfoStepView.swift
   - LocationStepView.swift
   - PreferencesStepView.swift
   - ZonesStepView.swift
   - SummaryStepView.swift

7. Vérifiez que MainView.swift a été mis à jour pour utiliser NewMyGardenView

8. Vérifiez que Info.plist contient les permissions pour:
   - Localisation
   - Caméra
   - Bibliothèque photo

9. Compilez le projet (⌘B) et corrigez les erreurs éventuelles

10. Lancez l'application (⌘R) et testez la nouvelle page Jardin

Pour plus de détails, consultez GARDEN_PAGE_DOCUMENTATION.md
""")

    print_header("✅ PRÊT À INTÉGRER")

if __name__ == "__main__":
    main()
