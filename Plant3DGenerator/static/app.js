const plantListEl = document.getElementById("plant-list");
const jobsEl = document.getElementById("jobs");
const template = document.getElementById("job-card-template");

const cardRefs = new Map(); // job_id -> DOM element

async function loadInput() {
  const res = await fetch("/api/input");
  const plants = await res.json();
  plantListEl.innerHTML = "";
  for (const p of plants) {
    const chip = document.createElement("div");
    chip.className = "plant-chip";
    chip.innerHTML = `
      <span class="name"><strong>${p.common}</strong><em>${p.latin}</em></span>
      <button data-action="full">Generate</button>
      <button data-action="preview">Preview only</button>
    `;
    chip.querySelector('[data-action="full"]').addEventListener("click", () => startJob(p, false));
    chip.querySelector('[data-action="preview"]').addEventListener("click", () => startJob(p, true));
    plantListEl.appendChild(chip);
  }
}

document.getElementById("reload-input").addEventListener("click", loadInput);

async function startJob(plant, previewOnly) {
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

function ensureCard(job) {
  let card = cardRefs.get(job.job_id);
  if (!card) {
    const empty = jobsEl.querySelector(".empty");
    if (empty) empty.remove();
    card = template.content.firstElementChild.cloneNode(true);
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

loadInput();
connectSSE();
