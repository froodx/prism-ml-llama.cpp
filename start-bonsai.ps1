# Start llama-server with the Bonsai 1.7B model and open the Web UI
# CPU-only (no GPU layers). Chat UI at http://localhost:8080
# MCP proxy enabled - configure MCP servers in Settings -> MCP

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$ServerExe   = "$ProjectRoot\build\bin\Release\llama-server.exe"
$ModelPath   = "C:\Local\Local-LLMs\1-Bit-Bonsai\Bonsai-1.7B-Q1_0.gguf"
$Host_       = "0.0.0.0"
$Port        = 8080

if (-not (Test-Path $ServerExe)) {
    Write-Error "llama-server.exe not found. Run build.ps1 first."
    exit 1
}
if (-not (Test-Path $ModelPath)) {
    Write-Error "Model not found at: $ModelPath"
    exit 1
}

Write-Host "=== Starting Bonsai 1.7B ===" -ForegroundColor Cyan
Write-Host "Model  : $ModelPath"
Write-Host "Server : http://localhost:$Port"
Write-Host ""
Write-Host "Web UI will open automatically. Press Ctrl+C to stop the server."
Write-Host ""

# Open browser after a short delay (server needs a moment to start)
Start-Job -ScriptBlock {
    Start-Sleep -Seconds 3
    Start-Process "http://localhost:8080"
} | Out-Null

# Start server (blocks here — output streams to this terminal)
& $ServerExe `
    -m $ModelPath `
    --host $Host_ `
    --port $Port `
    -ngl 0 `
    --ctx-size 8192 `
    --threads ([Environment]::ProcessorCount) `
    --webui-mcp-proxy
