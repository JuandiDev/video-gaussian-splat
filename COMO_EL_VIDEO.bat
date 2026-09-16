@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================
echo  Instalar COMO EL VIDEO de Stephens
echo  Orden: Git, Conda, VS C++, CUDA Toolkit,
echo         DESPUES recrear el env conda
echo ============================================
echo.
echo NO se desinstala: Git, Miniconda, Visual Studio,
echo FFmpeg, COLMAP, VS Code.
echo.
echo SI se borra: el entorno conda gaussian_splatting
echo (se creo sin el compilador CUDA / nvcc).
echo.
echo Notebook enchufada. Puede tardar 20-40 min.
echo Si instala CUDA 11.8, quizas pida REINICIAR
echo y volver a abrir este .bat
echo.
pause

powershell -ExecutionPolicy Bypass -File "%~dp0scripts\orden_stephens.ps1"
if errorlevel 1 (
    echo.
    echo Fallo. Si acaba de instalar CUDA: reinicia Windows
    echo y volve a ejecutar COMO_EL_VIDEO.bat
    pause
    exit /b 1
)

echo.
echo LISTO. Ahora EMPEZAR.bat
pause
