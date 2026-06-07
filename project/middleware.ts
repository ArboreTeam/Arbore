import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// Protection des routes côté serveur (avant rendu).
// Gate sur le cookie de session posé par lib/authService.ts (onIdTokenChanged).
// NB : sécurité réelle = vérification du token Firebase par le backend sur chaque
// appel API. Ce middleware n'améliore que l'UX (pas de flash de page protégée).

const SESSION_COOKIE = 'arbore_auth';
const PROTECTED = ['/garden', '/profile', '/welcome'];
const AUTH_PAGES = ['/login', '/signup'];

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const authed = req.cookies.has(SESSION_COOKIE);

  const isProtected = PROTECTED.some(
    (p) => pathname === p || pathname.startsWith(`${p}/`),
  );

  // Non connecté sur une route protégée -> /login (avec retour après connexion).
  if (isProtected && !authed) {
    const url = req.nextUrl.clone();
    url.pathname = '/login';
    url.searchParams.set('redirect', pathname);
    return NextResponse.redirect(url);
  }

  // Déjà connecté sur login/signup -> /garden.
  if (AUTH_PAGES.includes(pathname) && authed) {
    const url = req.nextUrl.clone();
    url.pathname = '/garden';
    return NextResponse.redirect(url);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/garden/:path*', '/profile/:path*', '/welcome', '/login', '/signup'],
};
