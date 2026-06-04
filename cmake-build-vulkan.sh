#!/usr/bin/env bash
# cmake-build-vulkan.sh — Build llama.cpp with Vulkan GPU support (AMD/Intel/any)
#
# WARNING: NOT recommended for Bonsai Q1_0 models.
# Vulkan cannot execute Q1_0_g128 kernels natively — the scheduler creates
# ~227 CPU↔GPU sync points per forward pass, making generation far slower
# than the CPU-only build. Use ./cmake-build.sh instead.
#
# Only use this if you are running non-Q1_0 models (Q4, Q5, Q8, etc.)
# where Vulkan offload is actually beneficial.
#
# Prerequisites (first time only):
#   sudo apt-get install -y cmake build-essential libvulkan-dev glslang-tools glslc

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "WARNING: Vulkan build is NOT recommended for Q1_0 Bonsai models."
echo "         For Bonsai, use: ./cmake-build.sh  (CPU + AVX512, ~130 tok/s)"
echo ""
read -rp "Continue with Vulkan build anyway? (y/N) " yn
[[ "${yn,,}" == "y" ]] || exit 0

if ! command -v cmake &>/dev/null; then
    echo "cmake not found. Run: sudo apt-get install -y cmake build-essential"
    exit 1
fi

if ! dpkg -s libvulkan-dev &>/dev/null 2>&1 || ! command -v glslc &>/dev/null; then
    echo "Vulkan dev libs not found. Run:"
    echo "  sudo apt-get install -y libvulkan-dev glslang-tools glslc"
    exit 1
fi

echo "=== Configuring build (Vulkan + -march=native) ==="
cmake -B "$SCRIPT_DIR/build" \
    -DGGML_VULKAN=ON \
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
echo "Launch : GPU_LAYERS=999 ./start-up.sh"
