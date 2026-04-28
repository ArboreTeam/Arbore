// lib/authService.ts
import {
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  User,
  updateProfile,
  onAuthStateChanged,
} from 'firebase/auth';
import { auth } from './firebase';

const BACKEND_URL = 'http://localhost:8080';

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
