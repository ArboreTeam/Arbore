import { NextResponse } from 'next/server';

// Proxy same-origin vers le backend Go.
// But : la web app appelle les MÊMES endpoints que l'app mobile, sans CORS
// (requêtes same-origin), et la clé API n'est JAMAIS exposée au navigateur.
//
// Le navigateur appelle `/api/backend/<path>` ; ce handler (côté serveur) :
//   - injecte X-API-Key depuis une variable serveur-only (ARBORE_API_KEY)
//   - transmet le token Firebase du client (Authorization: Bearer ...)
//   - forwarde méthode / body / query string vers le backend
//
// Variables d'env (serveur, jamais NEXT_PUBLIC_) :
//   BACKEND_API_URL  (défaut http://localhost:8080)
//   ARBORE_API_KEY   (identique à ARBORE_API_KEY côté backend)

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

const BACKEND_URL = (process.env.BACKEND_API_URL || 'http://localhost:8080').replace(/\/+$/, '');
const API_KEY = process.env.ARBORE_API_KEY || '';

async function proxy(req: Request, path: string[]) {
  const { search } = new URL(req.url);
  const target = `${BACKEND_URL}/${path.join('/')}${search}`;

  const headers = new Headers();
  headers.set('X-API-Key', API_KEY);
  const auth = req.headers.get('authorization');
  if (auth) headers.set('Authorization', auth);
  const contentType = req.headers.get('content-type');
  if (contentType) headers.set('Content-Type', contentType);

  const method = req.method.toUpperCase();
  const init: RequestInit = { method, headers, cache: 'no-store', redirect: 'manual' };
  if (method !== 'GET' && method !== 'HEAD') {
    const body = await req.arrayBuffer();
    if (body.byteLength > 0) init.body = body;
  }

  let upstream: Response;
  try {
    upstream = await fetch(target, init);
  } catch {
    return NextResponse.json({ error: 'Backend injoignable' }, { status: 502 });
  }

  const resHeaders = new Headers();
  const ct = upstream.headers.get('content-type');
  if (ct) resHeaders.set('Content-Type', ct);
  const buf = await upstream.arrayBuffer();
  return new NextResponse(buf, { status: upstream.status, headers: resHeaders });
}

type Ctx = { params: { path: string[] } };

export function GET(req: Request, { params }: Ctx) { return proxy(req, params.path); }
export function POST(req: Request, { params }: Ctx) { return proxy(req, params.path); }
export function PUT(req: Request, { params }: Ctx) { return proxy(req, params.path); }
export function PATCH(req: Request, { params }: Ctx) { return proxy(req, params.path); }
export function DELETE(req: Request, { params }: Ctx) { return proxy(req, params.path); }
