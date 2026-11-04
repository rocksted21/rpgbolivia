param(
    [string]$Godot = 'C:\Users\leand\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [string]$Version = '0.1.0',
    [long]$PatchId = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(),
    [string]$Preset = 'Windows',
    [int]$PartSizeMB = 16
)
$ErrorActionPreference = 'Stop'
if ($PatchId -le 0 -or $PartSizeMB -lt 1 -or $PartSizeMB -gt 64) {
    throw 'PatchId deve ser positivo; PartSizeMB deve ficar entre 1 e 64.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $projectRoot 'project.godot'
$output = Join-Path $projectRoot "build\update-$PatchId"
if (Test-Path -LiteralPath $output) { throw "A versão já foi gerada: $output. Use outro PatchId." }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$original = [IO.File]::ReadAllText($projectFile)
$packPath = Join-Path $output 'patch.pck'
try {
    $config = [regex]::Replace($original, '(?m)^config/patch_id=.*$', "config/patch_id=$PatchId")
    $config = [regex]::Replace($config, '(?m)^config/version=.*$', 'config/version="' + $Version.Replace('"', '') + '"')
    [IO.File]::WriteAllText($projectFile, $config)
    [IO.File]::WriteAllText((Join-Path $projectRoot 'update/runtime.cfg'), $config)
    & $Godot --headless --path $projectRoot --export-pack $Preset $packPath
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $packPath)) { throw 'Falha ao exportar o PCK.' }
} finally {
    [IO.File]::WriteAllText($projectFile, $original)
}
$source = [IO.File]::OpenRead($packPath)
$parts = [Collections.Generic.List[string]]::new()
$download = 0L
$buffer = [byte[]]::new($PartSizeMB * 1MB)
try {
    $index = 0
    while ($source.Position -lt $source.Length) {
        $count = 0
        while ($count -lt $buffer.Length) {
            $read = $source.Read($buffer, $count, $buffer.Length - $count)
            if ($read -eq 0) { break }
            $count += $read
        }
        $name = 'patch.pck.parte{0:D3}' -f $index
        $partPath = Join-Path $output $name
        $target = [IO.File]::Create($partPath)
        $gzip = [IO.Compression.GZipStream]::new($target, [IO.Compression.CompressionLevel]::Optimal)
        try { $gzip.Write($buffer, 0, $count) } finally { $gzip.Dispose(); $target.Dispose() }
        $download += (Get-Item -LiteralPath $partPath).Length
        $parts.Add($name)
        $index++
    }
} finally { $source.Dispose() }
$metadata = [ordered]@{
    patch_id = $PatchId
    version = $Version
    size = (Get-Item -LiteralPath $packPath).Length
    download = $download
    sha256 = (Get-FileHash -LiteralPath $packPath -Algorithm SHA256).Hash.ToLowerInvariant()
    gz = $true
    base_url = "https://github.com/rocksted21/rpgbolivia/releases/download/combate-$PatchId/"
    parts = @($parts.ToArray())
}
[IO.File]::WriteAllText((Join-Path $output 'version.json'), ($metadata | ConvertTo-Json -Depth 4))
Write-Host "Atualização pronta: $output"
Write-Host "Crie a release combate-$PatchId e anexe version.json e todos os patch.pck.parteNNN."
