// GateView Windows/Linux shell UI. Plain ES modules, no bundler — Tauri's
// withGlobalTauri exposes window.__TAURI__. Mirrors the macOS dashboard:
// left column = clock/weather/stats, right glass panel = theme.widgetOrder.

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const L = {
  id: {
    goodMorning: "Selamat Pagi", goodAfternoon: "Selamat Siang",
    goodEvening: "Selamat Malam", daysLeft: (n) => `${n} hari lagi`,
    today: "Hari ini!", tomorrow: "Besok", iqomahIn: "Iqomah dalam",
    adzanIn: "adzan dalam", ongoing: "sedang berjamaah", notes: "Catatan",
    notesHint: "Klik untuk menulis…", reminders: "Reminders", countdown: "Hitung Mundur",
    nowPlaying: "Now Playing", prayerTimes: "Jadwal Sholat", addNotes: "Tambah di theme.json",
  },
  en: {
    goodMorning: "Good Morning", goodAfternoon: "Good Afternoon",
    goodEvening: "Good Evening", daysLeft: (n) => `${n} days left`,
    today: "Today!", tomorrow: "Tomorrow", iqomahIn: "Iqomah in",
    adzanIn: "adzan in", ongoing: "in congregation", notes: "Notes",
    notesHint: "Click to write…", reminders: "Reminders", countdown: "Countdown",
    nowPlaying: "Now Playing", prayerTimes: "Prayer times", addNotes: "Add in theme.json",
  },
};
const WIDGET_NAMES = {
  prayer: ["Jadwal Sholat", "Prayer times"], agenda: ["Agenda", "Agenda"],
  nowPlaying: ["Now Playing", "Now Playing"], calendar: ["Calendar", "Calendar"],
  notes: ["Catatan", "Notes"], reminders: ["Reminders", "Reminders"],
  countdown: ["Hitung Mundur", "Countdown"], gallery: ["Gallery", "Gallery"],
};

let state = null;         // last Payload
let remindersOpen = false;
let notesOpen = false;
let notchOpen = false;
let dockWindows = [];
let hoveredHwnd = null;
let previewCache = new Map();
let previewHideTimer = null;

function lang() {
  const mode = state?.theme?.language ?? "auto";
  if (mode === "id" || mode === "en") return mode;
  return (navigator.language || "").toLowerCase().startsWith("id") ? "id" : "en";
}
// Most entries are plain strings; only a few (daysLeft) are functions of their arguments.
const t = (key, ...args) => {
  const v = L[lang()][key];
  return typeof v === "function" ? v(...args) : v;
};

// MARK: Clock & date (ticks locally every second, like the macOS TimelineView)

const DAYS_ID = ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"];
const MONTHS_ID = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli",
  "Agustus", "September", "Oktober", "November", "Desember"];
const DAYS_EN = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTHS_EN = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"];

function tickClock() {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const ss = String(now.getSeconds()).padStart(2, "0");
  document.getElementById("clock").textContent = `${hh}:${mm}`;
  document.getElementById("seconds").textContent = ss;
  const isId = lang() === "id";
  const day = (isId ? DAYS_ID : DAYS_EN)[now.getDay()];
  const month = (isId ? MONTHS_ID : MONTHS_EN)[now.getMonth()];
  document.getElementById("date-line").textContent = `${day}, ${now.getDate()} ${month}`;
  const h = now.getHours();
  const name = state?.theme?.greetingName ?? "";
  const suffix = name ? `, ${name}` : "";
  const greeting =
    lang() === "id"
      ? `${h < 11 ? t("goodMorning") : h < 15 ? t("goodAfternoon") : t("goodEvening")}${suffix}`
      : `${h < 12 ? t("goodMorning") : h < 18 ? t("goodAfternoon") : t("goodEvening")}${suffix}`;
  document.getElementById("greeting").textContent = greeting;
  tickNowPlaying(now);
}
setInterval(tickClock, 1000);

// MARK: Rendering

function render() {
  if (!state) return;
  const theme = state.theme;
  document.documentElement.style.setProperty("--accent", theme.accent || "#ffc56b");
  const dash = document.getElementById("dashboard");
  dash.style.flexDirection = theme.panelSide === "left" ? "row-reverse" : "row";
  dash.classList.toggle("with-dock", theme.showDock !== false);

  // Weather chip
  const chip = document.getElementById("weather-chip");
  if (state.weather && theme.showWeather) {
    chip.classList.remove("hidden");
    document.getElementById("weather-temp").textContent = `${state.weather.temperature}°`;
    document.getElementById("weather-label").textContent = state.weather.label;
  } else {
    chip.classList.add("hidden");
  }

  renderNotch();
  renderDock();
  renderPanel();
  pushHitRegions();
}

