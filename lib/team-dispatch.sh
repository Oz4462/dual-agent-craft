#!/usr/bin/env bash
# team-dispatch.sh — after PLAN is ready, ALL workers execute: Claude + Grok + Codex.
#
# Architect (Claude) still owns PLAN, but ALSO receives ≥1 work package and codes.
# Packages are path-disjoint. Assignment is capability-biased + fair (every worker
# works when ≥3 packages and CLIs are available).
#
# Commands:
#   lib/team-dispatch.sh decompose --plan PLAN.md [--out ledger/WORK.json] [--task T]
#   lib/team-dispatch.sh assign    --work ledger/WORK.json [--out …]
#   lib/team-dispatch.sh execute   --work ledger/WORK.json [--plan PLAN.md] [--dry-run]
#   lib/team-dispatch.sh status    --work ledger/WORK.json
#   lib/team-dispatch.sh run       --plan PLAN.md [--task T] [--dry-run]
#                                  # decompose + assign + execute
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$_HERE/common.sh"

team_config_path() {
  if [[ -n "${DUAL_TEAM_WORK_CONFIG:-}" ]]; then
    printf '%s\n' "$DUAL_TEAM_WORK_CONFIG"
    return
  fi
  printf '%s\n' "$(cd "$_HERE/.." && pwd)/config/team-work.json"
}

_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    cd "$_HERE/.." && pwd
  fi
}

# --- decompose: PLAN → work packages (deterministic, offline) ---------------
cmd_decompose() {
  local plan="" out="" task=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan) plan="${2:?}"; shift 2;;
      --out)  out="${2:?}"; shift 2;;
      --task) task="${2:?}"; shift 2;;
      *) fail "decompose: unknown arg '$1'";;
    esac
  done
  [[ -n "$plan" && -f "$plan" ]] || fail "decompose: --plan required"
  [[ -n "$out" ]] || out="$(_root)/ledger/WORK.json"
  mkdir -p "$(dirname "$out")"

  PLAN="$plan" OUT="$out" TASK="$task" CFG="$(team_config_path)" python3 - <<'PY'
import json, os, re, sys
from datetime import datetime, timezone

plan = open(os.environ["PLAN"], encoding="utf-8", errors="replace").read()
cfg_path = os.environ.get("CFG", "")
cfg = {}
if cfg_path and os.path.isfile(cfg_path):
    try:
        cfg = json.load(open(cfg_path, encoding="utf-8"))
    except Exception:
        cfg = {}
task = os.environ.get("TASK") or ""

def section(name_pat: str) -> str:
    """Grab markdown ## section body until the next ## (no DOTALL — safer)."""
    lines = plan.splitlines()
    capturing = False
    body = []
    hdr = re.compile(rf"(?i)^##\s+.*(?:{name_pat}).*$")
    any_hdr = re.compile(r"^##\s+")
    for line in lines:
        if any_hdr.match(line):
            if capturing:
                break
            if hdr.match(line):
                capturing = True
            continue
        if capturing:
            body.append(line)
    return "\n".join(body)

def bullets(text: str):
    items = []
    if not text:
        return items
    for line in text.splitlines():
        line = line.strip()
        # - [ ] crit   or  - crit  or * crit
        m = re.match(r"^(?:[-*+]|\d+\.)\s+(?:\[.\]\s*)?(.+)$", line)
        if m:
            t = m.group(1).strip()
            if t and not t.startswith("<") and "Kriterium" not in t:
                items.append(t)
    return items

acc = bullets(section(r"Akzeptanz|Acceptance|4\."))
tests = bullets(section(r"Test-Liste|Test list|5\."))
iface = bullets(section(r"Interface|3\."))
# also pull fenced signatures loosely
for line in (section(r"Interface|3\.") or "").splitlines():
    if re.search(r"function\s+\w+|def\s+\w+|class\s+\w+|^\s*[\w.]+\(.*\)\s*->", line):
        s = line.strip().lstrip("#").strip()
        if s and s not in iface:
            iface.append(s)

packages = []
n = 0

