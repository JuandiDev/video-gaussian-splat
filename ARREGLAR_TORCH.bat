@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ============================================
echo  Arreglar PyTorch (fbgemm.dll / WinError 182)
echo  NO borra COLMAP ni hay que hacer INSTALLAR.bat
echo ============================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0scripts\fix_torch.ps1"
if errorlevel 1 (
    echo Fallo el arreglo. Copiá el texto rojo y mandaselo.
    pause
    exit /b 1
)

echo.
echo Tiene que decir LISTO con numpy y cuda.
echo Despues: EMPEZAR.bat
pause
