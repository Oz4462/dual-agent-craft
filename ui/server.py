#!/usr/bin/env python3
"""Dual-Craft Chat Cockpit — local HTTP API + static UI.

Professional task chat that drives dual-run.sh. Binds 127.0.0.1 only by default.
No vendor API keys; uses local CLI subscriptions via the existing harness.

Usage:
  python3 ui/server.py [--port 8787] [--host 127.0.0.1] [--root REPO]
  ./dual-chat.sh [--port 8787] [--open]
"""
from __future__ import annotations

import argparse
import json
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional
from urllib.parse import parse_qs, urlparse

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parent
STATIC = HERE / "static"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


# ---------------------------------------------------------------------------
# App state
# ---------------------------------------------------------------------------


STATUS_DE = {
    "queued": "wartend",
    "running": "läuft",
    "succeeded": "erfolgreich",
    "failed": "fehlgeschlagen",
    "cancelled": "abgebrochen",
}


def mode_summary_de(mode: dict) -> str:
    """German, human-readable summary of what a run will/won't do."""
    parts: list[str] = []
    if mode.get("dry_run"):
        parts.append("**Dry-Run** — keine echten Schreibzugriffe, keine Vendor-Aufrufe, Pakete werden nur `dry-ok` markiert")
    else:
        parts.append("**Echte Ausführung** — Worker schreiben Dateien; der Harness committet lokal (`[no-push]`)")
    if mode.get("skip_merge"):
        parts.append("**Merge übersprungen** — Ergebnis bleibt auf dem Arbeits-Branch, `main` wird NICHT verändert")
    else:
        parts.append("**Merge aktiv** — bei grünem Gate wird nach `main` gemerged")
    if mode.get("team_work"):
        parts.append("**Team-Arbeit an** — Phase W verteilt Pakete an Claude, Grok und Codex")
    else:
        parts.append("**Solo-Modus** — keine Team-Phase W")
    if mode.get("fortify"):
        parts.append("**Härten aktiv** — zusätzlicher Fortify-Pass")
    return "\n".join(f"- {p}" for p in parts)


class RunState:
    def __init__(self, run_id: str, task: str, argv: list[str], cwd: Path, mode: Optional[dict] = None):
        self.id = run_id
        self.task = task
        self.argv = argv
        self.cwd = cwd
        self.mode = mode or {}
        self.status = "queued"  # queued|running|succeeded|failed|cancelled
        self.started_at = utc_now()
        self.finished_at: Optional[str] = None
        self.exit_code: Optional[int] = None
        self.lines: list[str] = []
        self.subscribers: list[queue.Queue] = []
        self.proc: Optional[subprocess.Popen] = None
        self._lock = threading.Lock()

    def publish(self, line: str) -> None:
        with self._lock:
            self.lines.append(line)
            dead: list[queue.Queue] = []
            for q in self.subscribers:
                try:
                    q.put_nowait(line)
                except Exception:
                    dead.append(q)
            for q in dead:
                if q in self.subscribers:
                    self.subscribers.remove(q)

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {
                "id": self.id,
                "task": self.task,
                "status": self.status,
                "argv": self.argv,
                "started_at": self.started_at,
                "finished_at": self.finished_at,
                "exit_code": self.exit_code,
                "line_count": len(self.lines),
                # Enough history for dashboard reconnect mid-run
                "tail": self.lines[-250:],
                "mode": self.mode,
            }


