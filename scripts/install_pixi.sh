#!/usr/bin/env bash
# Install pixi (the conda-ecosystem toolchain/package manager) without root.
# pixi manages this project's NON-Python dependencies (CUDA, compilers, native
# libs) via pixi.toml, installing them into the project-local .pixi/ — no global
# conda env, no writes to /usr. Idempotent: exits early if pixi is already present.
set -euo pipefail

export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$PATH"

if command -v pixi >/dev/null 2>&1; then
  echo "pixi already installed: $(pixi --version)"
  exit 0
fi

echo "Installing pixi ..."
curl -fsSL https://pixi.sh/install.sh | bash

export PATH="$HOME/.pixi/bin:$PATH"
echo "pixi installed: $(pixi --version 2>/dev/null || echo 'restart shell to pick up PATH')"
