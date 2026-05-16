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
  // the pot's rim (top of pot bbox). If no pot loaded, plant sits on the
  // ground disc directly.
  function placePlantOnRim() {
    rimY = 0;
    if (potObj) {
      potObj.position.set(0, 0, 0);
      // Force matrices to be up to date before bbox computation.
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
  plantSelect.addEventListener("change", (e) => replace("plant", e.target.value));
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
