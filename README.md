# opus-tools build (clang, full LTO, CMake + Ninja)

Builds `opusenc`, `opusdec` and `opusinfo` from the latest git master of opus-tools, libopusenc,
opusfile, opus, ogg and flac, in a single CMake tree. The output is static .exe files that need no
DLLs beyond Windows' own.

```powershell
./fetch-sources.ps1                  # clone, or update src/* to latest master, + Opus DNN model data
cmake --preset release               # configure (Ninja, clang GNU driver, -flto, -march=native, /MT)
cmake --build --preset release       # build + install to dist/bin
```

Use the `release-portable` preset (`-march=x86-64-v2`, installs to `dist-portable/`) for binaries
that need to run on other machines.

## How it fits together

| Library     | Upstream build | Here |
|-------------|----------------|------|
| ogg, opus, flac | CMake      | `add_subdirectory`; tests, programs, docs and installs switched off |
| opusfile    | CMake, but its install/export rules need ogg and opus to be installed packages | own targets in `CMakeLists.txt` |
| libopusenc  | autotools only | own target, sources from its `Makefile.am` |
| opus-tools  | autotools only | own targets, sources from `Makefile.am` + the win32 VS projects |

- `cmake/clang-lto.toolchain.cmake`: clang/clang++, lld, llvm-ar, full LTO, static CRT.
- `cmake/config/*.h.in`: generated `config.h` files. They replace the upstream `win32/config.h`
  files, and the version strings come from `git describe`.
- Opus is built with DEEP_PLC, DRED and OSCE, as in the official Windows builds. That needs the
  model data that `fetch-sources.ps1` downloads (with a hash check) into `src/opus/dnn`.
- opusdec has no HTTP(S) URL input. That needs OpenSSL, so opusfile's HTTP support is off.
