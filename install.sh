#!/usr/bin/env bash
# Install the reproduce-project skill at the user level so all Claude/Cursor/Codex/Opencode
# sessions can find it. Run once from the repo root:
#   bash .claude/skills/reproduce-project/install.sh
#
# Result:
#   ~/.claude/skills/reproduce-project          (full copy)
#   ~/.cursor/skills/reproduce-project   -> ~/.claude/skills/reproduce-project
#   ~/.codex/skills/reproduce-project    -> ~/.claude/skills/reproduce-project
#   ~/.opencode/skills/reproduce-project -> ~/.claude/skills/reproduce-project
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.claude/skills/reproduce-project"

echo "Installing skill to $DST"
mkdir -p "$(dirname "$DST")"
rm -rf "$DST"
cp -r "$SCRIPT_DIR" "$DST"
chmod +x "$DST/scripts/"*.sh "$DST/install.sh"

for tool in cursor codex opencode; do
  tool_dir="$HOME/.$tool/skills"
  mkdir -p "$tool_dir"
  ln -sfn "$DST" "$tool_dir/reproduce-project"
  echo "  linked $tool_dir/reproduce-project -> $DST"
done

echo "Done. Reproducible-skill installed."
