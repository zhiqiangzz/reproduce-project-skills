# Dependency Discovery Recipes

How to extract a structured dependency plan from common manifest files. Read these in priority order — earlier files override later ones on conflicts.

## Priority order

1. `docker/Dockerfile`, `Dockerfile` — the most reliable source of truth: someone got it to build once and wrote it down.
2. `INSTALL.md`, `INSTALL.rst`, `BUILD.md` — usually explicit prerequisites lists.
3. `README.md`, `README.rst` — `## Installation` / `## Getting Started` sections.
4. Python manifests: `pyproject.toml`, `setup.py`, `requirements*.txt`.
5. Conda env files: `environment.yml`, `conda.yaml` — read as a dependency source only; route Python entries to `pyproject.toml` (uv) and non-Python entries to `pixi.toml` (pixi). Do NOT create a conda env.
6. Build manifests: `CMakeLists.txt` (look for `find_package`, `find_library`), `Makefile`, `meson.build`, `Cargo.toml`, `go.mod`.

## Extraction rules

### Dockerfile

| Line pattern | Output bucket |
|---|---|
| `FROM nvidia/cuda:X.Y-...` | `cuda_min_version=X.Y` (a FLOOR, not a pin), `cuda_required=true` — resolve to newest-reasonable ≤ driver cap in Phase 4 |
| `apt-get install -y <pkgs>` | `system_pkgs` — try uv pip first, else add to `pixi.toml` (see `system_pkg_userspace.md`) |
| `conda install ... <pkgs>` | split by language: Python names (`cython numpy onnx protobuf`) → `pyproject.toml` (uv); native tools/libs (`cmake make ffmpeg cudatoolkit`) → `pixi.toml` (pixi) |
| `pip install <pkgs>` | `python_pkgs` directly |
| `wget .../cudnn-X.Y-linux-...tgz` | special: cuDNN needs a manual download |
| `ENV KEY=VALUE` | append to `.env` (only the project-specific ones, not container paths like `PATH=/opt/conda/bin:...`) |
| `RUN curl/wget ... && tar -xzf ... -C /usr/local` | a binary tarball install — replicate to `~/.local` or `<project>/third_party/` |
| `WORKDIR /usr/X` | hints at the project's expected `_HOME` env var (e.g. `TASO_HOME`) |

### setup.py

- `install_requires=[...]` → `python_pkgs`
- `ext_modules=[Extension(..., libraries=["foo"])]` → C library `libfoo` must be linkable; add `foo` to `system_pkgs`
- `include_dirs=["/usr/local/cuda/include"]` → `cuda_required=true`
- `cythonize(...)` → add `cython` to `python_pkgs`

### pyproject.toml

- `[project.dependencies]` / `[tool.poetry.dependencies]` → `python_pkgs`
- `[build-system].requires` → `python_pkgs` (build-time)
- `[tool.scikit-build]`, `[tool.maturin]` → native build; add `cmake` / `rustc` accordingly

### requirements*.txt

Trivial: one `python_pkgs` entry per non-comment line. Strip version pins unless the line is clearly a critical lower bound.

### environment.yml / conda.yaml

Read for the dependency list, then route each entry — never create a conda env:

```yaml
dependencies:
  - python=3.9      # -> uv venv --python 3.9
  - numpy           # -> python_pkgs (pyproject.toml, uv)
  - cmake           # -> non-Python: try uv pip, else pixi.toml [dependencies]
  - cudatoolkit     # -> non-Python: pixi.toml [dependencies] (cuda-toolkit)
  - pip:
      - onnx==1.7.0 # -> python_pkgs (pyproject.toml, uv)
```

conda / conda-forge package names are the same ones pixi uses, so non-Python entries
map straight into `pixi.toml`.

### CMakeLists.txt

| Token | Output |
|---|---|
| `project(... LANGUAGES ... CUDA)` | `cuda_required=true` |
| `find_package(Protobuf REQUIRED)` | `system_pkgs += protobuf` (try `uv pip install protobuf` for the compiler binary) |
| `find_package(CUDA REQUIRED)` / `find_package(CUDAToolkit)` | needs `nvcc` |
| `find_package(Threads/MPI/OpenMP)` | usually already present; no action |
| `cuda_add_library`, `cuda_add_executable` | needs `nvcc` |
| `cmake_minimum_required(VERSION X.Y)` | `cmake >= X.Y` (use `uv pip install 'cmake>=X.Y'`) |

## Pip-name vs import-name normalisation

Common mismatches the agent should resolve before `uv pip install`:

| Import | Pip name |
|---|---|
| `cv2` | `opencv-python` |
| `PIL` | `pillow` |
| `sklearn` | `scikit-learn` |
| `yaml` | `pyyaml` |
| `bs4` | `beautifulsoup4` |
| `serial` | `pyserial` |
| `google.protobuf` | `protobuf` |
| `onnx` | `onnx` (same) |
| `cython` | `Cython` (case-insensitive on pip) |
| `tensorflow` | `tensorflow` or `tensorflow-cpu` or `tensorflow-gpu` (legacy) — pick based on Phase 4 CUDA detection |

## Version selection (resolving a constraint to a concrete version)

A manifest usually gives a **constraint**, not the version to install. Resolve it with:

1. Read the constraint as a floor/range (`llvm > 15`, `cmake >= 3.18`, `cudatoolkit > 11`).
2. Clamp to system caps first — most importantly the NVIDIA **driver → max CUDA toolkit**
   ceiling (driver 570 → ≤ 12.8). See `system_pkg_userspace.md`.
3. If the floor is above the cap, **error out** (e.g. needs CUDA > 13 on a 570 driver) — do
   not downgrade the driver, do not silently pick something incompatible.
4. Otherwise pick **newest-reasonable**: a recent, established stable release a notch or two
   below the latest — never the floor, never a nightly/just-released major.

| Constraint | System cap | Pick |
|---|---|---|
| `llvm > 15` | — | `llvm 19`/`20` (not 15, not a brand-new 21) |
| `cudatoolkit > 11` | driver 570 → ≤ 12.8 | `12.6` (12.8 only if a dep demands it) |
| project needs CUDA `> 13` | driver 570 → ≤ 12.8 | **ERROR** — driver too old, no permission to change |

## Simplest example detection (for Phase 8 verify)

1. Glob `examples/*.py`, sort by file size ascending.
2. Skip files that import things not in the project (`examples/test_onnx.py` is fine, but skip a file that imports `tensorflow` if tensorflow isn't in `python_pkgs`).
3. Skip files with obvious external prerequisites (read top 30 lines for hardcoded paths like `/home/foo/...` or `download_dataset` calls).
4. If `examples/` is empty, fall back to `tests/test_smoke.py` or the smallest file in `tests/`.
