import { describe, it, expect, vi, beforeEach } from 'vitest';

// On mocke authService pour éviter de charger Firebase (initializeApp) dans le test.
vi.mock('./authService', () => ({
  getFirebaseToken: vi.fn(async () => 'TEST_TOKEN'),
}));

import { fetchWithAuth, apiGet, apiSend, ApiError, API_URL } from './api';

/** Mock de fetch typé (url, init) -> 200 {} ; renvoie le mock pour inspecter les appels. */
function mockFetch() {
  const fn = vi.fn((_url: string, _init: RequestInit) =>
    Promise.resolve(new Response('{}', { status: 200 })),
  );
  vi.stubGlobal('fetch', fn);
  return fn;
}

describe('lib/api', () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
  });

  describe('fetchWithAuth', () => {
    it('attache le token Firebase et le Content-Type JSON', async () => {
      const fetchMock = mockFetch();

      await fetchWithAuth(`${API_URL}/gardens`);

      expect(fetchMock).toHaveBeenCalledTimes(1);
      const [url, init] = fetchMock.mock.calls[0];
      expect(url).toBe('/api/backend/gardens');
      const headers = init.headers as Record<string, string>;
      expect(headers.Authorization).toBe('Bearer TEST_TOKEN');
      expect(headers['Content-Type']).toBe('application/json');
    });

    it('résout un chemin relatif contre la base du proxy', async () => {
      const fetchMock = mockFetch();

      await fetchWithAuth('plants');

      expect(fetchMock.mock.calls[0][0]).toBe('/api/backend/plants');
    });
  });

  describe('apiGet', () => {
    it('renvoie le JSON parsé sur 2xx', async () => {
      vi.stubGlobal(
        'fetch',
        vi.fn(async () => new Response(JSON.stringify({ id: '1' }), { status: 200 })),
      );

      const data = await apiGet<{ id: string }>('/gardens/1');

      expect(data).toEqual({ id: '1' });
    });

    it('lève une ApiError sur statut non-2xx', async () => {
      vi.stubGlobal(
        'fetch',
        vi.fn(async () => new Response('forbidden', { status: 403 })),
      );

      await expect(apiGet('/gardens')).rejects.toBeInstanceOf(ApiError);
    });
  });

  describe('apiSend', () => {
    it('sérialise le body et applique la méthode', async () => {
      const fetchMock = mockFetch();

      await apiSend('POST', '/gardens', { name: 'Test' });

      const [, init] = fetchMock.mock.calls[0];
      expect(init.method).toBe('POST');
      expect(init.body).toBe(JSON.stringify({ name: 'Test' }));
    });
  });
});
