#!/usr/bin/env bash
# Setup DuckDuckGo Search MCP for llama.cpp Web UI — Linux / Ubuntu
# Completely FREE, no API key required.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Setting up DuckDuckGo Search MCP ==="
echo ""

# Python deps
echo "Installing Python packages..."
pip3 install --quiet -r "$SCRIPT_DIR/mcp-duckduckgo/requirements.txt"
echo "  ✓ mcp, duckduckgo-search"

# Node dep (stdio -> HTTP/SSE bridge)
if ! command -v node &>/dev/null; then
    echo ""
    echo "Node.js not found. Installing via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

echo "Installing supergateway..."
npm install -g supergateway --silent
echo "  ✓ supergateway"

chmod +x "$SCRIPT_DIR/launch.sh"
chmod +x "$SCRIPT_DIR/cmake-build.sh"
chmod +x "$SCRIPT_DIR/start-mcp-search.sh"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "To use:"
echo "  ./launch.sh     — start everything with model picker"
echo ""
echo "Or manually:"
echo "  Terminal 1:  ./start-mcp-search.sh"
echo "  Terminal 2:  ./launch.sh"
