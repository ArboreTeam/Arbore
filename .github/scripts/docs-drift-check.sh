#!/usr/bin/env bash
#
# docs-drift-check.sh
#
# Scanne tous les fichiers Markdown sous docs/ et vérifie que les chemins
# de fichiers code (extensions .swift, .go, .py, .ts, .tsx, .yaml, .yml,
# .json, .toml, .xcconfig, .pbxproj, .plist) qu'ils citent existent
# toujours dans le dépôt. Fail si au moins un chemin cité est absent.
#
# Heuristique de détection : chemins entre backticks contenant '/' et
# se terminant par une des extensions surveillées. Le script tolère les
# chemins entre backticks doubles et les chemins escapés.
#
# Mots-clés ignorés (faux positifs connus) :
#   - chemins relatifs commençant par './' ou '../' qui pointent vers d'autres docs
#   - URLs (commençant par http:// ou https://)
#   - chemins commençant par '/' (paths backend, ex: /users/me) — ce sont des
#     endpoints, pas des fichiers
#   - extensions Markdown .md (liens inter-docs gérés par lychee)
#
# Stratégie de matching : un chemin cité (par exemple
# "Models/User.swift") est considéré valide si **au moins un fichier du
# dépôt y termine** (suffix match). Cela évite d'imposer aux docs
# d'utiliser le chemin complet depuis la racine pour chaque fichier,
# tout en détectant correctement les suppressions et renommages.
#
# Exit codes :
#   0 — aucun drift détecté
#   1 — au moins un chemin code référencé n'existe nulle part dans le dépôt

set -euo pipefail

# Extensions surveillées. Tout ce qui n'est pas dans cette liste est ignoré.
EXTS_REGEX='\.(swift|go|py|ts|tsx|js|yaml|yml|json|toml|xcconfig|pbxproj|plist|sh|dockerfile|mod|sum)'

missing_count=0
checked_count=0
missing_paths=()

# Liste tous les fichiers .md dans docs/ (portable bash 3.2+)
md_files=()
while IFS= read -r line; do
  md_files+=("$line")
done < <(find docs -type f -name "*.md" | sort)

