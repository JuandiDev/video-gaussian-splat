# Requires: Windows 10+, PowerShell 5+, winget
# Installs ffmpeg (winget) and COLMAP 4.2 into tools/colmap

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $RepoRoot "run_splat.py"))) {
    throw "Run this script from the clone; expected run_splat.py next to the scripts folder."
}

Write-Host "Repo: $RepoRoot"

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

Write-Host "`n=== FFmpeg ==="
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Write-Host "ffmpeg already on PATH"
} else {
    winget install --id Gyan.FFmpeg --accept-package-agreements --accept-source-agreements
    Refresh-Path
}
Refresh-Path
ffmpeg -version | Select-Object -First 1

Write-Host "`n=== COLMAP 4.2.0 ==="
$tools = Join-Path $RepoRoot "tools"
$colmapDir = Join-Path $tools "colmap"
$bat = Join-Path $colmapDir "COLMAP.bat"
if (Test-Path $bat) {
    Write-Host "COLMAP already at $bat"
} else {
    New-Item -ItemType Directory -Force -Path $tools | Out-Null
    $zip = Join-Path $tools "colmap-x64-windows-cuda.zip"
    $url = "https://github.com/colmap/colmap/releases/download/4.2.0/colmap-x64-windows-cuda.zip"
    Write-Host "Downloading $url"
    curl.exe -L --fail --retry 3 -o $zip $url
    if (Test-Path $colmapDir) { Remove-Item -Recurse -Force $colmapDir }
    Expand-Archive -Path $zip -DestinationPath $colmapDir -Force
    Remove-Item $zip -Force
}
if (-not (Test-Path $bat)) {
    throw "COLMAP.bat not found after extract: $colmapDir"
}
& $bat -h | Select-Object -First 5
Write-Host "`nInstall OK."
Write-Host "COLMAP: $bat"
Write-Host "Next: scripts/setup_env.ps1  then  python run_splat.py --video path\to\video.mp4"
