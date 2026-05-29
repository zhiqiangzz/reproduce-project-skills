#!/usr/bin/env bash
# Install uv (https://docs.astral.sh/uv/) without sudo.
# Tries the official curl installer first, falls back to pip --user.
set -euo pipefail

if command -v uv >/dev/null 2>&1; then
  echo "uv already installed: $(uv --version)"
  exit 0
fi

if command -v curl >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
elif command -v wget >/dev/null 2>&1; then
  wget -qO- https://astral.sh/uv/install.sh | sh
elif command -v pip >/dev/null 2>&1; then
  pip install --user uv
elif command -v pip3 >/dev/null 2>&1; then
  pip3 install --user uv
else
  echo "ERROR: need one of curl, wget, or pip to install uv." >&2
  exit 1
fi

# Both installers drop uv in ~/.local/bin (curl) or ~/.local/bin via pip --user.
export PATH="$HOME/.local/bin:$PATH"
echo "Add the following to your shell rc if not already there:"
echo '  export PATH="$HOME/.local/bin:$PATH"'

uv --version
