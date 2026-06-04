#!/usr/bin/env bash
# start-up.sh — All-in-one launcher for prism-ml-llama.cpp (Linux)
# Starts the DuckDuckGo MCP server, presents a model picker, launches
# llama-server, and opens Chrome. The MCP server page also doubles as a
# live model switcher — no restart needed to change models.
#
# Usage:
#   ./start-up.sh            — interactive model menu
#   ./start-up.sh 2          — pick model 2 directly
#
# Overrides:
#   MODEL_DIR=/path/to/models ./start-up.sh
#   CTX_SIZE=16384 ./start-up.sh
#   GPU_LAYERS=0   ./start-up.sh   — CPU-only (default and recommended for Q1_0)

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_BIN="$SCRIPT_DIR/build/bin/llama-server"
SERVER_PY="$SCRIPT_DIR/mcp-duckduckgo/server.py"
WEBUI_CFG="$SCRIPT_DIR/webui-config.json"
MODEL_DIR="${MODEL_DIR:-$HOME/.lmstudio/models}"
PORT=8080
MCP_PORT=8808
# 8192 tokens: fast KV cache (~900 MB). Use CTX_SIZE=32768 for long sessions.
CTX_SIZE="${CTX_SIZE:-8192}"
# GPU_LAYERS: only matters for Vulkan/CUDA builds. CPU-only build ignores it.
GPU_LAYERS="${GPU_LAYERS:-999}"

# ── PIDs to clean up ──────────────────────────────────────────────────────────
MCP_PID=""
BROWSER_PID=""
LLAMA_PID=""

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'

die() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${RESET}"
    [[ -n "$LLAMA_PID"   ]] && kill "$LLAMA_PID"   2>/dev/null || true
    [[ -n "$MCP_PID"     ]] && kill "$MCP_PID"     2>/dev/null || true
    [[ -n "$BROWSER_PID" ]] && kill "$BROWSER_PID" 2>/dev/null || true
    echo -e "${GREEN}Done.${RESET}"
}
trap cleanup EXIT INT TERM

# ── Preflight checks ──────────────────────────────────────────────────────────
[[ -f "$SERVER_BIN" ]] || die "llama-server not found at:\n        $SERVER_BIN\n\n        Build: ./cmake-build.sh"
[[ -f "$SERVER_PY"  ]] || die "MCP server not found at: $SERVER_PY"
[[ -f "$WEBUI_CFG"  ]] || die "webui-config.json not found at: $WEBUI_CFG"
[[ -d "$MODEL_DIR"  ]] || die "Model directory not found: $MODEL_DIR\n        Set MODEL_DIR env var to override."

