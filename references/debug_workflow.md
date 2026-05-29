# Python + C++ joint debugging in VSCode

The `.vscode/launch.json` produced by this skill exposes a compound named **`Python + C++ (joint)`**. F5 → pick this compound.

## Required extensions

| Extension | ID | Why |
|---|---|---|
| Python | `ms-python.python` | language support |
| Python Debugger | `ms-python.debugpy` | `type: "debugpy"` in launch.json |
| CodeLLDB | `vadimcn.vscode-lldb` | `type: "lldb"` in launch.json — LLDB DAP wrapper that supports `pickMyProcess` |

Install on the command line if VSCode is headless:

```bash
code --install-extension ms-python.python
code --install-extension ms-python.debugpy
code --install-extension vadimcn.vscode-lldb
```

## Step-by-step

1. Open the project folder in VSCode (`File > Open Folder`).
2. Confirm the bottom-right interpreter shows `.venv/bin/python` (Python extension reads it from `python.defaultInterpreterPath` in `settings.json`).
3. Open a Python file inside `examples/`. Set a Python breakpoint where you want to enter C++ from.
4. Open a C++/CUDA source file in `src/`. Set a breakpoint inside a function you know will be called from Python.
5. Press **F5**. The Run-and-Debug dropdown should show `"Python + C++ (joint)"` — pick it.
6. VSCode launches `debugpy` and immediately shows a PID picker (CodeLLDB's `pickMyProcess`). Pick the Python process you just launched (usually has the example filename in its argv).
7. LLDB attaches. Both debuggers are now active; the Call Stack panel shows two sessions.
8. Continue (`F5`) from the Python session. When Python hits its breakpoint, step over the line that calls into C++. Execution will then break at the C++ breakpoint.

## ptrace gotcha

On Ubuntu, kernel hardening blocks non-parent attach by default. If LLDB attach fails with `ptrace_scope`:

```bash
# One-time per boot, requires sudo (print this for the user):
sudo sysctl -w kernel.yama.ptrace_scope=0
```

To persist across reboots, edit `/etc/sysctl.d/10-ptrace.conf` — also a user task. Do not auto-modify sysctl.

## Common failure modes

- **"could not find Python frame"** in LLDB → CodeLLDB attached too early. Add a `time.sleep(2)` at the top of the Python entry point, or set `"stopOnEntry": true` on the Python config so it pauses long enough to attach.
- **No symbols in C++** → the native library wasn't built with `-g`. Check `CMAKE_BUILD_TYPE=Debug` or `-DCMAKE_BUILD_TYPE=Debug` in the cmake call. Update `scripts/reproduce.sh` to build Debug.
- **`compile_commands.json` missing** (Intellisense for C++) → ensure `CMakeLists.txt` sets `CMAKE_EXPORT_COMPILE_COMMANDS=ON` (TASO already does — see `CMakeLists.txt:21`) and the file is written to `build/`. The `vscode_settings.json` template already points `C_Cpp.default.compileCommands` at it.
- **LLDB can't load CUDA libs** → `LD_LIBRARY_PATH` not inherited. Confirm `.env` is loaded by the launcher; check the bottom of the Debug Console for `LD_LIBRARY_PATH=...` lines.
