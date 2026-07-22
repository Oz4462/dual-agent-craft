#!/usr/bin/env python3
"""Smoke tests for ui/server.py (stdlib unittest, no network vendors)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ui"))


def http_json(method: str, url: str, body: dict | None = None, timeout: float = 5.0):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))


class ChatUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # ephemeral port
        cls.port = 18787
        cls.proc = subprocess.Popen(
            [
                sys.executable,
                str(ROOT / "ui" / "server.py"),
                "--host",
                "127.0.0.1",
                "--port",
                str(cls.port),
                "--root",
                str(ROOT),
            ],
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        cls.base = f"http://127.0.0.1:{cls.port}"
        # wait for health
        deadline = time.time() + 8
        last = None
        while time.time() < deadline:
            try:
                st, body = http_json("GET", cls.base + "/api/health")
                if st == 200 and body.get("ok"):
                    return
            except Exception as e:
                last = e
                time.sleep(0.15)
        cls.proc.kill()
        out = cls.proc.stdout.read() if cls.proc.stdout else ""
        raise RuntimeError(f"server failed to start: {last}\n{out}")

    @classmethod
    def tearDownClass(cls):
        if cls.proc.poll() is None:
            cls.proc.terminate()
            try:
                cls.proc.wait(timeout=3)
            except Exception:
                cls.proc.kill()

    def test_health(self):
        st, body = http_json("GET", self.base + "/api/health")
        self.assertEqual(st, 200)
        self.assertTrue(body["ok"])

    def test_index(self):
        with urllib.request.urlopen(self.base + "/", timeout=5) as r:
            html = r.read().decode("utf-8")
        self.assertIn("Dual-Craft", html)
        self.assertIn("btnSend", html)
        self.assertIn("composer", html)
        self.assertIn("lang=\"de\"", html)
        self.assertIn("Starten", html)
        self.assertIn("/static/app.js", html)
        self.assertIn("/static/app.css", html)

    def test_status(self):
        st, body = http_json("GET", self.base + "/api/status")
        self.assertEqual(st, 200)
        self.assertIn("clis", body)
        self.assertIn("git", body)

    def test_who(self):
        st, body = http_json("GET", self.base + "/api/who?task=tiny+spike")
        self.assertEqual(st, 200)
        self.assertTrue("profile" in body or "error" in body or "functions" in body)

    def test_chat_preview(self):
        st, body = http_json(
            "POST",
            self.base + "/api/chat",
            {
                "message": "Tiny hello world spike",
                "preview_only": True,
                "profile": "minimal",
                "dry_run": True,
            },
        )
        self.assertEqual(st, 200)
        self.assertEqual(body["user"]["role"], "user")
        self.assertEqual(body["assistant"]["role"], "assistant")
        self.assertIsNone(body.get("run"))
        # Deutsch + Transparenz: Vorschau speichert nichts
        self.assertIn("Vorschau", body["assistant"]["content"])
        self.assertIn("nichts gespeichert", body["assistant"]["content"])

    def test_persistence_endpoint(self):
        st, body = http_json("GET", self.base + "/api/persistence")
        self.assertEqual(st, 200)
        for key in ("ok", "packages", "warnings", "team_commits", "dirty_count"):
            self.assertIn(key, body)
        self.assertIsInstance(body["packages"], list)
        self.assertIsInstance(body["warnings"], list)

    def test_index_mode_and_persist_cards(self):
        with urllib.request.urlopen(self.base + "/", timeout=5) as r:
            html = r.read().decode("utf-8")
        self.assertIn("modeChips", html)
        self.assertIn("persistCard", html)
        self.assertIn("Persistenz-Check", html)

    def test_history(self):
        st, body = http_json("GET", self.base + "/api/history")
        self.assertEqual(st, 200)
        self.assertIn("messages", body)
        self.assertGreaterEqual(len(body["messages"]), 1)


if __name__ == "__main__":
    unittest.main()
