@echo off
setlocal EnableDelayedExpansion
rem Roda os testes de regras sem abrir janela e guarda o resultado em tools\saida_testes.
rem Clique duas vezes neste arquivo com o Godot fechado.
cd /d "%~dp0.."
set "GODOT=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if not exist "%GODOT%" (
  echo Godot nao encontrado em "%GODOT%". Ajuste a linha GODOT deste arquivo.
  pause
  exit /b 1
)
set "OUT=%CD%\tools\saida_testes"
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
echo.> "%OUT%\.gdignore"
echo Importando arte e scripts novos...
"%GODOT%" --headless --path . --import --log-file "%OUT%\import.txt"
echo import !errorlevel!>> "%OUT%\resumo.txt"
set SKIP_SIM=1
for %%T in (test_town test_expedition test_save test_battle test_world test_battle_camera test_audio test_music test_ruin_scenes test_lanterns) do (
  echo Rodando %%T...
  "%GODOT%" --headless --path . --script tests\%%T.gd --log-file "%OUT%\%%T.txt"
  echo %%T !errorlevel!>> "%OUT%\resumo.txt"
)
echo FIM>> "%OUT%\resumo.txt"
echo.
type "%OUT%\resumo.txt"
echo.
echo Pronto. 0 = passou; 1 = falhou. Detalhes em tools\saida_testes.
timeout /t 8