class App:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.chat_dir = self.root / ".dual-agent" / "chat"
        self.chat_dir.mkdir(parents=True, exist_ok=True)
        self.history_path = self.chat_dir / "history.jsonl"
        self.runs: dict[str, RunState] = {}
        self._run_lock = threading.Lock()
        self.active_run_id: Optional[str] = None

    # --- history ------------------------------------------------------------
    def append_history(self, role: str, content: str, meta: Optional[dict] = None) -> dict:
        msg = {
            "id": str(uuid.uuid4()),
            "role": role,  # user|assistant|system
            "content": content,
            "meta": meta or {},
            "ts": utc_now(),
        }
        with open(self.history_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(msg, ensure_ascii=False) + "\n")
        return msg

    def load_history(self, limit: int = 200) -> list[dict]:
        if not self.history_path.exists():
            return []
        rows: list[dict] = []
        for line in self.history_path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return rows[-limit:]

    def clear_history(self) -> None:
        if self.history_path.exists():
            self.history_path.write_text("", encoding="utf-8")

    # --- status aggregation -------------------------------------------------
    def _read_json(self, path: Path) -> Any:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None

    def _run_cmd(self, argv: list[str], timeout: int = 30) -> tuple[int, str]:
        try:
            p = subprocess.run(
                argv,
                cwd=str(self.root),
                capture_output=True,
                text=True,
                timeout=timeout,
                env={**os.environ, "LC_ALL": "C"},
            )
            out = (p.stdout or "") + (("\n" + p.stderr) if p.stderr else "")
            return p.returncode, out
        except Exception as e:
            return 1, str(e)

    def status(self) -> dict[str, Any]:
        # git
        branch = "-"
        dirty = 0
        try:
            branch = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=str(self.root),
                text=True,
            ).strip()
            dirty = len(
                [
                    ln
                    for ln in subprocess.check_output(
                        ["git", "status", "--porcelain"],
                        cwd=str(self.root),
                        text=True,
                    ).splitlines()
                    if ln.strip()
                ]
            )
        except Exception:
            pass

        plan_path = self.root / "PLAN.md"
        has_plan = plan_path.exists() and plan_path.stat().st_size > 20

        # lock / run-state
        lock = self.root / ".dual-agent" / "dual-run.lock"
        run_state = self._read_json(self.root / ".dual-agent" / "run-state.json")
        role_asg = self._read_json(self.root / ".dual-agent" / "role-assignment.json")
        work = self._read_json(self.root / "ledger" / "WORK.json")

        lock_info = None
        if lock.exists():
            try:
                txt = lock.read_text(encoding="utf-8", errors="replace")
                pid = None
                for line in txt.splitlines():
                    if line.startswith("pid="):
                        pid = int(line.split("=", 1)[1])
                alive = bool(pid and Path(f"/proc/{pid}").exists()) if os.name == "posix" and pid else None
                # portable alive check
                if pid:
                    try:
                        os.kill(pid, 0)
                        alive = True
                    except OSError:
                        alive = False
                lock_info = {"path": str(lock), "raw": txt.strip(), "pid": pid, "alive": alive}
            except Exception as e:
                lock_info = {"error": str(e)}

        ledger = {}
        for name in ("REVIEW", "EVAL", "IMPORT-SCAN", "TEST-GUARD", "TIEBREAK"):
            j = self._read_json(self.root / "ledger" / f"{name}.json")
            if j:
                ledger[name] = {
                    "verdict": j.get("verdict") or j.get("winner") or j.get("pass_pow_k"),
                    "stamp": j.get("stamp") or j.get("started") or j.get("finished_at"),
                }

        # CLIs
        clis = {c: bool(shutil.which(c)) for c in ("git", "python3", "claude", "grok", "codex", "ollama", "tmux")}

        active = None
        if self.active_run_id and self.active_run_id in self.runs:
            active = self.runs[self.active_run_id].snapshot()

        return {
            "ok": True,
            "stamp": utc_now(),
            "repo": str(self.root),
            "repo_name": self.root.name,
            "git": {"branch": branch, "dirty": dirty},
            "has_plan": has_plan,
            "lock": lock_info,
            "run_state": run_state,
            "role_assignment": role_asg,
            "work": work,
            "ledger": ledger,
            "clis": clis,
            "active_run": active,
            "history_count": len(self.load_history(10_000)),
        }

    def who(self, task: str = "", profile: str = "auto") -> dict[str, Any]:
        router = self.root / "lib" / "role-router.sh"
        argv = ["bash", str(router), "route", "--json", "--profile", profile or "auto"]
        if task.strip():
            argv += ["--task", task.strip()]
        plan = self.root / "PLAN.md"
        if plan.exists():
            argv += ["--plan", str(plan)]
        code, out = self._run_cmd(argv, timeout=20)
        try:
            # last JSON object in output
            text = out.strip()
            # find first {
            i = text.find("{")
            data = json.loads(text[i:]) if i >= 0 else {"raw": text}
        except Exception:
            data = {"error": "parse_failed", "raw": out[:2000], "exit": code}
        data["_exit"] = code
        return data

    # --- persistence check ----------------------------------------------------
    def persistence_check(self) -> dict[str, Any]:
        """Wurde wirklich gespeichert? Vergleicht WORK.json-Status mit git-Realität.

        Lücke, die hier sichtbar wird: ein Paket kann "done" sein, obwohl der
        Worker-CLI mit exit 0 beendet hat OHNE Dateien zu schreiben — dann gibt
        es weder einen team-Commit noch geänderte Dateien unter seinen Pfaden.
        """
        dirty: list[str] = []
        try:
            out = subprocess.check_output(
                ["git", "status", "--porcelain"], cwd=str(self.root), text=True
            )
            dirty = [ln[3:].strip() for ln in out.splitlines() if ln.strip()]
        except Exception:
            pass

        team_commits: list[dict[str, str]] = []
        try:
            out = subprocess.check_output(
                ["git", "log", "-25", "--pretty=%h\t%s"], cwd=str(self.root), text=True
            )
            for ln in out.splitlines():
                h, _, subject = ln.partition("\t")
                if subject.startswith("team("):
                    team_commits.append({"hash": h, "subject": subject})
        except Exception:
            pass

        work = self._read_json(self.root / "ledger" / "WORK.json") or {}
        packages: list[dict[str, Any]] = []
        warnings: list[str] = []
        for p in work.get("packages") or []:
            pid = str(p.get("id") or "")
            status = str(p.get("status") or "")
            paths = [str(x) for x in (p.get("paths") or [])]
            commit = next((c for c in team_commits if pid and pid in c["subject"]), None)
            touched = [d for d in dirty if any(d.startswith(pfx) for pfx in paths)]
            entry = {
                "id": pid,
                "status": status,
                "assignee": p.get("assignee"),
                "paths": paths,
                "commit": commit,
                "dirty_touched": touched,
            }
            if status == "done" and not commit and not touched:
                entry["persisted"] = False
                warnings.append(
                    f"Paket {pid} ist „done“, aber es gibt weder einen team-Commit "
                    f"noch geänderte Dateien unter {', '.join(paths) or '—'} — "
                    f"möglicherweise wurde nichts gespeichert (Worker-CLI exit 0 ohne Writes)."
                )
            elif status == "dry-ok":
                entry["persisted"] = None  # Dry-Run: nichts zu erwarten
            else:
                entry["persisted"] = bool(commit or touched) if status == "done" else None
            packages.append(entry)

        return {
            "ok": not warnings,
            "stamp": utc_now(),
            "dirty_count": len(dirty),
            "dirty_files": dirty[:50],
            "team_commits": team_commits[:10],
            "packages": packages,
            "warnings": warnings,
        }

    # --- runs ---------------------------------------------------------------
    def start_run(
        self,
        task: str,
        *,
        verify: str = "true",
        profile: str = "auto",
        dry_run: bool = False,
        auto_plan: bool = False,
        skip_merge: bool = True,
        team_work: bool = True,
        fortify: bool = False,
    ) -> RunState:
        with self._run_lock:
            if self.active_run_id and self.runs.get(self.active_run_id):
                cur = self.runs[self.active_run_id]
                if cur.status in ("queued", "running"):
                    raise RuntimeError(f"Es läuft bereits ein Lauf: {cur.id} ({STATUS_DE.get(cur.status, cur.status)})")

            run_id = f"run-{iso_stamp()}-{uuid.uuid4().hex[:6]}"
            dual_run = self.root / "dual-run.sh"
            argv = ["bash", str(dual_run)]
            if task.strip():
                argv += ["--task", task.strip()]
            if verify.strip():
                argv += ["--verify", verify.strip()]
            if profile and profile != "auto":
                argv += ["--profile", profile]
            if dry_run:
                argv.append("--dry-run")
            if auto_plan:
                argv.append("--auto-plan")
            if skip_merge:
                argv.append("--skip-merge")
            if not team_work:
                argv.append("--no-team-work")
            if fortify:
                argv.append("--fortify")

            mode = {
                "profile": profile,
                "verify": verify,
                "dry_run": dry_run,
                "auto_plan": auto_plan,
                "skip_merge": skip_merge,
                "team_work": team_work,
                "fortify": fortify,
            }
            rs = RunState(run_id, task.strip(), argv, self.root, mode=mode)
            self.runs[run_id] = rs
            self.active_run_id = run_id

        def worker() -> None:
            rs.status = "running"
            rs.publish(f"$ {' '.join(argv)}\n")
            log_path = self.chat_dir / f"{run_id}.log"
            try:
                # Line-buffer dual-run so the dashboard sees CLI output live
                # (not one dump at process end). stdbuf is optional (GNU coreutils).
                run_argv = list(argv)
                if shutil.which("stdbuf"):
                    run_argv = ["stdbuf", "-oL", "-eL"] + run_argv
                with open(log_path, "w", encoding="utf-8") as logf:
                    proc = subprocess.Popen(
                        run_argv,
                        cwd=str(self.root),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        bufsize=1,
                        env={
                            **os.environ,
                            "LC_ALL": "C",
                            "PYTHONUNBUFFERED": "1",
                            # Prefer streamy vendor CLIs when they honor these
                            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": os.environ.get(
                                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1"
                            ),
                        },
                    )
                    rs.proc = proc
                    assert proc.stdout is not None
                    for line in proc.stdout:
                        logf.write(line)
                        logf.flush()
                        rs.publish(line.rstrip("\n"))
                    code = proc.wait()
                    rs.exit_code = code
                    rs.status = "succeeded" if code == 0 else "failed"
                    rs.publish(f"[exit {code}]")
            except Exception as e:
                rs.status = "failed"
                rs.exit_code = 1
                rs.publish(f"\n[error] {e}\n")
            finally:
                rs.finished_at = utc_now()
                rs.proc = None
                # system chat message (deutsch) + Persistenz-Check
                status_de = STATUS_DE.get(rs.status, rs.status)
                self.append_history(
                    "system",
                    f"Lauf `{run_id}` beendet: **{status_de}** (Exit {rs.exit_code}).",
                    {"run_id": run_id, "status": rs.status, "exit_code": rs.exit_code},
                )
                try:
                    if rs.mode.get("team_work") and not rs.mode.get("dry_run"):
                        pc = self.persistence_check()
                        if pc["warnings"]:
                            body_lines = ["**Persistenz-Check: WARNUNG**", ""]
                            body_lines += [f"- ⚠️ {w}" for w in pc["warnings"]]
                            body_lines += [
                                "",
                                "Details im Panel „Persistenz-Check“ (Mission-Leiste).",
                            ]
                        else:
                            done_n = sum(1 for p in pc["packages"] if p.get("status") == "done")
                            body_lines = [
                                f"**Persistenz-Check: OK** — {done_n} erledigte(s) Paket(e), "
                                f"{len(pc['team_commits'])} team-Commit(s), "
                                f"{pc['dirty_count']} uncommittete Datei(en)."
                            ]
                        self.append_history(
                            "system", "\n".join(body_lines), {"kind": "persistence", "data": pc}
                        )
                except Exception:
                    pass

        threading.Thread(target=worker, name=f"dual-run-{run_id}", daemon=True).start()
        self.append_history(
            "assistant",
            f"Lauf `{run_id}` gestartet.\n\n```\n{' '.join(argv)}\n```\n\n"
            f"**Modus:**\n{mode_summary_de(rs.mode)}\n\nLive-Log läuft…",
            {"run_id": run_id, "kind": "run_started", "mode": rs.mode},
        )
        return rs

    def cancel_run(self, run_id: str) -> dict:
        rs = self.runs.get(run_id)
        if not rs:
            raise KeyError(run_id)
        if rs.proc and rs.proc.poll() is None:
            try:
                rs.proc.send_signal(signal.SIGTERM)
                rs.publish("\n[cancel] SIGTERM sent\n")
            except Exception as e:
                rs.publish(f"\n[cancel error] {e}\n")
            rs.status = "cancelled"
            rs.finished_at = utc_now()
        return rs.snapshot()


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

