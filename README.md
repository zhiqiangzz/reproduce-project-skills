# reproduce-project skill

Project-agnostic Claude/Cursor/Codex/Opencode skill for reproducing arbitrary software projects locally — uv-managed Python venv, a pixi.toml managing the non-Python toolchain (CUDA, compilers, native libs) from conda-forge, VSCode Python+C++ joint debugging, idempotent reproduction script, optional paper-to-code annotation.

## Install

```bash
bash .claude/skills/reproduce-project/install.sh
```

This copies the skill to `~/.claude/skills/reproduce-project/` and symlinks it into `~/.cursor/skills/`, `~/.codex/skills/`, `~/.opencode/skills/`.

## Trigger

Phrases like:
- "reproduce this project"
- "set up this repo"
- "install dependencies"
- "get it building"
- "replicate the paper"

See `SKILL.md` for the full playbook and `references/*.md` for extraction recipes.
