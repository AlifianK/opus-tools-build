# One CMake tree for opus-tools (opusenc, opusdec, opusinfo) and every library it needs:
#   ogg, opus, opusfile/opusurl, flac  -> their own upstream CMake builds (add_subdirectory)
#   libopusenc, opus-tools             -> autotools-only upstream, so built by targets defined here
# Everything is compiled in this tree, so with -flto the final link optimizes across all of it.
cmake_minimum_required(VERSION 4.4)

set(CMAKE_POLICY_DEFAULT_CMP0077 NEW) # let option() in subprojects take the values set below
project(opus-tools-build LANGUAGES C)

set(SRC "${CMAKE_CURRENT_SOURCE_DIR}/src")
foreach(dep ogg opus opusfile flac libopusenc opus-tools)
  if(NOT EXISTS "${SRC}/${dep}")
    message(FATAL_ERROR "Missing ${SRC}/${dep}. Run fetch-sources.ps1 first.")
  endif()
endforeach()

# Version string from `git describe` (e.g. 0.2-59-g4110587), like upstream's genversion scripts.
function(git_version out dir)
  execute_process(COMMAND git -C "${dir}" describe --tags --match "v*" --dirty
                  OUTPUT_VARIABLE v OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET RESULT_VARIABLE rc)
  if(rc EQUAL 0)
    string(REGEX REPLACE "^v" "" v "${v}")
  else()
    set(v "unknown")
  endif()
  set(${out} "${v}" PARENT_SCOPE)
endfunction()

# Static libraries only, nothing from the subprojects' tests, programs, docs or install rules.
set(BUILD_SHARED_LIBS OFF)
set(BUILD_TESTING OFF)

# --- ogg ------------------------------------------------------------------------------------------
set(INSTALL_DOCS OFF)
set(INSTALL_PKG_CONFIG_MODULE OFF)
set(INSTALL_CMAKE_PACKAGE_MODULE OFF)
add_subdirectory("${SRC}/ogg" ogg EXCLUDE_FROM_ALL)

# --- opus -----------------------------------------------------------------------------------------
# Neural features as in the upstream Windows release builds. They need the model data that
# fetch-sources.ps1 unpacks into src/opus/dnn.
set(OPUS_DEEP_PLC ON)
set(OPUS_DRED ON)
set(OPUS_OSCE ON)
set(OPUS_BUILD_PROGRAMS OFF)
set(OPUS_BUILD_TESTING OFF)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF)
if(NOT EXISTS "${SRC}/opus/dnn/fargan_data.c")
  message(FATAL_ERROR "Opus DNN model data missing from src/opus/dnn. Run fetch-sources.ps1.")
endif()
add_subdirectory("${SRC}/opus" opus EXCLUDE_FROM_ALL)

# --- opusfile + opusurl ---------------------------------------------------------------------------
# Built here rather than with opusfile's own CMake, whose install(EXPORT) rules need ogg and opus
# to be installed packages. Sources and defines follow src/opusfile/CMakeLists.txt.
# No HTTP(S) streaming in opusdec: that needs OpenSSL. opusurl is still built (http.c then holds
# stubs), since opusdec calls op_open_url().
set(_of "${SRC}/opusfile/src")
add_library(opusfile STATIC ${_of}/info.c ${_of}/internal.c ${_of}/opusfile.c ${_of}/stream.c)
target_include_directories(opusfile PUBLIC "${SRC}/opusfile/include")
target_compile_definitions(opusfile PRIVATE OP_HAVE_LRINTF)
target_link_libraries(opusfile PUBLIC Ogg::ogg Opus::opus)
add_library(opusurl STATIC ${_of}/http.c ${_of}/internal.c)
target_compile_definitions(opusurl PRIVATE OP_HAVE_LRINTF)
target_link_libraries(opusurl PUBLIC opusfile)

# --- flac (decoder used by opusenc for FLAC input) ------------------------------------------------
enable_language(CXX) # flac's project() declares C and CXX
set(BUILD_CXXLIBS OFF)
set(BUILD_PROGRAMS OFF)
set(BUILD_EXAMPLES OFF)
set(BUILD_DOCS OFF)
set(INSTALL_MANPAGES OFF)
set(INSTALL_PKGCONFIG_MODULES OFF)
set(INSTALL_CMAKE_CONFIG_MODULE OFF)
set(WITH_OGG ON)
set(ENABLE_MULTITHREADING OFF) # opusenc only decodes; avoids a pthreads dependency
add_subdirectory("${SRC}/flac" flac EXCLUDE_FROM_ALL)

# --- libopusenc (autotools upstream; sources from its Makefile.am) --------------------------------
git_version(LIBOPUSENC_VERSION "${SRC}/libopusenc")
configure_file(cmake/config/libopusenc.config.h.in gen/libopusenc/config.h @ONLY)
set(_ope "${SRC}/libopusenc/src")
add_library(libopusenc STATIC
  ${_ope}/ogg_packer.c ${_ope}/opus_header.c ${_ope}/opusenc.c ${_ope}/picture.c
  ${_ope}/random.c ${_ope}/resample.c ${_ope}/unicode_support.c)
target_include_directories(libopusenc
  PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/gen/libopusenc"
  PUBLIC  "${SRC}/libopusenc/include")
target_compile_definitions(libopusenc PRIVATE HAVE_CONFIG_H WIN32 RANDOM_PREFIX=libopusenc OUTSIDE_SPEEX)
target_link_libraries(libopusenc PUBLIC Opus::opus)

# --- opus-tools (autotools upstream; sources from its Makefile.am + win32 VS projects) ------------
git_version(OPUSTOOLS_VERSION "${SRC}/opus-tools")
configure_file(cmake/config/opus-tools.config.h.in gen/opus-tools/config.h @ONLY)
set(_ot "${SRC}/opus-tools")

add_library(opustools_common INTERFACE)
target_include_directories(opustools_common INTERFACE
  "${CMAKE_CURRENT_BINARY_DIR}/gen/opus-tools" # our config.h, ahead of win32/config.h
  "${_ot}/src" "${_ot}/win32" "${_ot}/include")
target_compile_definitions(opustools_common INTERFACE HAVE_CONFIG_H WIN32)
target_sources(opustools_common INTERFACE
  ${_ot}/share/getopt.c ${_ot}/share/getopt1.c ${_ot}/src/opus_header.c ${_ot}/win32/unicode_support.c)

add_executable(opusenc
  ${_ot}/src/opusenc.c ${_ot}/src/tagcompare.c ${_ot}/src/audio-in.c ${_ot}/src/diag_range.c
  ${_ot}/src/flac.c)
target_link_libraries(opusenc PRIVATE opustools_common libopusenc Opus::opus FLAC::FLAC Ogg::ogg)

add_executable(opusdec
  ${_ot}/src/wav_io.c ${_ot}/src/wave_out.c ${_ot}/src/opusdec.c ${_ot}/src/resample.c
  ${_ot}/src/diag_range.c)
target_link_libraries(opusdec PRIVATE opustools_common opusurl opusfile
                                      Opus::opus Ogg::ogg winmm)

add_executable(opusinfo
  ${_ot}/src/opusinfo.c ${_ot}/src/info_opus.c ${_ot}/src/picture.c ${_ot}/src/tagcompare.c)
target_link_libraries(opusinfo PRIVATE opustools_common Ogg::ogg)

install(TARGETS opusenc opusdec opusinfo RUNTIME DESTINATION bin)

message(STATUS "opus-tools ${OPUSTOOLS_VERSION}, libopusenc ${LIBOPUSENC_VERSION}")
