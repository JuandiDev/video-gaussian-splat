@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================
echo  Arreglar PyTorch (fbgemm.dll / WinError 182)
echo  NO reinstala COLMAP ni el entorno completo.
echo ============================================
echo.

echo --- Visual C++ Redistributable ---
winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-package-agreements --accept-source-agreements

set "CONDA_EXE="
if exist "%USERPROFILE%\miniconda3\Scripts\conda.exe" set "CONDA_EXE=%USERPROFILE%\miniconda3\Scripts\conda.exe"
if exist "%LOCALAPPDATA%\miniconda3\Scripts\conda.exe" set "CONDA_EXE=%LOCALAPPDATA%\miniconda3\Scripts\conda.exe"
if exist "%USERPROFILE%\anaconda3\Scripts\conda.exe" set "CONDA_EXE=%USERPROFILE%\anaconda3\Scripts\conda.exe"

if "%CONDA_EXE%"=="" (
    echo No encuentro conda. Igual instala el Redistributable de arriba.
    goto END
)

echo --- OpenMP en el env gaussian_splatting ---
"%CONDA_EXE%" install -n gaussian_splatting -c conda-forge llvm-openmp vs2015_runtime -y

:END
echo.
echo Listo. REINICIA Windows y despues EMPEZAR.bat
echo Si COLMAP ya habia terminado, no lo vuelve a hacer.
pause