def add(kind, title, paths, allows_tests=False, tags=None):
    global n
    n += 1
    packages.append({
        "id": f"WP{n:02d}",
        "kind": kind,
        "title": title[:200],
        "paths": paths,
        "allows_tests": allows_tests,
        "tags": tags or [kind],
        "status": "pending",
        "assignee": None,
        "evidence": None,
    })

# Map acceptance criteria → impl packages
for i, c in enumerate(acc[:6]):
    kind = "core_impl"
    low = c.lower()
    if any(k in low for k in ("error", "fail", "invalid", "edge", "empty", "timeout")):
        kind = "error_handling"
    if any(k in low for k in ("auth", "secret", "security", "token", "permission")):
        kind = "security"
    if any(k in low for k in ("file", "path", "shell", "network", "upload", "download")):
        kind = "risky_io"
    paths = ["src/"]
    if kind == "risky_io":
        paths = ["src/", "scripts/"]
    if kind == "security":
        paths = ["src/", "src/security/"]
    add(kind, f"Implement: {c}", paths, tags=[kind, "acceptance", f"A{i+1}"])

# Interface leftovers as core if no acceptance
if not packages and iface:
    for i, sig in enumerate(iface[:4]):
        add("core_impl", f"Implement interface: {sig}", ["src/"], tags=["interface"])

# Always: edge package if we only have one happy path
if len(packages) == 1:
    add("error_handling", "Fail-closed edge cases and input validation", ["src/"], tags=["error_handling"])

# Claude-owned tests package (architect also works — pins tests)
dec = cfg.get("decompose") or {}
if dec.get("always_emit_test_package_for_claude", True):
    ttitle = "Pin acceptance tests"
    if tests:
        ttitle = "Pin tests: " + "; ".join(tests[:3])
    add("tests", ttitle, ["tests/", "verify/"], allows_tests=True, tags=["tests"])

# Fallback triad
if len(packages) < int((cfg.get("min_packages") or 3)):
    for fb in (dec.get("fallback_packages") or []):
        if len(packages) >= 3:
            break
        allows = fb.get("kind") == "tests"
        paths = ["tests/", "verify/"] if allows else ["src/"]
        add(fb.get("kind", "core_impl"), fb.get("title", "Work"), paths, allows_tests=allows, tags=[fb.get("kind", "core_impl")])

# Ensure unique path ownership hints: later packages get subdirs
for i, p in enumerate(packages):
    if p["kind"] == "tests":
        p["paths"] = ["tests/", "verify/"]
    elif p["kind"] == "risky_io":
        p["paths"] = [f"src/pkg{i:02d}/", "scripts/"]
    elif p["kind"] == "security":
        p["paths"] = [f"src/pkg{i:02d}/", "src/security/"]
    else:
        p["paths"] = [f"src/pkg{i:02d}/"]

work = {
    "version": 1,
    "stamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "plan": os.environ["PLAN"],
    "task": task,
    "phase": "decomposed",
    "packages": packages,
    "policy": "path-disjoint sequential execution; all workers code",
}
open(os.environ["OUT"], "w", encoding="utf-8").write(json.dumps(work, indent=2) + "\n")
print(os.environ["OUT"])
print(f"packages={len(packages)}", file=sys.stderr)
PY
  local rc=$?
  [[ $rc -eq 0 && -f "$out" ]] || fail "decompose failed (python exit=$rc)"
  ok "decomposed → $out"
}

# --- assign: packages → claude/grok/codex (all work) ------------------------
cmd_assign() {
  local work="" out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --work) work="${2:?}"; shift 2;;
      --out)  out="${2:?}"; shift 2;;
      *) fail "assign: unknown arg '$1'";;
    esac
  done
  [[ -n "$work" ]] || fail "assign: --work required"
  [[ -f "$work" ]] || fail "assign: work file missing: $work"
  [[ -n "$out" ]] || out="$work"

  WORK="$work" OUT="$out" CFG="$(team_config_path)" python3 - <<'PY'
import json, os, shutil, sys
from datetime import datetime, timezone

work = json.load(open(os.environ["WORK"], encoding="utf-8"))
cfg = {}
cp = os.environ.get("CFG", "")
if cp and os.path.isfile(cp):
    cfg = json.load(open(cp, encoding="utf-8"))

workers_cfg = list(cfg.get("workers") or ["claude", "grok", "codex"])
# Availability: only assign to CLIs present (still prefer all three)
def has(cli):
    return shutil.which(cli) is not None

