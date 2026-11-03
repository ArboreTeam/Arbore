import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// lib/authService.test.ts — la connexion web. (#725 point 8)
//
// 63 instructions, **zéro test** jusqu'au 2026-11-03, alors que ce fichier
// porte `signUp`, `login`, `signInWithGoogle`, `signInWithApple`, le cookie
// que `middleware.ts` consomme, et l'upsert du compte backend. C'est le
// chemin par lequel tout utilisateur web entre dans le produit.
//
// Firebase est mocké intégralement : charger le vrai SDK demanderait un
// `initializeApp` et une configuration, et ce n'est pas Firebase qu'on teste —
// c'est ce que NOTRE code en fait.

// `vi.hoisted` : `vi.mock` est remonté en tête de fichier par vitest, donc
// une constante déclarée normalement n'existerait pas encore quand la
// fabrique s'exécute. Tout ce que la fabrique touche doit être hissé avec
// elle.
const h = vi.hoisted(() => {
  const etat = {
    auth: { currentUser: null as unknown },
    rappelJetonChange: undefined as ((user: unknown) => void) | undefined,
  };
  const firebaseAuth = {
    createUserWithEmailAndPassword: vi.fn(),
    signInWithEmailAndPassword: vi.fn(),
    signOut: vi.fn(async () => undefined),
    updateProfile: vi.fn(async () => undefined),
    onAuthStateChanged: vi.fn(() => () => undefined),
    onIdTokenChanged: vi.fn((_auth: unknown, cb: (user: unknown) => void) => {
      etat.rappelJetonChange = cb;
      return () => undefined;
    }),
    signInWithPopup: vi.fn(),
    GoogleAuthProvider: vi.fn(function (this: Record<string, unknown>) {
      this.setCustomParameters = vi.fn();
      this.addScope = vi.fn();
    }),
    OAuthProvider: vi.fn(function (this: Record<string, unknown>, id: string) {
      this.providerId = id;
      this.setCustomParameters = vi.fn();
      this.addScope = vi.fn();
    }),
  };
  return { etat, firebaseAuth };
});

const { auth } = h.etat;
const firebaseAuth = h.firebaseAuth;

vi.mock('firebase/auth', () => h.firebaseAuth);
vi.mock('./firebase', () => ({ auth: h.etat.auth }));

import {
  signUp,
  login,
  logout,
  signInWithGoogle,
  signInWithApple,
  getUserProfile,
  getCurrentUser,
  getFirebaseToken,
  onAuthStateChange,
} from './authService';

/** Un utilisateur Firebase réduit à ce que `authService` lui demande. */
function utilisateur(surcharges: Record<string, unknown> = {}) {
  return {
    uid: 'uid-123',
    email: 'personne@example.test',
    displayName: null,
    getIdToken: vi.fn(async () => 'JETON'),
    ...surcharges,
  };
}

function mockFetch(reponse = new Response('{}', { status: 200 })) {
  const fn = vi.fn(async () => reponse.clone());
  vi.stubGlobal('fetch', fn);
  return fn;
}

beforeEach(() => {
  vi.clearAllMocks();
  auth.currentUser = null;
  document.cookie = 'arbore_auth=; path=/; max-age=0';
});

afterEach(() => {
  vi.unstubAllGlobals();
});

// --- Le cookie de session, consommé par middleware.ts --------------------

describe('cookie de session', () => {
  it('est posé à la connexion, pour une heure et en SameSite=Lax', () => {
    const poses: string[] = [];
    const descripteur = Object.getOwnPropertyDescriptor(
      Document.prototype, 'cookie');
    Object.defineProperty(document, 'cookie', {
      configurable: true,
      set: (v: string) => poses.push(v),
      get: () => '',
    });

    h.etat.rappelJetonChange?.(utilisateur());

    Object.defineProperty(document, 'cookie', descripteur!);
    expect(poses).toHaveLength(1);
    expect(poses[0]).toContain('arbore_auth=1');
    // Alignée sur la durée de vie du jeton Firebase. Un cookie qui lui
    // survivrait laisserait `middleware.ts` afficher les pages protégées à
    // quelqu'un dont la session est expirée.
    expect(poses[0]).toContain('max-age=3600');
    expect(poses[0]).toContain('SameSite=Lax');
  });

  it('est EFFACÉ à la déconnexion', () => {
    const poses: string[] = [];
    const descripteur = Object.getOwnPropertyDescriptor(
      Document.prototype, 'cookie');
    Object.defineProperty(document, 'cookie', {
      configurable: true,
      set: (v: string) => poses.push(v),
      get: () => '',
    });

    h.etat.rappelJetonChange?.(null);

    Object.defineProperty(document, 'cookie', descripteur!);
    expect(poses[0]).toContain('max-age=0');
    expect(poses[0]).not.toContain('arbore_auth=1');
  });

  it("n'est pas marqué Secure en HTTP, sinon il ne serait pas posé en local", () => {
    const poses: string[] = [];
    const descripteur = Object.getOwnPropertyDescriptor(
      Document.prototype, 'cookie');
    Object.defineProperty(document, 'cookie', {
      configurable: true,
      set: (v: string) => poses.push(v),
      get: () => '',
    });

    h.etat.rappelJetonChange?.(utilisateur());

    Object.defineProperty(document, 'cookie', descripteur!);
    // jsdom sert la page en http:, donc pas de Secure attendu ici.
    expect(window.location.protocol).toBe('http:');
    expect(poses[0]).not.toContain('Secure');
  });
});

