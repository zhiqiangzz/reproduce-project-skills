---
name: reproduce-project
description: Reproduce, install, or set up a software project locally with a uv-managed .venv for Python, a generated pixi.toml that manages non-Python toolchain and system packages (CUDA, compilers, native libs) from conda-forge into a project-local .pixi/, VSCode .vscode (uv interpreter + Python+C++ joint LLDB debug compound), a project-local .env (project toolchains preferred over system), an editable idempotent reproduction script (scripts/reproduce.sh), the project's own example as the verification test, and (when a paper PDF exists) annotation of the paper's running example. Trigger phrases include "reproduce this project", "set up this repo", "install dependencies", "get it building", "replicate the paper".
---

# reproduce-project

Project-agnostic playbook for getting an arbitrary software project — especially Python + C/C++/CUDA research codebases — building and running locally, with a uv-managed venv, project-local toolchains, and Python+C++ joint debugging in VSCode.

`$SKILL_DIR` below means the directory this `SKILL.md` lives in.

## Hard rules

1. **uv-first for Python, pixi for everything else.** Python → project-local `.venv` via uv. Non-Python toolchain (CUDA, compilers, native libs) → project-local `.pixi/` via `pixi.toml`/conda-forge. Never pollute the system Python and never create a global conda/mamba env.
2. **No unattended sudo.** If a step needs `sudo`, print the command and pause for the user.
3. **Driver is sacred.** Never modify, downgrade, or reinstall the NVIDIA driver — assume no permission. The installed driver is a hard ceiling: pick a CUDA toolkit/runtime ≤ the driver-supported maximum. If the project's *minimum* required CUDA exceeds what the driver allows, **stop and report an error** — do not touch the driver and do not silently pick an incompatible version.
8. **Version selection: newest-reasonable, not oldest-allowed, not bleeding-edge.** When a dependency is given as a range or floor (`llvm > 15`, `cmake >= 3.18`, `cudatoolkit > 11`), do NOT install the floor (`15`) and do NOT install the absolute latest/nightly. Pick a recent, well-established stable release a notch or two below the newest — e.g. `llvm > 15` → install `llvm 19`/`20`, not `15` and not a just-released `21`. Always clamp to system constraints first (see rule 3).
4. **`/usr/local/` is read-only.** Project-local toolchains go in `<project>/third_party/`.
5. **Source code is read-only by default.** Wrap incompatible interfaces in a thin shim. Modify source only as a last resort, and never silently.
6. **`scripts/reproduce.sh` is the artefact.** Every successful command is appended to it. On failure, the agent edits the script and re-runs — the script is idempotent.
7. **`.env` must be in `.gitignore`.** It can contain machine-local paths.

## Workflow

Make a TODO list with the phases below and work through them in order. Phases 3 and 5 can run in parallel with 4; phases 7 depends on 2/3/4/6; phase 8 is the gate.

### Phase 0 — Pre-flight

```bash
command -v uv   >/dev/null || bash "$SKILL_DIR/scripts/install_uv.sh"
command -v pixi >/dev/null || bash "$SKILL_DIR/scripts/install_pixi.sh"
export PATH="$HOME/.local/bin:$HOME/.pixi/bin:$PATH"
nvidia-smi 2>/dev/null | head -3 || echo "(no NVIDIA GPU detected; CUDA phases will be skipped)"
```

If `CLAUDE.md` is missing in the project root, mention `/init` to the user but don't block.

### Phase 1 — Discover dependencies

Read-only parse, in this priority order. See `$SKILL_DIR/references/dep_discovery.md` for extraction recipes.

1. `docker/Dockerfile`, `Dockerfile`
2. `INSTALL.md`, `INSTALL.rst`, `BUILD.md`
3. `README.md`, `README.rst`
4. `setup.py`, `pyproject.toml`, `requirements*.txt`
5. `environment.yml`, `conda.yaml`
6. `CMakeLists.txt`, `Makefile`, `meson.build`, `Cargo.toml`, `go.mod`

Emit a structured plan: `{python_pkgs[], system_pkgs[], cuda_required: bool, cuda_min_version, build_tool, simplest_example_path}`.

For every versioned dependency, record the **constraint** (floor/range/pin), not a single number — Phase 2/3/4 resolve each to a concrete version per the version-selection rule (Hard rule 8): newest-reasonable that satisfies the constraint and the system caps, never the floor, never bleeding-edge.

### Phase 2 — venv + pyproject.toml + Python deps

```bash
uv venv --python 3.11   # falls back to 3.10 / 3.12 if a discovered pin demands it
```

**Root `pyproject.toml` (create if missing).** This becomes the single declarative source of truth for Python deps — `scripts/reproduce.sh` installs from it via `uv pip install -r pyproject.toml` instead of duplicating the list. If the root already has a `pyproject.toml`, leave it alone (the user may have configured it).

```bash
if [ ! -f pyproject.toml ]; then
  cp "$SKILL_DIR/templates/pyproject.toml" pyproject.toml
  # Fill the placeholders:
  #   __PROJECT_NAME__   → derived from the directory name (kebab-case)
  #   __PYTHON_VERSION__ → 3.11 (or the discovered minimum)
  # Then append the Phase-1 discovered deps under [project].dependencies.
fi
```