available = [w for w in workers_cfg if has(w)]
if not available:
    # offline tests: pretend all workers available
    available = list(workers_cfg)

prefer = (cfg.get("assignment_policy") or {}).get("prefer") or {}
never_tests = set((cfg.get("assignment_policy") or {}).get("never_assign_tests_to") or ["grok", "codex"])
require_all = bool(cfg.get("require_all_workers", True))
architect_works = bool(cfg.get("architect_also_works", True))

packages = work.get("packages") or []

def score(worker, pkg):
    tags = set(pkg.get("tags") or [pkg.get("kind")])
    prefs = set(prefer.get(worker) or [])
    s = 0
    for t in tags:
        if t in prefs:
            s += 3
        # soft keyword match
        for p in prefs:
            if p in t or t in p:
                s += 1
    if pkg.get("allows_tests") or pkg.get("kind") == "tests":
        if worker in never_tests:
            s -= 100
        if worker == "claude":
            s += 10
    if worker == "codex" and pkg.get("kind") in ("risky_io", "sandbox"):
        s += 5
    if worker == "grok" and pkg.get("kind") in ("core_impl", "feature", "api", "cli"):
        s += 3
    return s

# Fair assignment: first ensure each available worker gets best remaining package
assigned_counts = {w: 0 for w in available}
remaining = list(range(len(packages)))

def take_for(worker):
    global remaining
    best_i, best_s = None, -10**9
    for i in remaining:
        pkg = packages[i]
        if (pkg.get("allows_tests") or pkg.get("kind") == "tests") and worker in never_tests:
            continue
        sc = score(worker, pkg)
        if sc > best_s:
            best_s, best_i = sc, i
    if best_i is None:
        return False
    packages[best_i]["assignee"] = worker
    packages[best_i]["status"] = "assigned"
    assigned_counts[worker] = assigned_counts.get(worker, 0) + 1
    remaining = [j for j in remaining if j != best_i]
    return True

# Round 1: every worker at least one (if enough packages)
if require_all and len(packages) >= len(available):
    # Claude first if architect_also_works (tests package)
    order = list(available)
    if architect_works and "claude" in order:
        order = ["claude"] + [w for w in order if w != "claude"]
    for w in order:
        take_for(w)

# Round 2: remaining by best score among workers (balance load)
while remaining:
    # least loaded worker
    worker = min(available, key=lambda w: (assigned_counts.get(w, 0), w))
    # but prefer best scoring worker for this package
    i = remaining[0]
    pkg = packages[i]
    ranked = sorted(available, key=lambda w: (-score(w, pkg), assigned_counts.get(w, 0)))
    chosen = None
    for w in ranked:
        if (pkg.get("allows_tests") or pkg.get("kind") == "tests") and w in never_tests:
            continue
        chosen = w
        break
    if chosen is None:
        chosen = "claude" if "claude" in available else available[0]
    packages[i]["assignee"] = chosen
    packages[i]["status"] = "assigned"
    assigned_counts[chosen] = assigned_counts.get(chosen, 0) + 1
    remaining.pop(0)

# Hard guarantee: architect works
if architect_works and "claude" in available:
    if assigned_counts.get("claude", 0) == 0 and packages:
        # steal a non-test package for claude or give tests
        for p in packages:
            if p.get("kind") == "tests" or p.get("allows_tests"):
                p["assignee"] = "claude"
                assigned_counts["claude"] = assigned_counts.get("claude", 0) + 1
                # reduce previous
                break
        else:
            packages[0]["assignee"] = "claude"

