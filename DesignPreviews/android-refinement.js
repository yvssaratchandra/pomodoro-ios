(() => {
  "use strict";

  const variant = new URLSearchParams(window.location.search).get("variant") || "current";
  if (variant === "current" || !["ios", "proposed"].includes(variant)) return;

  const original = {
    render: window.render,
    action: window.action,
    editorHTML: window.editorHTML,
    alertsScreen: window.alertsScreen
  };
  paths.thoughts = '<path d="M4 4h16v12H9l-5 4z"/><path d="M8 8h8M8 12h5"/>';
  paths.more = '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>';
  const labelForPhase = () => ({ ready: "Focus", running: "Focusing", dim: "Focusing", breakReady: "Break", breakRunning: "Break", empty: "Focus" })[state.phase] || "Focus";
  const group = (title, content, extra = "") => `<section class="grouped-section ${extra}"><h2>${title}</h2><div class="grouped-list">${content}</div></section>`;
  const row = (title, detail, command, accessory = "chevron") => `<button class="row grouped-row" data-action="${command}"><span>${title}</span><span class="row-accessory">${detail || ""}${accessory === "chevron" ? icon("chevron") : ""}</span></button>`;
  const listButton = (label, command, className = "") => button(label, command, `row grouped-row ${className}`);
  const title = (text) => `<h1 class="large-title">${text}</h1>`;
  const selectedFilter = (items, selected, actionPrefix) => `<div class="chips" role="group">${items.map((item) => button(item, `${actionPrefix}:${item}`, "chip", `aria-pressed="${selected === item}"`)).join("")}</div>`;

  function refinedFocusScreen() {
    const project = currentProject();
    const planRow = `<button class="plan-summary" data-action="plan"><span>${data.plan.length ? `Session plan · ${data.plan.length} tasks` : "Plan this session"}</span>${icon("chevron")}</button>`;
    const timerControl = (time, kind, progress, command, accessibleLabel) => button(`${focusTimer(time, kind, progress)}<span class="timer-pencil" aria-hidden="true">${icon("edit")}</span>`, command, "focus-timer-button", `aria-label="${accessibleLabel}" title="${accessibleLabel}"`);

    if (state.phase === "empty") {
      return `<div class="focus-screen empty-state"><div class="empty-symbol">${icon("projects")}</div><h2>Make space for focused work</h2><p class="muted">Create a project, then begin a focus session.</p>${button("Create Project", "new-project", "primary timer-button")}</div>`;
    }
    if (state.phase === "running" || state.phase === "dim") {
      return `<div class="focus-screen focus-running"><h1 class="project-title">${escapeHTML(project.name)}</h1>${focusTimer("18:42", "Focus", .748)}${button("End Focus", "end-focus", "destructive-action")}${planRow}${button("Add a thought", "capture", "text-button")}</div>`;
    }
    if (state.phase === "breakReady") {
      return `<div class="focus-screen break-ready"><h1 class="project-title">Focus saved</h1>${timerControl("05:00", "Short break", 1, "break-duration", "Edit short break duration")}${button("Start Break", "start-break", "primary timer-button sage")}${button("Skip Break", "skip-break", "text-button")}${planRow}</div>`;
    }
    if (state.phase === "breakRunning") {
      return `<div class="focus-screen break-running"><h1 class="project-title">${escapeHTML(project.name)}</h1>${focusTimer("03:18", "Short break", .66)}${button("End Break", "end-break", "outlined sage")}${planRow}${button("Review thoughts", "project-thoughts", "text-button sage")}</div>`;
    }

    return `<div class="focus-screen focus-ready"><button class="project-selector" data-action="select-project">${icon("projects")}<span>${escapeHTML(project.name)}</span>${icon("down")}</button>${timerControl(`${project.focus}:00`, "Focus", 1, "focus-duration", "Edit focus duration")}${button("Start Focus", "start-focus", "primary timer-button")}${planRow}</div>`;
  }

  function refinedThoughtsScreen() {
    const filter = data.projects.find((project) => project.id === state.thoughtProject)?.name || (state.thoughtProject === "unassigned" ? "Unassigned" : "All projects");
    const thoughts = filteredThoughts().map((thought) => thoughtRow(thought).replace('class="thought-row"', 'class="thought-row ios-thought-row"')).join("") || `<p class="empty-list-state">No matching thoughts.</p>`;
    return `<div class="thoughts-screen">${title("Thoughts")}<input class="search-field compact-search" id="thought-search" type="search" value="${escapeHTML(state.query)}" placeholder="Search" aria-label="Search thoughts">${selectedFilter(["All", "Open", "Done"], state.thoughtFilter, "thought-filter")}<div class="grouped-list thought-list" id="thought-results">${thoughts}</div><span class="sr-only">Project filter: ${escapeHTML(filter)}</span></div>`;
  }

  function compactHistoryRows(count = 5) {
    const entries = [
      ["Draft the methods section", "10:30", "25 min"],
      ["Review experiment notes", "09:45", "25 min"],
      ["Prepare the next run", "08:50", "25 min · Ended early"],
      ["Check the latest results", "Yesterday", "25 min"],
      ["Write a short summary", "Yesterday", "25 min"]
    ];
    return entries.slice(0, count).map(([text, time, length], index) => `<button class="history-item grouped-row" data-action="session:${index}"><span><strong>${escapeHTML(currentProject().name)}</strong><small>${escapeHTML(text)}</small></span><span class="history-meta">${time} · ${length}</span></button>`).join("");
  }

  function refinedStatsScreen() {
    const values = periodValues();
    const total = state.range === "Day" ? ["all", "work"].includes(state.statsProject) ? data.savedToday : 0 : state.range === "All" ? state.statsProject === "work" ? 525 : state.statsProject === "reading" ? 150 : state.statsProject === "all" ? 675 : 0 : values.reduce((sum, value) => sum + value, 0);
    const project = data.projects.find((item) => item.id === state.statsProject);
    const goal = state.range === "Day" && project?.daily ? project.daily[5] : state.range === "Week" && project?.weekly ? project.weekly : null;
    const bars = ["Week", "Month"].includes(state.range) ? group("Daily focus", `<div class="chart" role="img" aria-label="Saved focus by day. Open Details for all values.">${values.map((value, index) => `<div class="bar-column"><button class="bar" data-action="day:${index}" aria-label="Day ${index + 1}: ${value} minutes" style="--height:${Math.max(2, value / Math.max(75, ...values) * 100)}%"></button>${state.range === "Week" ? `<small>${["M", "T", "W", "T", "F", "S", "S"][index]}</small>` : ""}</div>`).join("")}</div><p class="muted">Saved focus across this ${state.range.toLowerCase()}</p>${button("Details", "stats-details", "text-button")}`) : "";
    const currentProjectName = project?.name || "All projects";
    return `<div class="stats-screen">${title("Stats")}${selectedFilter(["Day", "Week", "Month", "All"], state.range, "range")}${state.range !== "All" ? `<div class="range-navigation">${button("‹", "previous", "period-arrow", 'aria-label="Previous period"')}${button(periodTitle(), "period-picker", "period-label")}${button("›", "next", "period-arrow", `aria-label="Next period" ${state.periodOffset >= 0 ? "disabled" : ""}`)}</div>${state.periodOffset < 0 ? button(`Return to current ${state.range.toLowerCase()}`, "current-period", "text-button") : ""}` : ""}${group("Focus time", `<div class="stats-total">${duration(total)}</div>${goal ? `<p class="muted">of ${duration(goal)} goal · ${escapeHTML(currentProjectName)}</p><div class="progress-track"><span style="--progress:${Math.min(100, total / goal * 100)}%"></span></div>` : ""}${running() && state.phase !== "breakRunning" && ["all", state.project].includes(state.statsProject) ? `<p class="muted">1 session in progress · not included yet</p>` : ""}`, "stats-summary")}${bars}${group("Recent sessions", total === 0 ? `<p class="muted">No saved sessions for this selection.</p>` : compactHistoryRows(5))}</div>`;
  }

  function projectListRows(projects) {
    return projects.map(project => `<button class="row grouped-row project-list-row" data-action="project:${project.id}"><span>${icon("projects")}${escapeHTML(project.name)}</span>${icon("chevron")}</button>`).join("") || `<p class="muted">No projects</p>`;
  }

  function projectDetailScreen(project) {
    const savedTotal = project.id === "work" ? "8 hr 45 min" : project.id === "reading" ? "2 hr 30 min" : "0 min";
    const weekly = project.weekly ? `${project.id === "work" ? "4 hr 50 min" : "1 hr 35 min"} of ${duration(project.weekly)}` : "No weekly goal";
    const recent = ["Draft the methods section", "Review experiment notes", "Prepare the next run"].map((text, index) => `<button class="history-item grouped-row" data-action="session:${index}"><span><strong>${escapeHTML(text)}</strong><small>${["10:30", "09:45", "08:50"][index]} · 25 min</small></span>${icon("chevron")}</button>`).join("");
    const planLabel = data.plan.length ? `${data.plan.length} ${data.plan.length === 1 ? "task" : "tasks"}` : "Add a session plan";
    const thoughtCount = data.thoughts.filter((thought) => thought.project === project.id).length;
    const menu = state.projectMenu ? `<div class="project-menu grouped-list" role="group" aria-label="Project actions">${listButton("Project settings and goals", "edit-project")}${listButton("Use for Focus", "use-project")}${listButton("Review thoughts", "detail-thoughts")}${listButton("Merge into another project", "merge", "destructive-action")}</div>` : "";
    const summary = `<div class="row grouped-row summary-row"><span>Saved focus</span><strong>${savedTotal}</strong></div><div class="row grouped-row summary-row"><span>This week</span><strong>${weekly}</strong></div><div class="row grouped-row summary-row"><span>Focus duration</span><strong>${duration(project.focus)}</strong></div>${project.weekly ? `<div class="grouped-row summary-progress"><div class="progress-track"><span style="--progress:48%"></span></div></div>` : ""}`;
    return `<div class="project-screen project-detail">${title(escapeHTML(project.name))}<p class="project-detail-status">${escapeHTML(project.status)}</p>${group("Summary", summary)}${group("Session plan", `<button class="row grouped-row" data-action="plan"><span>${planLabel}</span>${icon("chevron")}</button>`)}${group("Thoughts", `<button class="row grouped-row" data-action="detail-thoughts"><span>${thoughtCount} ${thoughtCount === 1 ? "thought" : "thoughts"}</span>${icon("chevron")}</button>`)}${group("Recent sessions", recent)}${menu}</div>`;
  }

  function refinedProjectScreen() {
    const project = data.projects.find((item) => item.id === state.projectDetail);
    if (project) return projectDetailScreen(project);
    const active = data.projects.filter((item) => item.status === "Ongoing");
    const onHold = data.projects.filter((item) => item.status === "On hold");
    const completed = data.projects.filter((item) => item.status === "Completed");
    return `<div class="project-screen">${title("Projects")}<div class="project-groups">${group(`Active (${active.length})`, projectListRows(active))}<section class="grouped-section"><button class="group-toggle" data-action="toggle-inactive:hold"><span>On Hold (${onHold.length})</span>${icon(state.showOnHold ? "down" : "chevron")}</button>${state.showOnHold ? `<div class="grouped-list">${projectListRows(onHold)}</div>` : ""}</section><section class="grouped-section"><button class="group-toggle" data-action="toggle-inactive:completed"><span>Completed (${completed.length})</span>${icon(state.showCompleted ? "down" : "chevron")}</button>${state.showCompleted ? `<div class="grouped-list">${projectListRows(completed)}</div>` : ""}</section></div></div>`;
  }

  function settingsHomeScreen() {
    const settings = data.settings;
    return `<div class="settings-screen">${title("Settings")}${group("Projects", row("Projects & goals", "", "go:projects"))}${group("Preferences", row("Timer defaults", "", "settings-page:timer") + row("Sounds & haptics", "", "settings-page:sounds") + row("Appearance", state.theme === "dark" ? "Dark" : "Light", "settings-page:appearance"))}${group("Access", row("Quick Start", "", "shortcut") + row("Lock Screen privacy", "", "settings-page:privacy"))}${group("Data & support", row("Backup & restore", "", "settings-page:backup") + row("Help", "", "settings-page:help"))}<p class="settings-footnote">All app data stays on this phone.</p></div>`;
  }

  function settingsSubpage(page) {
    const settings = data.settings;
    if (page === "timer") return `<div class="settings-screen">${title("Timer defaults")}${group("Durations", row("Focus", "25 min", "focus-duration") + row("Short break", "5 min", "break-duration") + row("Long break", "15 min", "long-duration") + row("Long break after", "4 sessions", "cycle"))}${group("Consistency", row("Weekly focused-day target", "4 days", "consistency") + `<p class="row grouped-row muted">At least 10 minutes of saved focus makes a focused day.</p>`)}</div>`;
    if (page === "sounds") return `<div class="settings-screen">${title("Sounds & haptics")}${group("Completion alerts", switchRow("Notification sounds", settings.sound, "toggle:sound") + row("Focus complete", settings.focusSound, "sound:focus") + row("Test focus alert", "", "test-alert") + row("Break complete", settings.breakSound, "sound:break") + row("Test break alert", "", "test-alert") + switchRow("Haptics", settings.haptics, "toggle:haptics"))}<p class="settings-footnote">Completion sounds use system notifications and ${variant === "ios" ? "your iPhone’s Ringtone and Alerts volume" : "Android notification volume and channel settings"}.</p></div>`;
    if (page === "appearance") return `<div class="settings-screen">${title("Appearance")}${group("Theme", row("Theme", state.theme === "dark" ? "Dark" : "Light", "toggle-theme"))}</div>`;
    if (page === "privacy") return `<div class="settings-screen">${title("Lock Screen privacy")}${group("Show on the Lock Screen", switchRow("Project name", settings.projectVisible, "toggle:projectVisible") + switchRow("Session plan", settings.planVisible, "toggle:planVisible"))}<p class="settings-footnote">Thoughts and next steps stay inside the app.</p></div>`;
    if (page === "backup") return `<div class="settings-screen">${title("Backup & restore")}<p class="settings-footnote">Comparison prototype: backup and restore use the Android document picker in the current app.</p>${backupScreen()}</div>`;
    return `<div class="settings-screen">${title("Help")}${group("Pomodoro", `<p class="grouped-row">Focus sessions, project goals, thoughts, and statistics stay together on this phone.</p>`)}</div>`;
  }

  function refinedSettingsScreen() {
    return state.settingsPage ? settingsSubpage(state.settingsPage) : settingsHomeScreen();
  }

  function refinedAlertsScreen() {
    if (variant !== "ios") return original.alertsScreen();
    return `<div class="settings-screen">${title("Android-only integration")}${group("Notifications", `<p class="row grouped-row">Android notification channels and exact alarms have no equivalent screen in this iOS reference.</p>`)}</div>`;
  }

  function refinedEditorHTML() {
    const editor = state.editor;
    if (!editor || editor.type !== "project") return original.editorHTML();
    const draft = editor.draft;
    const page = editor.projectPage || "root";
    const pageTitles = { root: editor.isNew ? "New Project" : "Project settings", timer: "Timer settings", goals: "Goals", daily: "Daily goal", weekly: "Weekly goal" };
    const nested = page !== "root";
    const inputNumber = (label, key, min, max) => `<label class="field">${label}<input type="number" data-project-number="${key}" min="${min}" max="${max}" value="${draft[key]}"></label>`;
    const dayFields = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].map((day, index) => `<label class="row goal-row" for="goal-${index}"><span>${day}</span><input aria-label="${day} goal in minutes" id="goal-${index}" data-goal-day="${index}" type="number" min="0" max="1440" value="${draft.daily?.[index] || 0}"></label>`).join("");
    let body = "";
    if (page === "root") {
      body = `<label class="field">Project name<input id="project-name" value="${escapeHTML(draft.name)}" maxlength="100" placeholder="Project name"></label>${!editor.isNew ? `<label class="field">Status<select id="project-status">${["Ongoing", "On hold", "Completed"].map((status) => `<option ${draft.status === status ? "selected" : ""}>${status}</option>`).join("")}</select></label>` : ""}${group("Project options", row("Timer settings", "", "project-editor-page:timer") + row("Daily and weekly goals", "", "project-editor-page:goals"))}`;
    } else if (page === "timer") {
      body = `${group("Durations", inputNumber("Focus minutes", "focus", 10, 60) + inputNumber("Short break minutes", "short", 1, 60) + inputNumber("Long break minutes", "long", 1, 60))}`;
    } else if (page === "goals") {
      body = group("Goals", row("Daily goal", draft.daily ? "Custom schedule" : "Off", "project-editor-page:daily") + row("Weekly goal", draft.weekly ? duration(draft.weekly) : "Off", "project-editor-page:weekly"));
    } else if (page === "daily") {
      body = group("Daily goal", `<p class="muted">Changes take effect today. Earlier days retain their recorded goals.</p>${dayFields}<p class="muted">0 min means a rest day.</p>`);
    } else {
      body = group("Weekly goal", `<label class="field">Minutes per week<input id="weekly-goal" type="number" min="1" max="10080" value="${draft.weekly || 300}"></label><p class="muted">Independent of the daily schedule.</p>`) + group("Scheduled changes", `<label class="field">Monday<input id="scheduled-date" type="date" value="2026-11-02" min="2026-11-02"></label><label class="field">Weekly minutes, or blank for off<input id="scheduled-goal" type="number" min="1" max="10080" placeholder="Off"></label>${button("Add scheduled change", "schedule-goal")}${editor.scheduled ? `<p class="muted">${escapeHTML(editor.scheduled)}</p>` : ""}`);
    }
    if (editor.error) body += `<p class="inline-error">${escapeHTML(editor.error)}</p>`;
    const save = button("Save", "save-project", "text-button");
    return modal(pageTitles[page], `<div class="project-editor-page">${body}</div>`, "", nested ? "Back" : "Cancel", nested ? "project-editor-back" : "close-editor", save);
  }

  function toolbarHTML() {
    if (state.screen === "focus") {
      const left = `${iconButton("settings", "Settings", "go:settings")}${["running", "dim"].includes(state.phase) ? iconButton("dim", "Dim Focus", "dim") : ""}`;
      return `<header class="toolbar refined-toolbar"><div class="toolbar-leading">${left}</div><h2 class="toolbar-title">${labelForPhase()}</h2><div class="toolbar-trailing">${iconButton("projects", "Projects", "go:projects")}</div></header>`;
    }
    if (state.screen === "thoughts") {
      return `<header class="toolbar refined-toolbar"><div class="toolbar-leading">${iconButton("projects", "Filter thoughts by project", "thought-project")}</div><h2 class="toolbar-title"></h2><div class="toolbar-trailing">${iconButton("plus", "Add a thought", "capture-standalone")}</div></header>`;
    }
    if (state.screen === "stats") {
      return `<header class="toolbar refined-toolbar"><div class="toolbar-leading">${iconButton("projects", "Filter statistics by project", "stats-project")}</div><h2 class="toolbar-title"></h2><div class="toolbar-trailing">${iconButton("calendar", "Consistency", "consistency")}</div></header>`;
    }
    if (state.screen === "projects") {
      const leading = state.projectDetail ? iconButton("back", "All projects", "projects-back") : iconButton("back", "Back to Focus", "go:focus");
      const trailing = state.projectDetail ? iconButton("more", "Project actions", "project-menu") : iconButton("plus", "Create project", "new-project");
      return `<header class="toolbar refined-toolbar"><div class="toolbar-leading">${leading}</div><h2 class="toolbar-title"></h2><div class="toolbar-trailing">${trailing}</div></header>`;
    }
    if (state.screen === "settings") {
      const nested = !!state.settingsPage;
      const leading = iconButton("back", nested ? "Settings" : "Back to Focus", nested ? "settings-back" : "settings-dismiss");
      return `<header class="toolbar refined-toolbar"><div class="toolbar-leading">${leading}</div><h2 class="toolbar-title"></h2><div class="toolbar-trailing"></div></header>`;
    }
    const back = iconButton("back", "Back to Focus", "go:focus");
    return `<header class="toolbar refined-toolbar"><div class="toolbar-leading">${back}</div><h2 class="toolbar-title">${state.screen === "backup" ? "Backup & restore" : ""}</h2><div class="toolbar-trailing"></div></header>`;
  }

  function refinedRender(...args) {
    document.body.classList.add("refined");
    document.body.classList.toggle("ios-reference", variant === "ios");
    original.render.apply(this, args);
    const app = document.querySelector("#app");
    const oldToolbar = app?.querySelector(":scope > .toolbar");
    if (oldToolbar) oldToolbar.outerHTML = toolbarHTML();
    if (!["focus", "thoughts", "stats"].includes(state.screen)) app.querySelector('.bottom-tabs [data-action="go:focus"]')?.setAttribute("aria-current", "page");
  }

  function refinedAction(command) {
    const [verb, argument] = command.split(":");
    if (verb === "toggle-inactive") { const key = argument === "hold" ? "showOnHold" : "showCompleted"; state[key] = !state[key]; return render(); }
    if (verb === "settings-page") { state.settingsPage = argument; state.screen = "settings"; return render(); }
    if (verb === "settings-back") { state.settingsPage = null; return render(); }
    if (verb === "settings-dismiss") { state.settingsPage = null; return original.action("go:focus"); }
    if (verb === "project-editor-page" && state.editor?.type === "project") { state.editor.projectPage = argument; return render(); }
    if (verb === "project-editor-back" && state.editor?.type === "project") { state.editor.projectPage = ["daily", "weekly"].includes(state.editor.projectPage) ? "goals" : "root"; return render(); }
    if (verb === "projects-back") { state.projectDetail = null; state.projectMenu = false; return render(); }
    if (verb === "project-menu") { state.projectMenu = !state.projectMenu; return render(); }
    if (verb === "go") {
      if (argument === "settings") state.settingsPage = null;
      else if (state.screen === "settings") state.settingsPage = null;
    }
    if (verb === "project") state.projectMenu = false;
    if (verb === "new-project") {
      const returnScreen = state.screen;
      const result = original.action(command);
      if (state.editor?.type === "project") {
        state.editor.projectPage = "root";
        state.editor.returnScreen = returnScreen;
      }
      return result;
    }
    if (verb === "save-project" && state.editor?.type === "project") {
      const draft = state.editor.draft;
      const isNew = state.editor.isNew;
      const returnScreen = state.editor.returnScreen;
      const result = original.action(command);
      if (isNew && !state.editor && returnScreen === "projects") {
        state.screen = "projects";
        state.projectDetail = draft.id;
        render();
      }
      return result;
    }
    if (verb === "session" && state.screen === "projects" && state.projectDetail) state.project = state.projectDetail;
    return original.action(command);
  }

  document.addEventListener("keydown", event => {
    if (event.key !== "Escape" || state.dialog) return;
    if (state.editor?.type === "project" && ![undefined, "root"].includes(state.editor.projectPage)) {
      event.preventDefault(); event.stopImmediatePropagation(); action("project-editor-back");
    } else if (!state.editor && state.screen === "settings" && state.settingsPage) {
      event.preventDefault(); event.stopImmediatePropagation(); action("settings-back");
    }
  }, true);

  window.focusScreen = refinedFocusScreen;
  window.thoughtsScreen = refinedThoughtsScreen;
  window.projectScreen = refinedProjectScreen;
  window.settingsScreen = refinedSettingsScreen;
  window.statsScreen = refinedStatsScreen;
  window.alertsScreen = refinedAlertsScreen;
  window.editorHTML = refinedEditorHTML;
  window.render = refinedRender;
  window.action = refinedAction;
  render();
})();
