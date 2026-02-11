const DATA_PATHS = {
  system: "./data/system-health.json",
  pipeline: "./data/skyhawk-pipeline.json",
  ventures: "./data/ventures.json",
  activity: "./data/activity-feed.json",
  progress: "./data/implementation-progress.json",
  finance: "./data/finance.json",
};

const el = (id) => document.getElementById(id);

const money = (value) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(
    Number(value || 0)
  );

function setStatusPill(node, statusText) {
  node.textContent = statusText;
  node.classList.remove("status-ok", "status-degraded", "status-unavailable", "status-pending");
  if (statusText === "ok" || statusText === "online" || statusText === "complete") node.classList.add("status-ok");
  if (statusText === "degraded" || statusText === "in_progress") node.classList.add("status-degraded");
  if (statusText === "unavailable" || statusText === "pending") node.classList.add("status-unavailable");
}

async function fetchJson(path) {
  const res = await fetch(path, { cache: "no-store" });
  if (!res.ok) throw new Error(`Failed to load ${path}`);
  return res.json();
}

function renderSystem(data) {
  setStatusPill(el("openclawStatus"), data.openclaw?.status || "unknown");
  el("openclawMode").textContent = `${data.openclaw?.mode || "-"} @ ${data.openclaw?.bind || "-"}`;
  el("primaryModel").textContent = data.model_routing?.primary || "-";

  const spend = data.token_spend || {};
  el("tokenSpend").textContent = `${(spend.total_tokens_sum || 0).toLocaleString()} tokens`;
  el("capacityRisk").textContent = `Max recent session usage: ${spend.max_percent_used || 0}%`;

  const routing = [
    `Primary: ${data.model_routing?.primary || "-"}`,
    `Fallbacks: ${(data.model_routing?.fallbacks || []).join(", ") || "none"}`,
    `Heartbeat: ${data.model_routing?.heartbeat_model || "-"}`,
    `Subagent: ${data.model_routing?.subagent_model || "-"}`,
  ];
  el("routingList").innerHTML = routing.map((line) => `<li>${line}</li>`).join("");
}

function renderPipeline(data) {
  setStatusPill(el("pipelineStatus"), data.status || "unknown");
  const rows = data.opportunities || [];
  el("pipelineRows").innerHTML = rows.length
    ? rows
        .map(
          (r) => `
      <tr>
        <td>${r.name}</td>
        <td>${r.stage || "-"}</td>
        <td>${money(r.amount || 0)}</td>
        <td>${r.close_date || "-"}</td>
      </tr>`
        )
        .join("")
    : `<tr><td colspan="4">No live opportunities available (${data.reason || "source unavailable"}).</td></tr>`;
}

function renderVentures(data) {
  const ventures = data.ventures || [];
  el("ventureCards").innerHTML = ventures
    .map(
      (v) => `
      <article class="venture">
        <div class="card-head">
          <h3>${v.name}</h3>
          <span class="pill">P${v.priority_tier}</span>
        </div>
        <p><strong>Stage:</strong> ${v.stage}</p>
        <p><strong>90-Day Goal:</strong> ${v.ninety_day_goal}</p>
        <p><strong>Current Priority:</strong> ${v.current_priority}</p>
      </article>
    `
    )
    .join("");
}

function renderActivity(data) {
  const items = data.events || [];
  el("activityList").innerHTML = items
    .map((item) => `<li><strong>${item.title}</strong><p>${item.detail}</p><small>${item.date} · ${item.source}</small></li>`)
    .join("");
}

function renderProgress(data) {
  const items = data.items || [];
  el("progressList").innerHTML = items
    .map(
      (item) =>
        `<li><div class="card-head"><strong>${item.name}</strong><span class="pill ${item.status === "complete" ? "status-ok" : item.status === "in_progress" ? "status-degraded" : "status-pending"}">${item.status}</span></div><p>${item.detail}</p></li>`
    )
    .join("");
}

function renderFinance(data) {
  setStatusPill(el("financeStatus"), data.status || "unknown");
  el("budgetCount").textContent = (data.budgets || []).length.toString();
  el("accountCount").textContent = (data.insights?.total_accounts || 0).toString();
  el("netWorth").textContent = money(data.insights?.net_worth || 0);

  el("financeReason").textContent =
    data.status === "ok" ? "Live YNAB snapshot loaded." : `Finance data degraded: ${data.reason || "unknown"}`;

  const categories = data.insights?.top_categories || [];
  el("categoryList").innerHTML = categories.length
    ? categories
        .map(
          (c) =>
            `<li><div class="card-head"><strong>${c.name}</strong><span>${money(c.activity)}</span></div><small>Budgeted ${money(
              c.budgeted
            )} · Balance ${money(c.balance)}</small></li>`
        )
        .join("")
    : `<li>No category data available.</li>`;
}

function setupTabs() {
  const tabs = [...document.querySelectorAll(".tab")];
  const panels = [...document.querySelectorAll(".tab-panel")];

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => t.classList.remove("is-active"));
      panels.forEach((p) => p.classList.remove("is-active"));
      tab.classList.add("is-active");
      document.querySelector(`[data-panel=\"${tab.dataset.tab}\"]`)?.classList.add("is-active");
    });
  });
}

async function loadDashboard() {
  try {
    const [system, pipeline, ventures, activity, progress, finance] = await Promise.all([
      fetchJson(DATA_PATHS.system),
      fetchJson(DATA_PATHS.pipeline),
      fetchJson(DATA_PATHS.ventures),
      fetchJson(DATA_PATHS.activity),
      fetchJson(DATA_PATHS.progress),
      fetchJson(DATA_PATHS.finance),
    ]);

    renderSystem(system);
    renderPipeline(pipeline);
    renderVentures(ventures);
    renderActivity(activity);
    renderProgress(progress);
    renderFinance(finance);

    const generated = [
      system.generated_at,
      pipeline.generated_at,
      ventures.generated_at,
      activity.generated_at,
      progress.generated_at,
      finance.generated_at,
    ]
      .filter(Boolean)
      .sort()
      .reverse()[0];

    el("generatedAt").textContent = generated ? `Data: ${new Date(generated).toLocaleString()}` : "Data: unavailable";
  } catch (error) {
    el("generatedAt").textContent = "Failed to load dashboard data";
    console.error(error);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  setupTabs();
  loadDashboard();
  el("refreshBtn").addEventListener("click", () => window.location.reload());
});
