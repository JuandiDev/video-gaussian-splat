@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================
echo  Video a Gaussian Splat
echo  No hace falta Cursor. Esta ventana es suficiente.
echo ============================================
echo.

REM Buscar conda
set "CONDA_BAT="
if exist "%USERPROFILE%\miniconda3\Scripts\activate.bat" set "CONDA_BAT=%USERPROFILE%\miniconda3\Scripts\activate.bat"
if exist "%USERPROFILE%\anaconda3\Scripts\activate.bat" set "CONDA_BAT=%USERPROFILE%\anaconda3\Scripts\activate.bat"
if exist "%LOCALAPPDATA%\miniconda3\Scripts\activate.bat" set "CONDA_BAT=%LOCALAPPDATA%\miniconda3\Scripts\activate.bat"
if exist "%LOCALAPPDATA%\anaconda3\Scripts\activate.bat" set "CONDA_BAT=%LOCALAPPDATA%\anaconda3\Scripts\activate.bat"
if exist "C:\ProgramData\miniconda3\Scripts\activate.bat" set "CONDA_BAT=C:\ProgramData\miniconda3\Scripts\activate.bat"
if exist "C:\ProgramData\anaconda3\Scripts\activate.bat" set "CONDA_BAT=C:\ProgramData\anaconda3\Scripts\activate.bat"

if "%CONDA_BAT%"=="" (
    echo No encuentro Miniconda/Anaconda.
    echo Primero ejecuta INSTALLAR.bat  o instala Miniconda y el entorno.
    echo Guia: COMO_EJECUTAR.md
    pause
    exit /b 1
)

call "%CONDA_BAT%" gaussian_splatting
if errorlevel 1 (
    echo No pude activar el entorno gaussian_splatting.
    echo Corre INSTALLAR.bat una vez.
    pause
    exit /b 1
)

python splat_app.py
if errorlevel 1 (
    echo.
    echo Si no se abrio la ventana, el entorno no esta listo.
    echo Mira COMO_EJECUTAR.md
    pause
)
