"use strict";

const $ = (selector) => document.querySelector(selector);
const escapeHTML = (value) => String(value).replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
const paths = {
  timer: '<circle cx="12" cy="13" r="8"/><path d="M9 2h6m-3 0v3m0 3v5l3 2m4-10 1.5-1.5"/>',
  thoughts: '<rect x="4" y="4" width="16" height="16" rx="1"/><path d="m8 12 3 3 6-7"/>',
  stats: '<path d="M5 20V12h3v8m3 0V5h3v15m3 0V9h3v11"/>',
  projects: '<path d="M3 7h7l2-2h9v15H3z"/>',
  settings: '<path d="m9 3-1 3-3 1-2 3 2 2v3l3 1 1 3h5l1-3 3-1 2-3-2-2V7l-3-1-1-3z"/><circle cx="11.5" cy="11" r="3"/>',
  bell: '<path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5zm5 4h4"/>',
  backup: '<path d="M12 3v12m-4-4 4 4 4-4M4 15v6h16v-6"/>',
  back: '<path d="m14 5-7 7 7 7M7 12h14"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  down: '<path d="m6 9 6 6 6-6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  delete: '<path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
  dim: '<path d="m12 2 3 3h4v4l3 3-3 3v4h-4l-3 3-3-3H5v-4l-3-3 3-3V5h4z"/><path d="M12 7a5 5 0 0 1 0 10z"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  edit: '<path d="m4 16-1 5 5-1L20 8l-4-4zM13 7l4 4"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4m10-4v4M3 11h18m-13 4h1m4 0h1"/>'
};
const icon = (name) => `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.timer}</svg>`;
const button = (label, action, style = "text-button", extra = "") => `<button class="${style}" data-action="${escapeHTML(action)}" ${extra}>${label}</button>`;
const iconButton = (name, label, action) => button(icon(name), action, "icon-button", `aria-label="${escapeHTML(label)}" title="${escapeHTML(label)}"`);
const duration = (minutes) => minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} hr${minutes % 60 ? ` ${minutes % 60} min` : ""}`;
const section = (title, content) => `<section><h3 class="section-heading">${title}</h3><div class="card">${content}</div></section>`;
const hint = (text) => `<p class="muted">${text}</p>`;
const row = (label, value, action) => `<button class="row" data-action="${action}"><span>${label}</span><span class="muted">${value || icon("chevron")}</span></button>`;
const switchRow = (label, checked, action) => `<div class="row"><span>${label}</span><button class="switch" role="switch" aria-label="${label}" aria-checked="${checked}" data-action="${action}"><span></span></button></div>`;

const screens = [
  ["focus", "Focus", "timer"], ["thoughts", "Thoughts", "thoughts"], ["projects", "Projects & goals", "projects"],
  ["stats", "Stats", "stats"], ["settings", "Settings", "settings"], ["alerts", "Android alerts", "bell"], ["backup", "Backups", "backup"]
];
const notes = {
  focus: ["01 / Focus", "One clear next action.", "The timer remains the visual anchor. <strong>Indigo marks focus</strong>; sage marks a break. Only the controls for the current phase are visible.", "Preserved components", ["Project selector and remembered duration.", "Optional task-list session plan.", "Saved progress against today’s project goal."], "Try it", "Start Focus, capture a thought, then use the state selector to inspect the break and Dim Focus. The next phase always waits for your tap.", ["200 dp timer ring", "48 dp controls", "20 dp inset"]],
  thoughts: ["02 / Thoughts", "Capture now. Review later.", "A permanent checklist shared across projects. Capture opens without pausing focus and keeps the project and session it was opened for.", "Interaction rules", ["All / Open / Done, search, and project filters.", "Completed thoughts stay visible in All with strikethrough.", "Discarding a session keeps its thoughts."], "Try it", "Check an item, switch to Done, or add a thought. Deleting shows the shared Undo snackbar above the bottom navigation.", ["500 characters", "Fixed capture context", "Independent history"]],
  projects: ["03 / Projects & goals", "The same project, across every view.", "Projects opens from Focus rather than adding a fourth tab. The detail brings together saved time, weekly progress, recent sessions, and settings.", "Editor behavior", ["New projects begin with just a name.", "Timer settings and goals are optional sections.", "Daily schedules and weekly targets belong to each project."], "Try it", "Open Work, then Project settings and goals. Edit the daily schedule; zero minutes represents a rest day. Cancel a changed editor to inspect draft protection.", ["One atomic project save", "Dated goal revisions", "Manual lifecycle"]],
  stats: ["04 / Stats", "Saved work, in context.", "Day, Week, Month, and All share one project filter. The main screen stays compact; Details holds daily values, comparisons, and drill-down.", "Counting rules", ["An active focus is labelled and excluded until saved.", "Time crossing midnight is split across local days.", "A focused day requires 10 minutes of saved work."], "Try it", "Switch to Week or Month. Open the period label for its picker, tap Details for readable values, or open Consistency for focused-day counts.", ["Saved focus only", "Monday–Sunday weeks", "Text chart equivalent"]],
  settings: ["05 / Settings", "Familiar choices. Native controls.", "Retain appearance, separate focus and break sounds, haptics, privacy, timer defaults, and backups. Use Android’s own system settings for delivery controls.", "Sound and privacy", ["Completion audio uses notification channels.", "Sound changes also update a running timer.", "Project and plan visibility are separate opt-in choices."], "Try it", "Switch the theme or toggle lock-screen privacy, then inspect Android alerts. Test buttons show preview feedback; this document never plays a notification sound.", ["System alerts only", "OLED black", "Local data"]],
  alerts: ["06 / Android integration", "A system countdown and completion alert.", "The Android port uses an exact alarm plus an ordinary notification. These examples document content and actions; <strong>Samsung’s actual presentation may differ</strong>.", "Delivery behavior", ["The running countdown is silent.", "Completion follows notification volume, channel settings, and Do Not Disturb.", "Thought text is never included in the notification."], "Try it", "Toggle project and session-plan visibility. Add a thought opens the same in-app composer. Physical foreground, background, and locked delivery still need S26 verification.", ["No continuous service", "Stable timer identity", "No replay on reopen"]],
  backup: ["07 / Backups", "Fresh on Android. Portable when you need it.", "Android and iPhone keep separate local stores. Manual JSON backups carry projects, saved sessions, thoughts, goals, and settings between them.", "Restore boundaries", ["Export excludes the active timer.", "Restore is available only while idle.", "Replacement requires an explicit confirmation."], "Try it", "Choose a sample backup to inspect the replacement confirmation. This prototype reads and writes no files. Use the focus state control to see restore disabled during a timer.", ["Schema 1–9 import", "50 MB import limit", "No automatic sync"]]
};

function initialData() {
  return {
    projects: [{ id: "work", name: "Work", status: "Ongoing", focus: 25, short: 5, long: 15, daily: [120, 120, 120, 120, 90, 60, 0], weekly: 600 }, { id: "reading", name: "Reading", status: "Ongoing", focus: 25, short: 5, long: 15, daily: [30, 30, 30, 30, 30, 30, 0], weekly: 150 }, { id: "archive", name: "Spring project", status: "Completed", focus: 25, short: 5, long: 15, daily: null, weekly: null }],
    thoughts: [{ id: 1, text: "Ask about the design review", project: "work", done: false }, { id: 2, text: "Compare the two approaches in the paper", project: "reading", done: false }, { id: 3, text: "Send the agenda for Monday", project: "work", done: true }],
    plan: ["Review the experiment notes", "Draft the methods section"],
    settings: { sound: true, haptics: true, projectVisible: false, planVisible: false, focusSound: "System default", breakSound: "Chime" },
    savedToday: 75
  };
}
let data = initialData();
let state = { screen: "focus", phase: "ready", project: "work", projectDetail: null, inactive: false, thoughtFilter: "All", thoughtProject: "all", query: "", range: "Day", periodOffset: 0, statsProject: "all", editor: null, dialog: null, undo: null, theme: "light", large: false };
let undoTimeout;
let dimTimeout;
const currentProject = () => data.projects.find((project) => project.id === state.project) || data.projects[0];
const running = () => ["running", "dim", "breakRunning"].includes(state.phase);

function focusTimer(time, kind = "Focus", progress = 0) {
  return `<div class="timer ${kind === "Focus" ? "" : "break"}"><div class="timer-ring" style="--ring-offset:${578 * (1 - progress)}"><svg viewBox="0 0 200 200" aria-hidden="true"><circle class="ring-track" cx="100" cy="100" r="92"/><circle class="ring-value" cx="100" cy="100" r="92"/></svg><span class="timer-number">${time}</span></div><span class="timer-label">${kind}</span></div>`;
}
function focusScreen() {
  const project = currentProject();
  if (state.phase === "empty") return `<div class="stack empty-state"><div class="empty-symbol">${icon("projects")}</div><h3>Make space for<br>focused work</h3>${hint("Create a project, then begin a focus session.")}${button("Create Project", "new-project", "primary")}</div>`;
  if (state.phase === "running" || state.phase === "dim") return `<div class="stack"><h3 class="project-title">${escapeHTML(project.name)}</h3>${focusTimer("18:42", "Focus", .252)}${data.plan.length ? hint(data.plan.map(escapeHTML).join("<br>")) : ""}${button(data.plan.length ? "Edit session plan" : "Add session plan", "plan")}${button("End Focus", "end-focus", "primary")}${button("Add a thought", "capture", "outlined")}${hint("Completion alerts follow your phone’s notification volume and system settings.")}</div>`;
  if (state.phase === "breakReady") return `<div class="stack"><h3 class="project-title">Focus saved</h3>${focusTimer("05:00", "Short break")}${button("Short break duration · 5 min", "break-duration", "text-button sage")}${button("Start Short break", "start-break", "primary sage")}${button("Skip Break", "skip-break")}${button("Plan next session", "plan")}</div>`;
  if (state.phase === "breakRunning") return `<div class="stack"><h3 class="project-title">${escapeHTML(project.name)}</h3>${focusTimer("03:18", "Short break", .34)}${button("End Break", "end-break", "primary sage")}${button("Review thoughts", "project-thoughts", "outlined")}${button("Plan next session", "plan")}${hint("The next focus session starts when you choose.")}</div>`;
  return `<div class="stack">${button(`Project: ${escapeHTML(project.name)} ${icon("down")}`, "select-project", "outlined")}${focusTimer(`${project.focus}:00`)}${button(`Focus duration · ${project.focus} min`, "focus-duration")}${button(data.plan.length ? `${data.plan.length} planned tasks` : "Add session plan", "plan", "outlined")}${data.plan.length ? hint(data.plan.map(escapeHTML).join("<br>")) : ""}${button("Start Focus", "start-focus", "primary")}${section("Today", `<div class="total">${duration(data.savedToday)}</div>${hint(`of ${project.daily ? project.daily[5] : "no recorded"} ${project.daily ? "min" : "goal"}`)}<div class="progress-track"><span style="--progress:${Math.min(100, data.savedToday / (project.daily?.[5] || 120) * 100)}%"></span></div>`)}</div>`;
}
function thoughtRow(thought) {
  const project = data.projects.find((item) => item.id === thought.project);
  return `<div class="thought-row"><label class="thought-check"><input type="checkbox" data-thought="${thought.id}" aria-label="Mark ${escapeHTML(thought.text)} ${thought.done ? "open" : "done"}" ${thought.done ? "checked" : ""}></label><button class="thought-copy ${thought.done ? "done" : ""}" data-action="edit-thought:${thought.id}"><span>${escapeHTML(thought.text)}</span><small>${escapeHTML(project?.name || "Unassigned")}</small></button>${iconButton("delete", "Delete thought", `delete-thought:${thought.id}`)}</div>`;
}
function filteredThoughts() {
  return data.thoughts.filter((thought) => (state.thoughtProject === "all" || thought.project === state.thoughtProject) && (state.thoughtFilter === "All" || thought.done === (state.thoughtFilter === "Done")) && thought.text.toLowerCase().includes(state.query.toLowerCase()));
}
function thoughtsScreen() {
  const projectLabel = data.projects.find((item) => item.id === state.thoughtProject)?.name || (state.thoughtProject === "unassigned" ? "Unassigned" : "All projects");
  return `<div class="stack">${button("Add a thought", "capture-standalone", "primary")}<input class="search-field" id="thought-search" type="search" value="${escapeHTML(state.query)}" placeholder="Search thoughts" aria-label="Search thoughts">${button(`Project: ${escapeHTML(projectLabel)} ${icon("down")}`, "thought-project", "outlined")}<div class="chips">${["All", "Open", "Done"].map((filter) => button(filter, `thought-filter:${filter}`, "chip", `aria-pressed="${state.thoughtFilter === filter}"`)).join("")}</div><div class="stack" id="thought-results">${thoughtResults()}</div></div>`;
}
function thoughtResults() { return filteredThoughts().map(thoughtRow).join("") || hint("No matching thoughts."); }
function projectScreen() {
  const project = data.projects.find((item) => item.id === state.projectDetail);
  if (project) return `<div class="stack">${button("All projects", "all-projects")}<div><h3 style="font-size:27px;font-weight:400;margin:0 0 9px">${escapeHTML(project.name)}</h3>${hint(project.status)}</div>${section("Saved focus", `<div class="total">8 hr 45 min</div>${hint("21 sessions")}`)}${section("This week", `<div class="total">4 hr 50 min</div>${hint(`of ${project.weekly || 0} min`)}<div class="progress-track"><span style="--progress:48%"></span></div>`)}${button("Use for Focus", "use-project", "primary")}${button("Project settings and goals", "edit-project", "outlined")}${button("Review thoughts", "detail-thoughts")}${button("Add quick-start shortcut", "shortcut")}${section("Recent sessions", historyRows())}${button("Merge into another project", "merge")}</div>`;
  return `<div class="stack">${button("Create Project", "new-project", "primary")}${section("Ongoing", data.projects.filter((item) => item.status === "Ongoing").map((item) => `<button class="row" data-action="project:${item.id}"><span class="row-copy"><span>${escapeHTML(item.name)}</span><small class="muted">${item.id === "work" ? "8 hr 45 min" : "2 hr 30 min"} saved</small></span>${icon("chevron")}</button>`).join(""))}${button(state.inactive ? "Hide inactive projects" : "Show inactive projects", "inactive")}${state.inactive ? section("Completed", row("Spring project", "", "project:archive")) : ""}</div>`;
}
function historyRows() {
  return ["Draft the methods section", "Review experiment notes", "Prepare the next run"].map((text, index) => `<button class="history-item" data-action="session:${index}"><strong>${escapeHTML(currentProject().name)}</strong><span>${text}</span><small>${["10:30", "09:45", "08:50"][index]} · 25 min${index === 2 ? " · Ended early" : ""}</small></button>`).join("");
}
function periodValues() {
  const work = state.range === "Month" ? Array.from({ length: 31 }, (_, index) => [25, 35, 0, 50, 40, 25, 0][index % 7]) : [35, 50, 25, 65, 40, data.savedToday, 0];
  const reading = work.map((_, index) => index % 7 === 0 ? 15 : index % 7 === 1 ? 10 : 0);
  if (state.statsProject === "work") return work;
  if (state.statsProject === "reading") return reading;
  if (state.statsProject !== "all") return work.map(() => 0);
  return work.map((minutes, index) => minutes + reading[index]);
}
function periodTitle() {
  if (state.periodOffset < 0) return state.range === "Week" ? "19–25 Oct 2026" : state.range === "Month" ? "September 2026" : "30 Oct 2026";
  return state.range === "Day" ? "Today" : state.range === "Week" ? "This week" : "This month";
}
function statsScreen() {
  const values = periodValues();
  const total = state.range === "Day" ? ["all", "work"].includes(state.statsProject) ? data.savedToday : 0 : state.range === "All" ? state.statsProject === "work" ? 525 : state.statsProject === "reading" ? 150 : state.statsProject === "all" ? 675 : 0 : values.reduce((sum, value) => sum + value, 0);
  const projectName = data.projects.find((project) => project.id === state.statsProject)?.name || "All projects";
  return `<div class="stack"><div class="chips">${["Day", "Week", "Month", "All"].map((range) => button(range, `range:${range}`, "chip", `aria-pressed="${state.range === range}"`)).join("")}</div>${button(`Project: ${escapeHTML(projectName)} ${icon("down")}`, "stats-project", "outlined")}${state.range !== "All" ? `<div class="range-navigation">${button("Previous", "previous", "")}${button(periodTitle(), "period-picker", "")}${button("Next", "next", "", state.periodOffset >= 0 ? "disabled" : "")}</div>${state.periodOffset < 0 ? button(`Return to current ${state.range.toLowerCase()}`, "current-period") : ""}` : ""}${section("Focus time", `<div class="hero-total">${duration(total)}</div>${running() && state.phase !== "breakRunning" && ["all", state.project].includes(state.statsProject) ? hint("1 session in progress · not included yet") : ""}`)}${["Week", "Month"].includes(state.range) ? section("Daily focus", `<div class="chart" role="img" aria-label="Saved focus by day. Open Details for all values.">${values.map((value, index) => `<div class="bar-column"><button class="bar" data-action="day:${index}" aria-label="Day ${index + 1}: ${value} minutes" style="--height:${Math.max(2, value / Math.max(75, ...values) * 100)}%"></button>${state.range === "Week" ? `<small>${["M", "T", "W", "T", "F", "S", "S"][index]}</small>` : ""}</div>`).join("")}</div>${hint(`<span class="chart-caption">Saved focus across this ${state.range.toLowerCase()}</span>`)}${button("Details", "stats-details")}`) : ""}${button("Consistency", "consistency")}${section("Recent sessions", total === 0 ? hint("No saved sessions for this selection.") : historyRows())}</div>`;
}
function settingsScreen() {
  const settings = data.settings;
  return `<div class="stack">${section("Appearance", button(`Theme: ${state.theme === "dark" ? "Dark" : "Light"} ${icon("down")}`, "toggle-theme", "outlined"))}${section("Completion alerts", switchRow("Notification sounds", settings.sound, "toggle:sound") + button(`Focus complete: ${settings.focusSound}`, "sound:focus", "outlined") + button("Test focus completion alert", "test-alert") + button(`Break complete: ${settings.breakSound}`, "sound:break", "outlined") + button("Test break completion alert", "test-alert") + hint("Completion alerts use system notifications and your phone’s notification volume. Sound changes also update a running timer.") + button("Open notification settings", "notification-settings"))}${section("Lock screen privacy", switchRow("Show project name", settings.projectVisible, "toggle:projectVisible") + switchRow("Show session plan", settings.planVisible, "toggle:planVisible") + hint("Thoughts and next steps stay inside the app."))}${section("Timer defaults", switchRow("Haptics", settings.haptics, "toggle:haptics") + row("Focus", "25 min", "focus-duration") + row("Short break", "5 min", "break-duration") + row("Long break", "15 min", "long-duration") + row("Long break after", "4 focus sessions", "cycle"))}${section("Consistency", row("Weekly focused-day target", "4 days", "consistency") + hint("At least 10 minutes of saved focus makes a focused day."))}${button("Backups", "go:backup", "outlined")}${button("Add thought shortcut", "shortcut")}${hint("All app data stays on this phone. No account, tracking, advertising, or automatic synchronization.")}</div>`;
}
function alertsScreen() {
  const settings = data.settings;
  const detail = [settings.projectVisible ? escapeHTML(currentProject().name) : "", settings.planVisible ? escapeHTML(data.plan[0] || "Draft the methods section") : ""].filter(Boolean).join(" · ") || "Tap to open Pomodoro";
  return `<div class="stack">${hint("Illustrative Android system surfaces. Notification layout varies by device.")}<section><h3 class="section-heading">Running timer · silent</h3><div class="system-example"><div class="notification"><div class="notification-app">${icon("timer")} Pomodoro · now</div><div class="notification-title">Focus</div>${hint(detail)}<div class="notification-time">18:42</div>${button("Add thought", "capture")}</div></div></section><section><h3 class="section-heading">Completion alert</h3><div class="system-example"><div class="notification"><div class="notification-app">${icon("timer")} Pomodoro · now</div><div class="notification-title">Timer complete</div>${hint("Open Pomodoro when you’re ready for the next session.")}</div></div></section>${section("Lock screen content", switchRow("Show project name", settings.projectVisible, "toggle:projectVisible") + switchRow("Show session plan", settings.planVisible, "toggle:planVisible"))}<div class="notice">${hint("Permission, notification-channel settings, and Do Not Disturb determine alert delivery. This page does not request system permissions.")}</div>${button("Preview permission request", "permission", "outlined")}</div>`;
}
function backupScreen() {
  return `<div class="stack">${section("Backups", hint("Export projects, saved sessions, thoughts, goals, and settings as an iPhone-compatible JSON file.") + hint("An active timer is not exported.") + button("Export backup", "export", "outlined"))}${section("Restore backup", hint("Choose a backup to replace the current saved data after confirmation.") + button("Choose sample backup", "import", "primary", running() ? "disabled" : "") + (running() ? hint("End your timer before restoring a backup.") : hint("Maximum backup size: 50 MB. Sample file: Pomodoro-Backup.json.")))}${section("Your data", hint("App data stays in private device storage. The location you choose for a manual export controls how that file is stored or shared.") + hint("Automatic backup and device transfer of app storage are disabled."))}</div>`;
}

function render() {
  const focused = document.activeElement;
  const focusID = focused?.id;
  const selection = typeof focused?.selectionStart === "number" ? [focused.selectionStart, focused.selectionEnd] : null;
  $("#phone").classList.toggle("dark", state.theme === "dark");
  $("#phone").classList.toggle("large", state.large);
  $("#appearance").value = state.theme;
  $("#large-text").checked = state.large;
  $("#scenario").value = state.phase;
  $("#screen-navigation").innerHTML = screens.map(([id, title, symbol]) => button(icon(symbol) + title, `go:${id}`, "", state.screen === id ? 'aria-current="page"' : "")).join("");
  const title = screens.find(([id]) => id === state.screen)?.[1] || "Focus";
  const toolbarActions = state.screen === "focus" ? `${["running", "dim"].includes(state.phase) ? iconButton("dim", "Enable Dim Focus", "dim") : ""}${iconButton("settings", "Settings", "go:settings")}${iconButton("projects", "Projects", "go:projects")}` : "";
  const back = !["focus", "thoughts", "stats"].includes(state.screen) ? iconButton("back", "Back to Focus", "go:focus") : "";
  const content = { focus: focusScreen, thoughts: thoughtsScreen, projects: projectScreen, stats: statsScreen, settings: settingsScreen, alerts: alertsScreen, backup: backupScreen }[state.screen]();
  $("#app").innerHTML = `<header class="toolbar">${back}<h2>${state.screen === "projects" ? "Projects" : title}</h2>${toolbarActions}</header><div class="page phone-body" id="phone-page">${content}</div>${state.undo ? `<div class="undo"><span>Thought deleted</span>${button("Undo", "undo", "")}</div>` : ""}<nav class="bottom-tabs" aria-label="App tabs">${[["focus", "Focus", "timer"], ["thoughts", "Thoughts", "thoughts"], ["stats", "Stats", "stats"]].map(([id, label, symbol]) => button(`<span class="nav-icon">${icon(symbol)}</span><span>${label}</span>`, `go:${id}`, "nav-item", state.screen === id ? 'aria-current="page"' : "")).join("")}</nav>`;
  const note = notes[state.screen];
  $("#design-notes").innerHTML = `<span class="note-index">${note[0]}</span><h2>${note[1]}</h2><p>${note[2]}</p><div class="note-section"><h3>${note[3]}</h3><ul>${note[4].map((item) => `<li>${item}</li>`).join("")}</ul></div><div class="note-section"><h3>${note[5]}</h3><p>${note[6]}</p></div><div class="note-section">${note[7].map((item) => `<span class="note-chip">${item}</span>`).join("")}</div>`;
  renderOverlay();
  $("#app").inert = !!state.editor || !!state.dialog || (state.phase === "dim" && state.screen === "focus");
  if (focusID && document.getElementById(focusID)) {
    document.getElementById(focusID).focus({ preventScroll: true });
    if (selection && document.getElementById(focusID).setSelectionRange) document.getElementById(focusID).setSelectionRange(...selection);
  }
}
function modal(title, body, footer = "", closeLabel = "Cancel", action = "close-editor", trailing = "") {
  return `<section class="modal-screen" role="dialog" aria-modal="true" aria-labelledby="editor-title"><header class="toolbar">${button(closeLabel, action)}<h2 id="editor-title">${title}</h2>${trailing || '<span style="width:64px"></span>'}</header><div class="page stack">${body}</div>${footer ? `<div class="modal-footer">${footer}</div>` : ""}</section>`;
}
function editorHTML() {
  const editor = state.editor;
  if (!editor) return "";
  if (editor.type === "plan") return modal("Session plan", `${data.plan.length ? data.plan.map((text, index) => `<div class="task-row"><p>• ${escapeHTML(text)}</p>${button("Edit", `edit-task:${index}`, "text-button compact")}${button("Delete", `delete-task:${index}`, "text-button compact")}</div>`).join("") : hint("Add a few tasks for this focus session.")}${editor.error ? `<p class="inline-error">${escapeHTML(editor.error)}</p>` : ""}`, `<label class="field">${editor.editing == null ? "Add a task" : "Edit task"}<textarea id="draft-text" rows="2" placeholder="What will you work on?">${escapeHTML(editor.text)}</textarea></label>${hint(`${data.plan.join("\n").length} / 280 characters saved · one task per line`)}${button(editor.editing == null ? "Add task" : "Save task", "save-task", "primary")}`, "Done");
  if (editor.type === "capture" || editor.type === "editThought") return modal(editor.type === "editThought" ? "Edit thought" : editor.origin ? "Session thoughts" : "New thoughts", `${editor.type === "capture" ? data.thoughts.filter((thought) => editor.added.includes(thought.id)).map(thoughtRow).join("") || hint("Capture a thought and return to your focus. Saved thoughts remain even if you discard the session.") : ""}${hint(editor.origin ? `Captured for ${escapeHTML(editor.projectName)} · current focus` : "Save thoughts to the selected project.")}${!editor.origin ? `<label class="field">Project<select id="capture-project"><option value="unassigned" ${editor.project === "unassigned" ? "selected" : ""}>Unassigned</option>${data.projects.map((project) => `<option value="${project.id}" ${editor.project === project.id ? "selected" : ""}>${escapeHTML(project.name)}</option>`).join("")}</select></label>` : ""}${editor.error ? `<p class="inline-error">${editor.error}</p>` : ""}`, `<label class="field">Add a thought…<textarea id="draft-text" rows="3" maxlength="500">${escapeHTML(editor.text)}</textarea></label>${hint('<span id="character-count">' + editor.text.length + '</span> / 500 characters')}${button(editor.type === "editThought" ? "Save" : "Add thought", "save-thought", "primary")}`, "Done");
  if (editor.type === "project") {
    const draft = editor.draft;
    return modal(editor.isNew ? "New project" : "Project settings", `<label class="field">Project name<input id="project-name" value="${escapeHTML(draft.name)}" maxlength="100" placeholder="Project name"></label>${!editor.isNew ? `<label class="field">Status<select id="project-status">${["Ongoing", "On hold", "Completed"].map((status) => `<option ${draft.status === status ? "selected" : ""}>${status}</option>`).join("")}</select></label>` : ""}<details ${!editor.isNew ? "open" : ""}><summary class="row">Timer settings</summary><div class="stack">${["focus", "short", "long"].map((key) => `<label class="field">${{ focus: "Focus", short: "Short break", long: "Long break" }[key]} minutes<input type="number" data-project-number="${key}" min="${key === "focus" ? 10 : 1}" max="60" value="${draft[key]}"></label>`).join("")}</div></details><details ${!editor.isNew ? "open" : ""}><summary class="row">Daily and weekly goals</summary><div class="stack">${section("Daily goal", hint("Changes take effect today. Earlier days retain their recorded goals.") + ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].map((day, index) => `<div class="row"><label for="goal-${index}">${day}</label><input aria-label="${day} goal in minutes" id="goal-${index}" data-goal-day="${index}" type="number" min="0" max="1440" value="${draft.daily?.[index] || 0}" style="width:85px;background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:9px;color:var(--ink)"></div>`).join("") + hint("0 min means a rest day."))}${section("Weekly goal", `<label class="field">Minutes per week<input id="weekly-goal" type="number" min="1" max="10080" value="${draft.weekly || 300}"></label>` + hint("Weekly goals are independent of the daily schedule."))}${section("Scheduled weekly changes", hint("Schedule a Monday after the current week.") + '<label class="field">Monday<input id="scheduled-date" type="date" value="2026-11-02" min="2026-11-02"></label><label class="field">Weekly minutes, or blank for off<input id="scheduled-goal" type="number" min="1" max="10080" placeholder="Off"></label>' + button("Add scheduled change", "schedule-goal") + (editor.scheduled ? hint(escapeHTML(editor.scheduled)) : ""))}</div></details>${editor.error ? `<p class="inline-error">${editor.error}</p>` : ""}`, "", "Cancel", "close-editor", button("Save", "save-project"));
  }
  if (editor.type === "details") return modal("Period details", `${periodValues().map((minutes, index) => button(`${state.range === "Week" ? ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][index] : `Day ${index + 1}`} · ${duration(minutes)}`, `day:${index}`, "outlined")).join("")}${hint("Sessions are counted by their start date. Time is split across each local day it overlaps.")}`, "", "Done");
  if (editor.type === "consistency") return modal("Consistency", `<h3 style="font-size:25px;font-weight:400;margin:5px 0">3 of 4 days this week</h3>${hint("A focused day has at least 10 minutes of saved focus. Active sessions count after saving.")}${section("Previous weeks", [4, 3, 5, 4, 2, 4, 3, 5].map((count, index) => `<div class="row"><span>Week of ${["19 Oct", "12 Oct", "5 Oct", "28 Sep", "21 Sep", "14 Sep", "7 Sep", "31 Aug"][index]}</span><span>${count} days</span></div>`).join(""))}`, "", "Done");
  if (editor.type === "session") return modal("Session", `<h3 style="font-size:26px;font-weight:400;margin:0">${escapeHTML(currentProject().name)}</h3><div class="hero-total">25 min</div>${hint("31 Oct 2026 · Completed · Started 10:30")}${section("Session plan", hint("Draft the methods section") + button("Edit session plan", "plan"))}${section("Next step", hint("Review the revised figures") + button("Use for next session", "promote-plan"))}${button("Delete Session", "delete-session", "text-button danger")}`, "", "Done");
  if (editor.type === "day") return modal("Sessions · selected day", section("Saved focus", historyRows()), "", "Done");
  if (editor.type === "period") {
    if (state.range === "Day") return modal("Choose a day", '<label class="field">Date<input id="period-day" type="date" value="2026-10-31" max="2026-10-31"></label>' + button("Select day", "pick-period", "primary"));
    if (state.range === "Week") return modal("Choose a week", hint("2026") + `<div class="week-options">${["26 Oct – 1 Nov", "19 – 25 Oct", "12 – 18 Oct", "5 – 11 Oct", "28 Sep – 4 Oct"].map((label) => button(label, "pick-period", "outlined")).join("")}</div>`);
    return modal("Choose a month", hint("2026") + `<div class="calendar-months">${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].map((month, index) => button(month, "pick-period", "", index > 9 ? "disabled" : "")).join("")}</div>`);
  }
  return "";
}
function renderOverlay() {
  const dialog = state.dialog;
  $("#overlay-root").innerHTML = `${editorHTML()}${state.phase === "dim" && state.screen === "focus" && !state.editor ? `<div class="dim-surface"><button class="dim-reveal" data-action="reveal" aria-label="Reveal Focus controls"></button><div class="dim-track" role="img" aria-label="Focus progress, 18 minutes 42 seconds remaining"><span></span></div>${iconButton("plus", "Capture thought", "capture")}</div>` : ""}${dialog ? `<div class="dialog-backdrop"><section class="alert-dialog" role="alertdialog" aria-modal="true" aria-labelledby="dialog-title"><h3 id="dialog-title">${dialog.title}</h3><p>${dialog.message}</p><div class="dialog-actions">${dialog.actions.map(([label, action, danger]) => button(label, action, `text-button${danger ? " danger" : ""}`)).join("")}</div></section></div>` : ""}`;
}
function announce(message) { $("#preview-feedback").textContent = message; }
function openEditor(editor) {
  state.editor = editor;
  render();
  requestAnimationFrame(() => $("#draft-text, #project-name, .modal-screen input, .modal-screen button")?.focus({ preventScroll: true }));
}
function showDialog(title, message, actions) {
  state.dialog = { title, message, actions };
  render();
  requestAnimationFrame(() => $(".alert-dialog button")?.focus({ preventScroll: true }));
}
function isDirty() {
  if (!state.editor) return false;
  return state.editor.type === "project" ? JSON.stringify(state.editor.draft) !== state.editor.initial || !!state.editor.scheduled : ["plan", "capture", "editThought"].includes(state.editor.type) && state.editor.text !== (state.editor.initial || "");
}
function closeEditor() {
  if (isDirty()) return showDialog("Discard unsaved changes?", "Your unsaved text will be lost. Anything you have already saved will remain.", [["Keep editing", "keep-editing"], ["Discard draft", "discard-editor", true]]);
  state.editor = null;
  render();
}
function navigate(screen) {
  clearTimeout(dimTimeout);
  if (state.editor && isDirty()) return showDialog("Keep editing your draft?", "Close or save this editor before switching screens.", [["Keep editing", "keep-editing"], ["Discard draft", `discard-go:${screen}`, true]]);
  state.editor = null;
  state.dialog = null;
  state.screen = screen;
  render();
}

function action(command) {
  const [verb, argument] = command.split(":");
  const editor = state.editor;
  if (verb === "go") return navigate(argument);
  if (verb === "reset") {
    clearTimeout(dimTimeout); clearTimeout(undoTimeout);
    data = initialData(); state = { ...state, screen: "focus", phase: "ready", project: "work", projectDetail: null, inactive: false, thoughtFilter: "All", thoughtProject: "all", query: "", range: "Day", periodOffset: 0, statsProject: "all", editor: null, dialog: null, undo: null };
    announce("Sample data reset."); return render();
  }
  if (verb === "close-editor") return closeEditor();
  if (verb === "keep-editing" || verb === "cancel-dialog") { state.dialog = null; render(); return; }
  if (verb === "discard-editor") { state.dialog = null; state.editor = null; render(); return; }
  if (verb === "discard-go") { state.dialog = null; state.editor = null; return navigate(argument); }
  if (verb === "start-focus") { state.phase = "running"; announce("Focus started. The preview timer is frozen at 18:42."); }
  else if (verb === "end-focus") return showDialog("End this focus session?", "Save the time you’ve focused, or discard this session. Your thoughts remain saved.", [["Keep focusing", "cancel-dialog"], ["Discard Session", "discard-session", true], ["Save Session", "save-session"]]);
  else if (verb === "save-session") { state.phase = "breakReady"; data.savedToday += 25; state.dialog = null; announce("Sample session saved. A break waits for you to start it."); }
  else if (verb === "discard-session") { state.phase = "ready"; state.dialog = null; announce("Session discarded. Thoughts remain saved."); }
  else if (verb === "start-break") state.phase = "breakRunning";
  else if (verb === "skip-break" || verb === "end-break") state.phase = "ready";
  else if (verb === "dim") state.phase = "dim";
  else if (verb === "reveal") {
    state.phase = "running"; render(); announce("Controls revealed. Dim Focus returns after five seconds of inactivity.");
    clearTimeout(dimTimeout); dimTimeout = setTimeout(() => { if (state.screen === "focus" && !state.editor && !state.dialog && state.phase === "running") { state.phase = "dim"; render(); } }, 5000); return;
  }
  else if (verb === "plan") return openEditor({ type: "plan", text: "", initial: "", editing: null });
  else if (verb === "save-task") {
    const text = editor.text.trim();
    if (!text) { editor.error = "Enter a task first."; return render(); }
    const candidate = [...data.plan];
    if (editor.editing == null) candidate.push(text); else candidate[editor.editing] = text;
    if (candidate.join("\n").length > 280) { editor.error = "Keep the entire plan within 280 characters."; return render(); }
    data.plan = candidate; editor.text = ""; editor.initial = ""; editor.editing = null; editor.error = ""; announce("Task saved in this preview.");
  }
  else if (verb === "edit-task") { if (isDirty()) return showDialog("Unsaved task", "Save the task you’re writing before editing another one.", [["Keep editing", "keep-editing"]]); editor.text = data.plan[+argument]; editor.initial = editor.text; editor.editing = +argument; }
  else if (verb === "delete-task") return showDialog("Delete task?", "This changes the saved session plan.", [["Cancel", "cancel-dialog"], ["Delete", `confirm-task:${argument}`, true]]);
  else if (verb === "confirm-task") { data.plan.splice(+argument, 1); state.dialog = null; }
  else if (verb === "capture" || verb === "capture-standalone") {
    clearTimeout(dimTimeout);
    const origin = verb === "capture" && ["running", "dim"].includes(state.phase);
    if (state.phase === "dim") state.phase = "running";
    return openEditor({ type: "capture", text: "", initial: "", origin, project: origin ? state.project : state.thoughtProject === "all" ? "unassigned" : state.thoughtProject, projectName: currentProject().name, added: [] });
  }
  else if (verb === "save-thought") {
    const text = editor.text.trim();
    if (!text || text.length > 500) { editor.error = "Enter between 1 and 500 characters."; return render(); }
    if (editor.type === "editThought") { data.thoughts.find((thought) => thought.id === editor.id).text = text; state.editor = null; }
    else { const thought = { id: Date.now(), text, project: editor.project, done: false }; data.thoughts.unshift(thought); editor.added.push(thought.id); editor.text = ""; editor.error = ""; }
    announce("Thought saved in this preview. The focus timer keeps running.");
  }
  else if (verb === "edit-thought") { const thought = data.thoughts.find((item) => item.id === +argument); return openEditor({ type: "editThought", text: thought.text, initial: thought.text, id: thought.id, project: thought.project, origin: false }); }
  else if (verb === "delete-thought") return showDialog("Delete thought?", "You can Undo briefly after deleting.", [["Cancel", "cancel-dialog"], ["Delete", `confirm-thought:${argument}`, true]]);
  else if (verb === "confirm-thought") {
    state.undo = data.thoughts.find((item) => item.id === +argument); data.thoughts = data.thoughts.filter((item) => item.id !== +argument); state.dialog = null;
    clearTimeout(undoTimeout); undoTimeout = setTimeout(() => { state.undo = null; render(); }, 10000);
  }
  else if (verb === "undo") { data.thoughts.unshift(state.undo); state.undo = null; clearTimeout(undoTimeout); }
  else if (verb === "thought-filter") state.thoughtFilter = argument;
  else if (verb === "project-thoughts" || verb === "detail-thoughts") { state.thoughtProject = verb === "detail-thoughts" ? state.projectDetail : state.project; state.screen = "thoughts"; }
  else if (verb === "select-project" || verb === "thought-project" || verb === "stats-project") return showDialog("Choose a project", "Select which project to show.", [...(verb !== "select-project" ? [["All projects", `filter-project:${verb}|all`]] : []), ...(verb === "thought-project" ? [["Unassigned", `filter-project:${verb}|unassigned`]] : []), ...data.projects.filter((project) => verb !== "select-project" || project.status === "Ongoing").map((project) => [project.name, `filter-project:${verb}|${project.id}`])]);
  else if (verb === "filter-project") { const [target, id] = argument.split("|"); if (target === "select-project") state.project = id; else if (target === "stats-project") state.statsProject = id; else state.thoughtProject = id; state.dialog = null; }
  else if (verb === "project") state.projectDetail = argument;
  else if (verb === "all-projects") state.projectDetail = null;
  else if (verb === "inactive") state.inactive = !state.inactive;
  else if (verb === "use-project") { state.project = state.projectDetail; state.screen = "focus"; state.phase = "ready"; }
  else if (verb === "new-project" || verb === "edit-project") {
    const draft = verb === "edit-project" ? structuredClone(data.projects.find((project) => project.id === state.projectDetail)) : { id: `project-${Date.now()}`, name: "", status: "Ongoing", focus: 25, short: 5, long: 15, daily: null, weekly: null };
    return openEditor({ type: "project", draft, initial: JSON.stringify(draft), isNew: verb === "new-project" });
  }
  else if (verb === "save-project") {
    if (!editor.draft.name.trim()) { editor.error = "Enter a project name."; return render(); }
    if (["focus", "short", "long"].some((key) => editor.draft[key] < (key === "focus" ? 10 : 1) || editor.draft[key] > 60) || editor.draft.daily?.some((minutes) => !Number.isInteger(minutes) || minutes < 0 || minutes > 1440) || (editor.draft.weekly != null && (!Number.isInteger(editor.draft.weekly) || editor.draft.weekly < 1 || editor.draft.weekly > 10080))) { editor.error = "Check the timer durations and goal limits."; return render(); }
    if (editor.isNew) { data.projects.push(editor.draft); state.project = editor.draft.id; state.phase = "ready"; state.screen = "focus"; }
    else data.projects = data.projects.map((project) => project.id === editor.draft.id ? editor.draft : project);
    state.editor = null; announce("Project settings saved in this preview.");
  }
  else if (verb === "schedule-goal") {
    const date = $("#scheduled-date").value; const target = $("#scheduled-goal").value;
    if (!date || new Date(`${date}T12:00:00`).getDay() !== 1 || date < "2026-11-02") { editor.error = "Choose a Monday after the current week."; return render(); }
    editor.scheduled = `${date}: ${target ? `${target} min` : "Off"}`; announce("Scheduled change added to this project draft.");
  }
  else if (verb === "merge") return showDialog("Merge project", "Sessions and thoughts move to the destination. Destination goals are kept. Conflicting plans must be resolved first. This preview does not perform a merge.", [["Close", "cancel-dialog"]]);
  else if (verb === "range") { state.range = argument; state.periodOffset = 0; }
  else if (verb === "previous") state.periodOffset = -1;
  else if (verb === "next" || verb === "current-period") state.periodOffset = 0;
  else if (verb === "period-picker") return openEditor({ type: "period" });
  else if (verb === "pick-period") { state.periodOffset = -1; state.editor = null; announce("Historical period selected for this design example."); }
  else if (verb === "stats-details") return openEditor({ type: "details" });
  else if (verb === "day") return openEditor({ type: "day" });
  else if (verb === "consistency") return openEditor({ type: "consistency" });
  else if (verb === "session") return openEditor({ type: "session" });
  else if (verb === "promote-plan") return showDialog("Replace the current session plan?", "This next step becomes the project’s plan for its next focus session.", [["Cancel", "cancel-dialog"], ["Replace plan", "confirm-promote"]]);
  else if (verb === "confirm-promote") { data.plan = ["Review the revised figures"]; state.dialog = null; announce("Next-session plan replaced in the sample."); }
  else if (verb === "delete-session") return showDialog("Delete session?", "Its focus time is removed from statistics. Thoughts remain saved. Session deletion is illustrative here.", [["Keep session", "cancel-dialog"], ["Close example", "discard-editor"]]);
  else if (verb === "toggle") data.settings[argument] = !data.settings[argument];
  else if (verb === "toggle-theme") state.theme = state.theme === "light" ? "dark" : "light";
  else if (verb === "sound") return showDialog(argument === "focus" ? "Focus completion sound" : "Break completion sound", "Use System default, Silent, or a bundled sound.", ["System default", "Silent", "Bell", "Chime", "Soft tap", "Digital", "Mellow", "Ripple", "Wood"].map((sound) => [sound, `set-sound:${argument}|${sound}`]));
  else if (verb === "set-sound") { const [kind, sound] = argument.split("|"); data.settings[kind === "focus" ? "focusSound" : "breakSound"] = sound; state.dialog = null; }
  else if (verb === "test-alert") { announce(data.settings.sound ? "Design preview only. The app uses a system notification to test your selected sound." : "Sound is off."); return; }
  else if (["focus-duration", "break-duration", "long-duration", "cycle"].includes(verb)) return showDialog("Timer duration", `${verb === "focus-duration" ? "Focus accepts 10–60 minutes" : verb === "cycle" ? "The long break interval accepts 1–12 focus sessions" : "Breaks accept 1–60 minutes"}. The Android app saves this choice before dismissing its editor.`, [["Close", "cancel-dialog"]]);
  else if (verb === "notification-settings") return showDialog("Android notification settings", "The real app opens its Android system notification settings. This preview stays in your browser.", [["Close", "cancel-dialog"]]);
  else if (verb === "permission") return showDialog("Allow Pomodoro to send notifications?", "Illustrative permission request. In the app this is an Android-owned dialog, requested when starting a timer or enabling notifications.", [["Don’t allow", "cancel-dialog"], ["Allow", "cancel-dialog"]]);
  else if (verb === "shortcut") { announce("Preview only. The app asks your Android launcher to pin this shortcut."); return; }
  else if (verb === "export") { announce("Export example: Pomodoro-Backup.json. The real app opens Android’s document picker; this preview creates no file."); return; }
  else if (verb === "import") { if (running()) return; return showDialog("Replace all app data?", "Sample backup: 3 projects, 21 sessions, and 3 thoughts. Current data will be replaced. No files or real app data are changed in this preview.", [["Cancel", "cancel-dialog"], ["Replace with backup", "confirm-import", true]]); }
  else if (verb === "confirm-import") { state.dialog = null; announce("Restore confirmation reviewed. Your real app data is unchanged."); }
  render();
}

document.addEventListener("click", (event) => {
  const target = event.target.closest("[data-action]");
  if (!target || target.disabled) return;
  action(target.dataset.action);
});
document.addEventListener("input", (event) => {
  const target = event.target;
  if (target.id === "thought-search") { state.query = target.value; $("#thought-results").innerHTML = thoughtResults(); }
  else if (target.id === "draft-text" && state.editor) { state.editor.text = target.value; if ($("#character-count")) $("#character-count").textContent = target.value.length; }
  else if (target.id === "project-name" && state.editor) state.editor.draft.name = target.value;
  else if (target.dataset.projectNumber) state.editor.draft[target.dataset.projectNumber] = +target.value;
  else if (target.dataset.goalDay) { state.editor.draft.daily ||= [0, 0, 0, 0, 0, 0, 0]; state.editor.draft.daily[+target.dataset.goalDay] = +target.value; }
  else if (target.id === "weekly-goal" && state.editor) state.editor.draft.weekly = +target.value;
});
document.addEventListener("change", (event) => {
  const target = event.target;
  if (target.id === "appearance") state.theme = target.value;
  else if (target.id === "large-text") state.large = target.checked;
  else if (target.id === "scenario") { clearTimeout(dimTimeout); state.phase = target.value; state.screen = "focus"; state.editor = null; state.dialog = null; }
  else if (target.dataset.thought) { data.thoughts.find((thought) => thought.id === +target.dataset.thought).done = target.checked; }
  else if (target.id === "capture-project" && state.editor) state.editor.project = target.value;
  else if (target.id === "project-status" && state.editor) state.editor.draft.status = target.value;
  else return;
  render();
});
document.addEventListener("keydown", (event) => {
  const overlay = $(".alert-dialog") || $(".modal-screen");
  if (event.key === "Escape") {
    if (state.dialog) { state.dialog = null; render(); }
    else if (state.editor) closeEditor();
    else if (state.phase === "dim") action("reveal");
    else if (state.screen === "projects" && state.projectDetail) { state.projectDetail = null; render(); }
    else if (!["focus", "thoughts", "stats"].includes(state.screen)) navigate("focus");
  }
  if (event.key === "Tab" && overlay) {
    const focusable = [...overlay.querySelectorAll('button:not(:disabled), input, select, textarea, summary, [tabindex="0"]')].filter((element) => element.getClientRects().length);
    const first = focusable[0]; const last = focusable.at(-1);
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
  }
});
render();
