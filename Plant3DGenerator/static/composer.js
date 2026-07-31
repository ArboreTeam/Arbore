// composer.js — Plante + Pot 3D composer (tab "Plante + Pot")
//
// three.js scene with both GLBs loaded as children, plant translated so
// its Y=0 (soil line, cf "ligne de terre" convention) lands on the pot's
// rim Y (= pot.bbox.max.y). This is the same composition rule iOS will
// apply via `PlantPotComposer` (cf issue #185, solution C will add the
// habit-aware scaling on top).

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";

const containerEl = document.getElementById("composer-viewer");
const plantSelect = document.getElementById("composer-plant");
const potSelect = document.getElementById("composer-pot");
const resetBtn = document.getElementById("composer-reset");
const statusEl = document.getElementById("composer-status");

if (!containerEl || !plantSelect || !potSelect) {
  // Defensive : the composer tab might not be rendered (markup change).
  console.warn("[composer] missing DOM — aborting init");
} else {
  initComposer();
}

function initComposer() {
  // ── Scene ─────────────────────────────────────────────────────
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x070707);

  // Ground plane disc to anchor visually where Y=0 is.
  const ground = new THREE.Mesh(
    new THREE.CircleGeometry(1.5, 64),
    new THREE.MeshStandardMaterial({ color: 0x141414, roughness: 1, metalness: 0 })
  );
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);

  // ── Camera ────────────────────────────────────────────────────
  const camera = new THREE.PerspectiveCamera(35, 1, 0.01, 100);
  camera.position.set(1.8, 1.4, 1.8);
  scene.add(camera);

  // ── Renderer ──────────────────────────────────────────────────
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  containerEl.appendChild(renderer.domElement);

  const updateSize = () => {
    const r = containerEl.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return;
    renderer.setSize(r.width, r.height, false);
    camera.aspect = r.width / r.height;
    camera.updateProjectionMatrix();
  };
  updateSize();
  new ResizeObserver(updateSize).observe(containerEl);

  // ── Lighting ──────────────────────────────────────────────────
  scene.add(new THREE.AmbientLight(0xffffff, 0.6));
  const key = new THREE.DirectionalLight(0xffffff, 1.0);
  key.position.set(3, 5, 4);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xffffff, 0.35);
  fill.position.set(-3, 3, -2);
  scene.add(fill);

  // ── Controls ──────────────────────────────────────────────────
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.target.set(0, 0.4, 0);
  controls.enableDamping = true;
  controls.update();

  // ── Models ────────────────────────────────────────────────────
  const loader = new GLTFLoader();
  let plantObj = null;
  let potObj = null;
  let rimY = 0;

  const setStatus = (msg, kind = "info") => {
    statusEl.textContent = msg || "";
    statusEl.className = `composer-status ${msg ? kind : ""}`;
  };

  const loadGLB = (url) =>
    new Promise((resolve, reject) => loader.load(url, resolve, undefined, reject));

  // Normalize the mesh's scale to its declared real-world dimension.
  // Meshy auto_size estimates from the prompt and is unreliable (×4 drift
  // observed between stone_grey and glossy_black). At runtime we measure
  // the bbox and apply a uniform scale so the declared dimension matches.
  //
  //   - plant : declared `height_m` → scale so bbox.height == height_m
  //   - pot   : declared `diameter_cm` → scale so max(bbox.x, bbox.z) == diameter
  //
  // If no declared value, leave the mesh as-is.
  function normalizeScale(obj, kind, declared) {
    obj.scale.set(1, 1, 1);
    obj.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(obj);
    const size = box.getSize(new THREE.Vector3());
    let scale = 1;
    if (kind === "plant" && declared.height_m > 0 && size.y > 1e-4) {
      scale = declared.height_m / size.y;
    } else if (kind === "pot" && declared.diameter_m > 0) {
      const horiz = Math.max(size.x, size.z);
      if (horiz > 1e-4) {
        scale = declared.diameter_m / horiz;
      }
    }
    obj.scale.setScalar(scale);
    obj.updateMatrixWorld(true);
  }

  // Read declared dimensions from the selected <option>'s dataset.
  function readDeclared(selectEl) {
    const opt = selectEl.selectedOptions[0];
    if (!opt) return { height_m: 0, diameter_m: 0 };
    const heightM = parseFloat(opt.dataset.heightM || "0");
    const diameterCm = parseFloat(opt.dataset.diameterCm || "0");
    return {
      height_m: isFinite(heightM) ? heightM : 0,
      diameter_m: isFinite(diameterCm) ? diameterCm / 100 : 0,
    };
  }

  // Replace the current plant or pot with a new GLB. `kind` is "plant" or "pot".
  async function replace(kind, filename) {
    const slot = kind === "plant" ? plantObj : potObj;
    if (slot) {
      scene.remove(slot);
      if (kind === "plant") plantObj = null;
      else potObj = null;
    }
    if (!filename) {
      placePlantOnRim();
      fit();
      return;
    }
    // We prefer the GLB over USDZ for three.js (lighter, animatable).
    const url = "/output/" + filename.replace(/\.usdz$/i, ".glb");
    setStatus(`Chargement ${kind} : ${filename}…`);
    try {
      const gltf = await loadGLB(url);
      const obj = gltf.scene;
      const declared = readDeclared(kind === "plant" ? plantSelect : potSelect);
      normalizeScale(obj, kind, declared);
      if (kind === "plant") {
        plantObj = obj;
      } else {
        potObj = obj;
      }
      scene.add(obj);
      placePlantOnRim();
      fit();
      setStatus("");
    } catch (e) {
      setStatus(`Échec chargement ${kind} (${url}) — vérifier que le GLB existe`, "error");
      console.warn("[composer] load failed", url, e);
    }
  }

  // Translate the plant so its Y=0 (soil line in our convention) sits at
  // the pot's rim (top of pot bbox, AFTER normalize-scale). If no pot
  // loaded, plant sits on the ground disc directly.
  function placePlantOnRim() {
    rimY = 0;
    if (potObj) {
      potObj.position.set(0, 0, 0);
      potObj.updateMatrixWorld(true);
      const box = new THREE.Box3().setFromObject(potObj);
      rimY = box.max.y;
    }
    if (plantObj) {
      plantObj.position.set(0, rimY, 0);
    }
  }

  // Fit camera so both objects + ground are framed.
  function fit() {
    const box = new THREE.Box3();
    if (potObj) box.expandByObject(potObj);
    if (plantObj) box.expandByObject(plantObj);
    if (box.isEmpty()) {
      controls.target.set(0, 0.4, 0);
      controls.update();
      return;
    }
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const maxDim = Math.max(size.x, size.y, size.z, 0.1);
    // Camera at 1.5× the diagonal from center, slightly above.
    camera.position.set(
      center.x + maxDim * 1.6,
      center.y + maxDim * 0.5,
      center.z + maxDim * 1.6,
    );
    controls.target.copy(center);
    controls.update();
  }

  // ── Event wiring ──────────────────────────────────────────────
  plantSelect.addEventListener("change", async (e) => {
    await replace("plant", e.target.value);
    // Auto-pick le pot par défaut (col 6 input.txt) si l'user n'a pas
    // déjà sélectionné un pot spécifiquement. Le but : choisir une
    // plante seule te donne un aperçu "par défaut" plausible sans
    // devoir aussi cliquer dans le pot dropdown.
    const opt = plantSelect.selectedOptions[0];
    const defaultPotFilename = opt?.dataset?.defaultPotFilename;
    if (defaultPotFilename && !potSelect.value) {
      // Cherche l'option correspondante dans le dropdown pots.
      const target = Array.from(potSelect.options).find((o) => o.value === defaultPotFilename);
      if (target) {
        potSelect.value = defaultPotFilename;
        await replace("pot", defaultPotFilename);
      }
    }
  });
  potSelect.addEventListener("change", (e) => replace("pot", e.target.value));
  if (resetBtn) {
    resetBtn.addEventListener("click", fit);
  }

  // ── Render loop ───────────────────────────────────────────────
  function animate() {
    requestAnimationFrame(animate);
    controls.update();
    renderer.render(scene, camera);
  }
  animate();
}
