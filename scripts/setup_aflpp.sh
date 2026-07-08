#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[+] Installing AFL++ and build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    afl++ \
    build-essential \
    cmake \
    autoconf \
    automake \
    libtool \
    pkg-config \
    python3 \
    git \
    clang \
    llvm \
    2>/dev/null

echo "[+] AFL++ version:"
afl-cc --version 2>&1 | head -1 || echo "afl-cc not found, trying afl-clang-fast"
afl-clang-fast --version 2>&1 | head -1 || true

echo "[+] Setup complete"
