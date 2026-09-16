# Fix WinError 182 on import torch (fbgemm.dll). Do not copy mismatched OpenMP DLLs.
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

Write-Host "=== 1) Visual C++ Redistributable (x64 y x86) ==="
winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-package-agreements --accept-source-agreements
winget install --id Microsoft.VCRedist.2015+.x86 -e --accept-package-agreements --accept-source-agreements

$py = Get-EnvPython
if (-not $py) {
    throw "No encuentro gaussian_splatting\python.exe"
}
$envRoot = Split-Path $py
$torchLib = Join-Path $envRoot "Lib\site-packages\torch\lib"
Write-Host "Python: $py"

if (Test-Path $torchLib) {
    Write-Host "=== 2) Sacar copias viejas de OpenMP en torch\lib ==="
    Remove-Item (Join-Path $torchLib "libomp140.x86_64.dll") -Force -ErrorAction SilentlyContinue
}

Write-Host "=== 3) Desinstalar PyTorch de conda/pip ==="
& $py -m pip uninstall -y torch torchvision torchaudio
$conda = Join-Path (Split-Path (Split-Path $envRoot)) "Scripts\conda.exe"
if (-not (Test-Path $conda)) {
    $conda = "$env:USERPROFILE\miniconda3\Scripts\conda.exe"
}
if (Test-Path $conda) {
    & $conda remove -n gaussian_splatting pytorch torchvision pytorch-cuda cpuonly -y --force 2>$null
}

Write-Host "=== 4) Instalar PyTorch oficial CUDA 11.8 (pip) ==="
& $py -m pip install --upgrade pip
$ok = $false
$specs = @(
    @("torch==2.1.2+cu118", "torchvision==0.16.2+cu118"),
    @("torch==2.2.2+cu118", "torchvision==0.17.2+cu118"),
    @("torch==2.3.1+cu118", "torchvision==0.18.1+cu118")
)
foreach ($spec in $specs) {
    Write-Host "Probando $($spec[0]) ..."
    & $py -m pip uninstall -y torch torchvision torchaudio
    & $py -m pip install $spec[0] $spec[1] --index-url https://download.pytorch.org/whl/cu118
    & $py -c "import torch; print('OK', torch.__version__, 'cuda', torch.cuda.is_available())"
    if ($LASTEXITCODE -eq 0) {
        $ok = $true
        Write-Host "TORCH OK con $($spec[0])"
        break
    }
    Write-Host "Esa version fallo, pruebo otra..."
}

if (-not $ok) {
    throw "Ninguna version de PyTorch cargo. REINICIA Windows y corre ARREGLAR_TORCH.bat otra vez."
}

$repo = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $repo "submodules\diff-gaussian-rasterization")) {
    Write-Host "=== 5) Recompilar extensiones CUDA (5-15 min) ==="
    $env:DISTUTILS_USE_SDK = "1"
    Push-Location $repo
    & $py -m pip install ./submodules/diff-gaussian-rasterization --no-build-isolation --force-reinstall
    & $py -m pip install ./submodules/simple-knn --no-build-isolation --force-reinstall
    Pop-Location
}

Write-Host ""
Write-Host "LISTO: import torch funciona. Ahora EMPEZAR.bat"
