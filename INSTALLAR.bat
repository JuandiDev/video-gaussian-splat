@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================
echo  Instalacion (una sola vez) en esta PC
echo ============================================
echo.
echo Esto puede tardar 30-90 minutos e instala:
echo  - Git, Miniconda, Visual Studio C++, CUDA 11.8
echo  - FFmpeg, COLMAP
echo  - Entorno conda gaussian_splatting
echo.
echo El VIDEO no se instala. Se elige despues en EMPEZAR.bat
echo Notebook enchufada. Cerra otros programas.
echo.
pause

echo.
echo --- 1/3 Herramientas de sistema ---
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\install_prereqs.ps1"
if errorlevel 1 (
    echo Fallo la instalacion de requisitos.
    pause
    exit /b 1
)

echo.
echo --- 2/3 FFmpeg y COLMAP ---
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\install_windows.ps1"
if errorlevel 1 (
    echo Fallo FFmpeg/COLMAP.
    pause
    exit /b 1
)

echo.
echo --- 3/3 Entorno conda (compila CUDA, tarda) ---
set DISTUTILS_USE_SDK=1
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\setup_env.ps1"
if errorlevel 1 (
    echo Fallo el entorno conda.
    echo Si acabas de instalar Visual Studio o CUDA, reinicia Windows y volve a correr INSTALLAR.bat
    pause
    exit /b 1
)

echo.
echo Listo. A partir de ahora: doble clic en EMPEZAR.bat
echo Elegi el video ahi. No hace falta Cursor.
pause
