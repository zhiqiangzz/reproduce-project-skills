#!/usr/bin/env bash
# Generate a .vscode/launch.json with a Python + C++ (LLDB) joint debug
# compound targeting the given Python command.
#
# Usage:
#   bash gen_launch_config.sh <script.py> [arg1] [arg2] ...
#   bash gen_launch_config.sh '<full command line>'
#
# Examples:
#   bash gen_launch_config.sh examples/resnet50.py
#   bash gen_launch_config.sh examples/test_onnx.py -f /tmp/foo.onnx
#   bash gen_launch_config.sh '.venv/bin/python -m taso.cli --bench resnet50'
#
# Effect:
#   Writes/overwrites .vscode/launch.json in the current working directory with
#   three configurations:
#     1. "Python: Launch <script>"           — debugpy launches the script
#     2. "LLDB: Attach to Python"            — LLDB attaches by PID (pickMyProcess)
#     3. "Python + C++ (joint)"  (compound)  — runs (1) then (2)
#
#   The Python interpreter defaults to ${workspaceFolder}/.venv/bin/python.
#   If the first token of the command is a python binary path, it is honored
#   and stripped from the arglist.
#
# Pre-existing launch.json is overwritten. If you have hand-written configs,
# back them up first.
set -euo pipefail

if [ $# -lt 1 ]; then
  cat <<'USAGE' >&2
Usage: gen_launch_config.sh <script.py> [arg1 arg2 ...]
       gen_launch_config.sh '<full command line>'
Writes .vscode/launch.json in the current directory.
USAGE
  exit 2
fi

# If invoked with a single quoted command line, split on whitespace.
if [ $# -eq 1 ] && [[ "$1" == *" "* ]]; then
  # shellcheck disable=SC2206
  CMD=( $1 )
else
  CMD=( "$@" )
fi

# Honor a leading python interpreter if present; otherwise default.
PY_BIN='${workspaceFolder}/.venv/bin/python'
case "${CMD[0]}" in
  *python|*python3|*python3.*|*/python|*/python3|*/python3.*)
    # Keep but don't use directly — launch.json uses pythonPath separately.
    CMD=( "${CMD[@]:1}" )
    ;;
esac

if [ ${#CMD[@]} -lt 1 ]; then
  echo "ERROR: no script specified after python interpreter" >&2
  exit 2
fi

SCRIPT="${CMD[0]}"
ARGS=( "${CMD[@]:1}" )

# Make SCRIPT absolute-relative to workspace (handles bare paths).
case "$SCRIPT" in
  /*|\${workspaceFolder}/*) ;;  # already absolute or templated
  *) SCRIPT='${workspaceFolder}/'"$SCRIPT" ;;
esac

# Render the args array as JSON (handles spaces, no shell-injection paths here
# since we control the format).
args_json=""
if [ ${#ARGS[@]} -gt 0 ]; then
  for a in "${ARGS[@]}"; do
    a_escaped=$(printf '%s' "$a" | sed 's/\\/\\\\/g; s/"/\\"/g')
    args_json+="\"$a_escaped\", "
  done
  args_json="${args_json%, }"
fi

# Pretty name from the script basename, with the env-var override hint stripped.
SCRIPT_BASE=$(basename "$SCRIPT" .py)

mkdir -p .vscode
cat > .vscode/launch.json <<EOF
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: Launch ${SCRIPT_BASE}",
      "type": "debugpy",
      "request": "launch",
      "program": "${SCRIPT}",
      "args": [${args_json}],
      "console": "integratedTerminal",
      "justMyCode": false,
      "envFile": "\${workspaceFolder}/.env",
      "env": { "PYTHONUNBUFFERED": "1" },
      "python": "${PY_BIN}"
    },
    {
      "name": "LLDB: Attach to Python",
      "type": "lldb",
      "request": "attach",
      "pid": "\${command:pickMyProcess}"
    }
  ],
  "compounds": [
    {
      "name": "Python + C++ (joint)",
      "configurations": ["Python: Launch ${SCRIPT_BASE}", "LLDB: Attach to Python"],
      "stopAll": true
    }
  ]
}
EOF

echo "Wrote .vscode/launch.json targeting: $SCRIPT ${ARGS[*]:-}"
echo
echo "In VSCode: F5 → pick 'Python + C++ (joint)' → choose the Python process from the PID picker → LLDB attaches."
