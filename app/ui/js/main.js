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

function lang() {
  const mode = state?.theme?.language ?? "auto";
  if (mode === "id" || mode === "en") return mode;
  return (navigator.language || "").toLowerCase().startsWith("id") ? "id" : "en";
}
const t = (key, ...args) => L[lang()][key](...args);

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
  document.getElementById("dashboard").style.flexDirection =
    theme.panelSide === "left" ? "row-reverse" : "row";

  // Weather chip
  const chip = document.getElementById("weather-chip");
  if (state.weather && theme.showWeather) {
    chip.classList.remove("hidden");
    document.getElementById("weather-temp").textContent = `${state.weather.temperature}°`;
    document.getElementById("weather-label").textContent = state.weather.label;
  } else {
    chip.classList.add("hidden");
  }

  renderPanel();
  pushHitRegions();
}

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
  if (!np) return `<div class="next-in" style="opacity:.45">${lang() === "id" ? "Tidak ada pemutaran" : "Nothing playing"}</div>`;
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
  const fill = document.getElementById("np-fill");
  if (!fill) return;
  const elapsed = np.elapsed + (np.is_playing ? (now.getTime() / 1000 - np.timestamp) * Math.max(np.rate, 1) : 0);
  fill.style.width = `${Math.min(100, elapsed / np.duration * 100)}%`;
  document.getElementById("np-pos").textContent = fmtTime(elapsed);
  document.getElementById("np-dur").textContent = fmtTime(np.duration);
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

document.addEventListener("click", (e) => {
  if (notesOpen && !e.target.closest('[data-hit="notes"]')) {
    notesOpen = false;
    renderPanel();
  }
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
  document.getElementById("stats-chip").classList.remove("hidden");
  document.getElementById("cpu").textContent = `${Math.round(s.cpu)}%`;
  document.getElementById("ram").textContent = `${Math.round(s.ram_percent)}%`;
});

state = await invoke("get_state");
render();
tickClock();
