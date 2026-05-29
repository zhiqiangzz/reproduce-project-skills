# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **Claude Code Skill** named `reproduce-project` — a packaged playbook + scaffolding
that Claude follows when a user asks to reproduce/install/set up a software project (tuned for
Python + C/C++/CUDA research codebases). The repo is the *source* of the skill; the skill's
actual work always happens in a **separate target project**, not here.

Two distinct contexts, don't conflate them:
- **Editing the skill** (what you do in this repo): change the playbook, templates, scripts, or guides.
- **Running the skill** (what `SKILL.md` instructs a future Claude to do): apply those assets to some other project.

## Install / validate

```bash
bash install.sh      # symlinks this dir into ~/.claude/skills/reproduce-project
```

There is **no build, lint, or test tooling** — the deliverables are Markdown + templates + shell
scripts. "Testing a change" means: re-read `SKILL.md` for internal consistency, shellcheck the
scripts mentally, and ideally exercise the skill end-to-end against a real target project
(trigger it in Claude Code with *"reproduce this project"*).

## Layout & how the pieces connect

- `SKILL.md` — the orchestrator. YAML frontmatter (`name`, `description`) is what the harness
  matches to trigger the skill; the body is the phased workflow Claude executes.
- `templates/` — files **copied verbatim into the target project** (`pyproject.toml` for
  Python deps, `pixi.toml` for the non-Python toolchain, `vscode_launch.json`,
  `vscode_settings.json`, `pyrightconfig.json`, `env.template`, `gitignore_additions`). They
  contain `__PLACEHOLDER__` tokens (e.g. `__PROJECT_NAME__`, `__PYTHON_VERSION__`,
  `__TEST_PROGRAM__`, `__EXTRA_PATHS__`) that the running agent substitutes.
- `scripts/` — helpers invoked during the workflow: `install_uv.sh`, `install_pixi.sh`,
  `gen_launch_config.sh`
  (regenerates a target's `.vscode/launch.json` for a new debug target), and
  `reproduce.sh.template` (copied into the target as the editable, idempotent setup record;
  contains `AGENT FILLS` blocks).
- `references/` — deep-dive guides (`dep_discovery.md`, `system_pkg_userspace.md`,
  `debug_workflow.md`, `paper_annotation.md`) loaded **on demand** from the relevant phase, to
  keep `SKILL.md` lean.
- `install.sh` — symlinks the skill into `~/.claude/skills/`.

`SKILL.md` references the other assets via the `$SKILL_DIR` convention (the skill's own root).
The workflow is phased (Phase 0 pre-flight → Phase 10 optional paper annotation), executed in
order as a TODO list.

## Invariants to preserve when editing

These are load-bearing — changing one asset usually requires updating `SKILL.md` to match:

1. **Frontmatter ↔ body sync.** The `description` is a dense summary of every deliverable plus
   the trigger phrases, and is the *only* part loaded before invocation. When you change what the
   skill produces, update both the `description` and the corresponding body section.
2. **`$SKILL_DIR`-relative paths.** Renaming/moving a file under `templates/`, `scripts/`, or
   `references/` breaks the `$SKILL_DIR/...` references in `SKILL.md` — update them together.
3. **Placeholders ↔ fill instructions.** Every `__TOKEN__` in a template (and every `AGENT FILLS`
   block in `reproduce.sh.template`) must have a matching "fill this with X" instruction in the
   relevant `SKILL.md` phase, or the running agent won't know to substitute it.
4. **Two package managers, one job each.** uv + `pyproject.toml` own Python (into `.venv`);
   pixi + `pixi.toml` own the non-Python toolchain — CUDA, compilers, native libs — from
   conda-forge (into `.pixi/`). No global conda/mamba env; CUDA via pixi, runfile only as a
   fallback. Both are project-local.
5. **The "Hard rules" in `SKILL.md` are the skill's contract.** uv-first / project-local `.venv`;
   no unattended `sudo` (print and pause); NVIDIA driver untouched, CUDA runtime ≤ driver-supported;
   `/usr/local` read-only (toolchains go in `.pixi/` or `<project>/third_party/`); source code
   read-only by default (shim, don't patch); the generated `scripts/reproduce.sh` is the idempotent
   artifact that every successful command lands in; `.env` is gitignored. Don't weaken without intent.
6. **Verification = the target project's own example**, run to exit code 0 — not a synthetic test.
