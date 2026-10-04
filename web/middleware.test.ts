import { describe, it, expect, beforeAll } from 'vitest';
import { NextRequest } from 'next/server';

import { COOKIE_SESSION, emettre } from '@/lib/generator/session';

const SECRET = 'secret-de-test-du-middleware';
const ATELIER = 'generator.arbore.app';
const PUBLIC = 'web.arbore.app';

process.env.GENERATOR_SESSION_SECRET = SECRET;
process.env.GENERATOR_HOST = ATELIER;

// Importé APRÈS les variables d'environnement : le module les lit à l'appel,
// mais on ne veut pas dépendre de cet ordre pour que le test tienne.
let middleware: (req: NextRequest) => Promise<Response>;
let jetonValide: string;

beforeAll(async () => {
  ({ middleware } = await import('./middleware'));
  jetonValide = await emettre(SECRET);
});

function requete(hote: string, chemin: string, jeton?: string) {
  const req = new NextRequest(new URL(`https://${hote}${chemin}`), {
    headers: new Headers({ host: hote }),
  });
  if (jeton) req.cookies.set(COOKIE_SESSION, jeton);
  return req;
}

describe('middleware — frontière de l atelier', () => {
  it('redirige une page vers le formulaire de clé sans session', async () => {
    const r = await middleware(requete(ATELIER, '/generator'));
    expect(r.status).toBe(307);
    expect(new URL(r.headers.get('location')!).pathname).toBe('/generator/login');
  });

  it('répond 401 à une API sans session, et non du HTML', async () => {
    // Un ouvrier Colab qui appelle l API doit recevoir une erreur exploitable,
    // pas une page de formulaire déguisée en succès.
    const r = await middleware(requete(ATELIER, '/api/generator/taches/prendre'));
    expect(r.status).toBe(401);
    expect(r.headers.get('content-type')).toContain('application/json');
  });

  it('laisse passer avec une session valide', async () => {
    const r = await middleware(requete(ATELIER, '/generator', jetonValide));
    expect(r.headers.get('x-middleware-next')).toBe('1');
  });

  it('refuse une session signée avec un autre secret', async () => {
    const usurpe = await emettre('mauvais-secret');
    const r = await middleware(requete(ATELIER, '/generator', usurpe));
    expect(r.status).toBe(307);
  });

  it('ouvre le formulaire de clé sans session', async () => {
    const r = await middleware(requete(ATELIER, '/generator/login'));
    expect(r.headers.get('x-middleware-next')).toBe('1');
  });

  it('évite le formulaire quand la session est déjà valide', async () => {
    const r = await middleware(requete(ATELIER, '/generator/login', jetonValide));
    expect(r.status).toBe(307);
    expect(new URL(r.headers.get('location')!).pathname).toBe('/generator');
  });

  it('laisse la route de connexion accessible sans session', async () => {
    const r = await middleware(requete(ATELIER, '/api/generator/login'));
    expect(r.headers.get('x-middleware-next')).toBe('1');
  });

  it('fait de la racine de l atelier son tableau de bord', async () => {
    const r = await middleware(requete(ATELIER, '/', jetonValide));
    expect(r.status).toBe(307);
    expect(new URL(r.headers.get('location')!).pathname).toBe('/generator');
  });
});

describe('middleware — protection croisée des hôtes', () => {
  // Le test le plus important du fichier : une erreur de configuration nginx
  // ne doit pas exposer l atelier — ni sa file de travail — sur le site public.
  it('rend l atelier introuvable depuis le site public', async () => {
    for (const chemin of ['/generator', '/generator/login', '/generator/revue']) {
      const r = await middleware(requete(PUBLIC, chemin, jetonValide));
      expect(r.status).toBe(404);
    }
  });

  it('rend les API de l atelier introuvables depuis le site public', async () => {
    for (const chemin of ['/api/generator/login', '/api/generator/taches/prendre']) {
      const r = await middleware(requete(PUBLIC, chemin, jetonValide));
      expect(r.status).toBe(404);
    }
  });

  it('un hôte inconnu ne donne pas accès à l atelier', async () => {
    const r = await middleware(requete('ailleurs.example', '/generator', jetonValide));
    expect(r.status).toBe(404);
  });
});

describe('middleware — le site public n a pas changé', () => {
  it('redirige une page protégée vers la connexion Firebase', async () => {
    const r = await middleware(requete(PUBLIC, '/garden'));
    expect(r.status).toBe(307);
    const url = new URL(r.headers.get('location')!);
    expect(url.pathname).toBe('/login');
    expect(url.searchParams.get('redirect')).toBe('/garden');
  });

  it('laisse passer les pages ouvertes', async () => {
    const r = await middleware(requete(PUBLIC, '/pricing'));
    expect(r.headers.get('x-middleware-next')).toBe('1');
  });

  it('la session de l atelier ne vaut rien sur le site public', async () => {
    // Les deux cookies sont distincts : l un n ouvre jamais l autre.
    const r = await middleware(requete(PUBLIC, '/garden', jetonValide));
    expect(r.status).toBe(307);
    expect(new URL(r.headers.get('location')!).pathname).toBe('/login');
  });
});
