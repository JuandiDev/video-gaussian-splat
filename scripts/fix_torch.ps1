# Fix WinError 182 loading torch/lib/fbgemm.dll (missing OpenMP / VC runtime)
$ErrorActionPreference = "Stop"

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

Write-Host "=== Visual C++ Redistributable ==="
winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-package-agreements --accept-source-agreements

$conda = Get-CondaExe
if (-not $conda) {
    throw "No encuentro conda. Instala Miniconda y corre INSTALLAR.bat una vez."
}

Write-Host "Using conda: $conda"
Write-Host "=== OpenMP + runtime ==="
& $conda install -n gaussian_splatting -c conda-forge llvm-openmp intel-openmp vs2015_runtime -y

$envRoot = Join-Path $env:USERPROFILE "miniconda3\envs\gaussian_splatting"
if (-not (Test-Path $envRoot)) {
    $envRoot = Join-Path $env:LOCALAPPDATA "miniconda3\envs\gaussian_splatting"
}
$torchLib = Join-Path $envRoot "Lib\site-packages\torch\lib"
$binDir = Join-Path $envRoot "Library\bin"
Write-Host "torch lib: $torchLib"
Write-Host "conda bin: $binDir"

if (Test-Path $binDir -and Test-Path $torchLib) {
    $omps = Get-ChildItem $binDir -Filter "*omp*.dll" -ErrorAction SilentlyContinue
    foreach ($dll in $omps) {
        Write-Host "Copy $($dll.Name) -> torch/lib"
        Copy-Item $dll.FullName $torchLib -Force
    }
    $target = Join-Path $torchLib "libomp140.x86_64.dll"
    if (-not (Test-Path $target) -and $omps) {
        Write-Host "Also copy as libomp140.x86_64.dll"
        Copy-Item $omps[0].FullName $target -Force
    }
}

Write-Host "=== Reinstall PyTorch 2.1.2 + CUDA 11.8 ==="
& $conda install -n gaussian_splatting pytorch=2.1.2 torchvision=0.16.2 pytorch-cuda=11.8 -c pytorch -c nvidia --force-reinstall -y

$py = Join-Path $envRoot "python.exe"
Write-Host "=== Test import torch ==="
& $py -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"
if ($LASTEXITCODE -ne 0) {
    throw "import torch sigue fallando. Reinicia Windows y volve a correr ARREGLAR_TORCH.bat"
}

Write-Host "PyTorch OK."
