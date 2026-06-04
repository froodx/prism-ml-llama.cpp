# Local Setup — Bonsai + DuckDuckGo MCP

Scripts and patches added to this fork on top of the upstream Prism-ML / llama.cpp codebase.

## What's been changed / added

| File | What changed |
|------|-------------|
| `ggml/src/ggml-cpu/arch/x86/quants.c` | **AVX512 kernel for Q1_0_g128** — replaces scalar stub with `_mm512_movm_epi8` + VNNI dot product (~130 tok/s on AVX512 CPUs vs ~2 tok/s scalar) |
| `cmake-build.sh` | Added `-march=native` to enable AVX512; CPU-only (no Vulkan/CUDA — see note below) |
| `cmake-build-vulkan.sh` | Vulkan build — **not recommended for Q1_0 models** (227 CPU↔GPU splits, slower) |
| `cmake-build-cuda.sh` | NVIDIA CUDA build — for non-Q1_0 models only |
| `start-up.sh` | Model picker, MCP server, browser launch — works first-go on Linux |
| `mcp-duckduckgo/server.py` | Added status page at `/`; runs as streamable HTTP (no supergateway needed) |
| `mcp-duckduckgo/requirements.txt` | Added `uvicorn` |
| `setup-mcp-search.sh` | Simplified — Python deps only, no Node.js/supergateway |
| `webui-config.json` | Pre-configures MCP endpoint in the llama.cpp Web UI |

## Why CPU-only is faster for Q1_0 models

The Vulkan backend cannot execute `Q1_0_g128` matrix multiplications natively.
With Vulkan enabled, the scheduler falls back to CPU for every GEMM but routes
other ops (layer norm, attention) to GPU — creating ~227 CPU↔GPU sync points
per forward pass. The synchronisation overhead dominates.

CPU-only with the AVX512 kernel eliminates all sync overhead. 1 graph split
instead of 227. On a 32-thread AVX512 machine: **~130 tokens/sec** on the 1.7B model.

## Quick start — Linux (first time)

```bash
# 1. Install build tools (once)
sudo apt-get install -y cmake build-essential

# 2. Build — CPU only, -march=native (enables AVX512 automatically)
./cmake-build.sh

# 3. Install Python deps for MCP server (once)
./setup-mcp-search.sh

# 4. Launch — model picker, starts MCP server, opens browser
./start-up.sh
```

## Quick start — Linux (returning user)

```bash
./start-up.sh          # interactive model picker
./start-up.sh 1        # Bonsai 1.7B directly
./start-up.sh 2        # Bonsai 8B directly
```

## Models

Place `.gguf` files in `~/.lmstudio/models/1-Bit-Bonsai/` (or set `MODEL_DIR`).

| Model | Size | Speed (AVX512, 32 threads) |
|-------|------|---------------------------|
| `Bonsai-1.7B-Q1_0.gguf` | 237 MB | ~130 tok/s |
| `Bonsai-8B-Q1_0.gguf`   | 1.1 GB | ~25–30 tok/s (est.) |

Download: https://huggingface.co/prism-ml/Bonsai-1.7B-gguf

## Hardware requirements for full performance

The Q1_0_g128 AVX512 kernel activates when the compiler sees `__AVX512F__` and
`__AVX512BW__`. `-march=native` in `cmake-build.sh` sets this automatically.
Falls back to scalar (slow) on non-AVX512 hardware.

Confirmed fast on: AMD Ryzen AI / Zen 4+ with AVX512, Intel Ice Lake+, Sapphire Rapids.

## Ports

| Service | Port |
|---------|------|
| llama-server Web UI | 8080 |
| DuckDuckGo MCP | 8808 |
