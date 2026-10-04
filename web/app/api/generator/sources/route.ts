import { NextRequest, NextResponse } from 'next/server';

import { sources } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/** Les images d'entrée présentes, avec ce que l'état sait de chaque plante. */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  return NextResponse.json({ sources: sources() });
}
