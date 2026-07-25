import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// UX gate only. The Go backend remains the security boundary and validates the
// Firebase token on every protected API request.
const SESSION_COOKIE = 'arbore_auth';
const PROTECTED = ['/garden', '/profile', '/welcome'];
const AUTH_PAGES = ['/login', '/signup'];

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const authed = req.cookies.has(SESSION_COOKIE);
  const isProtected = PROTECTED.some(
    (path) => pathname === path || pathname.startsWith(`${path}/`),
  );

  if (isProtected && !authed) {
    const url = req.nextUrl.clone();
    url.pathname = '/login';
    url.searchParams.set('redirect', pathname);
    return NextResponse.redirect(url);
  }

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
