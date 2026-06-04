#!/usr/bin/env bash
# start-up.sh — All-in-one launcher for prism-ml-llama.cpp (Linux)
# Starts the DuckDuckGo MCP server, presents a model picker from the GGUF
# folder, launches llama-server, and opens Chrome once everything is ready.
#
# Usage:
#   ./start-up.sh                  — interactive model menu
#   ./start-up.sh 2                — pick model by menu number directly
#
# Adjust MODEL_DIR below if your Linux model path differs.

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_BIN="$SCRIPT_DIR/build/bin/llama-server"
SERVER_PY="$SCRIPT_DIR/mcp-duckduckgo/server.py"
MODEL_DIR="${MODEL_DIR:-$HOME/Local-LLMs/1-Bit-Bonsai}"
PORT=8080
MCP_PORT=8808

# PIDs to clean up
MCP_PID=""
BROWSER_PID=""

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'

die() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${RESET}"
    [[ -n "$MCP_PID"     ]] && kill "$MCP_PID"     2>/dev/null || true
    [[ -n "$BROWSER_PID" ]] && kill "$BROWSER_PID" 2>/dev/null || true
    echo -e "${GREEN}Done.${RESET}"
}
trap cleanup EXIT INT TERM

# ── Preflight checks ──────────────────────────────────────────────────────────
[[ -f "$SERVER_BIN" ]] || die "llama-server not found at:\n        $SERVER_BIN\n        Run: cmake --build build --config Release"
[[ -f "$SERVER_PY"  ]] || die "MCP server not found at: $SERVER_PY\n        Run: pip install mcp duckduckgo-search && npm install -g supergateway"
[[ -d "$MODEL_DIR"  ]] || die "Model directory not found: $MODEL_DIR\n        Set MODEL_DIR env var to override."

# ── Discover models ───────────────────────────────────────────────────────────
mapfile -t MODEL_FILES < <(find "$MODEL_DIR" -maxdepth 1 -name "*.gguf" | sort)

[[ ${#MODEL_FILES[@]} -gt 0 ]] || die "No .gguf files found in $MODEL_DIR"

# ── Model selection ───────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}============================================${RESET}"
echo -e "${CYAN}   prism-ml / llama.cpp  —  Model Picker   ${RESET}"
echo -e "${CYAN}============================================${RESET}"
echo ""

for i in "${!MODEL_FILES[@]}"; do
    name="$(basename "${MODEL_FILES[$i]}")"
    size_bytes="$(stat -c '%s' "${MODEL_FILES[$i]}" 2>/dev/null || stat -f '%z' "${MODEL_FILES[$i]}")"
    size_mb=$(( size_bytes / 1024 / 1024 ))
    printf "  %2d.  %-45s %s MB\n" "$((i+1))" "$name" "$size_mb"
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
echo -e "  ${GREEN}Model${RESET}  : $SELECTED_NAME"
echo -e "  ${GREEN}Web UI${RESET} : http://localhost:$PORT"
echo -e "  ${GREEN}MCP${RESET}    : http://localhost:$MCP_PORT/sse"
echo ""

# ── Kill anything already on our ports ────────────────────────────────────────
for p in "$MCP_PORT" "$PORT"; do
    pid="$(lsof -ti tcp:"$p" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
done

# ── Start MCP server (background) ────────────────────────────────────────────
echo -e "${YELLOW}Starting DuckDuckGo MCP server on port $MCP_PORT...${RESET}"
PYTHONUNBUFFERED=1 npx supergateway --port "$MCP_PORT" --cors \
    --stdio "python -u \"$SERVER_PY\"" &>/tmp/mcp-server.log &
MCP_PID=$!

# Wait up to 20 s for MCP port
DEADLINE=$(( $(date +%s) + 20 ))
MCP_READY=false
while [[ $(date +%s) -lt $DEADLINE ]]; do
    if lsof -ti tcp:"$MCP_PORT" &>/dev/null; then
        MCP_READY=true; break
    fi
    sleep 0.4
done

if [[ "$MCP_READY" != true ]]; then
    echo -e "${RED}MCP server log:${RESET}"
    cat /tmp/mcp-server.log || true
    die "MCP server did not start within 20 s."
fi
echo -e "${GREEN}MCP server ready.${RESET}"

# ── Open Chrome once llama-server port is up (background) ────────────────────
(
    DEADLINE=$(( $(date +%s) + 60 ))
    while [[ $(date +%s) -lt $DEADLINE ]]; do
        if lsof -ti tcp:"$PORT" &>/dev/null; then break; fi
        sleep 0.5
    done

    URL="http://localhost:$PORT"
    if command -v google-chrome &>/dev/null; then
        google-chrome "$URL" &
    elif command -v chromium-browser &>/dev/null; then
        chromium-browser "$URL" &
    elif command -v chromium &>/dev/null; then
        chromium "$URL" &
    else
        xdg-open "$URL" &
    fi
) &
BROWSER_PID=$!

# ── Start llama-server (foreground — Ctrl+C stops everything) ─────────────────
echo ""
echo -e "${CYAN}Starting llama-server...  (Ctrl+C to stop all)${RESET}"
echo ""

"$SERVER_BIN" \
    --model      "$SELECTED_PATH" \
    --host       0.0.0.0 \
    --port       "$PORT" \
    -ngl         0 \
    --ctx-size   8192 \
    --threads    "$(nproc)" \
    --webui-mcp-proxy
