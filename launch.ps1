# Bonsai Model Launcher - Windows
# Usage:
#   .\launch.ps1          - interactive model menu
#   .\launch.ps1 -Model 1 - Bonsai 1.7B directly
#   .\launch.ps1 -Model 2 - Bonsai 8B directly

param([int]$Model = 0)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$ServerExe   = "$ProjectRoot\build\bin\Release\llama-server.exe"
$WebuiConfig = "$ProjectRoot\webui-config.json"
$ServerPy    = "$ProjectRoot\mcp-duckduckgo\server.py"
$Port        = 8080
$McpPort     = 8808

$ModelNames = @(
    "Bonsai 1.7B Q1_0 (fast, ~250 MB)",
    "Bonsai 8B   Q1_0 (smarter, ~1.5 GB)"
)
$ModelPaths = @(
    "C:\Local\Local-LLMs\1-Bit-Bonsai\Bonsai-1.7B-Q1_0.gguf",
    "C:\Local\Local-LLMs\1-Bit-Bonsai\Bonsai-8B-Q1_0.gguf"
)

# --- Preflight ---
if (-not (Test-Path $ServerExe)) {
    Write-Error "llama-server.exe not found. Run .\cmake-build.ps1 first."
    exit 1
}

# --- Model selection ---
if ($Model -eq 0) {
    Write-Host ""
    Write-Host "=== Bonsai Model Launcher ===" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $ModelNames.Count; $i++) {
        $found = Test-Path $ModelPaths[$i]
        $status = if ($found) { "[OK]" } else { "[NOT FOUND]" }
        Write-Host "  $($i+1). $($ModelNames[$i])  $status"
    }
    Write-Host ""
    $choice = Read-Host "Select model (1-$($ModelNames.Count))"
    $Model = [int]$choice
}

$idx = $Model - 1
$SelectedName = $ModelNames[$idx]
$SelectedPath = $ModelPaths[$idx]

if (-not (Test-Path $SelectedPath)) {
    Write-Error "Model not found: $SelectedPath"
    exit 1
}

Write-Host ""
Write-Host "Model  : $SelectedName" -ForegroundColor Green
Write-Host "File   : $SelectedPath"
Write-Host "Web UI : http://localhost:$Port"
Write-Host ""

# --- Kill anything already on our ports ---
foreach ($p in @($McpPort, $Port)) {
    Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
}

# --- Start MCP server as a background job ---
Write-Host "Starting DuckDuckGo MCP server (port $McpPort)..." -ForegroundColor Yellow
$env:PYTHONUNBUFFERED = "1"
$mcpJob = Start-Job -ScriptBlock {
    param($root, $py, $port)
    Set-Location $root
    $env:PYTHONUNBUFFERED = "1"
    npx supergateway --port $port --cors --stdio "python -u `"$py`""
} -ArgumentList $ProjectRoot, $ServerPy, $McpPort

# Wait up to 15s for port 8808 to open
$deadline = [DateTime]::Now.AddSeconds(15)
while ([DateTime]::Now -lt $deadline) {
    if (Get-NetTCPConnection -LocalPort $McpPort -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Milliseconds 500
}

if (-not (Get-NetTCPConnection -LocalPort $McpPort -ErrorAction SilentlyContinue)) {
    Write-Host "MCP server output:" -ForegroundColor Red
    Receive-Job $mcpJob
    Write-Error "MCP server failed to start on port $McpPort"
    exit 1
}
Write-Host "MCP server ready at http://localhost:$McpPort/sse" -ForegroundColor Green

# --- Open browser after server warms up ---
Start-Job -ScriptBlock { Start-Sleep 6; Start-Process "http://localhost:8080" } | Out-Null

# --- Start llama-server (foreground) ---
Write-Host ""
Write-Host "Starting llama-server... (Ctrl+C to stop)" -ForegroundColor Cyan
Write-Host ""

try {
    & $ServerExe `
        -m $SelectedPath `
        --host 0.0.0.0 `
        --port $Port `
        -ngl 0 `
        --ctx-size 8192 `
        --threads ([Environment]::ProcessorCount) `
        --webui-mcp-proxy `
        --webui-config-file $WebuiConfig
} finally {
    Write-Host ""
    Write-Host "Stopping MCP server..." -ForegroundColor Yellow
    Stop-Job $mcpJob -ErrorAction SilentlyContinue
    Remove-Job $mcpJob -ErrorAction SilentlyContinue
}
