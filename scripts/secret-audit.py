#!/usr/bin/env python3
"""Scan git-tracked files + history for private keys / vendor API tokens.

Exit 0 = clean, exit 1 = findings.
Usage: python3 scripts/secret-audit.py
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("private_key_pem", re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----")),
    ("openai_sk", re.compile(r"\bsk-[a-zA-Z0-9]{20,}\b")),
    ("anthropic_sk", re.compile(r"\bsk-ant-[a-zA-Z0-9_-]{20,}\b")),
    ("github_pat", re.compile(r"\b(?:ghp_|gho_|ghu_|ghs_|ghr_)[a-zA-Z0-9]{20,}\b")),
    ("github_fine", re.compile(r"\bgithub_pat_[a-zA-Z0-9_]{20,}\b")),
    ("aws_key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("google_api", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b")),
    ("slack", re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{10,}\b")),
    ("jwt", re.compile(r"\beyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\b")),
    ("bearer", re.compile(r"Bearer\s+[a-zA-Z0-9._\-]{20,}")),
    ("xai_key", re.compile(r"\bxai-[a-zA-Z0-9]{20,}\b", re.I)),
    (
        "secret_assign",
        re.compile(
            r"(?i)(api[_-]?key|client_secret|password|access_token|refresh_token)\s*[=:]\s*['\"][^'\"]{12,}['\"]"
        ),
    ),
]


def tracked_files() -> list[str]:
    out = subprocess.check_output(["git", "ls-files"], text=True)
    return [ln for ln in out.splitlines() if ln]


def scan_text(label: str, text: str) -> list[tuple[str, str, str]]:
    hits: list[tuple[str, str, str]] = []
    for name, pat in PATTERNS:
        for m in pat.finditer(text):
            snip = text[max(0, m.start() - 30) : m.end() + 30].replace("\n", " ")
            hits.append((label, name, snip[:140]))
    return hits


def main() -> int:
    root = Path(".").resolve()
    if not (root / ".git").exists():
        print("BLOCKED: run from git repo root", file=sys.stderr)
        return 2

    findings: list[tuple[str, str, str]] = []
    files = tracked_files()
    for f in files:
        try:
            text = Path(f).read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            findings.append((f, "read_error", str(e)))
            continue
        findings.extend(scan_text(f, text))

    # history (all commits, all blobs)
    commits = subprocess.check_output(["git", "rev-list", "--all"], text=True).splitlines()
    for c in commits:
        try:
            names = subprocess.check_output(
                ["git", "ls-tree", "-r", "--name-only", c], text=True
            ).splitlines()
        except subprocess.CalledProcessError:
            continue
        for f in names:
            try:
                blob = subprocess.check_output(
                    ["git", "show", f"{c}:{f}"], stderr=subprocess.DEVNULL
                )
            except subprocess.CalledProcessError:
                continue
            text = blob.decode("utf-8", errors="replace")
            for hit in scan_text(f"{c[:7]}:{f}", text):
                findings.append(hit)

    print(f"tracked_files={len(files)} commits={len(commits)} findings={len(findings)}")
    if findings:
        for label, name, snip in findings:
            print(f"FAIL [{name}] {label}: {snip}")
        print("VERDICT: FAIL — rotate any real credentials and purge history")
        return 1

    print("VERDICT: PASS — no private keys / vendor API tokens detected in tree or history")
    return 0


if __name__ == "__main__":
    sys.exit(main())
