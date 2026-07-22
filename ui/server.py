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


class RunState:
    def __init__(self, run_id: str, task: str, argv: list[str], cwd: Path):
        self.id = run_id
        self.task = task
        self.argv = argv
        self.cwd = cwd
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
                "tail": self.lines[-80:],
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
                    raise RuntimeError(f"run already active: {cur.id} ({cur.status})")

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

            rs = RunState(run_id, task.strip(), argv, self.root)
            self.runs[run_id] = rs
            self.active_run_id = run_id

        def worker() -> None:
            rs.status = "running"
            rs.publish(f"$ {' '.join(argv)}\n")
            log_path = self.chat_dir / f"{run_id}.log"
            try:
                with open(log_path, "w", encoding="utf-8") as logf:
                    proc = subprocess.Popen(
                        argv,
                        cwd=str(self.root),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        bufsize=1,
                        env={**os.environ, "LC_ALL": "C", "PYTHONUNBUFFERED": "1"},
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
                    rs.publish(f"\n[exit {code}]\n")
            except Exception as e:
                rs.status = "failed"
                rs.exit_code = 1
                rs.publish(f"\n[error] {e}\n")
            finally:
                rs.finished_at = utc_now()
                rs.proc = None
                # system chat message
                self.append_history(
                    "system",
                    f"Run {run_id} finished: **{rs.status}** (exit={rs.exit_code}).",
                    {"run_id": run_id, "status": rs.status, "exit_code": rs.exit_code},
                )

        threading.Thread(target=worker, name=f"dual-run-{run_id}", daemon=True).start()
        self.append_history(
            "assistant",
            f"Started dual-run `{run_id}`.\n\n```\n{' '.join(argv)}\n```\n\nStreaming logs…",
            {"run_id": run_id, "kind": "run_started"},
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
            APP.append_history("system", "History cleared.", {"kind": "history_clear"})
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
            lines = [f"**Task received.** Adaptive profile: `{profile_name}`."]
            if matrix:
                lines.append("")
                lines.append("| Phase | Function | Agent |")
                lines.append("|---|---|---|")
                for row in matrix:
                    lines.append(
                        f"| {row.get('phase','')} | {row.get('function','')} | `{row.get('agent') or '—'}` |"
                    )
            lines.append("")
            if body.get("preview_only"):
                lines.append("Preview only — not starting a run. Send again with **Run** to execute.")
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
                asst = APP.append_history("assistant", f"**Blocked:** {e}", {"kind": "error"})
                return self._json(409, {"error": str(e), "user": user_msg, "assistant": asst})

            lines.append(f"Starting dual-run `{rs.id}`…")
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
            "Welcome to the **Dual-Craft Chat Cockpit**. Describe a task in plain language — "
            "I will route it through Claude, Grok, and Codex with gates and a live status rail.",
            {"kind": "welcome"},
        )

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Dual-Craft Chat Cockpit")
    print(f"  repo  : {root}")
    print(f"  url   : http://{args.host}:{args.port}/")
    print(f"  bind  : {args.host}:{args.port} (local only)")
    print(f"  stop  : Ctrl+C")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down…")
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