work["packages"] = packages
work["phase"] = "assigned"
work["assignment"] = assigned_counts
work["available_workers"] = available
work["stamp_assigned"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
# roster summary
work["roster"] = {
    w: [p["id"] for p in packages if p.get("assignee") == w]
    for w in workers_cfg
}

# Path-disjointness validator (fail-closed): no prefix overlap between packages
# unless package has shared:true (rare; not used by default decompose).
def norm_prefixes(pkg):
    out = []
    for p in pkg.get("paths") or []:
        p = str(p).strip().lstrip("./")
        if not p:
            continue
        out.append(p if p.endswith("/") else p + "/")
    return out

def overlaps(a, b):
    for x in a:
        for y in b:
            if x == y or x.startswith(y) or y.startswith(x):
                return True
    return False

overlap_errs = []
for i in range(len(packages)):
    if packages[i].get("shared"):
        continue
    pi = norm_prefixes(packages[i])
    for j in range(i + 1, len(packages)):
        if packages[j].get("shared"):
            continue
        pj = norm_prefixes(packages[j])
        if pi and pj and overlaps(pi, pj):
            overlap_errs.append(
                f"{packages[i].get('id')} paths {pi} overlap {packages[j].get('id')} paths {pj}"
            )
if overlap_errs:
    print("BLOCKED: path-disjoint violation:", file=sys.stderr)
    for e in overlap_errs:
        print(f"  ! {e}", file=sys.stderr)
    sys.exit(2)

open(os.environ["OUT"], "w", encoding="utf-8").write(json.dumps(work, indent=2) + "\n")
print(json.dumps({"out": os.environ["OUT"], "assignment": assigned_counts, "roster": work["roster"]}))
# fairness check
missing = [w for w in available if assigned_counts.get(w, 0) == 0]
if missing and len(packages) >= len(available):
    print(f"WARN: workers without packages: {missing}", file=sys.stderr)
    sys.exit(2)
PY
  local assign_rc=$?
  if [[ $assign_rc -ne 0 ]]; then
    fail "assign failed (python exit=$assign_rc) — see path-disjoint / fairness errors above"
  fi
  ok "assigned → $out"
}

# --- execute: each worker runs their packages --------------------------------
cmd_execute() {
  local work="" plan="" dry=false max_turns=30
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --work) work="${2:?}"; shift 2;;
      --plan) plan="${2:?}"; shift 2;;
      --dry-run) dry=true; shift;;
      --max-turns) max_turns="${2:?}"; shift 2;;
      *) fail "execute: unknown arg '$1'";;
    esac
  done
  [[ -n "$work" && -f "$work" ]] || fail "execute: --work required"
  [[ -n "$plan" ]] || plan="$(json_field "$work" plan)"
  [[ -f "$plan" ]] || fail "execute: plan missing: $plan"

  local root n i
  root="$(_root)"
  n="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("packages")or[]))' "$work")"
  info "=== Team execute: $n packages (Claude+Grok+Codex work) ==="
  python3 -c '
import json,sys
w=json.load(open(sys.argv[1]))
for p in w.get("packages") or []:
    print("  %-6s  %-7s  %-16s  %s" % (
        p.get("id",""), str(p.get("assignee")), p.get("kind",""), (p.get("title") or "")[:60]))
' "$work"

  if [[ "$dry" == true ]]; then
    warn "DryRun — no vendor calls; marking packages dry-ok."
    WORK="$work" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
w=json.load(open(os.environ["WORK"], encoding="utf-8"))
for p in w.get("packages") or []:
    p["status"]="dry-ok"
    p["evidence"]="dry-run"
