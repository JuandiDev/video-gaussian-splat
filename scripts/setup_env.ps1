# Creates conda env gaussian_splatting from environment_windows.yml
# Prerequisites: Miniconda/Anaconda, Visual Studio 2019/2022 (C++), CUDA Toolkit 11.8 or 12.x

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

function Get-CondaExe {
    if (Get-Command conda -ErrorAction SilentlyContinue) {
        return (Get-Command conda).Source
    }
    $guesses = @(
        "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\Miniconda3\Scripts\conda.exe",
        "$env:LOCALAPPDATA\miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\anaconda3\Scripts\conda.exe",
        "$env:LOCALAPPDATA\anaconda3\Scripts\conda.exe"
    )
    foreach ($g in $guesses) {
        if (Test-Path $g) { return $g }
    }
    return $null
}

$conda = Get-CondaExe
if (-not $conda) {
    throw "conda not found. Run INSTALLAR.bat (Miniconda) and reopen the terminal."
}

$env:DISTUTILS_USE_SDK = "1"
Write-Host "Using conda: $conda"
Write-Host "Creating conda env from environment_windows.yml (this takes a while)..."
& $conda env create --file environment_windows.yml
if ($LASTEXITCODE -ne 0) {
    Write-Host "env create failed; trying update of existing env..."
    & $conda env update --file environment_windows.yml --prune
}

Write-Host @"

Activate with:
  conda activate gaussian_splatting

Daily use: double-click EMPEZAR.bat
"@
