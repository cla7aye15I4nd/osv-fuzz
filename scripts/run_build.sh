#!/bin/bash
set -euo pipefail

PROJECT="${1:?Usage: run_build.sh <project>}"
BUILD_SCRIPT="${2:?Usage: run_build.sh <project> <build_script>}"

export CC="${CC:-afl-cc}"
export CXX="${CXX:-afl-c++}"
export CFLAGS="${CFLAGS:-} -fsanitize=address"
export CXXFLAGS="${CXXFLAGS:-} -fsanitize=address"
export FUZZING_ENGINE=afl
export LIB_FUZZING_ENGINE=""
export SANITIZER=address
export ARCHITECTURE=x86_64
export SRC=/tmp/src
export OUT="${GITHUB_WORKSPACE:-$(pwd)}/build/fuzz-targets"
export WORK=/tmp/work

mkdir -p "$OUT" "$WORK"

# Make /usr/local writable for install commands (common in oss-fuzz builds)
sudo chmod -R a+w /usr/local/lib /usr/local/include /usr/local/bin 2>/dev/null || true
sudo mkdir -p /usr/local/lib/pkgconfig && sudo chmod a+w /usr/local/lib/pkgconfig 2>/dev/null || true

exec bash "$BUILD_SCRIPT"