w["phase"]="executed-dry"
w["stamp_executed"]=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
open(os.environ["WORK"],"w",encoding="utf-8").write(json.dumps(w,indent=2)+"\n")
PY
    ok "team execute dry-run complete."
    return 0
  fi

  # _team_mark_package <work> <idx> <status> [evidence]
  # Optional env: FILES_JSON='["a"]' COMMIT_SHA=abc (evidence schema)
  _team_mark_package() {
    WORK="$1" IDX="$2" ST="$3" EV="${4:-}" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
w = json.load(open(os.environ["WORK"], encoding="utf-8"))
p = w["packages"][int(os.environ["IDX"])]
p["status"] = os.environ["ST"]
if os.environ.get("EV"):
    p["evidence"] = os.environ["EV"]
fj = os.environ.get("FILES_JSON", "").strip()
if fj:
    try:
        p["files_changed"] = json.loads(fj)
    except Exception:
        p["files_changed"] = []
cs = os.environ.get("COMMIT_SHA", "").strip()
if cs:
    p["commit_sha"] = cs
if os.environ["ST"] in ("done", "failed"):
    p["finished_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
open(os.environ["WORK"], "w", encoding="utf-8").write(json.dumps(w, indent=2) + "\n")
PY
  }

  # Sequential path-locked execution
  for ((i=0; i<n; i++)); do
    local id assignee title kind paths_json status
    id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][int(sys.argv[2])]["id"])' "$work" "$i")"
    assignee="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][int(sys.argv[2])].get("assignee")or"")' "$work" "$i")"
    title="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][int(sys.argv[2])].get("title")or"")' "$work" "$i")"
    kind="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][int(sys.argv[2])].get("kind")or"")' "$work" "$i")"
    paths_json="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["packages"][int(sys.argv[2])].get("paths")or[]))' "$work" "$i")"
    status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][int(sys.argv[2])].get("status")or"")' "$work" "$i")"
    [[ "$status" == "done" || "$status" == "dry-ok" ]] && continue
    [[ -n "$assignee" ]] || fail "package $id has no assignee"

    info "\n── $id · worker=$assignee · $kind ──"
    log "title : $title"
    log "paths : $paths_json"

    command -v "$assignee" >/dev/null 2>&1 || fail "worker CLI not in PATH: $assignee (package $id)"

    # Mark in progress
    _team_mark_package "$work" "$i" "in_progress" "worker=$assignee started"

    # Snapshot porcelain BEFORE worker so pre-existing dirty files are not trespass.
    local baseline_porc=""
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      baseline_porc="$(git -C "$root" status --porcelain -uall 2>/dev/null || true)"
    fi

    local pf tmpdir
    tmpdir="$root/.dual-agent/tmp"
    mkdir -p "$tmpdir"
    pf="$tmpdir/team-$id-$assignee-$(utc_stamp).txt"
    local plan_text allows_tests_note
    plan_text="$(tr -d '\r' <"$plan")"
    allows_tests_note="NEVER edit tests/ or verify/ — another teammate owns tests."
    if [[ "$kind" == "tests" || "$assignee" == "claude" ]]; then
      # Claude may write tests when package allows
      if python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["packages"][int(sys.argv[2])]; sys.exit(0 if (p.get("allows_tests") or p.get("kind")=="tests") else 1)' "$work" "$i"; then
        allows_tests_note="You MAY write tests/ and verify/ for THIS package only. Pin acceptance criteria as real tests."
      fi
    fi

    cat >"$pf" <<EOF
You are a WORKER on a 3-agent team (Claude Code + Grok + Codex). You are NOT alone:
other teammates implement other path-disjoint packages in parallel (sequentially integrated).

YOUR IDENTITY: $assignee
PACKAGE: $id ($kind)
TITLE: $title
OWNED PATHS (write ONLY under these prefixes): $paths_json
$allows_tests_note

Rules:
- Smallest correct implementation for THIS package only.
- Do not rewrite other packages' directories.
- No secrets. No invented dependencies outside PLAN allow-list.
- You MUST create or modify at least one real file under OWNED PATHS.
- Exit 0 with no filesystem changes is a FAILURE (harness fail-closed).
- Commit is done by the harness after you finish; just write files.

=== FULL CONTRACT (PLAN.md) ===
$plan_text
EOF

    local rc=0
    case "$assignee" in
      grok)
        "$_HERE/grok-call.sh" --prompt-file "$pf" --cwd "$root" --max-turns "$max_turns" \
          --always-approve --tag "team-$id-grok" \
          --deny 'Bash(rm -rf *)' --deny 'Bash(git push *)' \
          >/dev/null || rc=$?
        ;;
      codex)
        "$_HERE/codex-call.sh" --prompt-file "$pf" --cwd "$root" \
          --sandbox workspace-write --tag "team-$id-codex" \
          >/dev/null || rc=$?
        ;;
      claude)
        # Claude as worker: may use Write/Edit (not assess-only disallowed)
        (
          cd "$root" || exit 1
          "$_HERE/claude-call.sh" --prompt-file "$pf" --tag "team-$id-claude"
        ) >/dev/null || rc=$?
        ;;
      *) fail "unknown worker $assignee";;
    esac

    if [[ $rc -ne 0 ]]; then
      _team_mark_package "$work" "$i" "failed" "worker=$assignee exit=$rc"
      fail "team package $id failed (worker=$assignee exit=$rc)"
    fi

    # Classify git changes: owned vs noise vs trespass.
    # - noise (.dual-agent/, ledger/) never counts as success or trespass
    # - owned paths must have ≥1 change (fail-closed empty)
    # - non-noise outside owned paths = trespass (fail-closed)
    local classify_json package_changes trespass_changes
    classify_json="$(
      PATHS_JSON="$paths_json" ROOT="$root" BASELINE="$baseline_porc" python3 - <<'PY'
