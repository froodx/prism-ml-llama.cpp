#!/usr/bin/env bash
# cmake-build-cuda.sh — Build llama.cpp with CUDA support (NVIDIA GPU only)
# Requires: cmake, gcc, CUDA toolkit (nvidia-cuda-toolkit or cuda-toolkit)
#
# For AMD GPUs, use ./cmake-build-vulkan.sh instead.
#
# If CUDA toolkit is not installed:
#   sudo apt-get install nvidia-cuda-toolkit
# Or grab the full toolkit from developer.nvidia.com/cuda-downloads

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Preflight ─────────────────────────────────────────────────────────────────
if ! command -v cmake &>/dev/null; then
    echo "cmake not found. Installing..."
    sudo apt-get update -qq && sudo apt-get install -y cmake build-essential
fi

if ! command -v nvcc &>/dev/null; then
    echo ""
    echo "WARNING: nvcc not found — CUDA toolkit may not be installed."
    echo "         Install: sudo apt-get install nvidia-cuda-toolkit"
    echo "         Or:      https://developer.nvidia.com/cuda-downloads"
    echo ""
    read -rp "Continue anyway? (y/N) " yn
    [[ "${yn,,}" == "y" ]] || exit 1
fi

# ── Configure ─────────────────────────────────────────────────────────────────
echo "=== Configuring build (CUDA-enabled) ==="
cmake -B "$SCRIPT_DIR/build" \
    -DGGML_CUDA=ON \
    -DGGML_METAL=OFF \
    -DGGML_VULKAN=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    "$SCRIPT_DIR"

# ── Build ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Building with $(nproc) jobs (this takes 5-20 min first time) ==="
cmake --build "$SCRIPT_DIR/build" --config Release -j "$(nproc)"

echo ""
echo "=== Build complete! ==="
echo "Binary : $SCRIPT_DIR/build/bin/llama-server"
echo ""
echo "Launch : ./start-up.sh"
echo "         (uses -ngl 999 by default — all layers on GPU)"
