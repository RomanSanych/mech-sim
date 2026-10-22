#Requires -Version 5.1
<#
.SYNOPSIS
  Fallback: document manual capture workflow for assembled UGO screenshots.
  Does not auto-parse unless ImageMagick is installed.
#>
param(
    [string]$PngPath,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\out\captures')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $PngPath -or -not (Test-Path -LiteralPath $PngPath)) {
    Write-Host @"
measure_capture.ps1 — fallback only.

Usage:
  Save assembled symbol screenshot (not picker icon) as PNG.
  .\measure_capture.ps1 -PngPath path\to\assembled_cylinder.png

Then trace polylines into out/strokes/*.json manually or with a future vector tool.
"@
    exit 0
}

$meta = @{
    source_png = (Resolve-Path -LiteralPath $PngPath).Path
    captured_at = (Get-Date).ToString('o')
    note = 'Assembled UGO only. Convert to strokes JSON separately.'
}
$base = [IO.Path]::GetFileNameWithoutExtension($PngPath)
$outPath = Join-Path $OutDir ($base + '_meta.json')
[System.IO.File]::WriteAllText($outPath, ($meta | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $outPath"
