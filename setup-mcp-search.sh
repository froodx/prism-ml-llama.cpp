#!/usr/bin/env bash
# setup-mcp-search.sh — Install Python deps for the DuckDuckGo MCP server
# No API key required. No Node.js / supergateway needed.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Setting up DuckDuckGo MCP server ==="
echo ""

echo "Installing Python packages (mcp, ddgs, uvicorn)..."
pip3 install --quiet --break-system-packages -r "$SCRIPT_DIR/mcp-duckduckgo/requirements.txt"
echo "  Done."

chmod +x "$SCRIPT_DIR/start-up.sh"
chmod +x "$SCRIPT_DIR/cmake-build.sh"
chmod +x "$SCRIPT_DIR/cmake-build-cuda.sh"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Build llama-server with CUDA:   ./cmake-build-cuda.sh"
echo "  2. Launch everything:              ./start-up.sh"
