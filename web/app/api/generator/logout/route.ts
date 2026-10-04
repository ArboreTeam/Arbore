import { NextRequest, NextResponse } from 'next/server';

import { hoteAtelier } from '@/lib/generator/config';
import { COOKIE_SESSION } from '@/lib/generator/session';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export async function POST(req: NextRequest) {
  if ((req.headers.get('host') || '').toLowerCase().split(':')[0] !== hoteAtelier()) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }
  const reponse = NextResponse.json({ ok: true });
  reponse.cookies.set(COOKIE_SESSION, '', { path: '/', maxAge: 0 });
  return reponse;
}