function renderNotch() {
  const el = document.getElementById("notch");
  if (!el) return;
  const enabled = state?.theme?.showNotch !== false;
  el.classList.toggle("hidden", !enabled);
  el.classList.toggle("expanded", enabled && notchOpen);
  if (!enabled) return;

  const ph = state?.phase;
  const np = state?.now_playing;
  const w = state?.weather;
  const stats = state?.stats;

  if (!notchOpen) {
    const leftHtml = ph
      ? `<span class="notch-label">${esc(ph.name)}</span><span class="notch-accent">${esc(ph.remaining || t("ongoing"))}</span>`
      : `<span class="notch-label">${esc(state?.theme?.city ?? "GateView")}</span>`;
    let rightHtml = "";
    if (np && np.is_playing) {
      rightHtml = `<span class="notch-eq"><span></span><span></span><span></span></span><span class="notch-label">${esc(np.title)}</span>`;
    } else if (w) {
      rightHtml = `<span class="notch-accent">${w.temperature}°</span><span class="notch-label">${esc(w.label)}</span>`;
    } else if (stats) {
      rightHtml = `<span class="notch-label">CPU</span><span class="notch-accent">${Math.round(stats.cpu)}%</span>`;
    }
    el.innerHTML = `
      <div class="notch-compact">
        <div class="notch-side left">${leftHtml}</div>
        <span class="notch-cam" aria-hidden="true"></span>
        <div class="notch-side right">${rightHtml}</div>
      </div>`;
    return;
  }

  const prayers = state?.prayers ?? [];
  const prayerGrid = prayers.map((p) => {
    const active = ph?.name === p.name ? " active" : "";
    return `<div class="item${active}"><span>${esc(p.name)}</span><b>${esc(p.time)}</b></div>`;
  }).join("");

  const npCard = np
    ? `<div class="notch-card">
        <div class="row"><span class="np-title">${esc(np.title)}</span><span class="notch-pill">${esc(np.source || t("nowPlaying"))}</span></div>
        <div class="np-artist">${esc(np.artist)}</div>
        ${np.duration > 0 ? `<div class="np-bar"><div class="np-fill" id="notch-np-fill" style="width:0%"></div></div>
        <div class="np-times"><span id="notch-np-pos">0:00</span><span id="notch-np-dur">0:00</span></div>` : ""}
      </div>`
    : "";

  const metaParts = [];
  if (w) metaParts.push(`${w.temperature}° ${esc(w.label)}`);
  if (stats) metaParts.push(`CPU ${Math.round(stats.cpu)}% · RAM ${Math.round(stats.ram_percent)}%`);

  el.innerHTML = `
    <div class="notch-drawer">
      <div class="notch-head">
        <span>${esc(state?.theme?.city ?? "GateView")}</span>
        <span class="notch-cam" aria-hidden="true"></span>
        <span>${metaParts.join(" · ") || "GateView"}</span>
      </div>
      ${npCard}
      ${prayers.length ? `<div class="notch-card">
        <div class="row" style="font-size:12px">
          <b>${esc(ph?.name ?? t("prayerTimes"))}</b>
          <span class="notch-accent">${esc(ph ? (ph.kind === "ongoing" ? t("ongoing") : `${ph.kind === "iqamah" ? t("iqomahIn") : t("adzanIn")} ${ph.remaining}`) : "")}</span>
        </div>
        <div class="notch-prayers">${prayerGrid}</div>
      </div>` : ""}
    </div>`;
}

// MARK: Immersive macOS-style Dock + Live Window Preview

const DOCK_PALETTE = ["#4A8FE7", "#E67E5A", "#5AC8FA", "#AF52DE", "#34C759", "#FF9F0A"];
function dockBadgeStyle(title) {
  let hash = 0;
  for (let i = 0; i < title.length; i++) hash = (hash * 31 + title.charCodeAt(i)) | 0;
  const color = DOCK_PALETTE[Math.abs(hash) % DOCK_PALETTE.length];
  return `background: linear-gradient(145deg, ${color}55, ${color}22);`;
}

