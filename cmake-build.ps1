# Build llama.cpp (CPU-only, Release) for Windows
# Finds cmake from PATH or VS2022 install, then configures and builds.

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

# --- Find cmake ---
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmake) {
    $cmakePath = $cmake.Source
} else {
    # Try winget-installed location
    $candidates = @(
        "$env:ProgramFiles\CMake\bin\cmake.exe",
        "$env:LOCALAPPDATA\Programs\CMake\bin\cmake.exe"
    )
    $cmakePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $cmakePath) {
        Write-Error "cmake not found. Install via: winget install Kitware.CMake"
        exit 1
    }
}

Write-Host "Using cmake: $cmakePath" -ForegroundColor Cyan
& $cmakePath --version

# --- Configure (CPU-only, no GPU flags) ---
Write-Host "`n=== Configuring build ===" -ForegroundColor Cyan
& $cmakePath -B "$ProjectRoot\build" `
    -G "Visual Studio 17 2022" -A x64 `
    -DGGML_CUDA=OFF `
    -DGGML_METAL=OFF `
    -DGGML_VULKAN=OFF `
    -DCMAKE_BUILD_TYPE=Release

if ($LASTEXITCODE -ne 0) { Write-Error "cmake configure failed"; exit 1 }

# --- Build ---
Write-Host "`n=== Building (this will take 5-15 minutes) ===" -ForegroundColor Cyan
$jobs = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
Write-Host "Using $jobs parallel jobs"
& $cmakePath --build "$ProjectRoot\build" --config Release -j $jobs

if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }
Write-Host "`n=== Build complete! ===" -ForegroundColor Green
Write-Host "Binaries at: $ProjectRoot\build\bin\Release\"
