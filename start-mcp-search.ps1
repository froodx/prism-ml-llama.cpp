# Start DuckDuckGo MCP server (HTTP/SSE bridge) — no API key required
# Keep this running while using the llama.cpp Web UI
# Listening at: http://localhost:8808/sse

$McpPort  = 8808
$ServerPy = "$PSScriptRoot\mcp-duckduckgo\server.py"

if (-not (Test-Path $ServerPy)) {
    Write-Error "MCP server not found at $ServerPy. Run setup-mcp-search.ps1 first."
    exit 1
}

Write-Host "=== DuckDuckGo MCP Server ===" -ForegroundColor Cyan
Write-Host "Endpoint : http://localhost:$McpPort/sse" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop.`n"

$env:PYTHONUNBUFFERED = "1"
npx supergateway --port $McpPort --stdio "python -u `"$ServerPy`""