function renderDock() {
  const wrap = document.getElementById("dock-wrap");
  const dock = document.getElementById("dock");
  if (!wrap || !dock) return;
  const enabled = state?.theme?.showDock !== false;
  wrap.classList.toggle("hidden", !enabled);
  if (!enabled) return;

  const appsHtml = dockWindows.slice(0, 12).map((w) => {
    const letter = esc((w.title.trim()[0] || "?").toUpperCase());
    const cls = `dock-item${w.is_active ? " active" : ""}${w.is_minimized ? " minimized" : ""}`;
    return `<button class="${cls}" data-hwnd="${w.hwnd}" style="${dockBadgeStyle(w.title)}" title="${esc(w.title)}">
      <span>${letter}</span><span class="dock-dot"></span>
    </button>`;
  }).join("");

  const sep = dockWindows.length ? `<span class="dock-sep"></span>` : "";
  const notchLabel = lang() === "id" ? "Buka/Tutup Notch" : "Toggle Notch";
  const notesLabel = t("notes");
  dock.innerHTML = `${appsHtml}${sep}
    <button class="dock-item${notchOpen ? " active" : ""}" data-dock-action="notch" title="${notchLabel}">⌃</button>
    <button class="dock-item${notesOpen ? " active" : ""}" data-dock-action="notes" title="${notesLabel}">✎</button>`;

  dock.querySelectorAll("[data-hwnd]").forEach((btn) => {
    const hwnd = Number(btn.dataset.hwnd);
    btn.addEventListener("mouseenter", () => showWindowPreview(hwnd));
    btn.addEventListener("mouseleave", scheduleHidePreview);
    btn.addEventListener("click", () => invoke("focus_window", { hwnd }));
  });
  dock.querySelector('[data-dock-action="notch"]')?.addEventListener("click", (e) => {
    e.stopPropagation();
    notchOpen = !notchOpen;
    renderNotch();
    renderDock();
    pushHitRegions();
  });
  dock.querySelector('[data-dock-action="notes"]')?.addEventListener("click", (e) => {
    e.stopPropagation();
    notesOpen = !notesOpen;
    renderPanel();
    renderDock();
    pushHitRegions();
  });
}

function bindDockMagnification() {
  const dock = document.getElementById("dock");
  if (!dock) return;
  dock.addEventListener("mousemove", (e) => {
    const items = dock.querySelectorAll(".dock-item");
    items.forEach((item) => {
      const r = item.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const dist = Math.abs(e.clientX - cx);
      const scale = Math.max(1, 1.52 - Math.min(dist, 120) / 120 * 0.52);
      const lift = (scale - 1) * 18;
      item.style.transform = `translateY(${-lift.toFixed(1)}px) scale(${scale.toFixed(3)})`;
    });
  });
  dock.addEventListener("mouseleave", () => {
    dock.querySelectorAll(".dock-item").forEach((item) => { item.style.transform = ""; });
  });
}
bindDockMagnification();

async function showWindowPreview(hwnd) {
  clearTimeout(previewHideTimer);
  hoveredHwnd = hwnd;
  const win = dockWindows.find((w) => w.hwnd === hwnd);
  const box = document.getElementById("dock-preview");
  if (!win || !box) return;
  box.classList.remove("hidden");
  const cached = previewCache.get(hwnd);
  renderPreviewBox(box, win, cached);
  pushHitRegions();

  const fresh = await invoke("get_window_preview", { hwnd }).catch(() => null);
  if (fresh) previewCache.set(hwnd, fresh);
  if (hoveredHwnd === hwnd) {
    renderPreviewBox(box, win, fresh ?? cached);
    pushHitRegions();
  }
}

function renderPreviewBox(box, win, imgUrl) {
  const thumb = imgUrl
    ? `<img src="${imgUrl}" alt="${esc(win.title)}" />`
    : `<span>${win.is_minimized ? (lang() === "id" ? "Minimized" : "Minimized") : (lang() === "id" ? "Memuat pratinjau…" : "Loading preview…")}</span>`;
  box.innerHTML = `
    <div class="preview-head">
      <span class="preview-title">${esc(win.title)}</span>
      <div class="preview-actions">
        <button class="preview-btn" data-act="min" title="Minimize">−</button>
        <button class="preview-btn close" data-act="close" title="Close">×</button>
      </div>
    </div>
    <div class="preview-thumb" data-act="focus">${thumb}</div>`;
  box.querySelector('[data-act="focus"]')?.addEventListener("click", () => invoke("focus_window", { hwnd: win.hwnd }));
  box.querySelector('[data-act="min"]')?.addEventListener("click", (e) => {
    e.stopPropagation();
    invoke("minimize_window", { hwnd: win.hwnd });
  });
  box.querySelector('[data-act="close"]')?.addEventListener("click", (e) => {
    e.stopPropagation();
    invoke("close_window", { hwnd: win.hwnd });
    hideWindowPreview();
  });
}

function scheduleHidePreview() {
  clearTimeout(previewHideTimer);
  previewHideTimer = setTimeout(hideWindowPreview, 180);
}

