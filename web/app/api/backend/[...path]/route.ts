import { NextRequest, NextResponse } from 'next/server';

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

// Allowlist des préfixes backend exposés via le proxy (défense en profondeur :
// empêche d'utiliser le proxy comme relais générique vers tout endpoint interne).
const ALLOWED_PREFIXES = new Set(['users', 'plants', 'gardens', 'consents', 'models', 'config']);

const MAX_PROXY_BODY_BYTES = 10 * 1024 * 1024;

async function proxy(req: NextRequest, path: string[]) {
  // Anti-traversal + allowlist.
  if (
    path.length === 0 ||
    !ALLOWED_PREFIXES.has(path[0]) ||
    path.some((seg) => seg === '..' || seg === '' || seg.includes('\\'))
  ) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }
	if (!API_KEY) {
		return NextResponse.json({ error: 'Backend configuration unavailable' }, { status: 503 });
	}

  // La génération de plantes par IA est debug-only (absente de l'iOS / de la prod) :
  // on la bloque côté proxy pour qu'elle ne soit pas appelable depuis le web.
  const joined = path.join('/');
  if (joined === 'plants/generate' || joined === 'plants/generate-multiple') {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }

  const { search } = new URL(req.url);
  const target = `${BACKEND_URL}/${path.map(encodeURIComponent).join('/')}${search}`;

  const headers = new Headers();
  headers.set('X-API-Key', API_KEY);
  const auth = req.headers.get('authorization');
  if (auth) headers.set('Authorization', auth);
  const contentType = req.headers.get('content-type');
  if (contentType) headers.set('Content-Type', contentType);

  const method = req.method.toUpperCase();
  const init: RequestInit = { method, headers, cache: 'no-store', redirect: 'manual' };
  if (method !== 'GET' && method !== 'HEAD') {
	const declaredLength = Number(req.headers.get('content-length') || '0');
	if (declaredLength > MAX_PROXY_BODY_BYTES) {
	  return NextResponse.json({ error: 'Request body too large' }, { status: 413 });
	}
    const body = await req.arrayBuffer();
	if (body.byteLength > MAX_PROXY_BODY_BYTES) {
	  return NextResponse.json({ error: 'Request body too large' }, { status: 413 });
	}
    if (body.byteLength > 0) init.body = body;
  }
	init.signal = AbortSignal.timeout(method === 'GET' ? 120_000 : 65_000);

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

type Ctx = { params: Promise<{ path: string[] }> };

async function handle(req: NextRequest, context: Ctx) {
	const { path } = await context.params;
	return proxy(req, path);
}

export async function GET(req: NextRequest, context: Ctx) { return handle(req, context); }
export async function POST(req: NextRequest, context: Ctx) { return handle(req, context); }
export async function PUT(req: NextRequest, context: Ctx) { return handle(req, context); }
export async function PATCH(req: NextRequest, context: Ctx) { return handle(req, context); }
export async function DELETE(req: NextRequest, context: Ctx) { return handle(req, context); }
