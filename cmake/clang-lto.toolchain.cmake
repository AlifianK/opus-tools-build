# Toolchain: LLVM clang (GNU-style driver) targeting x86_64-pc-windows-msvc, full LTO, lld, static CRT.
# Mirrors the choices of the shared x64-win-llvm-lto-static vcpkg triplet, but uses clang/clang++
# instead of clang-cl. Project-specific: lives here, not in the shared triplets.

set(_llvm_hints "$ENV{LLVMInstallDir}/bin" "C:/Program Files/LLVM/bin")
find_program(OPUSBUILD_CLANG   NAMES clang   HINTS ${_llvm_hints} REQUIRED)
find_program(OPUSBUILD_CLANGXX NAMES clang++ HINTS ${_llvm_hints} REQUIRED)
get_filename_component(_llvm_bin "${OPUSBUILD_CLANG}" DIRECTORY)

set(CMAKE_C_COMPILER   "${OPUSBUILD_CLANG}")
set(CMAKE_CXX_COMPILER "${OPUSBUILD_CLANGXX}")
set(CMAKE_AR           "${_llvm_bin}/llvm-ar.exe"     CACHE FILEPATH "")
set(CMAKE_RANLIB       "${_llvm_bin}/llvm-ranlib.exe" CACHE FILEPATH "")
set(CMAKE_RC_COMPILER  "${_llvm_bin}/llvm-rc.exe"     CACHE FILEPATH "")
set(CMAKE_MT           "${_llvm_bin}/llvm-mt.exe"     CACHE FILEPATH "")
set(CMAKE_LINKER_TYPE  LLD)

# Static CRT (/MT), so the .exe files need no runtime DLLs.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# -march=native: binaries run on this CPU (or newer) only. Configure with -DOPUSBUILD_NATIVE=OFF for
# binaries that ship to other machines.
option(OPUSBUILD_NATIVE "Compile for this machine's CPU (-march=native)" ON)
if(OPUSBUILD_NATIVE)
  set(_arch "-march=native")
else()
  set(_arch "-march=x86-64-v2")
endif()

set(CMAKE_C_FLAGS_INIT   "${_arch} -D_CRT_SECURE_NO_WARNINGS -D_CRT_NONSTDC_NO_DEPRECATE")
set(CMAKE_CXX_FLAGS_INIT "${_arch} -D_CRT_SECURE_NO_WARNINGS -D_CRT_NONSTDC_NO_DEPRECATE")

# Full (not thin) LTO for optimized configs; the whole program is small, and every library is
# built in this tree, so the link sees all of it as bitcode.
foreach(cfg RELEASE MINSIZEREL RELWITHDEBINFO)
  set(CMAKE_C_FLAGS_${cfg}_INIT   "-flto")
  set(CMAKE_CXX_FLAGS_${cfg}_INIT "-flto")
  set(CMAKE_EXE_LINKER_FLAGS_${cfg}_INIT "-flto -Wl,/OPT:REF,/OPT:ICF")
endforeach()
set(CMAKE_EXE_LINKER_FLAGS_INIT "-Wl,/INCREMENTAL:NO -Wl,/Brepro")

list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES OPUSBUILD_NATIVE)