import json, os, subprocess

root = os.environ["ROOT"]
baseline_raw = os.environ.get("BASELINE") or ""

def clean_rel(p: str) -> str:
    """Normalize repo-relative path. NEVER use lstrip('./') — that strips dots from .dual-agent."""
    p = str(p).strip().strip('"')
    while p.startswith("./"):
        p = p[2:]
    return p

def parse_porc(text: str) -> dict:
    """path -> full porcelain line (status)."""
    m = {}
    for ln in (text or "").splitlines():
        if not ln.strip():
            continue
        path = ln[3:].strip()
        if " -> " in path:
            path = path.split(" -> ", 1)[1].strip()
        path = clean_rel(path)
        m[path] = ln
    return m

prefixes = []
for p in json.loads(os.environ.get("PATHS_JSON") or "[]"):
    p = clean_rel(p)
    if not p:
        continue
    prefixes.append(p if p.endswith("/") else p + "/")

# Harness / orchestration surfaces — never success, never trespass.
noise_prefixes = (".dual-agent/", "ledger/")
noise_names = ("HANDOFF.md", "PLAN.md", "WORK.json", "MEMORY.md")
# Common local artifacts that must never fail a package
noise_suffixes = ("_preview.png", ".pyc")
noise_contains = ("/__pycache__/",)

def kind(rel: str) -> str:
    rel = clean_rel(rel)
    base = rel.rsplit("/", 1)[-1]
    if base in noise_names or rel in noise_names:
        return "noise"
    if any(rel.endswith(s) for s in noise_suffixes):
        return "noise"
    if any(s in ("/" + rel) or s in rel for s in noise_contains):
        return "noise"
    if any(rel == n.rstrip("/") or rel.startswith(n) for n in noise_prefixes):
        return "noise"
    if not prefixes:
        return "owned"
    if any(rel == p.rstrip("/") or rel.startswith(p) for p in prefixes):
        return "owned"
    return "trespass"

before = parse_porc(baseline_raw)
try:
    out = subprocess.check_output(
        ["git", "status", "--porcelain", "-uall"],
        cwd=root, text=True, stderr=subprocess.DEVNULL,
    )
except Exception:
    out = ""
after = parse_porc(out)

# Only paths that are NEW or CHANGED since package start (delta).
delta_paths = []
for path, ln in after.items():
    if path not in before or before[path] != ln:
        delta_paths.append(path)

owned, trespass, all_non_noise = [], [], []
for path in sorted(delta_paths):
    k = kind(path)
    if k == "owned":
        owned.append(path)
        all_non_noise.append(path)
    elif k == "trespass":
        trespass.append(path)
        all_non_noise.append(path)
print(json.dumps({"owned": owned, "trespass": trespass, "all": all_non_noise, "delta": delta_paths}))
PY
    )"
    package_changes="$(printf '%s' "$classify_json" | python3 -c 'import sys,json; print("\n".join(json.load(sys.stdin).get("owned")or[]))')"
    trespass_changes="$(printf '%s' "$classify_json" | python3 -c 'import sys,json; print("\n".join(json.load(sys.stdin).get("trespass")or[]))')"

    if [[ -n "${trespass_changes//[$'\t\r\n ']/}" ]]; then
      FILES_JSON="$(printf '%s' "$classify_json" | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin).get("trespass")or[]))')" \
        _team_mark_package "$work" "$i" "failed" \
        "fail-closed: trespass outside owned paths (worker=$assignee): $(printf '%s' "$trespass_changes" | tr '\n' ' ')"
      fail "team package $id trespass (worker=$assignee wrote outside owned paths) — fail-closed: $trespass_changes"
    fi

    if [[ -z "${package_changes//[$'\t\r\n ']/}" ]]; then
      _team_mark_package "$work" "$i" "failed" \
        "fail-closed: worker=$assignee exit=0 but no filesystem changes under package paths"
      fail "team package $id produced no file changes (worker=$assignee) — fail-closed (done without files is forbidden)"
    fi

    # Commit package work (include full dirty tree — standard team integrate)
    local commit_sha=""
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git -C "$root" add -A
      git -C "$root" commit -q -m "team($assignee): $id $title [no-push]" \
        || {
          _team_mark_package "$work" "$i" "failed" "worker=$assignee wrote files but commit failed"
          fail "team package $id: commit failed after writes (worker=$assignee)"
        }
      commit_sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)"
    fi

    FILES_JSON="$(printf '%s' "$classify_json" | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin).get("owned")or[]))')" \
      COMMIT_SHA="$commit_sha" \
      _team_mark_package "$work" "$i" "done" "worker=$assignee finished + files committed"
    ok "$id done by $assignee (files=$(printf '%s' "$package_changes" | wc -l) sha=${commit_sha:-n/a})"
  done

  WORK="$work" python3 - <<'PY'
