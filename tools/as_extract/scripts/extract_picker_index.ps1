#Requires -Version 5.1
param(
    [string]$AsRoot = 'C:\Program Files\Famic Technologies\Automation Studio P7.0',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\out\taxonomy')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$verinDll = Join-Path $AsRoot 'ASCFGVerin.dll'
$ver = [Reflection.Assembly]::LoadFrom($verinDll)
$stream = $ver.GetManifestResourceStream('ASCFGVerin.g.resources')
$icons = @()
$baml = @()
if ($stream) {
    $rr = New-Object System.Resources.ResourceReader($stream)
    $e = $rr.GetEnumerator()
    while ($e.MoveNext()) {
        $k = [string]$e.Key
        if ($k -match '\.png$') { $icons += $k }
        elseif ($k -match '\.baml$') { $baml += $k }
    }
    $rr.Close()
}

$doc = @{
    warning = 'Icons are picker thumbnails only. Do not use as schematic stroke reference.'
    png_keys = ($icons | Sort-Object)
    baml_keys = ($baml | Sort-Object)
}
$outPath = Join-Path $OutDir 'verin_picker_index.json'
[System.IO.File]::WriteAllText($outPath, ($doc | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $outPath ($($icons.Count) png, $($baml.Count) baml)"