# ── Discover models (recursive — finds models in subfolders too) ──────────────
mapfile -t MODEL_FILES < <(find "$MODEL_DIR" -name "*.gguf" | sort)
[[ ${#MODEL_FILES[@]} -gt 0 ]] || die "No .gguf files found under $MODEL_DIR"

# ── Model selection ───────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}============================================${RESET}"
echo -e "${CYAN}   prism-ml / llama.cpp  —  Model Picker   ${RESET}"
echo -e "${CYAN}============================================${RESET}"
echo ""

for i in "${!MODEL_FILES[@]}"; do
    name="$(basename "${MODEL_FILES[$i]}")"
    folder="$(basename "$(dirname "${MODEL_FILES[$i]}")")"
    size_bytes="$(stat -c '%s' "${MODEL_FILES[$i]}" 2>/dev/null || stat -f '%z' "${MODEL_FILES[$i]}")"
    size_mb=$(( size_bytes / 1024 / 1024 ))
    printf "  %2d.  %-20s  %-40s  %4d MB\n" "$((i+1))" "$folder" "$name" "$size_mb"
done
echo ""

MODEL_INDEX="${1:-0}"
if [[ "$MODEL_INDEX" -eq 0 ]]; then
    read -rp "Select model (1-${#MODEL_FILES[@]}): " MODEL_INDEX
fi

if ! [[ "$MODEL_INDEX" =~ ^[0-9]+$ ]] || \
   [[ "$MODEL_INDEX" -lt 1 ]] || \
   [[ "$MODEL_INDEX" -gt ${#MODEL_FILES[@]} ]]; then
    die "Selection out of range."
fi

SELECTED_PATH="${MODEL_FILES[$((MODEL_INDEX-1))]}"
SELECTED_NAME="$(basename "$SELECTED_PATH")"

echo ""
echo -e "  ${GREEN}Model${RESET}      : $SELECTED_NAME"
echo -e "  ${GREEN}Web UI${RESET}     : http://localhost:$PORT"
echo -e "  ${GREEN}Switcher${RESET}   : http://localhost:$MCP_PORT/"
echo -e "  ${GREEN}Context${RESET}    : $CTX_SIZE tokens"
echo ""

# ── Kill anything already on our ports ────────────────────────────────────────
for p in "$MCP_PORT" "$PORT"; do
    pid="$(lsof -ti tcp:"$p" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
done

# ── Start MCP server — passes config so it can switch models itself ───────────
echo -e "${YELLOW}Starting DuckDuckGo MCP + model switcher on port $MCP_PORT...${RESET}"
PYTHONUNBUFFERED=1 \
LLAMA_SERVER_BIN="$SERVER_BIN" \
LLAMA_MODEL_DIR="$MODEL_DIR" \
LLAMA_PORT="$PORT" \
LLAMA_GPU_LAYERS="$GPU_LAYERS" \
LLAMA_CTX_SIZE="$CTX_SIZE" \
LLAMA_WEBUI_CFG="$WEBUI_CFG" \
python3 -u "$SERVER_PY" --streamable-http --port "$MCP_PORT" \
    &>/tmp/mcp-server.log &
MCP_PID=$!

DEADLINE=$(( $(date +%s) + 20 ))
MCP_READY=false
while [[ $(date +%s) -lt $DEADLINE ]]; do
    if lsof -ti tcp:"$MCP_PORT" &>/dev/null; then
        MCP_READY=true; break
    fi
    sleep 0.4
done

if [[ "$MCP_READY" != true ]]; then
    echo -e "${RED}MCP server failed. Log:${RESET}"
    cat /tmp/mcp-server.log || true
    die "MCP server did not start within 20 s.\n        Check: pip3 install --break-system-packages mcp ddgs uvicorn"
fi
echo -e "${GREEN}MCP server ready.${RESET}"

# ── Open Chrome — switcher + chat UI (background, waits for llama-server) ─────
(
    DEADLINE=$(( $(date +%s) + 60 ))
    while [[ $(date +%s) -lt $DEADLINE ]]; do
        if lsof -ti tcp:"$PORT" &>/dev/null; then break; fi
        sleep 0.5
    done
    SWITCHER_URL="http://localhost:$MCP_PORT/"
    LLAMA_URL="http://localhost:$PORT"
    if   command -v google-chrome    &>/dev/null; then google-chrome    "$SWITCHER_URL" "$LLAMA_URL" &
    elif command -v chromium-browser &>/dev/null; then chromium-browser "$SWITCHER_URL" "$LLAMA_URL" &
    elif command -v chromium         &>/dev/null; then chromium         "$SWITCHER_URL" "$LLAMA_URL" &
    elif command -v xdg-open         &>/dev/null; then xdg-open         "$SWITCHER_URL" & xdg-open "$LLAMA_URL" &
    fi
) &
BROWSER_PID=$!

# ── Start llama-server as background process ──────────────────────────────────
echo ""
echo -e "${CYAN}Starting llama-server...${RESET}"
echo ""

"$SERVER_BIN" \
    --model              "$SELECTED_PATH" \
    --host               0.0.0.0 \
    --port               "$PORT" \
    -ngl                 "$GPU_LAYERS" \
    --ctx-size           "$CTX_SIZE" \
    --threads            "$(nproc)" \
    --webui-mcp-proxy \
    --webui-config-file  "$WEBUI_CFG" \
    &>/tmp/llama-server.log &
LLAMA_PID=$!

echo -e "${GREEN}llama-server started (PID $LLAMA_PID)${RESET}"
echo -e "  Web UI  : http://localhost:$PORT"
echo -e "  Switcher: http://localhost:$MCP_PORT/"
echo -e "  Log     : /tmp/llama-server.log"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all, or close this terminal to leave running.${RESET}"

# Wait for llama-server so Ctrl+C propagates
wait $LLAMA_PID
