@echo off
setlocal
chcp 65001 >nul
title Preparador do ambiente NTE PT-BR
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
  -File "%~dp0tool\Preparar-Ambiente-NTE.ps1" %*

if errorlevel 1 (
    echo.
    echo O ambiente nao foi preparado por completo.
    echo Leia a mensagem acima, corrija o item indicado e execute este arquivo novamente.
    pause
    exit /b 1
)

echo.
echo Ambiente NTE PT-BR pronto.
pause
