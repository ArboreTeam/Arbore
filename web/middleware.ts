import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

import { COOKIE_SESSION, verifier } from '@/lib/generator/session';

// ─────────────────────────────────────────────────────────────────────────────
// Site public — web.arbore.app
//
// Portillon d'EXPÉRIENCE seulement. Le backend Go reste la frontière de
// sécurité et valide le jeton Firebase à chaque requête protégée.
// ─────────────────────────────────────────────────────────────────────────────
const COOKIE_PUBLIC = 'arbore_auth';
const PROTEGEES = ['/garden', '/profile', '/welcome'];
const PAGES_AUTH = ['/login', '/signup'];

// ─────────────────────────────────────────────────────────────────────────────
// Atelier de génération 3D — generator.arbore.app
//
// Ici le middleware EST la frontière de sécurité : il n'y a pas de second
// contrôle en aval. Tout ce qui n'est pas explicitement ouvert exige une
// session valide.
//
// Le secret de signature est lu dans l'environnement et non dans un fichier :
// ce code s'exécute sur le runtime Edge, où `node:fs` n'existe pas. L'empreinte
// de la CLÉ, elle, accepte la variante fichier — elle n'est lue que par la
// route de connexion, qui tourne en Node.
// ─────────────────────────────────────────────────────────────────────────────
const OUVERTES = new Set(['/generator/login', '/api/generator/login', '/api/generator/logout']);

function hoteAtelier(): string {
  return (process.env.GENERATOR_HOST || 'generator.arbore.app').toLowerCase();
}

function introuvable() {
  return new NextResponse(null, { status: 404 });
}

async function atelier(req: NextRequest): Promise<NextResponse> {
  const { pathname } = req.nextUrl;

  if (OUVERTES.has(pathname)) {
    // Déjà connecté : on n'affiche pas un formulaire de clé pour rien.
    if (pathname === '/generator/login') {
      const secret = process.env.GENERATOR_SESSION_SECRET || '';
      if (await verifier(req.cookies.get(COOKIE_SESSION)?.value, secret)) {
        const url = req.nextUrl.clone();
        url.pathname = '/generator';
        return NextResponse.redirect(url);
      }
    }
    return NextResponse.next();
  }

  const secret = process.env.GENERATOR_SESSION_SECRET || '';
  if (await verifier(req.cookies.get(COOKIE_SESSION)?.value, secret)) {
    return NextResponse.next();
  }

  // Une API répond 401, une page redirige : un appel programmatique ne doit pas
  // recevoir du HTML de formulaire à la place d'une erreur.
  if (pathname.startsWith('/api/')) {
    return NextResponse.json({ error: 'Non authentifié' }, { status: 401 });
  }
  const url = req.nextUrl.clone();
  url.pathname = '/generator/login';
  url.search = '';
  return NextResponse.redirect(url);
}

export async function middleware(req: NextRequest) {
  const hote = (req.headers.get('host') || '').toLowerCase().split(':')[0];
  const { pathname } = req.nextUrl;

  if (hote === hoteAtelier()) {
    // La racine de l'atelier est son tableau de bord, pas le site public.
    if (pathname === '/') {
      const url = req.nextUrl.clone();
      url.pathname = '/generator';
      return NextResponse.redirect(url);
    }
    return atelier(req);
  }

  // Protection croisée : hors de son hôte, l'atelier n'existe pas. Sans cette
  // ligne, une erreur de configuration nginx exposerait ses pages — et sa file
  // de travail — sur le site public.
  if (pathname === '/generator' || pathname.startsWith('/generator/')
      || pathname.startsWith('/api/generator/')) {
    return introuvable();
  }

  const authed = req.cookies.has(COOKIE_PUBLIC);
  const protegee = PROTEGEES.some((p) => pathname === p || pathname.startsWith(`${p}/`));

  if (protegee && !authed) {
    const url = req.nextUrl.clone();
    url.pathname = '/login';
    url.searchParams.set('redirect', pathname);
    return NextResponse.redirect(url);
  }
  if (PAGES_AUTH.includes(pathname) && authed) {
    const url = req.nextUrl.clone();
    url.pathname = '/garden';
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

// Le middleware doit voir TOUTES les requêtes : le filtrage se fait par hôte,
// pas par chemin, et un chemin oublié dans cette liste serait un chemin non
// protégé. On n'exclut que ce qui ne peut rien exposer.
export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|icon.svg|.*\\.(?:png|jpg|jpeg|svg|webp|ico)$).*)'],
};
