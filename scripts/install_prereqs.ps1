# One-time Windows prerequisites: Git, Miniconda, VS C++ Build Tools, CUDA 11.8
$ErrorActionPreference = "Stop"

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Test-WingetId([string]$id) {
    $out = winget list --id $id -e 2>$null | Out-String
    return ($out -match [regex]::Escape($id))
}

function Install-WingetId([string]$id, [string[]]$extra = @()) {
    if (Test-WingetId $id) {
        Write-Host "Already installed: $id"
        return
    }
    Write-Host "Installing $id ..."
    $args = @("install", "--id", $id, "-e", "--accept-package-agreements", "--accept-source-agreements") + $extra
    & winget @args
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        # -1978335189 = already installed (some winget versions)
        throw "winget failed for $id (exit $LASTEXITCODE)"
    }
    Refresh-Path
}

Write-Host "=== Git ==="
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "git already on PATH"
} else {
    Install-WingetId "Git.Git"
}

Write-Host "`n=== Miniconda ==="
if (Get-Command conda -ErrorAction SilentlyContinue) {
    Write-Host "conda already on PATH"
} else {
    Install-WingetId "Anaconda.Miniconda3"
    Refresh-Path
    $condaBat = @(
        "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
        "$env:LOCALAPPDATA\miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\Miniconda3\Scripts\conda.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($condaBat) {
        & $condaBat init cmd.exe powershell | Out-Null
    }
}

Write-Host "`n=== Visual Studio Build Tools (C++) ==="
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVs = $false
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vsPath) { $hasVs = $true }
}
if ($hasVs) {
    Write-Host "C++ Build Tools already installed"
} else {
    Write-Host "Installing VS 2022 Build Tools with C++ (this takes a while)..."
    $override = "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-package-agreements --accept-source-agreements --override $override
    Refresh-Path
}

Write-Host "`n=== CUDA Toolkit 11.8 ==="
if (Get-Command nvcc -ErrorAction SilentlyContinue) {
    Write-Host "nvcc already on PATH"
} else {
    $nvccGuess = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.8\bin\nvcc.exe" -ErrorAction SilentlyContinue
    if ($nvccGuess) {
        Write-Host "CUDA 11.8 found, not on PATH yet (OK)"
    } else {
        Write-Host "Installing CUDA 11.8 ..."
        winget install --id Nvidia.CUDA -e --version 11.8 --accept-package-agreements --accept-source-agreements
        Refresh-Path
    }
}

Write-Host "`n=== Visual C++ Redistributable ==="
Install-WingetId "Microsoft.VCRedist.2015+.x64"

Write-Host "`nPrerequisites step finished. If VS or CUDA were just installed, reboot before training if setup_env fails."