// --- signUp ---------------------------------------------------------------

describe('signUp', () => {
  it('pose le nom affiché puis crée le compte côté backend', async () => {
    const user = utilisateur();
    firebaseAuth.createUserWithEmailAndPassword.mockResolvedValue({ user });
    const fetchMock = mockFetch();

    const rendu = await signUp('personne@example.test', 'mdp', 'Camille');

    expect(rendu).toBe(user);
    expect(firebaseAuth.updateProfile).toHaveBeenCalledWith(
      user, { displayName: 'Camille' });

    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/api/backend/users');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body as string)).toMatchObject({
      uid: 'uid-123', email: 'personne@example.test', name: 'Camille',
    });
  });

  it("rend quand même l'utilisateur si le backend refuse", async () => {
    // Comportement voulu et commenté dans le code : le compte Firebase EXISTE
    // déjà à ce stade. Échouer ici laisserait l'utilisateur avec une identité
    // sans moyen d'entrer, et un second essai buterait sur « email déjà pris ».
    const user = utilisateur();
    firebaseAuth.createUserWithEmailAndPassword.mockResolvedValue({ user });
    mockFetch(new Response('erreur', { status: 500 }));
    vi.spyOn(console, 'error').mockImplementation(() => undefined);

    await expect(signUp('a@b.test', 'mdp', 'Camille')).resolves.toBe(user);
  });

  it("rend quand même l'utilisateur si le backend est injoignable", async () => {
    const user = utilisateur();
    firebaseAuth.createUserWithEmailAndPassword.mockResolvedValue({ user });
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('offline'); }));
    vi.spyOn(console, 'error').mockImplementation(() => undefined);

    await expect(signUp('a@b.test', 'mdp', 'Camille')).resolves.toBe(user);
  });

  it('remonte une erreur Firebase', async () => {
    firebaseAuth.createUserWithEmailAndPassword.mockRejectedValue(
      new Error('auth/email-already-in-use'));

    await expect(signUp('a@b.test', 'mdp', 'Camille'))
      .rejects.toThrow('auth/email-already-in-use');
  });
});

// --- OAuth ----------------------------------------------------------------

describe('connexion OAuth', () => {
  it('Google demande explicitement le choix du compte', async () => {
    // Sans `prompt: select_account`, Google reconnecte en silence le dernier
    // compte utilisé — impossible d'en changer depuis la page.
    const user = utilisateur();
    firebaseAuth.signInWithPopup.mockResolvedValue({ user });
    mockFetch();

    await signInWithGoogle();

    const provider = firebaseAuth.signInWithPopup.mock.calls[0][1] as
      { setCustomParameters: ReturnType<typeof vi.fn> };
    expect(provider.setCustomParameters).toHaveBeenCalledWith(
      { prompt: 'select_account' });
  });

  it("Apple demande l'email et le nom", async () => {
    // Apple ne les transmet QUE si on les demande, et seulement au tout
    // premier consentement. Les oublier crée un compte sans identité, pour
    // toujours.
    const user = utilisateur();
    firebaseAuth.signInWithPopup.mockResolvedValue({ user });
    mockFetch();

    await signInWithApple();

    expect(firebaseAuth.OAuthProvider).toHaveBeenCalledWith('apple.com');
    const provider = firebaseAuth.signInWithPopup.mock.calls[0][1] as
      { addScope: ReturnType<typeof vi.fn> };
    expect(provider.addScope).toHaveBeenCalledWith('email');
    expect(provider.addScope).toHaveBeenCalledWith('name');
  });

  it('crée le compte backend avec le jeton en en-tête', async () => {
    const user = utilisateur();
    firebaseAuth.signInWithPopup.mockResolvedValue({ user });
    const fetchMock = mockFetch();

    await signInWithGoogle();

    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/api/backend/users');
    expect((init.headers as Record<string, string>).Authorization)
      .toBe('Bearer JETON');
  });

  it("se rabat sur la partie locale de l'email quand Apple masque le nom", async () => {
    const user = utilisateur({ displayName: null, email: 'masque@privaterelay.test' });
    firebaseAuth.signInWithPopup.mockResolvedValue({ user });
    const fetchMock = mockFetch();

    await signInWithApple();

    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(init.body as string).name).toBe('masque');
  });

  it("ne casse PAS la connexion si l'upsert backend échoue", async () => {
    // Firebase a authentifié ; refuser l'entrée pour une panne de notre côté
    // serait une régression de disponibilité, pas une protection.
    const user = utilisateur();
    firebaseAuth.signInWithPopup.mockResolvedValue({ user });
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('offline'); }));
    vi.spyOn(console, 'error').mockImplementation(() => undefined);

    await expect(signInWithGoogle()).resolves.toBe(user);
  });
});

