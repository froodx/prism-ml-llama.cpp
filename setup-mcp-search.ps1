# Setup DuckDuckGo Search MCP for llama.cpp Web UI
# Completely FREE - no API key required.
#
# Usage: .\setup-mcp-search.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$McpPort     = 8808
$ServerPy    = "$ProjectRoot\mcp-duckduckgo\server.py"

Write-Host "=== Setting up DuckDuckGo Search MCP ===" -ForegroundColor Cyan
Write-Host "Free, no API key required.`n"

# --- Python deps ---
Write-Host "Installing Python packages..." -ForegroundColor Yellow
pip install --quiet mcp duckduckgo-search
Write-Host "Python packages ready." -ForegroundColor Green

# --- Node dep (supergateway = stdio -> HTTP/SSE bridge) ---
Write-Host "Installing supergateway (stdio -> HTTP bridge)..." -ForegroundColor Yellow
npm install -g supergateway --silent
Write-Host "supergateway ready." -ForegroundColor Green

# --- Write the start script ---
$StartScript = @"
# Start DuckDuckGo MCP server (HTTP/SSE on port $McpPort)
# Keep this terminal open while using the llama.cpp Web UI.
#
# After starting, add this URL in the Web UI:
#   Settings (gear icon) -> MCP -> Add New Server
#   URL: http://localhost:$McpPort/sse

Write-Host '=== DuckDuckGo MCP Server ===' -ForegroundColor Cyan
Write-Host "Listening at: http://localhost:$McpPort/sse" -ForegroundColor Green
Write-Host 'Add that URL in the Web UI -> Settings -> MCP -> Add New Server' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Press Ctrl+C to stop.'
npx supergateway --port $McpPort --stdio "python `"$ServerPy`""
"@

Set-Content -Path "$ProjectRoot\start-mcp-search.ps1" -Value $StartScript

Write-Host "`n=== Setup complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "To use:" -ForegroundColor Cyan
Write-Host "  1. Open a terminal and run:  .\start-mcp-search.ps1"
Write-Host "  2. Open another terminal and run:  .\start-bonsai.ps1"
Write-Host "  3. In the Web UI: click the gear (Settings) -> MCP -> Add New Server"
Write-Host "     Enter URL:  http://localhost:$McpPort/sse"
Write-Host "  4. Ask Bonsai to search the web!"
Write-Host ""
