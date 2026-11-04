$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Instale Node.js para executar o servidor online.'
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules/ws'))) {
    & npm.cmd ci --omit=dev
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível instalar as dependências.' }
}
Write-Host 'Servidor local: ws://127.0.0.1:8787. Mantenha este terminal aberto.'
$env:PORT = '8787'
& node server.js
