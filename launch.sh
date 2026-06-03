#!/usr/bin/env bash
# Bonsai Model Launcher — Linux / Ubuntu
# Starts DuckDuckGo MCP server, prompts for model selection, opens Web UI
#
# Usage:
#   ./launch.sh          — interactive model menu
#   ./launch.sh 1        — Bonsai 1.7B directly
#   ./launch.sh 2        — Bonsai 8B directly
#
# Set MODELS_DIR to override the default model directory:
#   MODELS_DIR=~/my-models ./launch.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
PORT=8080
MCP_PORT=8808
WEBUI_CONFIG="$SCRIPT_DIR/webui-config.json"
SERVER_BIN="$SCRIPT_DIR/build/bin/llama-server"
MCP_SCRIPT="$SCRIPT_DIR/start-mcp-search.sh"

# Model definitions
MODEL_NAMES=(
    "Bonsai 1.7B  Q1_0  (fast, ~250 MB)"
    "Bonsai 8B    Q1_0  (smarter, ~1.5 GB)"
)
MODEL_FILES=(
    "$MODELS_DIR/Bonsai-1.7B-Q1_0.gguf"
    "$MODELS_DIR/Bonsai-8B-Q1_0.gguf"
)

# --- Preflight ---
if [ ! -f "$SERVER_BIN" ]; then
    echo "ERROR: llama-server not found. Run ./cmake-build.sh first."
    exit 1
fi

# --- Model selection ---
CHOICE="${1:-0}"
if [ "$CHOICE" -eq 0 ] 2>/dev/null; then
    echo ""
    echo "  ╔══════════════════════════════════╗"
    echo "  ║     Bonsai Model Launcher        ║"
    echo "  ╚══════════════════════════════════╝"
    echo ""
    for i in "${!MODEL_NAMES[@]}"; do
        AVAIL="✓"
        [ ! -f "${MODEL_FILES[$i]}" ] && AVAIL="✗ not found"
        echo "  $((i+1)).  ${MODEL_NAMES[$i]}  [$AVAIL]"
    done
    echo ""
    read -rp "  Select model (1-${#MODEL_NAMES[@]}): " CHOICE
fi

IDX=$((CHOICE - 1))
MODEL_PATH="${MODEL_FILES[$IDX]}"

if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Model not found: $MODEL_PATH"
    echo "Set MODELS_DIR env var to your models directory, e.g.:"
    echo "  MODELS_DIR=/data/models ./launch.sh"
    exit 1
fi

echo ""
echo "  Model  : ${MODEL_NAMES[$IDX]}"
echo "  File   : $MODEL_PATH"
echo "  Web UI : http://localhost:$PORT"
echo ""

# --- Start MCP server in background ---
echo "Starting DuckDuckGo MCP server..."
bash "$MCP_SCRIPT" &
MCP_PID=$!
trap "kill $MCP_PID 2>/dev/null || true" EXIT
sleep 3

# --- Open browser (best-effort) ---
(sleep 5 && xdg-open "http://localhost:$PORT" 2>/dev/null || true) &

# --- Start llama-server (foreground) ---
echo "Starting llama-server... (Ctrl+C to stop)"
echo ""
THREADS=$(nproc)
"$SERVER_BIN" \
    -m "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port "$PORT" \
    -ngl 0 \
    --ctx-size 8192 \
    --threads "$THREADS" \
    --webui-mcp-proxy \
    --webui-config-file "$WEBUI_CONFIG"