function hideWindowPreview() {
  hoveredHwnd = null;
  const box = document.getElementById("dock-preview");
  if (box && !box.classList.contains("hidden")) {
    box.classList.add("hidden");
    pushHitRegions();
  }
}

document.getElementById("dock-preview")?.addEventListener("mouseenter", () => clearTimeout(previewHideTimer));
document.getElementById("dock-preview")?.addEventListener("mouseleave", scheduleHidePreview);

function widgetHeader(key) {
  const [id, en] = WIDGET_NAMES[key] ?? [key, key];
  return `<h3>${lang() === "id" ? id : en}</h3>`;
}

function renderPanel() {
  const panel = document.getElementById("panel");
  const widgets = state.theme.widgetOrder ?? [];
  panel.hidden = widgets.length === 0;
  panel.innerHTML = widgets.map((key, i) => `
    ${i > 0 ? '<div class="divider"></div>' : ""}
    <div class="widget" data-hit="${key}">${widgetHeader(key)}${widgetBody(key)}</div>
  `).join("");

  if (widgets.includes("notes")) bindNotes();
  if (widgets.includes("reminders")) bindReminders();
}

function widgetBody(key) {
  switch (key) {
    case "prayer": return prayerBody();
    case "countdown": return countdownBody();
    case "nowPlaying": return nowPlayingBody();
    case "notes": return notesBody();
    case "reminders": return remindersBody();
    default: return `<div class="next-in" style="opacity:.45">${lang() === "id" ? "Segera" : "Coming soon"}</div>`;
  }
}

function prayerBody() {
  const rows = state.prayers ?? [];
  if (!rows.length) return `<div class="next-in">…</div>`;
  const ph = state.phase;
  const sub = !ph ? "" : ph.kind === "ongoing"
    ? t("ongoing")
    : `${ph.kind === "iqamah" ? t("iqomahIn") : t("adzanIn")} ${ph.remaining}`;
  const grid = rows.map((p) => `
    <span><span>${p.name}</span><span style="color:var(--accent)">${p.time}</span></span>`).join("");
  return `
    <div class="row"><span class="prayer-name">${ph?.name ?? rows[0].name}</span>
    <span class="prayer-time">${ph?.kind === "upcoming" ? rows.find((r) => r.name === ph.name)?.time ?? "" : ""}</span></div>
    <div class="next-in">${sub}</div>
    <div class="small-grid">${grid}</div>`;
}

function countdownBody() {
  const items = state.countdowns ?? [];
  if (!items.length) return `<div class="next-in" style="opacity:.45">${t("addNotes")} → "countdowns"</div>`;
  const next = items[0];
  const label = next.days === 0 ? t("today") : next.days === 1 ? t("tomorrow") : t("daysLeft", next.days);
  return `
    <div class="count-big"><span class="count-days">${next.days}</span>
    <span><b>${next.title}</b><br><span class="next-in">${label}</span></span></div>
    ${items.slice(1).map((c) => `
      <div class="row" style="font-size:13px"><span>${c.title}</span>
      <span style="opacity:.6">${c.days === 0 ? t("today") : t("daysLeft", c.days)}</span></div>`).join("")}`;
}

function nowPlayingBody() {
  const np = state.now_playing;
  if (!np) {
    // Linux preview: MPRIS support lands in M3.
    const linux = navigator.userAgent.includes("Linux");
    const msg = linux ? (lang() === "id" ? "Segera hadir di Linux" : "Coming soon on Linux")
                      : (lang() === "id" ? "Tidak ada pemutaran" : "Nothing playing");
    return `<div class="next-in" style="opacity:.45">${msg}</div>`;
  }
  return `
    <div><div class="np-title">${esc(np.title)}</div><div class="np-artist">${esc(np.artist)}</div></div>
    ${np.duration > 0 ? `
    <div class="np-bar"><div class="np-fill" id="np-fill" style="width:0%"></div></div>
    <div class="np-times"><span id="np-pos">0:00</span><span id="np-dur">0:00</span></div>`
    : `<div class="next-in">${esc(np.source)}</div>`}`;
}

function notesBody() {
  if (notesOpen) {
    return `<textarea class="notes-edit" id="notes-edit">${esc(state.notes ?? "")}</textarea>
      <div class="next-in">${lang() === "id" ? "Tersimpan otomatis" : "Saved automatically"} · theme.json dir</div>`;
  }
  const text = (state.notes ?? "").split("\n").slice(0, 4).join("\n");
  return `<div class="notes-text">${esc(text || t("notesHint"))}</div>`;
}

