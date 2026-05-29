# Userspace system-package install recipes

When a build needs a "system" library or tool and you don't have root, get it into
`$HOME`, the project-local `.pixi/`, or `<project>/third_party` — never `/usr` or
`/usr/local`. Try these in order.

## 1. pip/uv has it (fastest, for build tools)

Many build tools ship as manylinux wheels — install into `.venv` with `uv pip install`:

| Need              | pip package                                  |
|-------------------|----------------------------------------------|
| cmake             | `cmake`                                       |
| ninja             | `ninja`                                       |
| protobuf compiler | `protobuf` (gives `protoc` via grpcio-tools)  |
| patchelf          | `patchelf`                                    |
| pybind11 headers  | `pybind11`                                    |
| swig              | `swig`                                        |
| meson             | `meson`                                       |

## 2. pixi / conda-forge (PREFERRED for non-Python toolchain & native libs)

For CUDA, compilers (gcc/gxx), cuDNN, and native libraries (FFmpeg, OpenCV, MKL, boost,
eigen, protobuf, ...) — anything painful to build or not shipped as a Python wheel — add it
to the project's `pixi.toml` and let pixi solve it from conda-forge into the project-local
`.pixi/` (no root, no `/usr`, reproducible via `pixi.lock`):

```bash
pixi init --channel conda-forge      # only if pixi.toml doesn't exist yet
pixi add ffmpeg opencv gxx cmake     # appends to [dependencies] and re-locks
pixi install                         # materializes .pixi/envs/default
```

The skill's `.env` puts `.pixi/envs/default/{bin,lib}` on PATH/LD_LIBRARY_PATH and points
`CMAKE_PREFIX_PATH`/`CUDA_HOME` at it, so builds find these automatically. Prefer pixi over
tarball/source builds for anything conda-forge ships.

## 3. Prebuilt portable tarball into ~/.local

For tools not on conda-forge but shipped as portable Linux tarballs (GitHub releases):

```bash
mkdir -p ~/.local
curl -LsSf <release-url>.tar.gz | tar xz -C ~/.local --strip-components=1
# now ~/.local/bin/<tool> is on PATH (if ~/.local/bin is in PATH)
```

## 4. Build from source with a user prefix

```bash
curl -LsSf <src>.tar.gz | tar xz && cd <src>
./configure --prefix=$HOME/.local
make -j"$(nproc)" && make install
```

## 5. Last resort: ask the user for sudo

```bash
echo "These need root:"
echo "  sudo apt-get install -y <pkg>"
```

Never run sudo unattended. Print the exact command and let the user decide.

## CUDA-specific notes

- PREFERRED: declare the toolkit in `pixi.toml` — `cuda-version` pinned to the highest
  value ≤ the driver-supported CUDA, plus `cuda-toolkit`, `cudnn`, and a matching `gxx`,
  with `[system-requirements] cuda = "<major>"`. `pixi install` places `nvcc` and the CUDA
  libs in `.pixi/envs/default`; the skill's `.env` then sets `CUDA_HOME` there.
- FALLBACK (a needed component isn't on conda-forge): download the runfile,
  `--toolkit --toolkitpath=<project>/third_party/cuda --silent --override --no-man-page`.
  No driver install.
- For PyTorch etc., still prefer the GPU wheels (`--index-url
  https://download.pytorch.org/whl/cu121`) installed via uv over a full local toolkit.
