// lib/api.ts
// Couche API unique de la web app.
//
// Tous les appels backend passent par le proxy same-origin `/api/backend`
// (voir app/api/backend/[...path]/route.ts) : pas de CORS, et la clé API
// (ARBORE_API_KEY) est injectée côté serveur — jamais exposée au navigateur.
// Ici, côté client, on n'attache que le token Firebase de l'utilisateur.

import { getFirebaseToken } from './authService';

export const API_URL = '/api/backend';

/** Erreur API typée (statut HTTP + corps). */
export class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message || `HTTP ${status}`);
    this.name = 'ApiError';
  }
}

/**
 * fetch authentifié : attache le token Firebase et JSON par défaut.
 * Accepte une URL absolue (`${API_URL}/gardens`) ou relative au proxy.
 */
export async function fetchWithAuth(url: string, options: RequestInit = {}): Promise<Response> {
  const token = await getFirebaseToken();
  const target = url.startsWith('http') || url.startsWith('/') ? url : `${API_URL}/${url}`;
  return fetch(target, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(options.headers || {}),
    },
  });
}

async function safeText(res: Response): Promise<string> {
  try {
    return await res.text();
  } catch {
    return '';
  }
}

/** GET typé : renvoie le JSON, lève une ApiError sur statut non-2xx. */
export async function apiGet<T>(path: string): Promise<T> {
  const res = await fetchWithAuth(`${API_URL}${path}`);
  if (!res.ok) throw new ApiError(res.status, await safeText(res));
  return (await res.json()) as T;
}

/** POST/PUT/PATCH/DELETE typé avec corps JSON optionnel. */
export async function apiSend<T>(
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE',
  path: string,
  body?: unknown,
): Promise<T> {
  const res = await fetchWithAuth(`${API_URL}${path}`, {
    method,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new ApiError(res.status, await safeText(res));
  return res.json().catch(() => ({}) as T);
}

// ─── Types de domaine partagés (à enrichir au fil de l'eau) ───────────────

export interface Plant {
  id?: string;
  _id?: string;
  name?: string;
  generated?: boolean;
  source?: string; // "botanic" = scrapé depuis botanic.com ; sinon legacy/beta
  [key: string]: unknown;
}

export interface Garden {
  id?: string;
  _id?: string;
  name?: string;
  plants?: unknown[];
  [key: string]: unknown;
}
