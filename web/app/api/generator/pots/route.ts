import { NextRequest, NextResponse } from 'next/server';

import { pots } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/** La bibliothèque de pots, chacun avec le rebord mesuré à l'ingestion. */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  return NextResponse.json({ pots: pots() });
}
