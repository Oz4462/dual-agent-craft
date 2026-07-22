/* Dual-Craft Team-Cockpit — Client (DE) */
(() => {
  "use strict";

  const $ = (sel) => document.querySelector(sel);
  const body = $(".body");
  const chatScroll = $("#chatScroll");
  const liveLog = $("#liveLog");
  const input = $("#input");
  const btnSend = $("#btnSend");
  const btnPreview = $("#btnPreview");
  const btnCancel = $("#btnCancel");
  const btnRefresh = $("#btnRefresh");
  const btnClear = $("#btnClear");
  const optionsPanel = $("#optionsPanel");
  const btnOptions = $("#btnOptions");

  let activeRunId = null;
  /** Run currently attached to SSE (may differ from activeRunId while reconnecting). */
  let streamingRunId = null;
  let es = null;
  let statusTimer = null;
  let statusPollMs = 4000;
  let hasMessages = false;
  let msgAnimIndex = 0;
  /** Dedup activity feed lines (phase / agent milestones). */
  const activitySeen = new Set();
  let liveFollow = true;

  const DE = {
    ready: "Bereit",
    queued: "Warteschlange",
    running: "Läuft",
    succeeded: "Erfolgreich",
    failed: "Fehlgeschlagen",
    cancelled: "Abgebrochen",
    lockFree: "Sperre frei",
    lockHeld: "Gesperrt",
    lockStale: "Verwaiste Sperre",
    you: "Du",
    orchestrator: "Orchestrator",
    system: "System",
    workStream: "Live-Arbeit (CLI)",
    activity: "Ereignis",
    thinking: "denkt nach…",
    logCopy: "Log kopiert",
    followOn: "Auto-Scroll an",
    followOff: "Auto-Scroll aus",
    noCli: "Noch kein CLI-Scan",
    noGates: "Noch keine Gate-Ergebnisse",
    readyTag: "bereit",
    missingTag: "fehlt",
    noAssign: "Noch keine Zuweisung",
    whoEmpty: "Vorschau starten, um die Matrix zu sehen.",
    workEmpty: "Erscheint bei aktiver Team-Arbeit.",
    idleLog: "ruhe",
    profile: "Profil",
    wait: "warte",
    done: "fertig",
    live: "live",
    fail: "fehler",
    phase: "Phase",
    role: "Rolle",
    agent: "Agent",
    clearConfirm: "Chat-Verlauf auf diesem Rechner leeren?",
    apiFail: "API nicht erreichbar",
    startHint: "Starte mit `./dual-chat.sh` und öffne http://127.0.0.1:8787/",
    error: "Fehler",
    modeNone: "Kein aktiver Lauf.",
    modeReal: "Echte Ausführung",
    modeDry: "Dry-Run — kein Code",
    modeSkipMerge: "Kein main-Merge",
    modeMerge: "Merge nach main",
    modeTeam: "Team-Arbeit",
    modeSolo: "Solo",
    modeFortify: "Härten",
    persistOk: "Alles gespeichert",
    persistWarn: "Warnung",
    persistDry: "Dry-Run — nichts zu speichern",
    persistCommits: "team-Commits",
    persistDirty: "uncommittete Dateien",
  };

  const PHASE_NAMES = {
    C: "Contract",
    W: "Team-Arbeit",
    G: "Guards",
    A: "Assess",
    F: "Härten",
    T: "Gate",
  };

  // --- Ambient particles --------------------------------------------------
  function initFx() {
    const canvas = $("#fxCanvas");
    if (!canvas || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) return;

    let w = 0;
    let h = 0;
    let raf = 0;
    const particles = [];
    const N = 48;

    function resize() {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = window.innerWidth;
      h = window.innerHeight;
      canvas.width = Math.floor(w * dpr);
      canvas.height = Math.floor(h * dpr);
      canvas.style.width = w + "px";
      canvas.style.height = h + "px";
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function seed() {
      particles.length = 0;
      for (let i = 0; i < N; i++) {
        particles.push({
          x: Math.random() * w,
          y: Math.random() * h,
          r: 0.6 + Math.random() * 1.8,
          vx: (Math.random() - 0.5) * 0.25,
          vy: (Math.random() - 0.5) * 0.25,
          a: 0.15 + Math.random() * 0.45,
          hue: Math.random() > 0.55 ? 265 : 190,
        });
      }
    }

    function tick() {
      ctx.clearRect(0, 0, w, h);
      for (const p of particles) {
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < -10) p.x = w + 10;
        if (p.x > w + 10) p.x = -10;
        if (p.y < -10) p.y = h + 10;
        if (p.y > h + 10) p.y = -10;
        ctx.beginPath();
        ctx.fillStyle = `hsla(${p.hue}, 80%, 72%, ${p.a})`;
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fill();
      }
      // soft links
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const a = particles[i];
          const b = particles[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const d = Math.hypot(dx, dy);
          if (d < 110) {
            ctx.strokeStyle = `rgba(167, 139, 250, ${0.08 * (1 - d / 110)})`;
            ctx.lineWidth = 0.6;
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }
      raf = requestAnimationFrame(tick);
    }

    resize();
    seed();
    tick();
    window.addEventListener("resize", () => {
      resize();
      seed();
    });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) cancelAnimationFrame(raf);
      else raf = requestAnimationFrame(tick);
    });
  }

  // --- utils --------------------------------------------------------------
  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function renderMarkdown(src) {
    let t = escapeHtml(src);
    t = t.replace(/```([\s\S]*?)```/g, (_, code) => `<pre><code>${code}</code></pre>`);
    t = t.replace(/`([^`]+)`/g, "<code>$1</code>");
    t = t.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    t = t.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
    t = t.replace(/(^|\n)(\|.+\|)\n(\|[-:| ]+\|)\n((?:\|.+\|\n?)*)/g, (m, p, header, sep, bodyRows) => {
      const th = header
        .split("|")
        .filter(Boolean)
        .map((c) => `<th>${c.trim()}</th>`)
        .join("");
      const rows = bodyRows
        .trim()
        .split("\n")
        .filter(Boolean)
        .map((line) => {
          const tds = line
            .split("|")
            .filter(Boolean)
            .map((c) => `<td>${c.trim()}</td>`)
            .join("");
          return `<tr>${tds}</tr>`;
        })
        .join("");
      return `${p}<table><thead><tr>${th}</tr></thead><tbody>${rows}</tbody></table>`;
    });
    t = t.replace(/\n\n/g, "</p><p>").replace(/\n/g, "<br>");
    return `<p>${t}</p>`;
  }

  function autoGrow() {
    input.style.height = "auto";
    input.style.height = Math.min(input.scrollHeight, 180) + "px";
  }

  function isNarrow() {
    return window.matchMedia("(max-width: 1100px)").matches;
  }

  function formatTime(ts) {
    if (!ts) return "";
    try {
      const d = new Date(ts);
      if (!Number.isNaN(d.getTime())) {
        return d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
      }
    } catch (_) {
      /* keep */
    }
    return String(ts);
  }

  // --- empty state --------------------------------------------------------
  function showEmptyState() {
    chatScroll.innerHTML = `
      <div class="empty-state" id="emptyState">
        <div class="empty-orb" aria-hidden="true">
          <img src="/static/brand.jpg" alt="" width="88" height="88" />
        </div>
        <h1>Was soll das Team bauen?</h1>
        <p>Beschreibe die Aufgabe in Alltagssprache. Dual-Craft verteilt die Arbeit an Claude, Grok und Codex — mit klarer Pipeline.</p>
        <div class="empty-tips">
          <button type="button" class="empty-tip" data-fill="Einen /health-Endpoint hinzufügen, der JSON mit status ok zurückgibt, plus Unit-Test.">Health-Endpoint</button>
          <button type="button" class="empty-tip" data-fill="Fehlerbehandlung fail-closed refactoren und mit Tests absichern.">Fail-closed Errors</button>
          <button type="button" class="empty-tip" data-fill="Kurzes Design für eine lokale Task-Queue schreiben.">Design-Spike</button>
        </div>
      </div>`;
    chatScroll.querySelectorAll(".empty-tip").forEach((btn) => {
      btn.addEventListener("click", () => {
        input.value = btn.getAttribute("data-fill") || "";
        autoGrow();
        input.focus();
      });
    });
    hasMessages = false;
  }

  function clearEmptyState() {
    const empty = $("#emptyState");
    if (empty) empty.remove();
  }

  // --- messages -----------------------------------------------------------
  function addMessage(msg, { scroll = true } = {}) {
    clearEmptyState();
    hasMessages = true;
    const el = document.createElement("article");
    el.className = `msg ${msg.role || "system"}`;
    el.dataset.id = msg.id || "";
    el.style.animationDelay = `${Math.min(msgAnimIndex++ * 0.04, 0.24)}s`;
    const who =
      msg.role === "user" ? DE.you : msg.role === "assistant" ? DE.orchestrator : DE.system;
    const ts = formatTime(msg.ts);
    el.innerHTML = `
      <div class="msg-inner">
        <div class="msg-meta"><span>${who}</span><span>${escapeHtml(ts)}</span></div>
        <div class="msg-body">${renderMarkdown(msg.content || "")}</div>
      </div>`;
    chatScroll.appendChild(el);
    if (scroll) chatScroll.scrollTop = chatScroll.scrollHeight;
  }

  function setTyping(on) {
    let t = $("#typingRow");
    if (on) {
      if (t) return;
      clearEmptyState();
      t = document.createElement("article");
      t.id = "typingRow";
      t.className = "msg assistant";
      t.innerHTML = `<div class="msg-inner">
        <div class="msg-meta"><span>${DE.orchestrator}</span><span>${DE.thinking}</span></div>
        <div class="msg-body"><span class="typing"><i></i><i></i><i></i></span></div>
      </div>`;
      chatScroll.appendChild(t);
      chatScroll.scrollTop = chatScroll.scrollHeight;
    } else if (t) {
      t.remove();
    }
  }

  // --- Live work stream (CLI mirror in chat) ------------------------------
  function ensureLiveWork(runId) {
    clearEmptyState();
    let wrap = $("#liveWorkMsg");
    if (wrap) {
      const idEl = wrap.querySelector("[data-run-id]");
      if (idEl) idEl.textContent = runId;
      return wrap;
    }
    wrap = document.createElement("article");
    wrap.id = "liveWorkMsg";
    wrap.className = "msg system live-work";
    wrap.innerHTML = `
      <div class="msg-inner">
        <div class="msg-meta">
          <span>${DE.workStream}</span>
          <span data-run-id>${escapeHtml(runId)}</span>
        </div>
        <div class="msg-body">
          <div class="live-activity" id="liveActivity" aria-label="Ereignisse"></div>
          <div class="live-term-wrap">
            <div class="live-term-bar">
              <span class="live-term-title">stdout · dual-run</span>
              <button type="button" class="text-btn" id="btnLiveFollow" title="Auto-Scroll">${DE.followOn}</button>
            </div>
            <pre class="live-term" id="liveTerm" aria-live="polite" aria-label="Live CLI Ausgabe"></pre>
          </div>
        </div>
      </div>`;
    chatScroll.appendChild(wrap);
    const followBtn = wrap.querySelector("#btnLiveFollow");
    if (followBtn) {
      followBtn.addEventListener("click", () => {
        liveFollow = !liveFollow;
        followBtn.textContent = liveFollow ? DE.followOn : DE.followOff;
      });
    }
    chatScroll.scrollTop = chatScroll.scrollHeight;
    return wrap;
  }

  function finishLiveWork(status, exitCode) {
    const wrap = $("#liveWorkMsg");
    if (!wrap) return;
    wrap.classList.add("live-work-done");
    const bar = wrap.querySelector(".live-term-title");
    if (bar) {
      bar.textContent = `stdout · beendet · ${status || "?"} · exit ${exitCode ?? "—"}`;
    }
  }

  /**
   * Turn raw dual-run / vendor CLI lines into human activity chips + optional
   * chat milestones (so the chat shows what the CLI is doing).
   */
  function classifyLine(line) {
    const s = String(line || "").trim();
    if (!s) return null;

    // Phase markers
    let m = s.match(/\bphase[=\s:]+([CWRGAFT])\b/i) || s.match(/\bPHASE:\s*([CWRGAFT])\b/i);
    if (m) {
      const p = m[1].toUpperCase();
      return { key: `phase-${p}`, kind: "phase", text: `Phase ${p} · ${PHASE_NAMES[p] || p}` };
    }
    m = s.match(/\b(Contract|Team-Work|Guards|Assess|Fortify|Test-Merge|Render)\b/i);
    if (
      m &&
      (/^(==+|---+|\[|\*)/.test(s) || /phase|▶|→|starting|start/i.test(s))
    ) {
      return { key: `name-${m[1].toLowerCase()}`, kind: "phase", text: m[1] };
    }

    // Agents / team packages
    m = s.match(/\bteam\((claude|grok|codex)\)/i) || s.match(/\b(claude|grok|codex)\b.*\b(WP\d+|package|Paket)/i);
    if (m) {
      const agent = (m[1] || "").toLowerCase();
      return {
        key: `team-${s.slice(0, 80)}`,
        kind: "agent",
        agent,
        text: s.length > 140 ? s.slice(0, 140) + "…" : s,
      };
    }
    if (/\b(claude|grok|codex)\b/i.test(s) && /(call|worker|builder|architect|hardener|review|fortify|plan)/i.test(s)) {
      const agent = (s.match(/\b(claude|grok|codex)\b/i) || [])[1] || "agent";
      return {
        key: `agent-${s.slice(0, 60)}`,
        kind: "agent",
        agent: agent.toLowerCase(),
        text: s.length > 140 ? s.slice(0, 140) + "…" : s,
      };
    }

    // Gates
    if (/import-scan/i.test(s)) {
      const bad = /BLOCK|FAIL|fail/i.test(s);
      return { key: `is-${s.slice(0, 40)}`, kind: bad ? "fail" : "gate", text: s.length > 120 ? s.slice(0, 120) + "…" : s };
    }
    if (/test-guard/i.test(s)) {
      const bad = /BLOCK|FAIL|fail/i.test(s);
      return { key: `tg-${s.slice(0, 40)}`, kind: bad ? "fail" : "gate", text: s.length > 120 ? s.slice(0, 120) + "…" : s };
    }
    if (/\b(PASS|ok ✓|✓ ok|EXIT 0)\b/i.test(s) && !/dry-ok/i.test(s)) {
      return { key: `ok-${s.slice(0, 50)}`, kind: "ok", text: s.length > 120 ? s.slice(0, 120) + "…" : s };
    }
    if (/\b(BLOCKED|FAIL-CLOSED|FAIL|error:|fatal)\b/i.test(s)) {
      return { key: `fail-${s.slice(0, 50)}`, kind: "fail", text: s.length > 140 ? s.slice(0, 140) + "…" : s };
    }
    if (/\[exit\s+\d+\]/i.test(s)) {
      return { key: `exit-${s}`, kind: /exit 0/i.test(s) ? "ok" : "fail", text: s };
    }
    if (/^\$\s/.test(s)) {
      return { key: `cmd-${s.slice(0, 60)}`, kind: "cmd", text: s.length > 120 ? s.slice(0, 120) + "…" : s };
    }
    // PLAN / commit milestones
    if (/wrote PLAN|PLAN\.md|Contract ready|baton\s*->/i.test(s)) {
      return { key: `mile-${s.slice(0, 50)}`, kind: "phase", text: s.length > 120 ? s.slice(0, 120) + "…" : s };
    }
    if (/^team\([^)]+\):/i.test(s) || /\[no-push\]/i.test(s)) {
      return { key: `commit-${s.slice(0, 60)}`, kind: "ok", text: s.length > 120 ? s.slice(0, 120) + "…" : s };
    }
    return null;
  }

  function pushActivity(evt) {
    if (!evt || !evt.key || activitySeen.has(evt.key)) return;
    activitySeen.add(evt.key);
    // cap memory
    if (activitySeen.size > 400) {
      const first = activitySeen.values().next().value;
      activitySeen.delete(first);
    }
    ensureLiveWork(activeRunId || streamingRunId || "run");
    const box = $("#liveActivity");
    if (!box) return;
    const row = document.createElement("div");
    row.className = `act act-${evt.kind || "info"}${evt.agent ? ` act-agent-${evt.agent}` : ""}`;
    const who = evt.agent ? evt.agent : evt.kind === "cmd" ? "cli" : evt.kind === "phase" ? "phase" : "sys";
    row.innerHTML = `<span class="act-who">${escapeHtml(who)}</span><span class="act-text">${escapeHtml(
      evt.text || ""
    )}</span>`;
    box.appendChild(row);
    // keep last ~40 chips
    while (box.children.length > 40) box.removeChild(box.firstChild);
    if (liveFollow) chatScroll.scrollTop = chatScroll.scrollHeight;
  }

  function appendLogLine(line) {
    const text = String(line ?? "");
    // side panel
    if (liveLog) {
      liveLog.textContent += text + "\n";
      if (liveFollow) liveLog.scrollTop = liveLog.scrollHeight;
    }
    // chat terminal mirror
    ensureLiveWork(streamingRunId || activeRunId || "run");
    const term = $("#liveTerm");
    if (term) {
      term.textContent += text + "\n";
      // keep terminal from growing unboundedly in DOM
      if (term.textContent.length > 200_000) {
        term.textContent = term.textContent.slice(-150_000);
      }
      if (liveFollow) term.scrollTop = term.scrollHeight;
    }
    const evt = classifyLine(text);
    if (evt) pushActivity(evt);
  }

  function openMissionPanel() {
    if (isNarrow()) {
      body.classList.add("panel-open");
      body.classList.remove("panel-collapsed", "nav-open");
    } else {
      body.classList.remove("panel-collapsed");
    }
  }

  // --- options ------------------------------------------------------------
  function opts() {
    return {
      profile: $("#optProfile").value,
      verify: $("#optVerify").value.trim() || "true",
      auto_plan: $("#optAutoPlan").checked,
      team_work: $("#optTeamWork").checked,
      skip_merge: $("#optSkipMerge").checked,
      dry_run: $("#optDryRun").checked,
      fortify: $("#optFortify").checked,
    };
  }

  // --- API ----------------------------------------------------------------
  async function api(path, init) {
    const res = await fetch(path, {
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      ...init,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(data.error || res.statusText || "Anfrage fehlgeschlagen");
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  async function loadHistory() {
    const data = await api("/api/history?limit=300");
    chatScroll.innerHTML = "";
    msgAnimIndex = 0;
    const messages = data.messages || [];
    if (!messages.length) {
      showEmptyState();
      return;
    }
    messages.forEach((m) => addMessage(m, { scroll: false }));
    chatScroll.scrollTop = chatScroll.scrollHeight;
  }

  function renderClis(clis) {
    const ul = $("#cliList");
    ul.innerHTML = "";
    const entries = Object.entries(clis || {});
    if (!entries.length) {
      ul.innerHTML = `<li><span class="name" style="color:var(--text-4)">${DE.noCli}</span></li>`;
      return;
    }
    entries.forEach(([name, ok]) => {
      const li = document.createElement("li");
      li.innerHTML = `<span class="name"><span class="dot ${ok ? "ok" : "no"}"></span>${escapeHtml(
        name
      )}</span><span class="tag">${ok ? DE.readyTag : DE.missingTag}</span>`;
      ul.appendChild(li);
    });
  }

  function renderLedger(ledger) {
    const ul = $("#ledgerList");
    ul.innerHTML = "";
    const entries = Object.entries(ledger || {});
    if (!entries.length) {
      ul.innerHTML = `<li><span class="name" style="color:var(--text-4)">${DE.noGates}</span></li>`;
      return;
    }
    entries.slice(-12).forEach(([k, v]) => {
      const li = document.createElement("li");
      const verdict = v && v.verdict != null ? String(v.verdict) : "—";
      let cls = "ok";
      if (/block|fail|red|0/i.test(verdict)) cls = "crit";
      else if (/warn|tie|pending/i.test(verdict)) cls = "warn";
      li.innerHTML = `<span class="name"><span class="dot ${cls}"></span>${escapeHtml(
        k
      )}</span><span class="tag">${escapeHtml(verdict)}</span>`;
      ul.appendChild(li);
    });
  }

  function renderPhases(status) {
    const track = $("#phaseTrack");
    const rs = status.run_state || {};
    const phase =
      rs.phase || (status.active_run && status.active_run.status === "running" ? "W" : "—");
    const order = ["C", "W", "G", "A", "F", "T"];
    const running = status.active_run && status.active_run.status === "running";
    const failed = status.active_run && status.active_run.status === "failed";
    const idx = order.indexOf(phase);

    track.innerHTML = order
      .map((k, i) => {
        let cls = "";
        let state = DE.wait;
        if (idx >= 0 && i < idx) {
          cls = "done";
          state = DE.done;
        }
        if (k === phase) {
          if (failed) {
            cls = "fail";
            state = DE.fail;
          } else if (running) {
            cls = "active";
            state = DE.live;
          } else if (idx >= 0) {
            cls = "done";
            state = DE.done;
          }
        }
        return `<li class="${cls}">
          <span class="step-key">${k}</span>
          <span class="step-name">${PHASE_NAMES[k]}</span>
          <span class="step-state">${state}</span>
        </li>`;
      })
      .join("");
  }

  function renderWho(who) {
    $("#whoProfile").textContent =
      who && who.profile ? `${DE.profile} · ${who.profile}` : DE.noAssign;
    const box = $("#whoTable");
    const matrix = (who && who.who_matrix) || [];
    if (!matrix.length) {
      box.innerHTML = `<p class="empty-inline">${DE.whoEmpty}</p>`;
      return;
    }
    const rows = matrix
      .map(
        (r) =>
          `<tr>
            <td>${escapeHtml(r.phase || "")}</td>
            <td>${escapeHtml(r.function || "")}</td>
            <td><span class="agent-pill">${escapeHtml(String(r.agent ?? "—"))}</span></td>
          </tr>`
      )
      .join("");
    box.innerHTML = `<table><thead><tr><th>${DE.phase}</th><th>${DE.role}</th><th>${DE.agent}</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  function renderWork(work) {
    const box = $("#workRoster");
    if (!work || !work.packages || !work.packages.length) {
      box.innerHTML = `<p class="empty-inline">${DE.workEmpty}</p>`;
      return;
    }
    box.innerHTML = work.packages
      .map((p) => {
        return `<div class="pkg">
          <div class="pkg-top">
            <span class="id">${escapeHtml(p.id || "")}</span>
            <span class="assignee">${escapeHtml(p.assignee || "?")}</span>
          </div>
          <div class="meta">${escapeHtml(p.status || "")} · ${escapeHtml(p.kind || "")} — ${escapeHtml(
          (p.title || "").slice(0, 90)
        )}</div>
        </div>`;
      })
      .join("");
  }

  function renderModeChips(status) {
    const box = $("#modeChips");
    if (!box) return;
    const ar = status.active_run;
    const mode = ar && ar.mode;
    if (!mode || !Object.keys(mode).length) {
      box.innerHTML = `<p class="empty-inline">${DE.modeNone}</p>`;
      return;
    }
    const chips = [];
    chips.push(
      mode.dry_run
        ? `<span class="mode-chip warn" title="Es wird kein echter Code geschrieben">${DE.modeDry}</span>`
        : `<span class="mode-chip ok" title="Worker schreiben Dateien; lokale Commits [no-push]">${DE.modeReal}</span>`
    );
    chips.push(
      mode.skip_merge
        ? `<span class="mode-chip" title="Ergebnis bleibt auf dem Arbeits-Branch — main unverändert">${DE.modeSkipMerge}</span>`
        : `<span class="mode-chip accent" title="Bei grünem Gate wird nach main gemerged">${DE.modeMerge}</span>`
    );
    chips.push(
      mode.team_work
        ? `<span class="mode-chip accent" title="Phase W: Claude + Grok + Codex">${DE.modeTeam}</span>`
        : `<span class="mode-chip" title="Keine Team-Phase">${DE.modeSolo}</span>`
    );
    if (mode.fortify) chips.push(`<span class="mode-chip">${DE.modeFortify}</span>`);
    if (mode.profile) chips.push(`<span class="mode-chip dim">${escapeHtml(String(mode.profile))}</span>`);
    box.innerHTML = chips.join("");
  }

  async function loadPersistence() {
    const card = $("#persistCard");
    const bodyEl = $("#persistBody");
    if (!card || !bodyEl) return;
    try {
      const pc = await api("/api/persistence");
      card.hidden = false;
      const head = pc.ok
        ? `<p class="persist-head ok">✓ ${DE.persistOk} · ${pc.team_commits.length} ${DE.persistCommits} · ${pc.dirty_count} ${DE.persistDirty}</p>`
        : `<p class="persist-head warn">⚠ ${DE.persistWarn}</p>`;
      const warns = (pc.warnings || [])
        .map((w) => `<p class="persist-warn">${escapeHtml(w)}</p>`)
        .join("");
      const rows = (pc.packages || [])
        .map((p) => {
          let mark = "·";
          let cls = "";
          if (p.status === "dry-ok") {
            mark = "◌";
            cls = "dim";
          } else if (p.persisted === true) {
            mark = "✓";
            cls = "ok";
          } else if (p.persisted === false) {
            mark = "✗";
            cls = "crit";
          }
          const commit = p.commit ? ` · ${escapeHtml(p.commit.hash)}` : "";
          return `<div class="persist-row ${cls}"><span class="mark">${mark}</span><span class="pid">${escapeHtml(
            p.id || ""
          )}</span><span class="pmeta">${escapeHtml(p.status || "")}${commit}</span></div>`;
        })
        .join("");
      bodyEl.innerHTML = head + warns + rows;
    } catch (e) {
      console.warn("persistence", e);
    }
  }

  function setStatusUI(status) {
    const branch = (status.git && status.git.branch) || "—";
    const dirty = (status.git && status.git.dirty) || 0;
    $("#metaBranch").textContent = dirty ? `${branch} · ${dirty} uncommitted` : branch;
    $("#metaBranch").title = `Branch: ${branch}${dirty ? ` (${dirty} geänderte Dateien)` : ""}`;

    const lock = status.lock;
    const ml = $("#metaLock");
    if (lock && lock.alive) {
      ml.textContent = `${DE.lockHeld} · ${lock.pid}`;
      ml.title = `Lauf-Sperre durch PID ${lock.pid}`;
    } else if (lock && lock.pid && lock.alive === false) {
      ml.textContent = DE.lockStale;
      ml.title = "Verwaiste Lock-Datei gefunden";
    } else {
      ml.textContent = DE.lockFree;
      ml.title = "Keine Lauf-Sperre";
    }

    const ar = status.active_run;
    const chip = $("#chipRun");
    const label = chip.querySelector(".status-label");

    if (ar && (ar.status === "running" || ar.status === "queued")) {
      chip.dataset.state = "running";
      label.textContent = ar.status === "queued" ? DE.queued : DE.running;
      btnCancel.disabled = false;
      btnCancel.hidden = false;
      activeRunId = ar.id;
    } else if (ar && ar.status === "succeeded") {
      chip.dataset.state = "ok";
      label.textContent = DE.succeeded;
      btnCancel.disabled = true;
      btnCancel.hidden = true;
    } else if (ar && ar.status === "failed") {
      chip.dataset.state = "fail";
      label.textContent =
        ar.exit_code != null ? `${DE.failed} · ${ar.exit_code}` : DE.failed;
      btnCancel.disabled = true;
      btnCancel.hidden = true;
    } else if (ar && ar.status === "cancelled") {
      chip.dataset.state = "warn";
      label.textContent = DE.cancelled;
      btnCancel.disabled = true;
      btnCancel.hidden = true;
    } else {
      chip.dataset.state = "idle";
      label.textContent = DE.ready;
      btnCancel.disabled = true;
      btnCancel.hidden = true;
    }
  }

  async function refreshStatus() {
    try {
      const status = await api("/api/status");
      setStatusUI(status);
      renderModeChips(status);
      renderClis(status.clis);
      renderLedger(status.ledger);
      renderPhases(status);
      renderWork(status.work);
      if (status.role_assignment) renderWho(status.role_assignment);
      if (
        status.active_run &&
        (status.active_run.status === "running" || status.active_run.status === "queued") &&
        status.active_run.id !== streamingRunId
      ) {
        attachStream(status.active_run.id, { seedTail: status.active_run.tail });
      }
      // Faster status while a run is live (work packages / pipeline)
      const running =
        status.active_run &&
        (status.active_run.status === "running" || status.active_run.status === "queued");
      const wantMs = running ? 2000 : 4000;
      if (statusTimer && wantMs !== statusPollMs) {
        statusPollMs = wantMs;
        clearInterval(statusTimer);
        statusTimer = setInterval(refreshStatus, statusPollMs);
      }
    } catch (e) {
      console.warn("status", e);
    }
  }

  function attachStream(runId, { seedTail } = {}) {
    if (streamingRunId === runId && es) return;
    if (es) {
      es.close();
      es = null;
    }
    activeRunId = runId;
    streamingRunId = runId;
    activitySeen.clear();
    btnCancel.disabled = false;
    btnCancel.hidden = false;
    openMissionPanel();
    if ($("#logMeta")) $("#logMeta").textContent = runId;
    if (liveLog) liveLog.textContent = "";
    ensureLiveWork(runId);
    const term = $("#liveTerm");
    if (term) term.textContent = "";
    const act = $("#liveActivity");
    if (act) act.innerHTML = "";

    // Replay any lines already buffered (reconnect / late open)
    if (Array.isArray(seedTail)) {
      for (const line of seedTail) appendLogLine(line);
    }

    pushActivity({
      key: `start-${runId}`,
      kind: "phase",
      text: `Lauf gestartet · ${runId}`,
    });

    es = new EventSource(`/api/runs/${encodeURIComponent(runId)}/stream`);
    es.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data.line) appendLogLine(data.line);
        if (data.done) {
          es.close();
          es = null;
          streamingRunId = null;
          btnCancel.disabled = true;
          btnCancel.hidden = true;
          if ($("#logMeta")) {
            $("#logMeta").textContent = `${data.status || "fertig"} · exit ${data.exit_code}`;
          }
          finishLiveWork(data.status, data.exit_code);
          pushActivity({
            key: `done-${runId}-${data.exit_code}`,
            kind: data.exit_code === 0 ? "ok" : "fail",
            text: `Lauf beendet · ${data.status || "?"} · exit ${data.exit_code}`,
          });
          refreshStatus();
          loadHistory();
          loadPersistence();
        }
      } catch (_) {
        /* ignore */
      }
    };
    es.onerror = () => {
      /* browser retries SSE */
    };
  }

  async function send({ previewOnly = false } = {}) {
    const message = input.value.trim();
    if (!message) {
      input.focus();
      return;
    }
    const payload = { message, preview_only: previewOnly, ...opts() };
    btnSend.disabled = true;
    btnPreview.disabled = true;
    setTyping(true);
    try {
      const data = await api("/api/chat", { method: "POST", body: JSON.stringify(payload) });
      setTyping(false);
      if (data.user) addMessage(data.user);
      if (data.assistant) addMessage(data.assistant);
      if (data.who) renderWho(data.who);
      if (data.run && data.run.id) {
        attachStream(data.run.id, { seedTail: data.run.tail });
      }
      input.value = "";
      autoGrow();
      await refreshStatus();
    } catch (e) {
      setTyping(false);
      const msg = (e.data && e.data.assistant) || null;
      if (e.data && e.data.user) addMessage(e.data.user);
      if (msg) addMessage(msg);
      else
        addMessage({
          role: "system",
          content: `**${DE.error}:** ${e.message || e}`,
          ts: new Date().toISOString(),
        });
    } finally {
      btnSend.disabled = false;
      btnPreview.disabled = false;
      input.focus();
    }
  }

  // --- layout -------------------------------------------------------------
  function initLayout() {
    if (isNarrow()) {
      body.classList.add("nav-collapsed", "panel-collapsed");
      body.classList.remove("nav-open", "panel-open");
    } else {
      body.classList.remove("nav-collapsed", "panel-collapsed", "nav-open", "panel-open");
    }
  }

  $("#btnToggleNav").addEventListener("click", () => {
    if (isNarrow()) {
      const open = body.classList.toggle("nav-open");
      if (open) body.classList.remove("panel-open");
    } else {
      body.classList.toggle("nav-collapsed");
    }
  });

  $("#btnTogglePanel").addEventListener("click", () => {
    if (isNarrow()) {
      const open = body.classList.toggle("panel-open");
      if (open) body.classList.remove("nav-open");
    } else {
      body.classList.toggle("panel-collapsed");
    }
  });

  btnOptions.addEventListener("click", () => {
    const open = optionsPanel.hasAttribute("hidden");
    if (open) {
      optionsPanel.removeAttribute("hidden");
      btnOptions.setAttribute("aria-expanded", "true");
    } else {
      optionsPanel.setAttribute("hidden", "");
      btnOptions.setAttribute("aria-expanded", "false");
    }
  });

  // --- events -------------------------------------------------------------
  btnSend.addEventListener("click", () => send({ previewOnly: false }));
  btnPreview.addEventListener("click", () => send({ previewOnly: true }));
  btnRefresh.addEventListener("click", () => {
    refreshStatus();
    loadHistory();
  });
  btnClear.addEventListener("click", async () => {
    if (!confirm(DE.clearConfirm)) return;
    await api("/api/history/clear", { method: "POST", body: "{}" });
    await loadHistory();
  });
  btnCancel.addEventListener("click", async () => {
    if (!activeRunId) return;
    try {
      await api(`/api/runs/${encodeURIComponent(activeRunId)}/cancel`, {
        method: "POST",
        body: "{}",
      });
      await refreshStatus();
    } catch (e) {
      alert(e.message || e);
    }
  });
  const btnLogCopy = $("#btnLogCopy");
  if (btnLogCopy) {
    btnLogCopy.addEventListener("click", async () => {
      const text = (liveLog && liveLog.textContent) || ($("#liveTerm") && $("#liveTerm").textContent) || "";
      try {
        await navigator.clipboard.writeText(text);
        btnLogCopy.textContent = DE.logCopy;
        setTimeout(() => {
          btnLogCopy.textContent = "Kopieren";
        }, 1500);
      } catch (_) {
        /* ignore */
      }
    });
  }
  const btnLogExpand = $("#btnLogExpand");
  if (btnLogExpand) {
    btnLogExpand.addEventListener("click", () => {
      const card = document.querySelector(".card-log");
      if (!card) return;
      card.classList.toggle("log-expanded");
      btnLogExpand.textContent = card.classList.contains("log-expanded") ? "Klein" : "Groß";
    });
  }

  input.addEventListener("input", autoGrow);
  input.addEventListener("keydown", (e) => {
    // Chat-Standard: Enter sendet, Shift+Enter = Zeilenumbruch (Ctrl/Cmd+Enter geht auch)
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      send({ previewOnly: false });
    }
  });

  // Plattformgerechter Shortcut-Hint (Linux/Windows: Strg statt ⌘)
  const kbdHint = document.querySelector("#btnSend .kbd");
  if (kbdHint && !/Mac/i.test(navigator.platform)) kbdHint.textContent = "↵";

  document.querySelectorAll(".template").forEach((btn) => {
    btn.addEventListener("click", () => {
      input.value = btn.getAttribute("data-task") || "";
      autoGrow();
      input.focus();
      if (isNarrow()) body.classList.remove("nav-open");
    });
  });

  // Pointer-reactive glow on composer
  const composer = $("#composer");
  if (composer) {
    composer.addEventListener("pointermove", (e) => {
      const r = composer.getBoundingClientRect();
      const x = ((e.clientX - r.left) / r.width) * 100;
      const y = ((e.clientY - r.top) / r.height) * 100;
      composer.style.setProperty("--mx", x + "%");
      composer.style.setProperty("--my", y + "%");
    });
  }

  // boot
  initFx();
  initLayout();
  showEmptyState();
  loadHistory()
    .then(refreshStatus)
    .catch((e) => {
      chatScroll.innerHTML = "";
      addMessage({
        role: "system",
        content: `**${DE.apiFail}:** ${e.message}. ${DE.startHint}`,
        ts: new Date().toISOString(),
      });
    });
  statusTimer = setInterval(refreshStatus, 4000);
  autoGrow();
})();