// --- login / logout -------------------------------------------------------

describe('login et logout', () => {
  it('login rend l’utilisateur', async () => {
    const user = utilisateur();
    firebaseAuth.signInWithEmailAndPassword.mockResolvedValue({ user });

    await expect(login('a@b.test', 'mdp')).resolves.toBe(user);
  });

  it('login remonte une erreur Firebase', async () => {
    firebaseAuth.signInWithEmailAndPassword.mockRejectedValue(
      new Error('auth/wrong-password'));

    await expect(login('a@b.test', 'mauvais'))
      .rejects.toThrow('auth/wrong-password');
  });

  it('logout appelle signOut', async () => {
    await logout();
    expect(firebaseAuth.signOut).toHaveBeenCalledWith(auth);
  });

  it('logout remonte une erreur plutôt que de la taire', async () => {
    // Un logout qui échoue en silence laisserait l'utilisateur croire qu'il
    // est déconnecté alors que son jeton reste valide.
    firebaseAuth.signOut.mockRejectedValueOnce(new Error('réseau'));
    await expect(logout()).rejects.toThrow('réseau');
  });
});

// --- Lectures -------------------------------------------------------------

describe('lectures', () => {
  it('getUserProfile rend le profil du corps de la réponse', async () => {
    mockFetch(new Response(JSON.stringify({ user: { uid: 'uid-123' } }),
                           { status: 200 }));

    await expect(getUserProfile('uid-123')).resolves.toEqual({ uid: 'uid-123' });
  });

  it('getUserProfile rend null sur une réponse non-OK', async () => {
    mockFetch(new Response('', { status: 404 }));
    await expect(getUserProfile('inconnu')).resolves.toBeNull();
  });

  it('getUserProfile rend null sur une panne réseau, sans lever', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('offline'); }));
    vi.spyOn(console, 'error').mockImplementation(() => undefined);

    await expect(getUserProfile('uid-123')).resolves.toBeNull();
  });

  it('getFirebaseToken rend null hors session, sans lever', async () => {
    auth.currentUser = null;
    await expect(getFirebaseToken()).resolves.toBeNull();
  });

  it('getFirebaseToken rend le jeton en session', async () => {
    auth.currentUser = utilisateur();
    await expect(getFirebaseToken()).resolves.toBe('JETON');
  });

  it('getCurrentUser lit directement Firebase', () => {
    const user = utilisateur();
    auth.currentUser = user;
    expect(getCurrentUser()).toBe(user);
  });

  it('onAuthStateChange branche le rappel sur Firebase', () => {
    const rappel = vi.fn();
    onAuthStateChange(rappel);
    expect(firebaseAuth.onAuthStateChanged).toHaveBeenCalledWith(auth, rappel);
  });
});

// --- La propriété de sécurité du proxy ------------------------------------

describe('aucun appel ne sort du proxy same-origin', () => {
  it("tous les appels visent /api/backend, jamais l'API directement", async () => {
    // C'est ce qui garde `ARBORE_API_KEY` côté serveur : le navigateur
    // n'appelle que sa propre origine. Un appel absolu vers api.arbore.app
    // obligerait à embarquer la clé dans le bundle.
    const user = utilisateur();
    firebaseAuth.createUserWithEmailAndPassword.mockResolvedValue({ user });
    firebaseAuth.signInWithPopup.mockResolvedValue({ user });
    const fetchMock = mockFetch();

    await signUp('a@b.test', 'mdp', 'Camille');
    await signInWithGoogle();
    await signInWithApple();
    await getUserProfile('uid-123');

    expect(fetchMock.mock.calls.length).toBeGreaterThanOrEqual(4);
    for (const [url] of fetchMock.mock.calls as unknown as [string][]) {
      expect(url.startsWith('/api/backend')).toBe(true);
      expect(url).not.toMatch(/^https?:\/\//);
    }
  });
});
