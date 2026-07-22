---
name: prs-rebases
description: PR and rebase craft — reviewable diffs, honest descriptions, safe history surgery with --force-with-lease on own branches only.
---
# PRs + Rebases

## PR rules
- One concern per PR; conventional-commit title; description = WHAT changed, WHY, and a copy-paste **verify command** with its observed output.
- Diff budget ~400 lines reviewable; bigger → split or pre-merge a mechanical-changes commit reviewers can skip.
- Full-history analysis before drafting: `git log main..HEAD --oneline` + `git diff main...HEAD --stat` — the PR describes ALL commits, not the last one.
- CI green + conflicts resolved BEFORE requesting review. Never mark ready with a red pipeline.

## Rebase rules
- Rebase = own feature branches only; shared/main history is immutable.
- `git push --force-with-lease` exclusively (plain --force is hook-blocked here).
- Before surgery: `git branch backup/$(date +%s)` — 2 seconds of insurance.
- Conflict during rebase: resolve per-commit with the suite run at each stop, or abort — never resolve blind and "fix later".
- Interactive-rebase fixups for review feedback; new review round gets real commits (reviewers diff since last look).

## Merge etiquette
No-Cut mindset from the harness applies to GitHub too: red check = no merge, conflict = human decision, squash vs merge follows the repo's existing convention (check `git log`, don't impose).
