// app.js — Plant3DGenerator web UI.
// Layout : 3 tabs (plants / pots / composer) qui ne sont QUE de la
// bascule DOM (display: none/block). La connexion SSE et la map des
// job-cards persistent à travers les changements d'onglet, donc les
// jobs en cours continuent à tourner et leurs cards restent dans le
// pipeline en bas.

const plantListEl = document.getElementById("plant-list");
const potListEl = document.getElementById("pot-list");
const jobsEl = document.getElementById("jobs");
const template = document.getElementById("job-card-template");

const cardRefs = new Map(); // job_id -> DOM element
const plantsCache = [];     // { common, latin, hint, height_m, habit }
const potsCache = [];       // { pot_id, display_name, style, top_diameter_cm, height_cm }

// -----------------------------------------------------------------
// Tabs : pure CSS toggle, no state reset.
// -----------------------------------------------------------------

document.querySelectorAll("#tabs .tab").forEach((btn) => {
  btn.addEventListener("click", () => {
    const target = btn.dataset.tab;
    document.querySelectorAll("#tabs .tab").forEach((b) => b.classList.toggle("active", b === btn));
    document.querySelectorAll(".tab-panel").forEach((p) => {
      p.classList.toggle("active", p.dataset.tabPanel === target);
    });
  });
});

// -----------------------------------------------------------------
// Plants tab
// -----------------------------------------------------------------

async function loadPlants() {
  const res = await fetch("/api/input");
  const plants = await res.json();
  plantsCache.length = 0;
  plantsCache.push(...plants);

  plantListEl.innerHTML = "";
  for (const p of plants) {
    const chip = document.createElement("div");
    chip.className = "plant-chip";
    chip.innerHTML = `
      <span class="name"><strong>${p.common}</strong><em>${p.latin}</em>
        <small class="meta">${p.height_m ? p.height_m + " m" : ""} ${p.habit ? "· " + p.habit : ""}</small>
      </span>
      <button data-action="full">Generate</button>
      <button data-action="preview">Preview only</button>
    `;
    chip.querySelector('[data-action="full"]').addEventListener("click", () => startPlantJob(p, false));
    chip.querySelector('[data-action="preview"]').addEventListener("click", () => startPlantJob(p, true));
    plantListEl.appendChild(chip);
  }

  refreshComposerSelects();
}

document.getElementById("generate-all-plants").addEventListener("click", async () => {
  const btn = document.getElementById("generate-all-plants");
  btn.disabled = true;
  btn.textContent = "⏳ Queuing...";
  try {
    const res = await fetch("/api/generate-all", { method: "POST" });
    if (!res.ok) {
      alert("Generate All failed: " + (await res.text()));
      return;
    }
    const data = await res.json();
    btn.textContent = `✓ ${data.enqueued} queued, ${data.skipped_done} skipped`;
    setTimeout(() => {
      btn.textContent = "▶ Generate All plants";
      btn.disabled = false;
    }, 4000);
  } catch (e) {
    alert("Network error: " + e);
    btn.textContent = "▶ Generate All plants";
    btn.disabled = false;
  }
});

async function startPlantJob(plant, previewOnly) {
  const res = await fetch("/api/generate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...plant, preview_only: previewOnly }),
  });
  if (!res.ok) {
    const text = await res.text();
    alert("Failed: " + text);
  }
}

// -----------------------------------------------------------------
// Pots tab
// -----------------------------------------------------------------

async function loadPots() {
  const res = await fetch("/api/pots");
  const pots = await res.json();
  potsCache.length = 0;
  potsCache.push(...pots);

  potListEl.innerHTML = "";
  for (const p of pots) {
    const chip = document.createElement("div");
    chip.className = "plant-chip pot-chip";
    chip.innerHTML = `
      <span class="name"><strong>${p.display_name}</strong><em>${p.pot_id}</em>
        <small class="meta">⌀ ${p.top_diameter_cm} cm · h ${p.height_cm} cm</small>
      </span>
      <button data-action="full">Generate</button>
      <button data-action="preview">Preview only</button>
    `;
    chip.querySelector('[data-action="full"]').addEventListener("click", () => startPotJob(p, false));
    chip.querySelector('[data-action="preview"]').addEventListener("click", () => startPotJob(p, true));
    potListEl.appendChild(chip);
  }

  refreshComposerSelects();
}