Anything import-named differently from its pip name (e.g. `cv2` ↔ `opencv-python`) should be normalised against `references/dep_discovery.md`. **For projects whose actual package code lives in a subdirectory** (`python/`, `src/foo/`), the root pyproject.toml is dependency-only; the sub-package is installed editable later via `cd <subdir> && uv pip install -e .` in `scripts/reproduce.sh`.

### Phase 3 — System-package decision tree

**Create `pixi.toml`** (the non-Python manifest) if the project needs any non-Python toolchain/lib and one doesn't exist yet:

```bash
if [ ! -f pixi.toml ]; then
  cp "$SKILL_DIR/templates/pixi.toml" pixi.toml
  # Fill __PROJECT_NAME__; add the discovered non-Python deps under [dependencies].
fi
```

If a `pixi.toml` already exists, leave it alone (the user may have configured it) — just `pixi add` the missing deps.

For each system package discovered:

1. Try `uv pip install <pkg>` — many build tools have pip equivalents (`cmake`, `ninja`, `protobuf`, `patchelf`, `pybind11`, `meson`, `swig`). See `$SKILL_DIR/references/system_pkg_userspace.md`.
2. Else add it to **`pixi.toml`** (`pixi add <pkg>` then `pixi install`) — conda-forge ships the vast majority of native libs/toolchains (FFmpeg, OpenCV, MKL, boost, eigen, compilers). This is the preferred route; it stays project-local in `.pixi/`.
3. Else: user-space install (portable tarball into `~/.local`, or source build with `--prefix=$HOME/.local`).
4. Else: **print** `sudo apt-get install -y <pkg>` to the user and wait for confirmation. Do not execute.

### Phase 4 — CUDA

```bash
DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
# Map driver -> MAX supported CUDA toolkit via the NVIDIA compatibility table.
```

**Driver → max-toolkit (the hard ceiling).** The driver version caps the CUDA toolkit, regardless of what the project asks for. Reference points (driver `≥` → max CUDA toolkit):
- `≥ 525` → 12.0,  `≥ 535` → 12.2,  `≥ 545` → 12.3,  `≥ 550` → 12.4,  `≥ 555` → 12.5,  `≥ 560` → 12.6,  `≥ 570` → 12.8,  `≥ 575`/580 → 12.9/13.x.
- Example: **driver 570** → toolkit must be `≤ 12.8`. There is no 13.x option on this driver.

**Resolution algorithm** (combine project constraint + driver cap + Hard rule 8):
1. Let `CAP` = max toolkit the driver supports (table above). For driver 570, `CAP = 12.8`.
2. Let `FLOOR` = the project's minimum required CUDA (e.g. `cudatoolkit > 11` → floor 11).
3. **If `FLOOR > CAP`** (e.g. project requires toolkit `> 13` but driver 570 caps at 12.8): **STOP — print an error and exit.** Do not touch the driver, do not pick a lower version silently. Tell the user the project needs a newer driver than they have permission to install.
4. Otherwise pick the **newest-reasonable** version in `[FLOOR, CAP]` per Hard rule 8 — not the floor, and back off slightly from the very top. For driver 570 + `cudatoolkit > 11`, choose **12.6** (a notch below the 12.8 cap); 12.8 is acceptable if a dep needs it.