APP: Optional[App] = None


class Handler(SimpleHTTPRequestHandler):
    server_version = "DualCraftChat/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def _send(self, code: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, obj: Any) -> None:
        raw = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
        self._send(code, raw, "application/json; charset=utf-8")

    def _read_json(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        try:
            return json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            return {}

    def do_OPTIONS(self) -> None:  # CORS not needed for same-origin; keep simple
        self.send_response(204)
        self.end_headers()

    def do_GET(self) -> None:
        assert APP is not None
        parsed = urlparse(self.path)
        path = parsed.path

        if path in ("/", "/index.html"):
            return self._serve_static("index.html", "text/html; charset=utf-8")
        if path.startswith("/static/"):
            rel = path[len("/static/") :]
            return self._serve_static(rel)

        if path == "/api/health":
            return self._json(200, {"ok": True, "stamp": utc_now()})

        if path == "/api/status":
            return self._json(200, APP.status())

        if path == "/api/persistence":
            return self._json(200, APP.persistence_check())

        if path == "/api/history":
            qs = parse_qs(parsed.query)
            limit = int((qs.get("limit") or ["200"])[0])
            return self._json(200, {"messages": APP.load_history(limit)})

        if path == "/api/who":
            qs = parse_qs(parsed.query)
            task = (qs.get("task") or [""])[0]
            profile = (qs.get("profile") or ["auto"])[0]
            return self._json(200, APP.who(task, profile))

        if path == "/api/runs":
            runs = [r.snapshot() for r in APP.runs.values()]
            runs.sort(key=lambda r: r.get("started_at") or "", reverse=True)
            return self._json(200, {"runs": runs[:50]})

        m = re.match(r"^/api/runs/([^/]+)$", path)
        if m:
            rs = APP.runs.get(m.group(1))
            if not rs:
                return self._json(404, {"error": "run not found"})
            return self._json(200, rs.snapshot())

        m = re.match(r"^/api/runs/([^/]+)/stream$", path)
        if m:
            return self._stream_run(m.group(1))

        return self._json(404, {"error": "not found", "path": path})

    def do_POST(self) -> None:
        assert APP is not None
        parsed = urlparse(self.path)
        path = parsed.path
        body = self._read_json()

        if path == "/api/history/clear":
            APP.clear_history()
            APP.append_history("system", "Verlauf geleert.", {"kind": "history_clear"})
            return self._json(200, {"ok": True})

        if path == "/api/chat":
            # conversational task message
            text = (body.get("message") or body.get("task") or "").strip()
            if not text:
                return self._json(400, {"error": "empty message"})
            if len(text) > 20_000:
                return self._json(400, {"error": "message too long (max 20000)"})

            user_msg = APP.append_history("user", text, {"kind": "task"})

            # who preview
            profile = body.get("profile") or "auto"
            who = APP.who(text, profile)
            profile_name = who.get("profile") or profile
            matrix = who.get("who_matrix") or []
            lines = [f"**Aufgabe erhalten.** Adaptives Profil: `{profile_name}`."]
            if matrix:
                lines.append("")
                lines.append("| Phase | Funktion | Agent |")
                lines.append("|---|---|---|")
                for row in matrix:
                    lines.append(
                        f"| {row.get('phase','')} | {row.get('function','')} | `{row.get('agent') or '—'}` |"
                    )
            lines.append("")
            if body.get("preview_only"):
                lines.append(
                    "**Nur Vorschau** — es wird kein Lauf gestartet und **nichts gespeichert**. "
                    "Zum Ausführen mit **Starten** senden."
                )
                asst = APP.append_history("assistant", "\n".join(lines), {"kind": "preview", "who": who})
                return self._json(200, {"user": user_msg, "assistant": asst, "who": who, "run": None})

            # start run
            try:
                rs = APP.start_run(
                    text,
                    verify=str(body.get("verify") or "true"),
                    profile=str(profile),
                    dry_run=bool(body.get("dry_run")),
                    auto_plan=bool(body.get("auto_plan", True)),
                    skip_merge=bool(body.get("skip_merge", True)),
                    team_work=bool(body.get("team_work", True)),
                    fortify=bool(body.get("fortify", False)),
                )
            except RuntimeError as e:
                asst = APP.append_history("assistant", f"**Blockiert:** {e}", {"kind": "error"})
                return self._json(409, {"error": str(e), "user": user_msg, "assistant": asst})

            lines.append(f"Starte Lauf `{rs.id}`…")
            asst = APP.append_history(
                "assistant",
                "\n".join(lines),
                {"kind": "run_started", "run_id": rs.id, "who": who},
            )
            return self._json(
                200,
                {"user": user_msg, "assistant": asst, "who": who, "run": rs.snapshot()},
            )

        if path == "/api/runs":
            task = (body.get("task") or "").strip()
            if not task:
                return self._json(400, {"error": "task required"})
            try:
                rs = APP.start_run(
                    task,
                    verify=str(body.get("verify") or "true"),
                    profile=str(body.get("profile") or "auto"),
                    dry_run=bool(body.get("dry_run")),
                    auto_plan=bool(body.get("auto_plan", True)),
                    skip_merge=bool(body.get("skip_merge", True)),
                    team_work=bool(body.get("team_work", True)),
                    fortify=bool(body.get("fortify", False)),
                )
            except RuntimeError as e:
                return self._json(409, {"error": str(e)})
            return self._json(200, rs.snapshot())

        m = re.match(r"^/api/runs/([^/]+)/cancel$", path)
        if m:
            try:
                snap = APP.cancel_run(m.group(1))
            except KeyError:
                return self._json(404, {"error": "run not found"})
            return self._json(200, snap)

        return self._json(404, {"error": "not found"})

    def _serve_static(self, rel: str, content_type: Optional[str] = None) -> None:
        # prevent path traversal
        rel = rel.lstrip("/").replace("..", "")
        path = (STATIC / rel).resolve()
        if not str(path).startswith(str(STATIC.resolve())) or not path.is_file():
            return self._json(404, {"error": "static not found", "rel": rel})
        data = path.read_bytes()
        if content_type is None:
            if rel.endswith(".css"):
                content_type = "text/css; charset=utf-8"
            elif rel.endswith(".js"):
                content_type = "application/javascript; charset=utf-8"
            elif rel.endswith(".svg"):
                content_type = "image/svg+xml"
            elif rel.endswith(".html"):
                content_type = "text/html; charset=utf-8"
            else:
                content_type = "application/octet-stream"
        self._send(200, data, content_type)

    def _stream_run(self, run_id: str) -> None:
        assert APP is not None
        rs = APP.runs.get(run_id)
        if not rs:
            return self._json(404, {"error": "run not found"})

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        q: queue.Queue = queue.Queue()
        # replay existing lines
        with rs._lock:
            history = list(rs.lines)
            rs.subscribers.append(q)

        try:
            for line in history:
                payload = json.dumps({"line": line, "status": rs.status})
                self.wfile.write(f"data: {payload}\n\n".encode("utf-8"))
            self.wfile.flush()

            while True:
                try:
                    line = q.get(timeout=1.0)
                    payload = json.dumps({"line": line, "status": rs.status})
                    self.wfile.write(f"data: {payload}\n\n".encode("utf-8"))
                    self.wfile.flush()
                except queue.Empty:
                    # heartbeat
                    try:
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                    except Exception:
                        break
                    if rs.status not in ("queued", "running") and q.empty():
                        payload = json.dumps(
                            {
                                "line": "",
                                "status": rs.status,
                                "done": True,
                                "exit_code": rs.exit_code,
                            }
                        )
                        self.wfile.write(f"data: {payload}\n\n".encode("utf-8"))
                        self.wfile.flush()
                        break
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with rs._lock:
                if q in rs.subscribers:
                    rs.subscribers.remove(q)


def main() -> int:
    global APP
    ap = argparse.ArgumentParser(description="Dual-Craft Chat Cockpit")
    ap.add_argument("--host", default="127.0.0.1", help="bind address (default localhost-only)")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--root", default=str(DEFAULT_ROOT), help="repo root")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not (root / "dual-run.sh").exists():
        print(f"BLOCKED: dual-run.sh not found under {root}", file=sys.stderr)
        return 1
    if not STATIC.is_dir():
        print(f"BLOCKED: UI static dir missing: {STATIC}", file=sys.stderr)
        return 1

    # safety: prefer localhost
    if args.host not in ("127.0.0.1", "localhost", "::1") and os.environ.get("DUAL_CHAT_ALLOW_REMOTE") != "1":
        print(
            "BLOCKED: refusing non-localhost bind (set DUAL_CHAT_ALLOW_REMOTE=1 to override).",
            file=sys.stderr,
        )
        return 1

    APP = App(root)
    if not APP.load_history(1):
        APP.append_history(
            "system",
            "Willkommen im **Dual-Craft Team-Cockpit**. Beschreibe eine Aufgabe in Alltagssprache — "
            "sie wird mit Gates und Live-Status an Claude, Grok und Codex verteilt.\n\n"
            "**Wichtig:** *Vorschau* startet nichts und speichert nichts · *Dry-Run* schreibt keinen Code · "
            "*Merge überspringen* lässt `main` unangetastet.",
            {"kind": "welcome"},
        )

    try:
        httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    except OSError as e:
        print(f"BLOCKED: cannot bind {args.host}:{args.port} — {e}", file=sys.stderr, flush=True)
        print("  Is dual-chat already running?  ./dual-chat.sh --status", file=sys.stderr, flush=True)
        print("  Or pick another port:         ./dual-chat.sh --port 8790", file=sys.stderr, flush=True)
        return 1

    print("Dual-Craft Chat Cockpit", flush=True)
    print(f"  repo  : {root}", flush=True)
    print(f"  url   : http://{args.host}:{args.port}/", flush=True)
    print(f"  bind  : {args.host}:{args.port} (local only)", flush=True)
    print("  stop  : Ctrl+C   or   ./dual-chat.sh --stop", flush=True)
    print("READY", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down…", flush=True)
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