if [ ${#md_files[@]} -eq 0 ]; then
  echo "No Markdown files found under docs/. Skipping drift check."
  exit 0
fi

echo "Scanning ${#md_files[@]} Markdown file(s) under docs/ for code references…"
echo ""

# Pré-cache : liste complète des fichiers source du dépôt qui pourraient
# être référencés. On exclut node_modules, build artifacts et .git.
repo_files=()
while IFS= read -r line; do
  repo_files+=("$line")
done < <(
  find . \
    \( -name node_modules -o -name .git -o -name DerivedData -o -name build -o -name Pods -o -name __pycache__ \) -prune -o \
    -type f -print | sed 's|^\./||' | sort
)
echo "Indexed ${#repo_files[@]} source file(s) in the repository."
echo ""

# Allowlist explicite : fichiers cités dans docs/ légitimement absents du dépôt
# (secrets cités par nom nu, fichiers générés, ressources externes). Une
# référence qui matche une entrée n'est pas comptée comme drift.
ALLOWLIST_FILE="$(dirname "$0")/docs-drift-allowlist.txt"
allowlist=()
if [ -f "$ALLOWLIST_FILE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"                                            # retire commentaires
    line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$line" ] && allowlist+=("$line")
  done < "$ALLOWLIST_FILE"
  echo "Loaded ${#allowlist[@]} allowlist entr(ies) from $ALLOWLIST_FILE."
  echo ""
fi

for md in "${md_files[@]}"; do
  # Extrait tous les contenus entre backticks (single or double) du fichier.
  # On utilise grep -oP avec une regex Perl-compatible pour matcher uniquement
  # le contenu interne.
  while IFS= read -r match; do
    # match contient déjà le texte interne du backtick. Trim espaces autour.
    candidate="$(echo "$match" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    # Skip URLs
    [[ "$candidate" =~ ^https?:// ]] && continue

    # Skip endpoints backend (commencent par /users, /gardens, etc.) — heuristique :
    # un chemin qui commence par '/' suivi d'une lettre minuscule sans extension
    # connue est probablement un endpoint, pas un fichier.
    if [[ "$candidate" =~ ^/[a-z] ]] && ! [[ "$candidate" =~ $EXTS_REGEX ]]; then
      continue
    fi

    # Skip chemins absolus système (container ou VPS) : la doc d'opérations
    # cite légitimement /root/firebase-adminsdk.json (intra-container),
    # /home/fedora/Arbore/... (VPS), /etc/nginx/conf.d/... etc. Ces
    # chemins n'ont pas de correspondance dans le dépôt et ne doivent
    # pas faire échouer le drift check.
    case "$candidate" in
      /root/*|/home/*|/etc/*|/usr/*|/var/*|/opt/*|/tmp/*|/proc/*|/sys/*)
        continue ;;
    esac

    # Skip si pas d'extension surveillée
    if ! [[ "$candidate" =~ $EXTS_REGEX$ ]]; then
      continue
    fi

    # Skip chemins relatifs vers d'autres docs (gérés par lychee)
    [[ "$candidate" == ./* ]] && continue
    [[ "$candidate" == ../* ]] && continue

    # Skip chemins avec wildcards (ils sont des références de pattern, pas des
    # fichiers réels).
    [[ "$candidate" == *"*"* ]] && continue

    # Nettoie les fragments éventuels (#anchor) ou query strings
    candidate="${candidate%%#*}"
    candidate="${candidate%%\?*}"

    # Skip si le chemin contient un caractère manifestement invalide pour un
    # chemin de fichier réel (placeholders type {id}, $var, etc.)
    [[ "$candidate" =~ \{ ]] && continue
    [[ "$candidate" =~ \$ ]] && continue

    # Skip chemins qui ressemblent à des fragments de texte (espaces, longueur
    # absurde, virgule, deux-points).
    [[ "$candidate" =~ [[:space:]] ]] && continue
    [[ "$candidate" =~ [,:] ]] && continue
    [ "${#candidate}" -gt 200 ] && continue

    # Si le chemin commence par '/' (absolu), on le rend relatif au repo
    if [[ "$candidate" == /* ]]; then
      candidate="${candidate#/}"
    fi

    checked_count=$((checked_count + 1))

    # Match : un fichier du repo dont le chemin termine par "$candidate".
    # Le candidate doit être précédé d'un séparateur de chemin pour éviter
    # qu'un chemin "x.swift" matche par accident "barx.swift".
    found=0
    if [ -e "$candidate" ]; then
      found=1
    else
      for repo_file in "${repo_files[@]}"; do
        if [[ "$repo_file" == */"$candidate" ]] || [[ "$repo_file" == "$candidate" ]]; then
          found=1
          break
        fi
      done
    fi

    # Skip gitignored files (Secrets.xcconfig, .env, *.adminsdk.json, etc.).
    # On les cite légitimement dans la doc même s'ils ne sont pas dans
    # le dépôt. git check-ignore renvoie 0 si le chemin matche .gitignore.
    if [ "$found" -eq 0 ]; then
      if git check-ignore --quiet "$candidate" 2>/dev/null; then
        found=1
      fi
    fi

    # Skip si présent dans l'allowlist explicite : match exact ou suffixe de
    # chemin ("/<entrée>"), pour couvrir aussi bien "AuthKey.json" que
    # "fastlane/AuthKey.json".
    if [ "$found" -eq 0 ] && [ ${#allowlist[@]} -gt 0 ]; then
      for entry in "${allowlist[@]}"; do
        if [[ "$candidate" == "$entry" ]] || [[ "$candidate" == *"/$entry" ]]; then
          found=1
          echo "  ℹ️  allowlisted: $candidate (entrée « $entry »)"
          break
        fi
      done
    fi

    if [ "$found" -eq 0 ]; then
      missing_count=$((missing_count + 1))
      missing_paths+=("$md → $candidate")
    fi
  done < <(grep -oE '`[^`]+`' "$md" 2>/dev/null | sed 's/^`//; s/`$//' || true)
done

echo "Checked $checked_count code path reference(s) across docs/"
echo ""

if [ "$missing_count" -gt 0 ]; then
  echo "::error::Doc drift detected — $missing_count code path(s) referenced in docs no longer exist:"
  for entry in "${missing_paths[@]}"; do
    echo "  - $entry"
  done
  echo ""
  echo "Update the offending Markdown files to point at the new path, or remove the obsolete reference."
  exit 1
fi

echo "✅ No doc drift detected."
exit 0
