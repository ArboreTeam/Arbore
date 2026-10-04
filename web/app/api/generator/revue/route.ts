import { NextRequest, NextResponse } from 'next/server';

import { aRevoir } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/** Plantes livrées dont le verdict reste à rendre. */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  return NextResponse.json({ file: aRevoir() });
}