import json,os
from datetime import datetime, timezone
w=json.load(open(os.environ["WORK"],encoding="utf-8"))
w["phase"]="executed"
w["stamp_executed"]=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
open(os.environ["WORK"],"w",encoding="utf-8").write(json.dumps(w,indent=2)+"\n")
PY
  ok "team execute complete — all workers contributed."
}

cmd_status() {
  local work="${1:-}"
  [[ -z "$work" ]] && work="$(_root)/ledger/WORK.json"
  [[ -f "$work" ]] || fail "no work file: $work"
  python3 - "$work" <<'PY'
import json,sys
w=json.load(open(sys.argv[1], encoding="utf-8"))
print(f"=== team work ({w.get('phase')}) ===")
print(f"plan: {w.get('plan')}")
print(f"assignment: {w.get('assignment')}")
print(f"roster: {w.get('roster')}")
print()
for p in w.get("packages") or []:
    print(f"  {p.get('id'):6}  {str(p.get('status')):12}  {str(p.get('assignee')):7}  {p.get('kind'):16}  {p.get('title','')[:50]}")
PY
}

cmd_run() {
  local plan="" task="" dry=false out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan) plan="${2:?}"; shift 2;;
      --task) task="${2:?}"; shift 2;;
      --out)  out="${2:?}"; shift 2;;
      --dry-run) dry=true; shift;;
      *) fail "run: unknown arg '$1'";;
    esac
  done
  [[ -n "$plan" && -f "$plan" ]] || fail "run: --plan required"
  [[ -n "$out" ]] || out="$(_root)/ledger/WORK.json"
  cmd_decompose --plan "$plan" --out "$out" ${task:+--task "$task"}
  cmd_assign --work "$out" --out "$out"
  if [[ "$dry" == true ]]; then
    cmd_execute --work "$out" --plan "$plan" --dry-run
  else
    cmd_execute --work "$out" --plan "$plan"
  fi
  cmd_status "$out"
}

# --- CLI --------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  sub="${1:-}"
  shift || true
  case "$sub" in
    ""|-h|--help)
      cat <<'EOF'
Usage:
  lib/team-dispatch.sh decompose --plan PLAN.md [--out ledger/WORK.json] [--task T]
  lib/team-dispatch.sh assign    --work ledger/WORK.json
  lib/team-dispatch.sh execute   --work ledger/WORK.json [--plan PLAN.md] [--dry-run]
  lib/team-dispatch.sh status    [ledger/WORK.json]
  lib/team-dispatch.sh run       --plan PLAN.md [--task T] [--dry-run]
                                 # full team: decompose → assign → all workers execute

Philosophy:
  Architect (Claude) writes PLAN and ALSO codes ≥1 package.
  Grok and Codex each receive packages and implement them.
  No one is "only management" — all three work.
EOF
      exit 0
      ;;
    decompose) cmd_decompose "$@" ;;
    assign)    cmd_assign "$@" ;;
    execute)   cmd_execute "$@" ;;
    status)    cmd_status "$@" ;;
    run)       cmd_run "$@" ;;
    *) fail "team-dispatch: unknown command '$sub'";;
  esac
fi