function remindersBody() {
  // M1: list only — EventKit-equivalent (Windows Appointments / EDS) is M4 parity work.
  return `<div class="next-in" style="opacity:.45">${lang() === "id"
    ? "Sinkronisasi reminders datang di M4" : "Reminder sync arrives in M4"}</div>`;
}

// MARK: Now Playing ticking (position advances locally between payloads, like macOS)

function tickNowPlaying(now) {
  const np = state?.now_playing;
  if (!np || !(np.duration > 0)) return;
  const elapsed = np.elapsed + (np.is_playing ? (now.getTime() / 1000 - np.timestamp) * Math.max(np.rate, 1) : 0);
  const pct = `${Math.min(100, elapsed / np.duration * 100)}%`;
  const posText = fmtTime(elapsed);
  const durText = fmtTime(np.duration);
  for (const prefix of ["np", "notch-np"]) {
    const fill = document.getElementById(`${prefix}-fill`);
    if (!fill) continue;
    fill.style.width = pct;
    document.getElementById(`${prefix}-pos`).textContent = posText;
    document.getElementById(`${prefix}-dur`).textContent = durText;
  }
}
function fmtTime(s) {
  s = Math.max(0, Math.floor(s));
  const m = Math.floor(s / 60), r = s % 60;
  return `${m}:${String(r).padStart(2, "0")}`;
}

// MARK: Interactions

function bindNotes() {
  const panel = document.getElementById("panel");
  const widget = panel.querySelector('[data-hit="notes"]');
  if (!widget) return;
  if (notesOpen) {
    const area = document.getElementById("notes-edit");
    area?.addEventListener("input", () => invoke("save_notes", { text: area.value }));
    setTimeout(() => area?.focus(), 50);
  } else {
    // A click expands the editor; clicks elsewhere collapse it (auto-collapse like macOS).
    widget.addEventListener("click", () => { notesOpen = true; renderPanel(); });
  }
}

function bindReminders() { /* list-only in M1 */ }

document.getElementById("notch")?.addEventListener("click", (e) => {
  e.stopPropagation();
  if (!notchOpen) {
    notchOpen = true;
    renderNotch();
    pushHitRegions();
  }
});

document.addEventListener("click", (e) => {
  let changed = false;
  if (notesOpen && !e.target.closest('[data-hit="notes"]')) {
    notesOpen = false;
    renderPanel();
    changed = true;
  }
  if (notchOpen && !e.target.closest("#notch")) {
    notchOpen = false;
    renderNotch();
    changed = true;
  }
  if (changed) pushHitRegions();
});

// MARK: Click-through hit regions (physical px relative to the window)

function pushHitRegions() {
  const dpr = window.devicePixelRatio || 1;
  const regions = {};
  document.querySelectorAll("[data-hit]").forEach((el) => {
    const r = el.getBoundingClientRect();
    regions[el.dataset.hit] = [
      Math.round(r.left * dpr), Math.round(r.top * dpr),
      Math.round(r.width * dpr), Math.round(r.height * dpr),
    ];
  });
  invoke("set_hit_regions", { regions });
}
window.addEventListener("resize", pushHitRegions);
new ResizeObserver(pushHitRegions).observe(document.body);

// MARK: Wiring

const esc = (s) => String(s).replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

await listen("dashboard", (e) => {
  // Re-render only on structural change: a 30 s payload must not steal focus
  // from the notes editor or reset the now-playing tick.
  const next = e.payload;
  const signature = (s) => JSON.stringify([s.theme, s.prayers, s.phase, s.countdowns,
    s.now_playing?.title, s.now_playing?.is_playing]);
  const structural = !state || signature(state) !== signature(next);
  const weatherChanged = JSON.stringify(state?.weather) !== JSON.stringify(next.weather);
  if (structural || weatherChanged) {
    state = next;
    render();
  } else if (state) {
    state.now_playing = next.now_playing;
  }
});
await listen("theme", (e) => {
  if (state) state.theme = e.payload; else state = { theme: e.payload };
  render();
});
await listen("stats", (e) => {
  const s = e.payload;
  if (!s) return;
  if (state) state.stats = s;
  document.getElementById("stats-chip").classList.remove("hidden");
  document.getElementById("cpu").textContent = `${Math.round(s.cpu)}%`;
  document.getElementById("ram").textContent = `${Math.round(s.ram_percent)}%`;
  if (notchOpen) renderNotch();
});
await listen("dock", (e) => {
  dockWindows = Array.isArray(e.payload) ? e.payload : [];
  renderDock();
  pushHitRegions();
});

state = await invoke("get_state");
dockWindows = await invoke("list_dock_windows").catch(() => []);
render();
tickClock();
