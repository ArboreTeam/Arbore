'use client';

import { useEffect, useRef, useState } from 'react';

// Visionneuse 3D d'un candidat de coupe.
//
// Les aperçus rendus par l'ouvrier répondent au coup d'œil — coupe trop haute,
// trop basse. Celle-ci répond au doute : tourner autour montre si la coupe a
// emporté une feuille basse, ce qu'une vue de face cache.
//
// three.js est chargé à la DEMANDE et non à l'import du module : la page de
// revue doit s'afficher même si on n'ouvre jamais la 3D, et le moteur pèse
// plus lourd que tout le reste de l'atelier réuni.

type Props = { url: string; octets: number | null };

function poids(octets: number | null): string {
  if (!octets) return 'taille inconnue';
  return `${(octets / 1e6).toFixed(0)} Mo`;
}

export default function Visionneuse({ url, octets }: Props) {
  const [ouvert, setOuvert] = useState(false);
  const [progression, setProgression] = useState<number | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);
  const hote = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ouvert || !hote.current) return;
    const conteneur = hote.current;
    let vivant = true;
    // Nettoyage renseigné au fur et à mesure du montage : si le composant est
    // démonté PENDANT le chargement du GLB — ce qui dure des secondes sur
    // 65 Mo — il faut quand même libérer le contexte WebGL, sinon quelques
    // allers-retours suffisent à épuiser les contextes du navigateur.
    let demonter = () => {};

    (async () => {
      try {
        const THREE = await import('three');
        const { GLTFLoader } = await import('three/examples/jsm/loaders/GLTFLoader.js');
        const { OrbitControls } = await import('three/examples/jsm/controls/OrbitControls.js');
        if (!vivant) return;

        const l = conteneur.clientWidth;
        const h = Math.round(l * 0.75);
        const scene = new THREE.Scene();
        scene.background = new THREE.Color(0xf7f6f3);
        const camera = new THREE.PerspectiveCamera(35, l / h, 0.01, 100);
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

        new GLTFLoader().load(
          url,
          (gltf) => {
            if (!vivant) return;
            const boite = new THREE.Box3().setFromObject(gltf.scene);
            const taille = boite.getSize(new THREE.Vector3());
            const centre = boite.getCenter(new THREE.Vector3());
            gltf.scene.position.sub(centre);
            scene.add(gltf.scene);

            const rayon = Math.max(taille.x, taille.y, taille.z) || 1;
            camera.position.set(0, rayon * 0.25, rayon * 2.2);
            camera.near = rayon / 100;
            camera.far = rayon * 100;
            camera.updateProjectionMatrix();
            controles.target.set(0, 0, 0);
            setProgression(null);
            boucle();
          },
          (e) => {
            if (vivant && e.total) setProgression(Math.round((e.loaded / e.total) * 100));
          },
          () => vivant && setErreur('chargement impossible'),
        );
      } catch {
        if (vivant) setErreur('moteur 3D indisponible');
      }
    })();

    return () => {
      vivant = false;
      demonter();
    };
  }, [ouvert, url]);

  if (!ouvert) {
    return (
      <button
        type="button"
        onClick={() => setOuvert(true)}
        className="mt-3 w-full rounded-lg border border-[#DDD8CF] px-3 py-2 text-sm text-[#6E746B] hover:border-[#234632] hover:text-[#234632]"
      >
        Examiner en 3D · {poids(octets)}
      </button>
    );
  }

  return (
    <div className="mt-3">
      <div ref={hote} className="overflow-hidden rounded-lg border border-[#DDD8CF] bg-[#F7F6F3]" />
      <div className="mt-2 flex items-center justify-between text-xs text-[#6E746B]">
        <span>
          {erreur
            ? erreur
            : progression !== null
              ? `chargement ${progression} %`
              : 'glisser pour tourner, molette pour zoomer'}
        </span>
        <button type="button" onClick={() => setOuvert(false)} className="underline">
          fermer
        </button>
      </div>
    </div>
  );
}
