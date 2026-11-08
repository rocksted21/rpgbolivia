# Roda os testes de regras sem janela e sem pausa (para o Claude Code ou o terminal).
# Uso: powershell -ExecutionPolicy Bypass -File tools/rodar_testes.ps1 [-ComSimulacao] [teste1 teste2 ...]
param(
    [switch]$ComSimulacao,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Testes
)
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")

$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" }
if (-not (Test-Path $godot)) { Write-Host "Godot nao encontrado em $godot (defina a variavel GODOT)."; exit 1 }

$todos = @("test_town","test_expedition","test_save","test_battle","test_world","test_battle_camera",
           "test_audio","test_music","test_ruin_scenes","test_lanterns","test_suburbs")
if (-not $Testes -or $Testes.Count -eq 0) { $Testes = $todos }

$out = Join-Path (Get-Location) "tools\saida_testes"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Path $out | Out-Null
Set-Content -Path (Join-Path $out ".gdignore") -Value ""
$resumo = Join-Path $out "resumo.txt"

Write-Host "Importando arte e scripts novos..."
& $godot --headless --path . --import --log-file (Join-Path $out "import.txt") | Out-Null
Add-Content $resumo "import $LASTEXITCODE"

if (-not $ComSimulacao) { $env:SKIP_SIM = "1" } else { Remove-Item Env:SKIP_SIM -ErrorAction SilentlyContinue }

$falhas = 0
foreach ($t in $Testes) {
    Write-Host "Rodando $t..."
    & $godot --headless --path . --script "tests\$t.gd" --log-file (Join-Path $out "$t.txt") | Out-Null
    $code = $LASTEXITCODE
    Add-Content $resumo "$t $code"
    if ($code -ne 0) { $falhas++ }
}
Add-Content $resumo "FIM"
Get-Content $resumo
if ($falhas -gt 0) { Write-Host "$falhas teste(s) falharam. Logs em tools\saida_testes."; exit 1 }
Write-Host "Todos passaram."
exit 0
