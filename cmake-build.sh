#!/usr/bin/env bash
# cmake-build.sh — Build llama.cpp (CPU, native SIMD) for Linux
#
# Detects AVX512 and enables it automatically via -march=native.
# This is the recommended build for Bonsai Q1_0 models — the custom
# ggml_vec_dot_q1_0_g128_q8_0 kernel requires AVX512F + AVX512BW.
#
# Prerequisites (first time only):
#   sudo apt-get install -y cmake build-essential
#
# Usage:
#   ./cmake-build.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v cmake &>/dev/null; then
    echo "cmake not found. Installing..."
    sudo apt-get update -qq && sudo apt-get install -y cmake build-essential
fi

# Check for AVX512 and warn if missing (kernel falls back to scalar)
if grep -q avx512f /proc/cpuinfo 2>/dev/null; then
    echo "AVX512 detected — Q1_0 SIMD kernel will be active."
else
    echo "WARNING: AVX512 not detected. Q1_0 kernel will fall back to scalar (slow)."
    echo "         This build is optimised for AVX512 CPUs (Skylake-X, Ice Lake, Zen 4+)."
fi

echo "=== Configuring build (CPU, -march=native) ==="
cmake -B "$SCRIPT_DIR/build" \
    -DGGML_VULKAN=OFF \
    -DGGML_CUDA=OFF \
    -DGGML_METAL=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-march=native" \
    -DCMAKE_CXX_FLAGS="-march=native" \
    "$SCRIPT_DIR"

echo ""
echo "=== Building with $(nproc) jobs ==="
cmake --build "$SCRIPT_DIR/build" --config Release -j "$(nproc)"

echo ""
echo "=== Build complete! ==="
echo "Binary : $SCRIPT_DIR/build/bin/llama-server"
echo ""
echo "Launch : ./start-up.sh"
