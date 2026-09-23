# The Lokt Harness

The **harness** is everything around the AI that isn't the AI (after Fowler,
"Harness Engineering"). It has two kinds of parts:

- **Guides** (feedforward): docs the agent reads *before* acting, so mistakes
  don't happen — `CLAUDE.md` (repo truth), `AGENT_PLAYBOOK.md` (how agents
  work here), the design-system rules.
- **Sensors** (feedback): checks that run *after* changes and catch what
  slipped through — `build.sh` (compiler), `checks.sh` (banned patterns,
  dataset integrity, drift counters), `backend-check.sh` (server liveness +
  request validation), and compiled logic checks (`logic-checks/`).

**The loop that makes it work:** when a mistake happens twice, don't just fix
it — add a guide line or a sensor so it can't happen a third time. Every
sensor in `checks.sh` exists because that exact failure occurred once.

## Contents

| File | Kind | What it does |
|---|---|---|
| `../CLAUDE.md` | guide | Current architecture, conventions, seams, gotchas |
| `AGENT_PLAYBOOK.md` | guide | Standing rules for delegated agents |
| `build.sh` | sensor | Canonical build, correct pinned destination |
| `test.sh` | sensor | Boots a dedicated iOS 18.5 simulator and runs deterministic unit tests |
| `checks.sh` | sensor | Fast greps: banned styles, secrets, dataset validity, singleton drift, M1b tracker |
| `backend-check.sh` | sensor | Backend health + zero-cost validation probes |
| `backend-hardening-check.sh` | sensor | Boots a throwaway hardened instance; asserts production fails closed without a token, auth, media/per-client 429s, and normal-body 413 (zero cost) |
| `logic-checks/` | sensor | Convention for compiled logic harnesses (see its README) |
| `install-hooks.sh` | wiring | Installs the pre-commit hook (checks.sh gates every commit) — run once per clone |
| `dashboard.sh` | display | Renders run history (`history.jsonl`, gitignored) to `dashboard.html`; `--open` to view |

## Porting this to another project

The skeleton is project-agnostic:

1. Write the project's `CLAUDE.md`: what it is, how to build, what must never
   break (the "seams"), environment gotchas. Keep it current — a stale guide
   is worse than none.
2. Copy `AGENT_PLAYBOOK.md` and edit the project-specific sections (build
   command, verification bar, protected seams).
3. Create `build.sh` (one canonical, always-correct build/test command) and a
   `checks.sh` that starts EMPTY — then add one grep per real incident.
4. Keep the loop: recurring mistake → new guide line or sensor, same commit
   as the fix.
