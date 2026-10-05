import { NextRequest, NextResponse } from 'next/server';

import { posables } from '@/lib/generator/depot';
import { bonHote, introuvable } from '@/lib/generator/http';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

/** Les plantes auxquelles on peut poser un pot : maillage coupé + socle. */
export async function GET(req: NextRequest) {
  if (!bonHote(req)) return introuvable();
  return NextResponse.json({ plantes: posables() });
}
