# Repair numpy + CUDA rasterizer. Use vcvars and --no-build-isolation (needs torch in env).
$ErrorActionPreference = "Continue"

function Get-EnvPython {
    $guesses = @(
        "$env:USERPROFILE\miniconda3\envs\gaussian_splatting\python.exe",
        "$env:LOCALAPPDATA\miniconda3\envs\gaussian_splatting\python.exe",
        "$env:USERPROFILE\Miniconda3\envs\gaussian_splatting\python.exe"
    )
    foreach ($g in $guesses) {
        if (Test-Path $g) { return $g }
    }
    return $null
}

function Get-VcVars {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $null }
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) {
        $vs = & $vswhere -latest -products * -property installationPath
    }
    if (-not $vs) { return $null }
    $vcvars = Join-Path $vs.Trim() "VC\Auxiliary\Build\vcvars64.bat"
    if (Test-Path $vcvars) { return $vcvars }
    return $null
}

function Get-CudaHome {
    if ($env:CUDA_PATH -and (Test-Path (Join-Path $env:CUDA_PATH "bin\nvcc.exe"))) {
        return $env:CUDA_PATH
    }
    $root = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    if (-not (Test-Path $root)) { return $null }
    $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($d in $dirs) {
        if (Test-Path (Join-Path $d.FullName "bin\nvcc.exe")) { return $d.FullName }
    }
    return $null
}

function Install-CudaExt([string]$py, [string]$folder, [string]$vcvars, [string]$cudaHome) {
    $bat = Join-Path $env:TEMP "install_gs_ext.bat"
    $lines = @("@echo off")
    if ($vcvars) { $lines += "call `"$vcvars`"" }
    $lines += "set DISTUTILS_USE_SDK=1"
    $lines += "set TORCH_CUDA_ARCH_LIST=7.5"
    if ($cudaHome) {
        $lines += "set CUDA_HOME=$cudaHome"
        $lines += "set CUDA_PATH=$cudaHome"
        $lines += "set PATH=$cudaHome\bin;%PATH%"
    }
    $lines += "`"$py`" -m pip install `"$folder`" --no-build-isolation --force-reinstall -v"
    Set-Content -Path $bat -Value $lines -Encoding ASCII
    Write-Host "Running $bat"
    Get-Content $bat | ForEach-Object { Write-Host $_ }
    cmd /c "`"$bat`""
    return $LASTEXITCODE
}

$py = Get-EnvPython
if (-not $py) { throw "No encuentro gaussian_splatting\python.exe" }
Write-Host "Python: $py"

Write-Host "=== NumPy 1.x ==="
& $py -m pip install "numpy>=1.24,<2"

Write-Host "=== Test torch ==="
& $py -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) {
    throw "import torch fallo. Corre ARREGLAR_TORCH otra vez despues de reinstalar PyTorch."
}

$vcvars = Get-VcVars
$cudaHome = Get-CudaHome
Write-Host "vcvars: $vcvars"
Write-Host "CUDA:   $cudaHome"
if (-not $vcvars) {
    Write-Host "No hay Visual Studio C++. Instalo Build Tools (tarda)..."
    $override = "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-package-agreements --accept-source-agreements --override $override
    $vcvars = Get-VcVars
}
if (-not $vcvars) {
    throw "Sigue sin vcvars64.bat. Instala Visual Studio 2022 Build Tools con 'Desktop development with C++' y reintenta."
}
if (-not $cudaHome) {
    throw "No encuentro nvcc. Instala CUDA Toolkit 11.8 y reintenta."
}

$repo = Split-Path -Parent $PSScriptRoot
$rast = Join-Path $repo "submodules\diff-gaussian-rasterization"
$knn = Join-Path $repo "submodules\simple-knn"
if (-not (Test-Path (Join-Path $rast "setup.py"))) {
    throw "Falta el submodulo. En Git Bash: git submodule update --init --recursive"
}

Write-Host "=== setuptools ==="
& $py -m pip install -U setuptools wheel ninja

Write-Host "=== Rasterizer (varios minutos) ==="
$code = Install-CudaExt $py $rast $vcvars $cudaHome
if ($code -ne 0) { throw "Fallo diff-gaussian-rasterization (codigo $code). Copia el log de pip." }

Write-Host "=== simple-knn ==="
$code = Install-CudaExt $py $knn $vcvars $cudaHome
if ($code -ne 0) { throw "Fallo simple-knn (codigo $code)." }

Write-Host "=== Test final ==="
& $py -c "import torch; import diff_gaussian_rasterization; import numpy; print('LISTO numpy', numpy.__version__, 'cuda', torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) { throw "El rasterizer no importa." }

Write-Host ""
Write-Host "LISTO. Ahora EMPEZAR.bat"
