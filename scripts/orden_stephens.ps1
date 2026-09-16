# Orden del video de Jonathan Stephens: VS C++ -> CUDA Toolkit -> recien ahi el env conda.
# No desinstala Git, Miniconda, Visual Studio ni FFmpeg.
# El rasterizer se compila DESPUES, con vcvars + nvcc (no durante conda env create).

$ErrorActionPreference = "Stop"

function Get-CondaExe {
    $guesses = @(
        "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\Miniconda3\Scripts\conda.exe",
        "$env:LOCALAPPDATA\miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\anaconda3\Scripts\conda.exe",
        "$env:LOCALAPPDATA\anaconda3\Scripts\conda.exe",
        "C:\ProgramData\miniconda3\Scripts\conda.exe",
        "C:\ProgramData\anaconda3\Scripts\conda.exe"
    )
    foreach ($g in $guesses) { if (Test-Path $g) { return $g } }
    if (Get-Command conda -ErrorAction SilentlyContinue) { return (Get-Command conda).Source }
    return $null
}

function Get-VcVars {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $null }
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { $vs = & $vswhere -latest -products * -property installationPath }
    if (-not $vs) { return $null }
    $vcvars = Join-Path $vs.Trim() "VC\Auxiliary\Build\vcvars64.bat"
    if (Test-Path $vcvars) { return $vcvars }
    return $null
}

function Get-CudaHome {
    $root = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    foreach ($ver in @("v11.8", "v11.7", "v11.6", "v12.1", "v12.4")) {
        $nvcc = Join-Path $root "$ver\bin\nvcc.exe"
        if (Test-Path $nvcc) { return (Join-Path $root $ver) }
    }
    if (Test-Path $root) {
        $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        foreach ($d in $dirs) {
            if (Test-Path (Join-Path $d.FullName "bin\nvcc.exe")) { return $d.FullName }
        }
    }
    if (Get-Command nvcc -ErrorAction SilentlyContinue) {
        return (Split-Path (Split-Path (Get-Command nvcc).Source))
    }
    return $null
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "============================================"
Write-Host " Orden del video de Stephens"
Write-Host " 1 Git  2 Conda  3 VS C++  4 CUDA Toolkit"
Write-Host " 5 Recien ahi borrar env y crearlo de nuevo"
Write-Host "============================================"
Write-Host ""
Write-Host "SE QUEDA: Git, Miniconda, Visual Studio C++, FFmpeg, COLMAP, VS Code"
Write-Host "SE TIRA: solo el entorno conda gaussian_splatting (se armo sin nvcc)"
Write-Host ""

$gitOk = [bool](Get-Command git -ErrorAction SilentlyContinue)
$conda = Get-CondaExe
$vcvars = Get-VcVars
$cudaHome = Get-CudaHome

Write-Host ("Git:       " + $(if ($gitOk) { "OK" } else { "FALTA" }))
Write-Host ("Conda:     " + $(if ($conda) { $conda } else { "FALTA" }))
Write-Host ("VS C++:    " + $(if ($vcvars) { $vcvars } else { "FALTA" }))
Write-Host ("CUDA nvcc: " + $(if ($cudaHome) { $cudaHome } else { "FALTA" }))
Write-Host ""

if (-not $gitOk -or -not $conda -or -not $vcvars) {
    throw "Falta Git, Conda o Visual Studio C++. Eso se queda instalado; no lo borres. Completa el INSTALLAR.bat o el video (min 3:22) y reintenta."
}

if (-not $cudaHome) {
    Write-Host "=== Instalando CUDA Toolkit 11.8 (como el video, DESPUES de VS) ==="
    $ErrorActionPreference = "Continue"
    winget install --id Nvidia.CUDA -e --version 11.8 --accept-package-agreements --accept-source-agreements
    $ErrorActionPreference = "Stop"
    $cudaHome = Get-CudaHome
    if (-not $cudaHome) {
        Write-Host ""
        Write-Host "CUDA se instalo o pidio reinicio. REINICIA Windows y volve a doble clic COMO_EL_VIDEO.bat"
        Write-Host "Manual: https://developer.nvidia.com/cuda-11-8-0-download-archive"
        throw "Reinicia y reintenta para que aparezca nvcc."
    }
}

Write-Host "CUDA OK: $cudaHome"

Write-Host "=== Borrar env viejo gaussian_splatting ==="
$ErrorActionPreference = "Continue"
& $conda env remove -n gaussian_splatting -y
$ErrorActionPreference = "Stop"

$env:DISTUTILS_USE_SDK = "1"
$env:CUDA_HOME = $cudaHome
$env:CUDA_PATH = $cudaHome
$env:TORCH_CUDA_ARCH_LIST = "7.5"

Write-Host "=== Crear env BASE (sin rasterizer; eso va DESPUES con nvcc) ==="
& $conda env create --file (Join-Path $RepoRoot "environment_base.yml")
if ($LASTEXITCODE -ne 0) {
    Write-Host "create fallo; intento update..."
    & $conda env update --file (Join-Path $RepoRoot "environment_base.yml") --prune
    if ($LASTEXITCODE -ne 0) { throw "No pude crear el entorno conda." }
}

$py = (& $conda run -n gaussian_splatting python -c "import sys; print(sys.executable)").Trim()
if (-not $py -or -not (Test-Path $py)) { throw "No aparecio python del env gaussian_splatting" }
Write-Host "Python: $py"

$rast = Join-Path $RepoRoot "submodules\diff-gaussian-rasterization"
$knn = Join-Path $RepoRoot "submodules\simple-knn"
if (-not (Test-Path $rast)) {
    throw "Faltan submodulos. En la carpeta del repo: git submodule update --init --recursive"
}

Write-Host "=== Compilar rasterizer con vcvars + nvcc (el paso magico del video) ==="
$bat = Join-Path $env:TEMP "gs_build_ext.bat"
$lines = @(
    "@echo off",
    "call `"$vcvars`"",
    "set DISTUTILS_USE_SDK=1",
    "set TORCH_CUDA_ARCH_LIST=7.5",
    "set CUDA_HOME=$cudaHome",
    "set CUDA_PATH=$cudaHome",
    "set PATH=$cudaHome\bin;%PATH%",
    "`"$py`" -m pip install `"numpy>=1.24,<2`"",
    "`"$py`" -m pip install `"$rast`" --no-build-isolation --force-reinstall",
    "`"$py`" -m pip install `"$knn`" --no-build-isolation --force-reinstall"
)
Set-Content -Path $bat -Value $lines -Encoding ASCII
cmd /c "`"$bat`""
if ($LASTEXITCODE -ne 0) { throw "Fallo la compilacion CUDA. Mira el log de cl.exe / nvcc." }

Write-Host "=== Test ==="
& $conda run -n gaussian_splatting python -c "import torch; import diff_gaussian_rasterization; print('LISTO torch', torch.__version__, 'cuda', torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) { throw "El test final fallo." }

Write-Host ""
Write-Host "LISTO. Doble clic EMPEZAR.bat"
