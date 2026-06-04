#!/usr/bin/env bash
# Start DuckDuckGo MCP server (HTTP/SSE bridge) — no API key required
# Listening at: http://localhost:8808/sse

set -e
MCP_PORT=8808
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PY="$SCRIPT_DIR/mcp-duckduckgo/server.py"

if [ ! -f "$SERVER_PY" ]; then
    echo "ERROR: MCP server not found at $SERVER_PY. Run setup-mcp-search.sh first."
    exit 1
fi

echo "=== DuckDuckGo MCP Server ==="
echo "Endpoint: http://localhost:$MCP_PORT/sse"
echo "Press Ctrl+C to stop."
echo ""

PYTHONUNBUFFERED=1 npx supergateway --port "$MCP_PORT" --cors --stdio "python3 -u '$SERVER_PY'"