document.getElementById("generate-all-pots").addEventListener("click", async () => {
  // No /api/generate-all-pots batch endpoint yet — enqueue one by one.
  const btn = document.getElementById("generate-all-pots");
  btn.disabled = true;
  btn.textContent = "⏳ Queuing...";
  let queued = 0;
  for (const p of potsCache) {
    try {
      await startPotJob(p, false);
      queued++;
    } catch (_) { /* swallow, server logs it */ }
  }
  btn.textContent = `✓ ${queued} queued`;
  setTimeout(() => {
    btn.textContent = "▶ Generate All pots";
    btn.disabled = false;
  }, 4000);
});

async function startPotJob(pot, previewOnly) {
  const res = await fetch("/api/generate-pot", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...pot, preview_only: previewOnly }),
  });
  if (!res.ok) {
    const text = await res.text();
    alert("Pot generation failed: " + text);
  }
}

// -----------------------------------------------------------------
// Composer tab (Plante + Pot) — side-by-side preview only
// -----------------------------------------------------------------

function refreshComposerSelects() {
  const plantSel = document.getElementById("composer-plant");
  const potSel = document.getElementById("composer-pot");
  if (!plantSel || !potSel) return;

  // Preserve current selection across refresh.
  const prevPlant = plantSel.value;
  const prevPot = potSel.value;

  plantSel.innerHTML = '<option value="">— sélectionner —</option>';
  for (const p of plantsCache) {
    const opt = document.createElement("option");
    opt.value = `${capitalizeLatin(p.latin)}.usdz`;   // matches safe_filename
    opt.textContent = `${p.common} · ${p.latin}`;
    plantSel.appendChild(opt);
  }
  if (prevPlant) plantSel.value = prevPlant;

  potSel.innerHTML = '<option value="">— sélectionner —</option>';
  for (const p of potsCache) {
    const opt = document.createElement("option");
    opt.value = `pot_${p.pot_id.toLowerCase().replace(/[-]/g, "_")}.usdz`;
    opt.textContent = `${p.display_name} (⌀ ${p.top_diameter_cm} cm)`;
    potSel.appendChild(opt);
  }
  if (prevPot) potSel.value = prevPot;
}

function capitalizeLatin(latin) {
  // Mirror Python's safe_filename: "monstera deliciosa" → "Monstera_Deliciosa"
  return latin.trim().split(/\s+/).map((p) => p.charAt(0).toUpperCase() + p.slice(1).toLowerCase()).join("_");
}

function renderComposerSide(viewerEl, filename) {
  viewerEl.innerHTML = "";
  if (!filename) return;
  const mv = document.createElement("model-viewer");
  mv.setAttribute("camera-controls", "");
  mv.setAttribute("auto-rotate", "");
  mv.setAttribute("shadow-intensity", "1");
  mv.setAttribute("exposure", "1.0");
  // For composer we prefer GLB if available (lighter and animatable in
  // model-viewer). Fallback to USDZ.
  const glbName = filename.replace(/\.usdz$/i, ".glb");
  mv.setAttribute("src", "/output/" + glbName + "?t=" + Date.now());
  mv.setAttribute("ios-src", "/output/" + filename);
  mv.style.width = "100%";
  mv.style.height = "100%";
  viewerEl.appendChild(mv);
}

document.getElementById("composer-plant").addEventListener("change", (e) => {
  renderComposerSide(document.getElementById("composer-plant-viewer"), e.target.value);
});
document.getElementById("composer-pot").addEventListener("change", (e) => {
  renderComposerSide(document.getElementById("composer-pot-viewer"), e.target.value);
});

