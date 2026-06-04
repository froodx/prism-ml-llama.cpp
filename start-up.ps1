# start-up.ps1 - All-in-one launcher for prism-ml-llama.cpp (Windows)
# Starts the DuckDuckGo MCP server, presents a model picker from the GGUF
# folder, launches llama-server, and opens Chrome once everything is ready.
#
# Usage:
#   .\start-up.ps1                - interactive model menu
#   .\start-up.ps1 -ModelIndex 1  - pick model by menu number directly

param(
    [int]$ModelIndex = 0
)

$ErrorActionPreference = "Stop"

# --- Paths ---
$ProjectRoot = $PSScriptRoot
$ServerExe   = "$ProjectRoot\build\bin\Release\llama-server.exe"
$ServerPy    = "$ProjectRoot\mcp-duckduckgo\server.py"
$ModelDir    = "C:\Local\Local-LLMs\1-Bit-Bonsai"
$Port        = 8080
$McpPort     = 8808

# Resolve the conda/anaconda Python explicitly so background jobs use the right env
$PythonExe = "c:\ProgramData\anaconda3\python.exe"
if (-not (Test-Path $PythonExe)) {
    $PythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
}

$pf86        = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
$ChromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$pf86\Google\Chrome\Application\chrome.exe",
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)

# --- Kill any existing processes on our ports (always, before anything else) ---
Write-Host "Clearing ports $Port and $McpPort..." -ForegroundColor DarkGray
foreach ($p in @($McpPort, $Port)) {
    $conns = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Milliseconds 800

# --- Preflight checks ---
if (-not (Test-Path $ServerExe)) {
    Write-Host "ERROR: llama-server.exe not found. Run .\cmake-build.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $ServerPy)) {
    Write-Host "ERROR: MCP server not found. Run .\setup-mcp-search.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $ModelDir)) {
    Write-Host "ERROR: Model directory not found: $ModelDir" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $PythonExe)) {
    Write-Host "ERROR: Python not found at: $PythonExe" -ForegroundColor Red
    exit 1
}

# --- Discover models ---
$ModelFiles = Get-ChildItem -Path $ModelDir -Filter "*.gguf" | Sort-Object Name
if ($ModelFiles.Count -eq 0) {
    Write-Host "ERROR: No .gguf files found in $ModelDir" -ForegroundColor Red
    exit 1
}

# --- Model selection ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  prism-ml / llama.cpp  -  Model Picker    " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

for ($i = 0; $i -lt $ModelFiles.Count; $i++) {
    $f    = $ModelFiles[$i]
    $size = "{0:N0} MB" -f ($f.Length / 1MB)
    Write-Host ("  {0,2}. {1,-45} {2}" -f ($i + 1), $f.Name, $size)
}
Write-Host ""

if ($ModelIndex -eq 0) {
    $raw = Read-Host "Select model (1-$($ModelFiles.Count))"
    if ($raw -notmatch '^\d+$') {
        Write-Host "ERROR: Invalid input." -ForegroundColor Red; exit 1
    }
    $ModelIndex = [int]$raw
}

if ($ModelIndex -lt 1 -or $ModelIndex -gt $ModelFiles.Count) {
    Write-Host "ERROR: Selection out of range." -ForegroundColor Red; exit 1
}

$SelectedFile = $ModelFiles[$ModelIndex - 1]
$SelectedPath = $SelectedFile.FullName

Write-Host ""
Write-Host "  Model  : $($SelectedFile.Name)" -ForegroundColor Green
Write-Host "  Web UI : http://localhost:$Port"
Write-Host "  MCP    : http://localhost:$McpPort/sse"
Write-Host "  Python : $PythonExe"
Write-Host ""

# --- Start MCP server (StreamableHTTP at /mcp, proxied via llama-server /cors-proxy) ---
Write-Host "Starting DuckDuckGo MCP server on port $McpPort..." -ForegroundColor Yellow

$mcpJob = Start-Job -ScriptBlock {
    param($pyExe, $py, $port)
    $env:PYTHONUNBUFFERED = "1"
    & $pyExe -u $py --streamable-http --port $port
} -ArgumentList $PythonExe, $ServerPy, $McpPort

# Wait up to 20 s for MCP port
$deadline = [DateTime]::Now.AddSeconds(20)
$mcpReady = $false
while ([DateTime]::Now -lt $deadline) {
    if (Get-NetTCPConnection -LocalPort $McpPort -ErrorAction SilentlyContinue) {
        $mcpReady = $true; break
    }
    Start-Sleep -Milliseconds 400
}

if (-not $mcpReady) {
    Write-Host ""
    Write-Host "MCP server failed. Output:" -ForegroundColor Red
    Receive-Job $mcpJob -ErrorAction SilentlyContinue
    Stop-Job  $mcpJob -ErrorAction SilentlyContinue
    Remove-Job $mcpJob -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "MCP server ready." -ForegroundColor Green

# --- Open Chrome once llama-server port is up ---
$chromePath = $ChromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

Start-Job -ScriptBlock {
    param($port, $chrome)
    $deadline = [DateTime]::Now.AddSeconds(60)
    while ([DateTime]::Now -lt $deadline) {
        try {
            $tc = New-Object Net.Sockets.TcpClient
            $ar = $tc.BeginConnect("127.0.0.1", $port, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(300, $false)) { $tc.Close(); break }
            $tc.Close()
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if ($chrome) { & $chrome "http://localhost:$port" }
    else { Start-Process "http://localhost:$port" }
} -ArgumentList $Port, $chromePath | Out-Null

# --- Start llama-server in foreground (Ctrl+C stops everything) ---
Write-Host ""
Write-Host "Starting llama-server... (Ctrl+C to stop all)" -ForegroundColor Cyan
Write-Host ""

try {
    & $ServerExe `
        --model             $SelectedPath `
        --host              0.0.0.0 `
        --port              $Port `
        -ngl                0 `
        --ctx-size          0 `
        --threads           ([Environment]::ProcessorCount) `
        --webui-mcp-proxy `
        --webui-config-file "$ProjectRoot\webui-config.json"
} finally {
    Write-Host ""
    Write-Host "Shutting down MCP server..." -ForegroundColor Yellow
    Stop-Job  $mcpJob -ErrorAction SilentlyContinue
    Remove-Job $mcpJob -Force -ErrorAction SilentlyContinue
    Write-Host "Done." -ForegroundColor Green
}
