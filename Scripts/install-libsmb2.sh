#!/bin/bash
# Build/install libsmb2 into /opt/homebrew (no Homebrew formula exists).
set -euo pipefail
PREFIX="${PREFIX:-/opt/homebrew}"
SRC="${SRC:-/tmp/libsmb2}"
if [[ ! -d "$SRC" ]]; then
  git clone --depth 1 https://github.com/sahlberg/libsmb2 "$SRC"
fi
cmake -S "$SRC" -B "$SRC/build" \
  -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DINSTALL_INC_DIR="$PREFIX/include" \
  -DINSTALL_LIB_DIR="$PREFIX/lib" \
  -DINSTALL_PKGCONFIG_DIR="$PREFIX/lib/pkgconfig" \
  -DINSTALL_CMAKE_DIR="$PREFIX/lib/cmake/libsmb2"
cmake --build "$SRC/build" -j 8
cmake --install "$SRC/build"
echo "libsmb2 installed to $PREFIX"