// -----------------------------------------------------------------
// Reload (re-fetch both lists)
// -----------------------------------------------------------------

document.getElementById("reload-input").addEventListener("click", () => {
  loadPlants();
  loadPots();
});

// -----------------------------------------------------------------
// Pipeline cards rendering + SSE
// -----------------------------------------------------------------

function ensureCard(job) {
  let card = cardRefs.get(job.job_id);
  if (!card) {
    const empty = jobsEl.querySelector(".empty");
    if (empty) empty.remove();
    card = template.content.firstElementChild.cloneNode(true);
    // Tag the card so we could later filter by type from CSS if needed.
    card.classList.add(job.job_id.startsWith("pot_") ? "kind-pot" : "kind-plant");
    cardRefs.set(job.job_id, card);
    jobsEl.prepend(card);
  }
  return card;
}

function renderJob(job) {
  const card = ensureCard(job);
  card.querySelector(".job-title").textContent = job.common;
  card.querySelector(".job-latin").textContent = job.latin;
  card.querySelector(".job-prompt").textContent = job.prompt;
  card.querySelector(".job-texture-prompt").textContent = job.texture_prompt;

  updateStage(
    card.querySelector(".stage-preview"),
    job.stages.preview,
    job.stages.preview.glb_file,
  );
  updateStage(
    card.querySelector(".stage-refine"),
    job.stages.refine,
    job.final_glb,
  );

  const links = card.querySelector(".download-links");
  links.innerHTML = "";
  if (job.final_glb) {
    links.appendChild(makeLink("GLB", "/output/" + job.final_glb, job.final_glb));
  }
  if (job.final_usdz) {
    links.appendChild(makeLink("USDZ", "/output/" + job.final_usdz, job.final_usdz));
  }
}

function makeLink(label, href, fname) {
  const a = document.createElement("a");
  a.href = href;
  a.textContent = label;
  a.download = fname;
  return a;
}

function updateStage(stageEl, stage, glbFile) {
  stageEl.classList.remove("running", "done", "failed");
  if (stage.status === "running") stageEl.classList.add("running");
  if (stage.status === "done") stageEl.classList.add("done");
  if (stage.status === "failed") stageEl.classList.add("failed");

  const parts = [stage.status];
  if (stage.progress) parts.push(`${stage.progress}%`);
  if (stage.task_id) parts.push(stage.task_id.slice(0, 8));
  if (stage.error) parts.push(stage.error);
  stageEl.querySelector(".stage-status").textContent = parts.join(" — ");
  stageEl.querySelector(".bar").style.width = (stage.progress || 0) + "%";

  const viewer = stageEl.querySelector(".stage-viewer");
  if (glbFile) {
    let mv = viewer.querySelector("model-viewer");
    if (!mv) {
      mv = document.createElement("model-viewer");
      mv.setAttribute("camera-controls", "");
      mv.setAttribute("auto-rotate", "");
      mv.setAttribute("shadow-intensity", "1");
      mv.setAttribute("exposure", "1.0");
      mv.setAttribute("interaction-prompt", "none");
      viewer.innerHTML = "";
      viewer.appendChild(mv);
    }
    const src = "/output/" + glbFile + "?t=" + Date.now();
    if (!mv.getAttribute("src") || !mv.getAttribute("src").startsWith("/output/" + glbFile)) {
      mv.setAttribute("src", src);
    }
  }
}

function connectSSE() {
  const es = new EventSource("/api/stream");
  es.addEventListener("snapshot", (ev) => {
    const data = JSON.parse(ev.data);
    for (const job of data) renderJob(job);
  });
  es.addEventListener("update", (ev) => {
    const job = JSON.parse(ev.data);
    renderJob(job);
  });
  es.onerror = () => {
    // EventSource auto-reconnects
  };
}

// Initial bootstrap.
loadPlants();
loadPots();
connectSSE();
