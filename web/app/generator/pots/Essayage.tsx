'use client';

import { useEffect, useRef, useState } from 'react';

// Essayage d'un pot sous une plante.
//
// Toute la fonction tient dans une similitude, et les deux mesures qui la
// rendent possible ont été prises ailleurs : le SOCLE de la plante dit où son
// pot commençait et de quel rayon ; le REBORD du pot dit où est sa lèvre et de
// quel rayon. Poser l'un sous l'autre, c'est mettre le pot à l'échelle
// `socle.rayon / rebord.rayon`, le centrer, et aligner sa lèvre sur `socle.y`.
//
// Rien n'est réglé à la main, et c'est le but : une bibliothèque de cent pots
// ne se règle pas plante par plante.

export type Socle = { x: number; z: number; y: number; rayon: number; hauteurModele: number };
export type Pot = {
  fichier: string; rayon: number; y: number; x: number; z: number;
  hauteur: number; triangles: number; octets: number;
};
export type Plante = { plante: string; fichier: string; socle: Socle; verdict?: string };

type Props = { plante: Plante | null; pot: Pot | null };

export default function Essayage({ plante, pot }: Props) {
  const hote = useRef<HTMLDivElement>(null);
  const [etat, setEtat] = useState<string | null>(null);

  useEffect(() => {
    if (!hote.current) return;
    const conteneur = hote.current;
    let vivant = true;
    let demonter = () => {};

    (async () => {
      try {
        const THREE = await import('three');
        const { GLTFLoader } = await import('three/examples/jsm/loaders/GLTFLoader.js');
        const { OrbitControls } = await import('three/examples/jsm/controls/OrbitControls.js');
        if (!vivant) return;

        const l = conteneur.clientWidth || 640;
        const h = Math.round(l * 0.72);
        const scene = new THREE.Scene();
        scene.background = new THREE.Color(0xf7f6f3);
        const camera = new THREE.PerspectiveCamera(35, l / h, 0.001, 1000);
        const rendu = new THREE.WebGLRenderer({ antialias: true });
        rendu.setSize(l, h);
        rendu.setPixelRatio(Math.min(window.devicePixelRatio, 2));
        conteneur.replaceChildren(rendu.domElement);

        scene.add(new THREE.AmbientLight(0xffffff, 2.2));
        const jour = new THREE.DirectionalLight(0xffffff, 1.6);
        jour.position.set(2, 4, 3);
        scene.add(jour);

        const controles = new OrbitControls(camera, rendu.domElement);
        controles.enableDamping = true;

        let image = 0;
        const boucle = () => {
          if (!vivant) return;
          image = requestAnimationFrame(boucle);
          controles.update();
          rendu.render(scene, camera);
        };
        demonter = () => {
          cancelAnimationFrame(image);
          controles.dispose();
          rendu.dispose();
          rendu.forceContextLoss();
          conteneur.replaceChildren();
        };
        boucle();

        const loader = new GLTFLoader();
        const charger = (url: string) =>
          new Promise<import('three').Group>((ok, ko) =>
            loader.load(url, (g) => ok(g.scene), undefined, ko));

        const aCharger: string[] = [];
        if (plante) aCharger.push(`plante ${plante.plante}`);
        if (pot) aCharger.push(`pot ${pot.fichier}`);
        setEtat(aCharger.length ? `chargement · ${aCharger.join(' et ')}` : null);

        if (plante) {
          const g = await charger(
            `/api/generator/artefacts/${encodeURIComponent(plante.plante)}/${encodeURIComponent(plante.fichier)}`);
          if (!vivant) return;
          scene.add(g);
        }

        if (pot && plante) {
          const g = await charger(`/api/generator/pots/${encodeURIComponent(pot.fichier)}`);
          if (!vivant) return;
          // La similitude. Le facteur vient des deux rayons ; sans lui un pot
          // modélisé en centimètres passerait sous une plante en mètres.
          const k = plante.socle.rayon / pot.rayon;
          g.scale.setScalar(k);
          // Après mise à l'échelle, la lèvre du pot est à `pot.y * k` et son axe
          // à (`pot.x * k`, `pot.z * k`). On la déplace sur le socle.
          g.position.set(
            plante.socle.x - pot.x * k,
            plante.socle.y - pot.y * k,
            plante.socle.z - pot.z * k,
          );
          scene.add(g);
        } else if (pot) {
          const g = await charger(`/api/generator/pots/${encodeURIComponent(pot.fichier)}`);
          if (!vivant) return;
          scene.add(g);
        }

        if (!vivant) return;
        const boite = new THREE.Box3().setFromObject(scene);
        if (!boite.isEmpty()) {
          const taille = boite.getSize(new THREE.Vector3());
          const centre = boite.getCenter(new THREE.Vector3());
          const rayon = Math.max(taille.x, taille.y, taille.z) || 1;
          camera.position.set(centre.x, centre.y + rayon * 0.2, centre.z + rayon * 2.1);
          camera.near = rayon / 200;
          camera.far = rayon * 200;
          camera.updateProjectionMatrix();
          controles.target.copy(centre);
        }
        setEtat(null);
      } catch {
        if (vivant) setEtat('chargement impossible');
      }
    })();

    return () => {
      vivant = false;
      demonter();
    };
  }, [plante, pot]);

  const facteur = plante && pot ? plante.socle.rayon / pot.rayon : null;

  return (
    <div>
      <div ref={hote} className="overflow-hidden rounded-xl border border-[#DDD8CF] bg-[#F7F6F3]" />
      <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs text-[#6E746B]">
        <span>
          {etat
            ?? (plante && pot
              ? `pot mis à l'échelle ×${facteur!.toFixed(2)}, lèvre posée à y = ${plante.socle.y.toFixed(3)}`
              : plante
                ? 'choisis un pot pour l’essayer'
                : pot
                  ? 'choisis une plante pour poser ce pot'
                  : 'choisis une plante et un pot')}
        </span>
        <span>glisser pour tourner, molette pour zoomer</span>
      </div>
    </div>
  );
}
