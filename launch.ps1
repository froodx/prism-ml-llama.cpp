# Bonsai Model Launcher — Windows
# Starts DuckDuckGo MCP server, prompts for model selection, opens Web UI
#
# Usage:
#   .\launch.ps1          — interactive model menu
#   .\launch.ps1 -Model 1 — Bonsai 1.7B directly
#   .\launch.ps1 -Model 2 — Bonsai 8B directly

param([int]$Model = 0)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$ServerExe   = "$ProjectRoot\build\bin\Release\llama-server.exe"
$WebuiConfig = "$ProjectRoot\webui-config.json"
$McpScript   = "$ProjectRoot\start-mcp-search.ps1"
$Port        = 8080

# Model definitions — update paths if models live elsewhere
$Models = @(
    [PSCustomObject]@{
        Name = "Bonsai 1.7B  Q1_0  (fast, ~250 MB)"
        Path = "C:\Local\Local-LLMs\1-Bit-Bonsai\Bonsai-1.7B-Q1_0.gguf"
    },
    [PSCustomObject]@{
        Name = "Bonsai 8B    Q1_0  (smarter, ~1.5 GB)"
        Path = "C:\Local\Local-LLMs\1-Bit-Bonsai\Bonsai-8B-Q1_0.gguf"
    }
)

# --- Preflight checks ---
if (-not (Test-Path $ServerExe)) {
    Write-Error "llama-server.exe not found. Run .\cmake-build.ps1 first."
    exit 1
}

# --- Model selection ---
if ($Model -eq 0) {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║     Bonsai Model Launcher        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $Models.Count; $i++) {
        $avail = if (Test-Path $Models[$i].Path) { "✓" } else { "✗ not found" }
        Write-Host "  $($i+1).  $($Models[$i].Name)  [$avail]"
    }
    Write-Host ""
    $choice = Read-Host "  Select model (1-$($Models.Count))"
    $Model = [int]$choice
}

$Selected = $Models[$Model - 1]
if (-not (Test-Path $Selected.Path)) {
    Write-Error "Model file not found: $($Selected.Path)"
    exit 1
}

Write-Host ""
Write-Host "  Model  : $($Selected.Name)" -ForegroundColor Green
Write-Host "  File   : $($Selected.Path)"
Write-Host "  Web UI : http://localhost:$Port"
Write-Host ""

# --- Start MCP server in a separate window ---
Write-Host "Starting DuckDuckGo MCP server..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-NoProfile", "-Command", "& '$McpScript'" -WindowStyle Normal
Start-Sleep -Seconds 3

# --- Open browser after server is ready ---
Start-Job -ScriptBlock { Start-Sleep 5; Start-Process "http://localhost:8080" } | Out-Null

# --- Start llama-server (foreground — Ctrl+C to stop) ---
Write-Host "Starting llama-server... (Ctrl+C to stop)`n" -ForegroundColor Cyan
& $ServerExe `
    -m $Selected.Path `
    --host 0.0.0.0 `
    --port $Port `
    -ngl 0 `
    --ctx-size 8192 `
    --threads ([Environment]::ProcessorCount) `
    --webui-mcp-proxy `
    --webui-config-file $WebuiConfig
