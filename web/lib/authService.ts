// lib/authService.ts
import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  User,
  updateProfile,
  onAuthStateChanged,
  onIdTokenChanged,
  GoogleAuthProvider,
  OAuthProvider,
  signInWithPopup,
} from 'firebase/auth';
import { auth } from './firebase';

// Proxy same-origin (voir app/api/backend/[...path]/route.ts) :
// la clé API est injectée côté serveur, jamais exposée au navigateur.
const BACKEND_URL = '/api/backend';

// Cookie de session (UX) : permet à middleware.ts de protéger les routes
// AVANT le rendu (redirection serveur). Ce n'est PAS la sécurité — le backend
// vérifie le token Firebase sur chaque appel ; ce cookie ne fait que gater
// l'affichage. onIdTokenChanged se déclenche à la connexion, à la déconnexion
// et au rafraîchissement horaire du token, gardant le cookie à jour.
const SESSION_COOKIE = 'arbore_auth';
if (typeof document !== 'undefined') {
  // Secure uniquement en HTTPS (sinon le cookie ne serait pas posé en dev localhost).
  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  onIdTokenChanged(auth, (user) => {
    document.cookie = user
      ? `${SESSION_COOKIE}=1; path=/; max-age=3600; SameSite=Lax${secure}`
      : `${SESSION_COOKIE}=; path=/; max-age=0; SameSite=Lax${secure}`;
  });
}

// Sign up avec Firebase
export const signUp = async (email: string, password: string, displayName: string) => {
  try {
    const userCredential = await createUserWithEmailAndPassword(auth, email, password);
    const user = userCredential.user;

    // Mettre à jour le profil Firebase
    await updateProfile(user, {
      displayName: displayName,
    });

    // Créer l'utilisateur dans le backend MongoDB
    try {
      const response = await fetch(`${BACKEND_URL}/users`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          uid: user.uid,
          email: user.email,
          name: displayName,
          createdAt: new Date().toISOString(),
        }),
      });

      if (!response.ok) {
        console.error('Erreur lors de la création de l\'utilisateur dans le backend');
      }
    } catch (backendError) {
      console.error('Erreur backend:', backendError);
      // On continue même si le backend échoue (Firebase est créé)
    }

    return user;
  } catch (error: any) {
    throw new Error(error.message);
  }
};

// Crée (ou ignore si déjà présent) l'enregistrement utilisateur côté backend.
// Appelé après une connexion OAuth (Apple/Google) où le compte peut être nouveau.
// Passe par le proxy /api/backend (clé API injectée côté serveur) + token Firebase.
const ensureBackendUser = async (user: User) => {
  try {
    const token = await user.getIdToken();
    await fetch(`${BACKEND_URL}/users`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        uid: user.uid,
        email: user.email,
        name: user.displayName || user.email?.split('@')[0] || 'Utilisateur',
        createdAt: new Date().toISOString(),
      }),
    });
  } catch (e) {
    // Non bloquant : Firebase est créé, on ne casse pas le login si le backend échoue.
    console.error('Synchronisation backend échouée:', e);
  }
};

// Connexion avec Google (popup)
export const signInWithGoogle = async () => {
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: 'select_account' });
  const { user } = await signInWithPopup(auth, provider);
  await ensureBackendUser(user);
  return user;
};

// Connexion « Se connecter avec Apple » (popup)
export const signInWithApple = async () => {
  const provider = new OAuthProvider('apple.com');
  provider.addScope('email');
  provider.addScope('name');
  const { user } = await signInWithPopup(auth, provider);
  await ensureBackendUser(user);
  return user;
};

// Login avec Firebase
export const login = async (email: string, password: string) => {
  try {
    const userCredential = await signInWithEmailAndPassword(auth, email, password);
    return userCredential.user;
  } catch (error: any) {
    throw new Error(error.message);
  }
};

// Logout
export const logout = async () => {
  try {
    await signOut(auth);
  } catch (error: any) {
    throw new Error(error.message);
  }
};

// Récupérer les infos utilisateur depuis le backend
export const getUserProfile = async (uid: string) => {
  try {
    const response = await fetch(`${BACKEND_URL}/users/${uid}`);
    if (response.ok) {
      const data = await response.json();
      return data.user;
    }
    return null;
  } catch (error: any) {
    console.error('Erreur lors de la récupération du profil:', error);
    return null;
  }
};

// Vérifier si l'utilisateur est connecté
export const getCurrentUser = () => {
  return auth.currentUser;
};

// Obtenir le token JWT pour communiquer avec le backend
export const getFirebaseToken = async () => {
  const user = auth.currentUser;
  if (!user) return null;
  return await user.getIdToken();
};

// Écouter les changements d'état d'authentification
export const onAuthStateChange = (callback: (user: User | null) => void) => {
  return onAuthStateChanged(auth, callback);
};
