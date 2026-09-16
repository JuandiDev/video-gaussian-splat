# Repair torch env: numpy 1.x + CUDA rasterizer. Skip torch reinstall if import already works.
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

$py = Get-EnvPython
if (-not $py) { throw "No encuentro gaussian_splatting\python.exe" }
Write-Host "Python: $py"

Write-Host "=== NumPy 1.x (PyTorch no banca NumPy 2) ==="
& $py -m pip install "numpy>=1.24,<2"

Write-Host "=== Test torch ==="
& $py -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Torch no importa. Reinstalando ruedas CUDA 11.8..."
    winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-package-agreements --accept-source-agreements
    & $py -m pip uninstall -y torch torchvision torchaudio
    & $py -m pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 --index-url https://download.pytorch.org/whl/cu118
    & $py -m pip install "numpy>=1.24,<2"
    & $py -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"
    if ($LASTEXITCODE -ne 0) { throw "import torch fallo. Reinicia Windows y reintenta." }
}

$repo = Split-Path -Parent $PSScriptRoot
$rast = Join-Path $repo "submodules\diff-gaussian-rasterization"
$knn = Join-Path $repo "submodules\simple-knn"
if (-not (Test-Path $rast)) {
    throw "Falta $rast. En Git Bash: git submodule update --init --recursive"
}

Write-Host "=== Instalar rasterizer CUDA (5-15 min, notebook enchufada) ==="
$env:DISTUTILS_USE_SDK = "1"
Push-Location $repo
& $py -m pip install "$rast" --force-reinstall
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Fallo diff-gaussian-rasterization. Hace falta Visual Studio C++ y CUDA." }
& $py -m pip install "$knn" --force-reinstall
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Fallo simple-knn." }
Pop-Location

Write-Host "=== Test final ==="
& $py -c "import torch; import diff_gaussian_rasterization; import numpy; print('LISTO numpy', numpy.__version__, 'cuda', torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) {
    throw "Falta el rasterizer. Mira el error de pip de arriba."
}

Write-Host ""
Write-Host "LISTO. Ahora EMPEZAR.bat"