- Python GPU wheels (`torch`, `onnxruntime-gpu`, `cupy-cuda12x`, `jax[cuda12]`): pick the wheel index matching the resolved toolkit (e.g. `cu126`), installed via uv.
- If the project's C++ build needs `nvcc`: **declare the toolkit in `pixi.toml`** — set `cuda-version` to the resolved version (e.g. `12.6`), add `cuda-toolkit`, `cudnn`, and a matching `gxx`, and set `[system-requirements] cuda = "<major>"`. `pixi install` puts `nvcc` and the CUDA libs in `.pixi/envs/default`. **Do not** write to `/usr/local`.
- **Fallback** (a needed CUDA component isn't on conda-forge): download the runfile into `<project>/third_party/cuda/` using `--silent --toolkit --toolkitpath=$PWD/third_party/cuda --override --no-man-page`.
- The generated `.env` sets `CUDA_HOME` to the pixi env (or the `third_party/cuda` fallback) automatically.

### Phase 5 — `.vscode/` + `pyrightconfig.json`

```bash
mkdir -p .vscode
cp "$SKILL_DIR/templates/vscode_settings.json" .vscode/settings.json
cp "$SKILL_DIR/templates/vscode_launch.json"   .vscode/launch.json
# replace __TEST_PROGRAM__ with the simplest example path discovered in Phase 1
sed -i "s|__TEST_PROGRAM__|<example_path>|" .vscode/launch.json
```

**`pyrightconfig.json` at the project root** — Pyright/Pylance does pure static analysis and **does not** execute uv's PEP 660 editable finder (`.venv/lib/python*/site-packages/__editable__*_finder.py`), so any subdirectory package (`python/`, `src/foo/`) must be listed in `extraPaths` for jump-to-def and imports to resolve.

```bash
if [ ! -f pyrightconfig.json ]; then
  cp "$SKILL_DIR/templates/pyrightconfig.json" pyrightconfig.json
  # Fill placeholders:
  #   __PYTHON_VERSION__ → 3.11 (or whatever uv venv used)
  #   __EXTRA_PATHS__    → list of subdirs containing top-level packages
fi
```

**Detecting extraPaths** (in priority order):

1. Parse `.venv/lib/python*/site-packages/__editable__*_finder.py`; extract values of the `MAPPING` dict — these are the canonical package roots the editable install uses.
2. Else: scan the repo for top-level directories that contain `__init__.py` and aren't `.venv`/`build`/`third_party`/`node_modules`.
3. Else: read `setup.py` / `pyproject.toml` for `packages=` / `[tool.setuptools.packages.find]` / `[tool.setuptools.package-dir]`.

If `pyrightconfig.json` already exists, **do not overwrite it** — the user may have hand-tuned it. Mention to the user that the existing config is being kept.

Tell the user once: install VSCode extensions `ms-python.python`, `ms-python.debugpy`, `vadimcn.vscode-lldb`. F5 → pick `"Python + C++ (joint)"` → in the PID prompt, pick the just-launched Python process → LLDB attaches and C++ breakpoints become live.

**Re-targeting `launch.json` for a different script** — the user can run:

```bash
bash "$SKILL_DIR/scripts/gen_launch_config.sh" examples/foo.py --bench resnet
```

This regenerates `.vscode/launch.json` with the supplied command as the debug target plus the LLDB-attach compound. See the script header for the exact contract.

See `$SKILL_DIR/references/debug_workflow.md` for the full walkthrough including `kernel.yama.ptrace_scope` notes.

### Phase 6 — `.env`

```bash
cp "$SKILL_DIR/templates/env.template" .env
# Fill project-specific lines based on Dockerfile ENV / README hints.
```

The template makes `CUDA_HOME` and `LD_LIBRARY_PATH` prefer in-repo `third_party/cuda` and fall back to `/usr/local/cuda` if absent.

### Phase 7 — Build

```bash
cp "$SKILL_DIR/scripts/reproduce.sh.template" scripts/reproduce.sh
chmod +x scripts/reproduce.sh
# Fill the AGENT FILLS blocks, then:
bash scripts/reproduce.sh
```

The script runs `pixi install` (materializing the `pixi.toml` toolchain into `.pixi/`) and sources `.env` *before* the native build, so `nvcc`, compilers, and native libs from `.pixi/` are on PATH/`CMAKE_PREFIX_PATH` for CMake.

Build dispatch:
- `CMakeLists.txt` present → `mkdir -p build && cd build && cmake .. && make -j$(nproc)`
- `python/setup.py` (separate Python subdir) → `cd python && uv pip install -e .`
- `pyproject.toml` / top-level `setup.py` → `uv pip install -e .`
- `meson.build` → `meson setup build && meson compile -C build`

### Phase 8 — Verify

```bash
.venv/bin/python <simplest_example>
echo $?   # must be 0
```

If non-zero, capture stderr, patch `scripts/reproduce.sh` (add missing pkg, set missing env var, adjust CMake flag, etc.), re-run. Do not give up until verify passes or the user calls it.

### Phase 9 — `.gitignore`

```bash
cat "$SKILL_DIR/templates/gitignore_additions" >> .gitignore
# dedupe entries afterwards
sort -u .gitignore -o .gitignore.tmp && mv .gitignore.tmp .gitignore
```

### Phase 10 — Paper annotation (optional)

If `paper/*.pdf` or `docs/*.pdf` exists, see `$SKILL_DIR/references/paper_annotation.md`:

1. Extract text from the PDF.
2. Find sections matching `running example`, `motivating example`, `overview`, `case study`.
3. Match identifiers in those sections to functions/files in the repo (especially `examples/`).
4. Copy the matched example to `examples/<name>_annotated.py` and insert `# === Paper §X.Y / Figure Z ===` comment blocks above the relevant segments.

## Failure loop

On any failure:
1. Capture full stderr (and last 50 lines of stdout).
2. Decide: missing pkg? wrong version? missing env? wrong build flag? source bug?
3. Edit `scripts/reproduce.sh` — never run one-off commands that don't end up in the script.
4. Re-run `bash scripts/reproduce.sh`. Repeat until Phase 8 passes.

## Wrap-up message to user

Summarise:
- What was installed (uv Python pkgs, pixi toolchain/native pkgs, any system pkgs left for the user, CUDA path).
- Files created: `.venv/`, `.pixi/` + `pixi.toml`/`pixi.lock` (if non-Python deps were needed), `.vscode/`, `.env`, `pyproject.toml` (if newly created), `pyrightconfig.json` (if newly created), `scripts/reproduce.sh`, `.gitignore` additions, optional `examples/*_annotated.py`.
- Validation: ✅/‼️ Phase 8 result with the exact command run.
- Any `sudo apt-get …` commands the user still needs to run.
- VSCode extension list the user needs to install for joint debugging.
- Pointer to `gen_launch_config.sh` for re-targeting launch.json at other scripts.
