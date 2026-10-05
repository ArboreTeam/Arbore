// Lecture minimale d'un GLB : positions et triangles, rien d'autre.
//
// Pourquoi côté serveur et non dans le navigateur, qui a déjà three.js : la
// mesure du rebord décide de l'échelle à laquelle un pot sera posé. Faite par
// le client, elle serait une valeur ARRIVÉE PAR LE RÉSEAU que le serveur
// enregistrerait sans pouvoir la vérifier — un client fautif rangerait des
// ancrages faux et personne ne le saurait avant l'essayage.
//
// On ne lit que ce qui sert : POSITION et les indices. Ni UV, ni normales, ni
// textures, ni animations. Un pot pèse quelques mégaoctets et la lecture est
// bornée par le nombre de sommets, pas par le poids du fichier.
import { readFileSync } from 'node:fs';

const MAGIC = 0x46546c67; // "glTF"
const JSON_CHUNK = 0x4e4f534a;
const BIN_CHUNK = 0x004e4942;

/** Tailles en octets par type de composant glTF. */
const OCTETS: Record<number, number> = {
  5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4,
};
const COMPOSANTES: Record<string, number> = {
  SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16,
};

export type Maillage = {
  /** Sommets effectivement référencés par un triangle, à plat : x, y, z. */
  positions: Float32Array;
  triangles: number;
};

type Accesseur = {
  bufferView?: number;
  byteOffset?: number;
  componentType: number;
  count: number;
  type: string;
};

function lireAccesseur(
  meta: Record<string, unknown>, bin: Buffer, index: number,
): { donnees: Float64Array; composantes: number } {
  const accesseurs = meta.accessors as Accesseur[];
  const vues = (meta.bufferViews ?? []) as Array<Record<string, number>>;
  const a = accesseurs[index];
  if (!a || a.bufferView === undefined) throw new Error('accesseur sans vue');

  const vue = vues[a.bufferView];
  const composantes = COMPOSANTES[a.type];
  const taille = OCTETS[a.componentType];
  if (!composantes || !taille) throw new Error('type d accesseur inconnu');

  const debut = (vue.byteOffset ?? 0) + (a.byteOffset ?? 0);
  // `byteStride` : les attributs peuvent être entrelacés dans une même vue.
  // L'ignorer donnerait des positions mélangées à des normales, donc une boîte
  // englobante absurde — et un pot posé n'importe comment.
  const pas = vue.byteStride || composantes * taille;
  const sortie = new Float64Array(a.count * composantes);

  for (let i = 0; i < a.count; i += 1) {
    const base = debut + i * pas;
    for (let k = 0; k < composantes; k += 1) {
      const o = base + k * taille;
      if (o + taille > bin.length) throw new Error('accesseur hors du binaire');
      let v: number;
      switch (a.componentType) {
        case 5126: v = bin.readFloatLE(o); break;
        case 5125: v = bin.readUInt32LE(o); break;
        case 5123: v = bin.readUInt16LE(o); break;
        case 5121: v = bin.readUInt8(o); break;
        case 5122: v = bin.readInt16LE(o); break;
        default: v = bin.readInt8(o);
      }
      sortie[i * composantes + k] = v;
    }
  }
  return { donnees: sortie, composantes };
}

/**
 * Positions des sommets RÉFÉRENCÉS, toutes primitives confondues.
 *
 * Référencés et non tous : un GLB produit par `_ecrire` garde l'intégralité du
 * tampon de sommets alors que sa liste de triangles n'en désigne qu'une part.
 * Mesurer sur tous donnerait la boîte de la plante entière là où on veut celle
 * du pot — constaté, boîte de 0,921 au lieu de 0,318.
 */
export function lireMaillage(chemin: string, maxSommets = 4_000_000): Maillage {
  const d = readFileSync(chemin);
  if (d.length < 12 || d.readUInt32LE(0) !== MAGIC) throw new Error('pas un GLB');

  let off = 12;
  let meta: Record<string, unknown> | null = null;
  let bin: Buffer = Buffer.alloc(0);
  while (off + 8 <= d.length) {
    const lg = d.readUInt32LE(off);
    const typ = d.readUInt32LE(off + 4);
    const bloc = d.subarray(off + 8, off + 8 + lg);
    if (typ === JSON_CHUNK) meta = JSON.parse(bloc.toString('utf8'));
    else if (typ === BIN_CHUNK) bin = bloc;
    off += 8 + lg;
  }
  if (!meta) throw new Error('GLB sans bloc JSON');

  const sorties: number[] = [];
  let triangles = 0;

  for (const m of (meta.meshes ?? []) as Array<Record<string, unknown>>) {
    for (const p of (m.primitives ?? []) as Array<Record<string, unknown>>) {
      const attrs = (p.attributes ?? {}) as Record<string, number>;
      if (attrs.POSITION === undefined) continue;
      const pos = lireAccesseur(meta, bin, attrs.POSITION);

      let utilises: Set<number> | null = null;
      if (p.indices !== undefined) {
        const idx = lireAccesseur(meta, bin, p.indices as number);
        triangles += Math.floor(idx.donnees.length / 3);
        utilises = new Set<number>();
        // Boucle indexée et non `for…of` : la cible TypeScript du projet est
        // es5, qui n'itère pas les tableaux typés.
        for (let k = 0; k < idx.donnees.length; k += 1) utilises.add(idx.donnees[k]);
      } else {
        triangles += Math.floor(pos.donnees.length / pos.composantes / 3);
      }

      const total = pos.donnees.length / pos.composantes;
      for (let i = 0; i < total; i += 1) {
        if (utilises && !utilises.has(i)) continue;
        sorties.push(pos.donnees[i * pos.composantes],
                     pos.donnees[i * pos.composantes + 1],
                     pos.donnees[i * pos.composantes + 2]);
        if (sorties.length / 3 > maxSommets) throw new Error('maillage trop lourd');
      }
    }
  }

  if (sorties.length === 0) throw new Error('aucune position');
  return { positions: Float32Array.from(sorties), triangles };
}
