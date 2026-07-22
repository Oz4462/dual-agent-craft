/* Dual-Craft Chat Cockpit client */
(() => {
  "use strict";

  const $ = (sel) => document.querySelector(sel);
  const chatScroll = $("#chatScroll");
  const liveLog = $("#liveLog");
  const input = $("#input");
  const btnSend = $("#btnSend");
  const btnPreview = $("#btnPreview");
  const btnCancel = $("#btnCancel");
  const btnRefresh = $("#btnRefresh");
  const btnClear = $("#btnClear");

  let activeRunId = null;
  let es = null;
  let statusTimer = null;

  // --- markdown-lite (safe-ish) ------------------------------------------
  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function renderMarkdown(src) {
    let t = escapeHtml(src);
    // fenced code
    t = t.replace(/```([\s\S]*?)```/g, (_, code) => `<pre><code>${code}</code></pre>`);
    // inline code
    t = t.replace(/`([^`]+)`/g, "<code>$1</code>");
    // bold
    t = t.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    // tables (simple)
    t = t.replace(/(^|\n)(\|.+\|)\n(\|[-:| ]+\|)\n((?:\|.+\|\n?)*)/g, (m, p, header, sep, body) => {
      const th = header
        .split("|")
        .filter(Boolean)
        .map((c) => `<th>${c.trim()}</th>`)
        .join("");
      const rows = body
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
    // paragraphs / newlines
    t = t.replace(/\n\n/g, "</p><p>").replace(/\n/g, "<br>");
    return `<p>${t}</p>`;
  }

  function addMessage(msg, { scroll = true } = {}) {
    const el = document.createElement("article");
    el.className = `msg ${msg.role || "system"}`;
    el.dataset.id = msg.id || "";
    const who =
      msg.role === "user" ? "you" : msg.role === "assistant" ? "orchestrator" : "system";
    el.innerHTML = `
      <div class="msg-head"><span>${who}</span><span>${escapeHtml(msg.ts || "")}</span></div>
      <div class="msg-body">${renderMarkdown(msg.content || "")}</div>
    `;
    chatScroll.appendChild(el);
    if (scroll) chatScroll.scrollTop = chatScroll.scrollHeight;
  }

  function setTyping(on) {
    let t = $("#typingRow");
    if (on) {
      if (t) return;
      t = document.createElement("div");
      t.id = "typingRow";
      t.className = "msg assistant";
      t.innerHTML = `<div class="msg-head"><span>orchestrator</span><span>…</span></div>
        <div class="msg-body"><span class="typing"><i></i><i></i><i></i></span></div>`;
      chatScroll.appendChild(t);
      chatScroll.scrollTop = chatScroll.scrollHeight;
    } else if (t) {
      t.remove();
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
      const err = new Error(data.error || res.statusText || "request failed");
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  async function loadHistory() {
    const data = await api("/api/history?limit=300");
    chatScroll.innerHTML = "";
    (data.messages || []).forEach((m) => addMessage(m, { scroll: false }));
    chatScroll.scrollTop = chatScroll.scrollHeight;
  }

  function renderClis(clis) {
    const ul = $("#cliList");
    ul.innerHTML = "";
    Object.entries(clis || {}).forEach(([name, ok]) => {
      const li = document.createElement("li");
      li.innerHTML = `<span><span class="dot ${ok ? "ok" : "no"}"></span>${escapeHtml(name)}</span><span>${ok ? "ready" : "missing"}</span>`;
      ul.appendChild(li);
    });
  }

  function renderLedger(ledger) {
    const ul = $("#ledgerList");
    ul.innerHTML = "";
    const entries = Object.entries(ledger || {});
    if (!entries.length) {
      ul.innerHTML = `<li><span class="muted">empty</span></li>`;
      return;
    }
    entries.forEach(([k, v]) => {
      const li = document.createElement("li");
      const verdict = v && v.verdict != null ? String(v.verdict) : "—";
      let cls = "ok";
      if (/block|fail|red|0/i.test(verdict)) cls = "crit";
      else if (/warn|tie|pending/i.test(verdict)) cls = "warn";
      li.innerHTML = `<span><span class="dot ${cls}"></span>${escapeHtml(k)}</span><span>${escapeHtml(verdict)}</span>`;
      ul.appendChild(li);
    });
  }

  function renderPhases(status) {
    const track = $("#phaseTrack");
    const rs = status.run_state || {};
    const phase = rs.phase || (status.active_run && status.active_run.status === "running" ? "W" : "—");
    const order = ["C", "W", "G", "A", "F", "T"];
    const names = { C: "Contract", W: "Team", G: "Guards", A: "Assess", F: "Fortify", T: "Gate" };
    const idx = order.indexOf(phase);
    track.innerHTML = order
      .map((k, i) => {
        let cls = "idle";
        if (idx >= 0 && i < idx) cls = "ok";
        if (k === phase) cls = status.active_run && status.active_run.status === "running" ? "run" : "ok";
        if (status.active_run && status.active_run.status === "failed" && k === phase) cls = "crit";
        return `<div class="phase ${cls}"><span class="k">${k}</span><span class="n">${names[k]}</span></div>`;
      })
      .join("");
  }

  function renderWho(who) {
    $("#whoProfile").textContent = who && who.profile ? `profile · ${who.profile}` : "profile —";
    const box = $("#whoTable");
    const matrix = (who && who.who_matrix) || [];
    if (!matrix.length) {
      box.innerHTML = `<p class="muted">Send a task or Preview who.</p>`;
      return;
    }
    const rows = matrix
      .map(
        (r) =>
          `<tr><td>${escapeHtml(r.phase || "")}</td><td>${escapeHtml(r.function || "")}</td><td><code>${escapeHtml(
            String(r.agent ?? "—")
          )}</code></td></tr>`
      )
      .join("");
    box.innerHTML = `<table><thead><tr><th>Phase</th><th>Fn</th><th>Agent</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  function renderWork(work) {
    const box = $("#workRoster");
    if (!work || !work.packages) {
      box.innerHTML = `<p class="muted">No WORK.json yet.</p>`;
      return;
    }
    box.innerHTML = work.packages
      .map((p) => {
        return `<div class="pkg"><div><span class="id">${escapeHtml(p.id || "")}</span> · ${escapeHtml(
          p.assignee || "?"
        )} · ${escapeHtml(p.status || "")}</div>
        <div class="meta">${escapeHtml(p.kind || "")} — ${escapeHtml((p.title || "").slice(0, 80))}</div></div>`;
      })
      .join("");
  }

  function setPills(status) {
    const branch = (status.git && status.git.branch) || "—";
    const dirty = (status.git && status.git.dirty) || 0;
    $("#pillBranch").textContent = `branch ${branch}${dirty ? ` · dirty ${dirty}` : ""}`;

    const lock = status.lock;
    const pl = $("#pillLock");
    if (lock && lock.alive) {
      pl.textContent = `lock PID ${lock.pid}`;
      pl.className = "pill warn";
    } else if (lock && lock.pid && lock.alive === false) {
      pl.textContent = "lock stale";
      pl.className = "pill warn";
    } else {
      pl.textContent = "lock free";
      pl.className = "pill ok";
    }

    const ar = status.active_run;
    const pr = $("#pillRun");
    if (ar && (ar.status === "running" || ar.status === "queued")) {
      pr.textContent = `${ar.status} · ${ar.id}`;
      pr.className = "pill run";
      btnCancel.disabled = false;
      activeRunId = ar.id;
    } else if (ar) {
      pr.textContent = `${ar.status}${ar.exit_code != null ? ` · exit ${ar.exit_code}` : ""}`;
      pr.className = ar.status === "succeeded" ? "pill ok" : "pill crit";
      btnCancel.disabled = true;
    } else {
      pr.textContent = "idle";
      pr.className = "pill";
      btnCancel.disabled = true;
    }
  }

  async function refreshStatus() {
    try {
      const status = await api("/api/status");
      setPills(status);
      renderClis(status.clis);
      renderLedger(status.ledger);
      renderPhases(status);
      renderWork(status.work);
      if (status.role_assignment) renderWho(status.role_assignment);
      if (status.active_run && status.active_run.status === "running" && status.active_run.id !== activeRunId) {
        attachStream(status.active_run.id);
      }
    } catch (e) {
      console.warn("status", e);
    }
  }

  function attachStream(runId) {
    if (es) {
      es.close();
      es = null;
    }
    activeRunId = runId;
    btnCancel.disabled = false;
    $("#logMeta").textContent = runId;
    liveLog.textContent = "";
    es = new EventSource(`/api/runs/${encodeURIComponent(runId)}/stream`);
    es.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data.line) {
          liveLog.textContent += data.line + "\n";
          liveLog.scrollTop = liveLog.scrollHeight;
        }
        if (data.done) {
          es.close();
          es = null;
          btnCancel.disabled = true;
          $("#logMeta").textContent = `${data.status || "done"} · exit ${data.exit_code}`;
          refreshStatus();
          loadHistory();
        }
      } catch (_) {
        /* ignore */
      }
    };
    es.onerror = () => {
      /* browser will retry; if run ended, server closes */
    };
  }

  async function send({ previewOnly = false } = {}) {
    const message = input.value.trim();
    if (!message) {
      input.focus();
      return;
    }
    const body = { message, preview_only: previewOnly, ...opts() };
    btnSend.disabled = true;
    btnPreview.disabled = true;
    setTyping(true);
    try {
      const data = await api("/api/chat", { method: "POST", body: JSON.stringify(body) });
      setTyping(false);
      if (data.user) addMessage(data.user);
      if (data.assistant) addMessage(data.assistant);
      if (data.who) renderWho(data.who);
      if (data.run && data.run.id) attachStream(data.run.id);
      input.value = "";
      await refreshStatus();
    } catch (e) {
      setTyping(false);
      const msg = (e.data && e.data.assistant) || null;
      if (msg) addMessage(msg);
      else
        addMessage({
          role: "system",
          content: `**Error:** ${e.message || e}`,
          ts: new Date().toISOString(),
        });
      if (e.data && e.data.user) addMessage(e.data.user);
    } finally {
      btnSend.disabled = false;
      btnPreview.disabled = false;
      input.focus();
    }
  }

  // --- events -------------------------------------------------------------
  btnSend.addEventListener("click", () => send({ previewOnly: false }));
  btnPreview.addEventListener("click", () => send({ previewOnly: true }));
  btnRefresh.addEventListener("click", () => {
    refreshStatus();
    loadHistory();
  });
  btnClear.addEventListener("click", async () => {
    if (!confirm("Clear chat history on this machine?")) return;
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

  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      send({ previewOnly: false });
    }
  });

  document.querySelectorAll(".preset").forEach((btn) => {
    btn.addEventListener("click", () => {
      input.value = btn.getAttribute("data-task") || "";
      input.focus();
    });
  });

  // boot
  loadHistory()
    .then(refreshStatus)
    .catch((e) => {
      addMessage({
        role: "system",
        content: `Cannot reach API: ${e.message}. Is dual-chat running?`,
        ts: new Date().toISOString(),
      });
    });
  statusTimer = setInterval(refreshStatus, 4000);
})();
