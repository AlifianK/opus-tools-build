# opus-tools build (clang, full LTO, CMake + Ninja)

Builds `opusenc`, `opusdec` and `opusinfo` together with every library they need (opus-tools,
libopusenc, opusfile, opus, ogg, flac) in a single CMake tree. The output is static .exe files that
need no DLLs beyond Windows' own.

There are two channels:

- **latest** (the default): git master of every repo.
- **stable** (the fallback): the newest release tag of every repo, for when master is broken.

Upstream builds opus-tools and libopusenc with autotools only, and their Windows project files are
VS2015-era. This repo replaces both with plain CMake. No MSYS2, MinGW or autotools needed.

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| Windows | 10 or 11, x64 | `curl.exe` and `tar.exe` ship with Windows |
| PowerShell | 7+ | for `fetch-sources.ps1` |
| Git | any recent | sources and version strings come from git |
| CMake | 4.4+ | `cmake_minimum_required(VERSION 4.4)`: policies stay at 4.4 behavior until that line is raised |
| Ninja | any recent | |
| LLVM | recent release | `clang`, `clang++`, `lld`, `llvm-ar`, `llvm-rc`; found via `%LLVMInstallDir%\bin` or `C:\Program Files\LLVM\bin` |
| Visual Studio Build Tools | 2022 or newer | "Desktop development with C++" workload + a Windows SDK. clang uses its headers and libraries; no developer shell needed. |

With scoop, for example:

```powershell
scoop install git cmake ninja llvm
```

## Build (latest)

```powershell
git clone https://github.com/AlifianK/opus-tools-build.git
cd opus-tools-build
./fetch-sources.ps1                  # clone master of every repo into src/ + Opus DNN model data
cmake --preset latest                # configure (first run takes a few minutes: flac's checks)
cmake --build --preset latest        # build + install to dist/latest/bin
```

Result:

```
dist/latest/bin/opusenc.exe
dist/latest/bin/opusdec.exe
dist/latest/bin/opusinfo.exe
```

## Fallback: build the stable channel

When master of some repo doesn't build or misbehaves, build the newest releases instead:

```powershell
./fetch-sources.ps1 -Channel stable  # src-stable/ at the newest release tag of every repo
cmake --preset stable
cmake --build --preset stable        # → dist/stable/bin
```

`src-stable/` holds git worktrees of the `src/` clones, so nothing is downloaded twice. Each tree
gets the Opus model data its own opus version asks for.

To hold one repo at an older release (say a new release breaks something), pin it:

```powershell
./fetch-sources.ps1 -Channel stable -Pin @{ opus = 'v1.6'; flac = '1.4.3' }
```

Release tags as of writing: ogg v1.3.6, opus v1.6.1, opusfile v0.12, libopusenc v0.3, flac 1.5.0,
opus-tools v0.2. opus-tools v0.2 is from 2018, so the stable `opusenc`/`opusdec` lack several
years of fixes; prefer latest whenever it works.

## Presets

| Preset | Sources | CPU target | Output |
|--------|---------|-----------|--------|
| `latest` | `src/` (master) | `-march=native`: this machine's CPU (or newer) only | `dist/latest/bin` |
| `stable` | `src-stable/` (release tags) | `-march=native` | `dist/stable/bin` |
| `latest-portable` | `src/` | `-march=x86-64-v2`: any x64 CPU from roughly 2009 on | `dist/latest-portable/bin` |
| `stable-portable` | `src-stable/` | `-march=x86-64-v2` | `dist/stable-portable/bin` |

Each preset has its own build folder under `build/`, so they don't interfere.

## Update

```powershell
./fetch-sources.ps1                  # pull master in src/, refresh the model if it changed
cmake --build --preset latest        # rebuilds only what changed

./fetch-sources.ps1 -Channel stable  # move src-stable/ to any newer release tags
cmake --build --preset stable
```

`-Channel all` does both. `-NoUpdate` only creates what's missing and leaves the rest as it is.

If an upstream change adds or removes source files in libopusenc, opusfile or opus-tools, update
the file lists in `CMakeLists.txt` (compare with their `Makefile.am`). ogg, opus and flac use
their own CMake builds, so they need nothing. The few differences between the release tags and
master are already handled there (`if(EXISTS …)`).

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

- `OPUSBUILD_SOURCE_DIR` picks the source tree; it defaults to `src/` (latest). The presets set it.
- `cmake/clang-lto.toolchain.cmake`: clang/clang++ (GNU-style driver, MSVC ABI), lld, llvm-ar,
  full LTO, static CRT (`/MT`).
- `cmake/config/*.h.in`: generated `config.h` files. They replace the upstream `win32/config.h`
  files, and the version strings come from `git describe`.
- Opus is built with DEEP_PLC, DRED and OSCE, as in the official Windows builds. That needs the
  model data that `fetch-sources.ps1` downloads (with a SHA-256 check) into `<tree>/opus/dnn`.
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
| CMake: `Missing …/<repo>` or `Opus DNN model data missing` | Run `./fetch-sources.ps1` (add `-Channel stable` for the stable presets). |
| latest fails to build after an update | Build `stable` meanwhile; check whether upstream added or removed source files. |
| `src-stable/…` is broken after deleting or re-cloning `src/` | Delete `src-stable/` and run `./fetch-sources.ps1 -Channel stable` again. |
| CMake can't find `clang` | Install LLVM, or set `LLVMInstallDir` to its folder. |
| Linker can't find `libcmt.lib`, `kernel32.lib` etc. | Install VS Build Tools with the C++ workload and a Windows SDK. |
| Version shows `unknown` | The repo has no tags (shallow clone). Run `git -C src/<name> fetch --unshallow --tags`. |
| Odd errors after changing the toolchain or presets | `cmake --preset <name> --fresh` |
