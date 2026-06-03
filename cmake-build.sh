#!/usr/bin/env bash
# Build llama.cpp (CPU-only, Release) for Linux / Ubuntu
# Requires: cmake, gcc/clang, make/ninja

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check cmake
if ! command -v cmake &>/dev/null; then
    echo "cmake not found. Installing..."
    sudo apt-get update -qq && sudo apt-get install -y cmake build-essential
fi

echo "=== Configuring build (CPU-only) ==="
cmake -B "$SCRIPT_DIR/build" \
    -DGGML_CUDA=OFF \
    -DGGML_METAL=OFF \
    -DGGML_VULKAN=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    "$SCRIPT_DIR"

echo ""
echo "=== Building with $(nproc) jobs (this takes 5-15 min) ==="
cmake --build "$SCRIPT_DIR/build" --config Release -j "$(nproc)"

echo ""
echo "=== Build complete! ==="
echo "Binary: $SCRIPT_DIR/build/bin/llama-server"
