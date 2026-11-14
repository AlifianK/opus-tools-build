# opus-tools build (clang, full LTO, CMake + Ninja)

Builds `opusenc`, `opusdec` and `opusinfo` from the latest git master of opus-tools, libopusenc,
opusfile, opus, ogg and flac, in a single CMake tree. The output is static .exe files that need no
DLLs beyond Windows' own.

Upstream builds opus-tools and libopusenc with autotools only, and their Windows project files are
VS2015-era. This repo replaces both with plain CMake. No MSYS2, MinGW or autotools needed.

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| Windows | 10 or 11, x64 | `curl.exe` and `tar.exe` ship with Windows |
| PowerShell | 7+ | for `fetch-sources.ps1` |
| Git | any recent | sources and version strings come from git |
| CMake | 3.29+ | |
| Ninja | any recent | |
| LLVM | recent release | `clang`, `clang++`, `lld`, `llvm-ar`, `llvm-rc`; found via `%LLVMInstallDir%\bin` or `C:\Program Files\LLVM\bin` |
| Visual Studio Build Tools | 2022 or newer | "Desktop development with C++" workload + a Windows SDK. clang uses its headers and libraries; no developer shell needed. |

With scoop, for example:

```powershell
scoop install git cmake ninja llvm
```

## Build

```powershell
git clone https://github.com/AlifianK/opus-tools-build.git
cd opus-tools-build
./fetch-sources.ps1                  # clone upstream repos into src/ + Opus DNN model data
cmake --preset release               # configure (first run takes a few minutes: flac's checks)
cmake --build --preset release       # build + install to dist/bin
```

Result:

```
dist/bin/opusenc.exe
dist/bin/opusdec.exe
dist/bin/opusinfo.exe
```

### Presets

| Preset | CPU target | Output |
|--------|-----------|--------|
| `release` | `-march=native`: runs on this machine's CPU (or newer) only | `dist/bin` |
| `release-portable` | `-march=x86-64-v2`: runs on any x64 CPU from roughly 2009 on | `dist-portable/bin` |

```powershell
cmake --preset release-portable
cmake --build --preset release-portable
```

## Update to the latest upstream commits

```powershell
./fetch-sources.ps1                  # git pull every repo in src/, refresh the model if it changed
cmake --build --preset release       # rebuilds only what changed
```

`./fetch-sources.ps1 -NoUpdate` clones missing repos but leaves existing ones as they are.

If an upstream change adds or removes source files in libopusenc, opusfile or opus-tools, update
the file lists in `CMakeLists.txt` (compare with their `Makefile.am`). ogg, opus and flac use
their own CMake builds, so they need nothing.

## Quick usage

```powershell
opusenc --bitrate 128 input.wav output.opus      # also takes FLAC, AIFF and raw PCM input
opusenc input.flac output.opus                   # tags and cover art carried over
opusdec input.opus output.wav
opusinfo input.opus
```

`opusenc --help` and `opusdec --help` list every option.

## How it fits together

| Library     | Upstream build | Here |
|-------------|----------------|------|
| ogg, opus, flac | CMake      | `add_subdirectory`; tests, programs, docs and installs switched off |
| opusfile    | CMake, but its install/export rules need ogg and opus to be installed packages | own targets in `CMakeLists.txt` |
| libopusenc  | autotools only | own target, sources from its `Makefile.am` |
| opus-tools  | autotools only | own targets, sources from `Makefile.am` + the win32 VS projects |

- `cmake/clang-lto.toolchain.cmake`: clang/clang++ (GNU-style driver, MSVC ABI), lld, llvm-ar,
  full LTO, static CRT (`/MT`).
- `cmake/config/*.h.in`: generated `config.h` files. They replace the upstream `win32/config.h`
  files, and the version strings come from `git describe`.
- Opus is built with DEEP_PLC, DRED and OSCE, as in the official Windows builds. That needs the
  model data that `fetch-sources.ps1` downloads (with a SHA-256 check) into `src/opus/dnn`.
- Everything is compiled as LLVM bitcode and optimized together at link time, across all six
  libraries.

## Limits

- opusdec has no `http(s)://` input. That needs OpenSSL, so opusfile's HTTP support is off.
- No PGO.
- x64 only.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `fetch-sources.ps1`: model download fails or "hash check" error | media.xiph.org sometimes drops connections. Run the script again; it resumes. |
| CMake: `Missing src/...` or `Opus DNN model data missing` | Run `./fetch-sources.ps1`. |
| CMake can't find `clang` | Install LLVM, or set `LLVMInstallDir` to its folder. |
| Linker can't find `libcmt.lib`, `kernel32.lib` etc. | Install VS Build Tools with the C++ workload and a Windows SDK. |
| Version shows `unknown` | The repo in `src/` has no tags (shallow clone). Run `git -C src/<name> fetch --unshallow --tags`. |
| Odd errors after changing the toolchain or presets | `cmake --preset release --fresh` |
