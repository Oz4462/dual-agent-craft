# Platform support — Linux · macOS · Windows

Dual-agent-craft is **bash-first** with a preserved **PowerShell** tree for Windows.
Goal: the same CRAFT / team-work loop runs on all three platforms.

## Matrix

| Feature | Linux | macOS | Windows |
|---|---|---|---|
| Full team path (`dual-run.sh`, team-dispatch, adaptive roles) | ✅ native bash 5 | ✅ Homebrew bash 5 | ✅ Git Bash **or** WSL |
| Classic CRAFT (`dual-build` / `review` / `merge`) | ✅ bash | ✅ bash 5 | ✅ bash via Git Bash/WSL **or** `powershell/*.ps1` |
| Deterministic guards (import-scan, test-guard, eval) | ✅ | ✅ | ✅ (bash path) |
| Dashboard (`dual-dashboard.sh` → HTML) | ✅ | ✅ | ✅ (bash) / open HTML in browser |
| Live cockpit | tmux (`dual-view.sh`) | tmux (brew) | Windows Terminal (`powershell/dual-view.ps1`) |
| Grok `--sandbox` | ❌ macOS-only upstream | ✅ | ❌ — use worktree + `--deny` |
| Codex real sandbox (`-s`) | ✅ | ✅ (Codex) | via WSL recommended |
| CI | ubuntu-latest | macos-latest | (use bash in Git Bash locally) |

## Requirements (all platforms)

| Tool | Why |
|---|---|
| **bash 4.4+** (5.x preferred) | `mapfile`, assoc arrays; macOS `/bin/bash` 3.2 is **too old** |
| **git** | worktrees, No-Cut merge |
| **python3** | JSON, portable timestamps, dashboard render, import-scan |
| **claude** / **grok** CLIs | team workers (optional **codex**, **ollama**) |

### Linux (primary / verified)

```bash
# Debian/Ubuntu example
sudo apt-get install -y git python3 bash
# optional: bats shellcheck tmux
./dual-run.sh --status
tests/run.sh
```

### macOS

```bash
brew install bash git python3
# optional: bats shellcheck tmux
# IMPORTANT: invoke with brew bash, not /bin/bash
/opt/homebrew/bin/bash ./dual-run.sh --status
# or: echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zshrc
```

Portable helpers in `lib/common.sh` already cover:
- timestamps without GNU `%3N`
- `sed -i` vs `sed -i ''`
- `stat -c%s` vs `stat -f%z`

### Windows

**Recommended:** full feature path via **Git Bash** or **WSL2 (Ubuntu)**.

#### Option A — Git Bash (simple)

1. Install [Git for Windows](https://git-scm.com/download/win) (includes bash).
2. Install Python 3 and ensure `python`/`python3` is on PATH.
3. Install `claude` + `grok` CLIs for Windows.
4. From the repo:

```powershell
# PowerShell bridge (auto-finds Git Bash / WSL)
.\powershell\dual-run.ps1 --status
.\powershell\dual-run.ps1 --dry-run --verify "true" --skip-merge

# Or open "Git Bash" and run natively:
./dual-run.sh --status
```

#### Option B — WSL2 (closest to Linux)

```powershell
wsl --install   # once
# inside Ubuntu WSL:
cd /mnt/c/path/to/dual-agent-craft
./dual-run.sh --status
```

#### Option C — Classic PowerShell-only CRAFT (no team-work yet)

Preserved live-verified scripts:

```powershell
.\powershell\dual-build.ps1 -Adaptive -Variants 3 -Verify "py -3 -m pytest -q"
.\powershell\dual-review.ps1 -PocBranch feat/poc -Base main
.\powershell\dual-merge.ps1 -From feat/poc -Into main -Verify "py -3 -m pytest -q" -EvalK 5
.\powershell\dual-view.ps1   # Windows Terminal split cockpit
```

Team-work (`team-dispatch`, adaptive roles) is implemented in **bash**; use Option A/B for that.

## Entrypoints

| Goal | Linux/macOS | Windows |
|---|---|---|
| Doctor | `./dual-status.sh` | `.\powershell\dual-run.ps1 --status` or Git Bash `./dual-status.sh` |
| Full team loop | `./dual-run.sh` | `.\powershell\dual-run.ps1` → bash |
| Dashboard (status HTML) | `./dual-dashboard.sh` | same via bash, open `dashboard.html` |
| **Chat Task UI** | `./dual-chat.sh` → http://127.0.0.1:8787/ | Git Bash / WSL: `bash dual-chat.sh` |
| Split cockpit | `./dual-view.sh` (tmux) | `.\powershell\dual-view.ps1` (wt) |

## Design rules we follow for portability

1. **No GNU-only date/sed/stat** without a BSD/fallback path (`lib/common.sh`).
2. **python3** for JSON and timestamps — available on all three OSes.
3. **Paths with `/`** inside bash; PowerShell uses its own paths when native.
4. **LC_ALL=C** for numeric stability under de_DE etc.
5. **Windows team features** = run the bash harness under Git Bash/WSL, not a second divergent implementation.

## Quick self-check

```bash
bash --version          # need 4+
python3 --version
git --version
./dual-status.sh        # or powershell\dual-run.ps1 --status
./dual-run.sh --dry-run --verify true --skip-merge
```
