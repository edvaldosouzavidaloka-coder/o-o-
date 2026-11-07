@echo off
setlocal
title TOP GAMERS - Gerar EXE Windows
cd /d "%~dp0"
echo ==========================================
echo TOP GAMERS - Criador de Cercas FS25 v0.2
echo Gerador do arquivo EXE (Windows)
echo ==========================================
where py >nul 2>&1
if errorlevel 1 (
 echo.
 echo Python nao encontrado. Instale Python 3.10+ de python.org.
 echo Marque Add python.exe to PATH durante a instalacao.
 pause
 exit /b 1
)
if not exist "TG_Cerca_Editor_GE10_v0.2_I3D_TESTE.zip" (
 echo Arquivo ZIP v0.2 nao encontrado nesta pasta.
 pause
 exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '.\TG_Cerca_Editor_GE10_v0.2_I3D_TESTE.zip' -DestinationPath '.\_montagem_exe' -Force"
if errorlevel 1 goto failed
cd "_montagem_exe\TG_Cerca_Editor_GE10_v0.2"
py -m pip install --upgrade pyinstaller
if errorlevel 1 goto failed
py TESTAR.py
if errorlevel 1 goto failed
py -m PyInstaller --noconfirm --clean --windowed --onefile --name "TOP_GAMERS_Criador_Cercas_FS25" TG_Cerca_Editor.py
if errorlevel 1 goto failed
copy /y "dist\TOP_GAMERS_Criador_Cercas_FS25.exe" "..\..\TOP_GAMERS_Criador_Cercas_FS25.exe" >nul
echo.
echo PRONTO! Na pasta deste arquivo BAT voce encontrara:
echo TOP_GAMERS_Criador_Cercas_FS25.exe
start "" explorer "..\.."
pause
exit /b 0
:failed
echo.
echo Falhou ao gerar o EXE; confira as mensagens acima.
pause
exit /b 1
