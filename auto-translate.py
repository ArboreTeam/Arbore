#!/usr/bin/env python3

"""
🌍 Arbore Auto-Translator avec DeepL API
Traduit automatiquement les clés manquantes dans Localizable.strings
"""

import os
import re
import sys
import deepl
from pathlib import Path

# Configuration
SCRIPT_DIR = Path(__file__).parent
UI_DIR = SCRIPT_DIR / "ArboreUi" / "ArboreUi"
DEEPL_API_KEY_FILE = SCRIPT_DIR / ".deepl_api"

# Langues supportées
LANGUAGES = {
    "en": "EN-US",  # DeepL target code (anglais américain)
    "fr": "FR",     # Source
    "de": "DE",
    "es": "ES"
}

# Couleurs
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'

def print_header():
    print(f"{Colors.PURPLE}")
    print("╔════════════════════════════════════════╗")
    print("║  🌍 Arbore Auto-Translator (DeepL)  ║")
    print("╔════════════════════════════════════════╗")
    print(f"{Colors.NC}")

def load_deepl_key():
    """Charge la clé API DeepL depuis le fichier"""
    if not DEEPL_API_KEY_FILE.exists():
        print(f"{Colors.RED}❌ Fichier {DEEPL_API_KEY_FILE} non trouvé{Colors.NC}")
        sys.exit(1)

    with open(DEEPL_API_KEY_FILE, 'r') as f:
        key = f.read().strip()

    if not key:
        print(f"{Colors.RED}❌ Clé API DeepL vide dans {DEEPL_API_KEY_FILE}{Colors.NC}")
        sys.exit(1)

    return key

def parse_localizable_file(file_path):
    """Parse un fichier Localizable.strings et retourne un dict {key: value}"""
    translations = {}

    if not file_path.exists():
        return translations

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Regex pour extraire "KEY" = "VALUE";
    pattern = r'^"([^"]+)"\s*=\s*"(.+?)";'
    matches = re.finditer(pattern, content, re.MULTILINE)

    for match in matches:
        key = match.group(1)
        value = match.group(2)
        translations[key] = value

    return translations

def translate_with_deepl(text, target_lang, translator):
    """Traduit un texte avec l'API DeepL (bibliothèque officielle)"""
    try:
        # formality n'est supporté que pour DE, ES, FR, IT, JA, NL, PL, PT-BR, PT-PT, RU
        # PAS pour EN !
        kwargs = {
            "text": text,
            "source_lang": "FR",
            "target_lang": target_lang
        }

        # Ajouter formality seulement si la langue le supporte
        if not target_lang.startswith("EN"):
            kwargs["formality"] = "less"  # Tutoiement comme dans l'app

        result = translator.translate_text(**kwargs)
        return result.text
    except Exception as e:
        print(f"{Colors.RED}❌ Erreur DeepL: {e}{Colors.NC}")
        return None

def append_translations_to_file(file_path, new_translations):
    """Ajoute les nouvelles traductions à la fin du fichier"""
    with open(file_path, 'a', encoding='utf-8') as f:
        f.write("\n// Auto-translated with DeepL\n")
        for key, value in sorted(new_translations.items()):
            # Escape les guillemets dans la valeur
            escaped_value = value.replace('"', '\\"')
            f.write(f'"{key}" = "{escaped_value}";\n')

def main():
    print_header()

    # Charger la clé API
    print(f"{Colors.BLUE}🔑 Chargement de la clé API DeepL...{Colors.NC}")
    api_key = load_deepl_key()

    # Créer le client DeepL
    translator = deepl.Translator(api_key)
    print(f"{Colors.GREEN}✅ Client DeepL initialisé{Colors.NC}\n")

    # Charger toutes les traductions
    print(f"{Colors.BLUE}📊 Chargement des fichiers de traduction...{Colors.NC}")
    all_translations = {}

    for lang in LANGUAGES.keys():
        file_path = UI_DIR / f"{lang}.lproj" / "Localizable.strings"
        all_translations[lang] = parse_localizable_file(file_path)
        count = len(all_translations[lang])
        print(f"{Colors.GREEN}✅ {lang}: {count} clés{Colors.NC}")

    # Utiliser FR comme référence (la plus complète)
    reference_lang = "fr"
    reference_keys = set(all_translations[reference_lang].keys())

    print(f"\n{Colors.CYAN}📌 Utilisation de {reference_lang.upper()} comme référence ({len(reference_keys)} clés){Colors.NC}\n")

    # Traduire les clés manquantes pour chaque langue
    print(f"{Colors.BLUE}{'='*40}{Colors.NC}")
    print(f"{Colors.YELLOW}🔄 Traduction automatique en cours...{Colors.NC}")
    print(f"{Colors.BLUE}{'='*40}{Colors.NC}\n")

    total_translated = 0

    for lang, deepl_code in LANGUAGES.items():
        if lang == reference_lang:
            continue  # Skip la langue de référence

        current_keys = set(all_translations[lang].keys())
        missing_keys = reference_keys - current_keys

        if not missing_keys:
            print(f"{Colors.GREEN}✅ {lang.upper()}: Aucune clé manquante{Colors.NC}")
            continue

        print(f"{Colors.YELLOW}🔄 {lang.upper()}: {len(missing_keys)} clés à traduire...{Colors.NC}")

        new_translations = {}
        translated_count = 0

        for i, key in enumerate(sorted(missing_keys), 1):
            source_text = all_translations[reference_lang][key]

            # Afficher la progression tous les 10 items
            if i % 10 == 0 or i == len(missing_keys):
                print(f"   {Colors.CYAN}[{i}/{len(missing_keys)}] Traduction...{Colors.NC}", end='\r')

            translated = translate_with_deepl(source_text, deepl_code, translator)

            if translated:
                new_translations[key] = translated
                translated_count += 1
            else:
                print(f"\n{Colors.RED}   ⚠️  Échec pour '{key}'{Colors.NC}")

        print()  # Nouvelle ligne après la progression

        # Ajouter les traductions au fichier
        if new_translations:
            file_path = UI_DIR / f"{lang}.lproj" / "Localizable.strings"
            append_translations_to_file(file_path, new_translations)
            print(f"{Colors.GREEN}✅ {lang.upper()}: {translated_count} clés traduites et ajoutées{Colors.NC}")
            total_translated += translated_count

        print()

    # Résumé final
    print(f"{Colors.BLUE}{'='*40}{Colors.NC}")
    print(f"{Colors.PURPLE}📈 Résumé{Colors.NC}")
    print(f"{Colors.BLUE}{'='*40}{Colors.NC}\n")

    if total_translated > 0:
        print(f"{Colors.GREEN}🎉 {total_translated} traductions ajoutées avec succès !{Colors.NC}")
        print(f"{Colors.CYAN}💡 Relance ./check-translations.sh pour vérifier{Colors.NC}")
    else:
        print(f"{Colors.GREEN}✅ Toutes les traductions sont déjà complètes !{Colors.NC}")

    print()

if __name__ == "__main__":
    main()
