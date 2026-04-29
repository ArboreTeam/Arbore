# 🔐 Configuration des Secrets GitHub pour le CI

Ce document explique comment configurer les secrets GitHub nécessaires pour que le CI fonctionne avec Firebase et le backend.

## 📋 Secrets Requis

### 1. `GOOGLE_SERVICE_INFO_PLIST_BASE64`

**Description**: Fichier de configuration Firebase encodé en base64

**Comment l'obtenir**:

```bash
# Depuis le répertoire ArboreUi
base64 -i GoogleService-Info.plist | pbcopy
```

Cela copie le fichier encodé dans votre presse-papier.

**Comment le configurer**:
1. Allez sur GitHub → Repository Settings → Secrets and variables → Actions
2. Cliquez sur "New repository secret"
3. Nom: `GOOGLE_SERVICE_INFO_PLIST_BASE64`
4. Valeur: Collez le contenu encodé
5. Cliquez sur "Add secret"

---

### 2. `ARBORE_API_KEY`

**Description**: Clé API pour authentifier l'application iOS auprès du backend

**Format**: `arbore_ios_v1_<64 alphanumeric chars>`

**⚠️ La clé réelle ne doit jamais apparaître dans le repo.** Demandez-la
à un mainteneur (canal privé) ou régénérez-en une nouvelle sur le
backend (\`ssh fedora@<host>\`, voir \`/home/fedora/Arbore/.env\`).

**Comment le configurer**:
1. Allez sur GitHub → Repository Settings → Secrets and variables → Actions
2. Cliquez sur "New repository secret"
3. Nom: `ARBORE_API_KEY`
4. Valeur: la clé obtenue par canal sécurisé
5. Cliquez sur "Add secret"

⚠️ **Important**: En production, générez une nouvelle clé API sécurisée

---

### 3. `ARBORE_BACKEND_PROTOCOL`

**Description**: Protocole du backend (http ou https)

**Valeur pour le CI**: `http`

**Comment le configurer**:
1. Allez sur GitHub → Repository Settings → Secrets and variables → Actions
2. Cliquez sur "New repository secret"
3. Nom: `ARBORE_BACKEND_PROTOCOL`
4. Valeur: `http`
5. Cliquez sur "Add secret"

---

### 4. `ARBORE_BACKEND_HOST`

**Description**: Adresse du backend (IP:port ou domaine:port)

**Valeur pour le CI**: `79.137.92.154:8080`

**Comment le configurer**:
1. Allez sur GitHub → Repository Settings → Secrets and variables → Actions
2. Cliquez sur "New repository secret"
3. Nom: `ARBORE_BACKEND_HOST`
4. Valeur: `79.137.92.154:8080`
5. Cliquez sur "Add secret"

---

## ✅ Vérification

Une fois tous les secrets configurés, vous devriez avoir dans vos secrets GitHub Actions:

- ✅ `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- ✅ `ARBORE_API_KEY`
- ✅ `ARBORE_BACKEND_PROTOCOL`
- ✅ `ARBORE_BACKEND_HOST`

## 🔒 Sécurité

- ⚠️ **Ne partagez jamais** ces secrets publiquement
- ⚠️ **Ne committez jamais** `GoogleService-Info.plist` ou `Secrets.xcconfig` dans Git
- ✅ Ces fichiers sont déjà dans `.gitignore`
- ✅ Le CI les recrée automatiquement à partir des secrets

## 🧪 Tester localement

Pour tester que vos secrets sont corrects:

```bash
# Vérifier que GoogleService-Info.plist existe
ls -la ArboreUi/GoogleService-Info.plist

# Vérifier que Secrets.xcconfig existe
ls -la ArboreUi/Secrets.xcconfig

# Lancer les tests
cd ArboreUi
./ci-ui-local.sh
```

## 🆘 Problèmes courants

### ❌ "GoogleService-Info.plist not found"
→ Vérifiez que `GOOGLE_SERVICE_INFO_PLIST_BASE64` est bien configuré

### ❌ "ARBORE_API_KEY non configurée"
→ Vérifiez que tous les secrets `ARBORE_*` sont configurés

### ❌ Tests d'intégration échouent
→ Vérifiez que le backend est accessible depuis les runners GitHub
→ Vérifiez que l'API Key est correcte

## 📝 Notes pour Firebase

Si vous avez besoin de créer un nouveau projet Firebase pour le CI:

1. Allez sur [Firebase Console](https://console.firebase.google.com/)
2. Créez un nouveau projet "Arbore-CI" ou "Arbore-Test"
3. Téléchargez le nouveau `GoogleService-Info.plist`
4. Encodez-le en base64 et mettez à jour le secret GitHub
5. Activez **Authentication** → **Email/Password**
6. Activez **Firestore Database**

---

**Dernière mise à jour**: 26 janvier 2026
