#Requires -Version 5.1
<#
.SYNOPSIS
  Trace black ink from an assembled AS UGO screenshot into stroke polylines (fallback).
  Prefer import_dxf.ps1 when DXF export is available.
#>
param(
    [Parameter(Mandatory = $true)][string]$PngPath,
    [string]$OutJson = '',
    [int]$InkThreshold = 90,
    [double]$TargetBodyWidth = 160.0
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not (Test-Path -LiteralPath $PngPath)) { throw "PNG not found: $PngPath" }
if ($OutJson -eq '') {
    $base = [IO.Path]::GetFileNameWithoutExtension($PngPath)
    $OutJson = Join-Path (Join-Path $PSScriptRoot '..\out\strokes') ($base + '_trace.json')
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutJson) | Out-Null

$bmp = New-Object System.Drawing.Bitmap $PngPath
$w = $bmp.Width; $h = $bmp.Height
# Collect ink pixels, then extract long vertical/horizontal runs as segments
$segments = New-Object System.Collections.Generic.List[object]
# Vertical runs
for ($x = 0; $x -lt $w; $x++) {
    $run0 = -1
    for ($y = 0; $y -le $h; $y++) {
        $ink = $false
        if ($y -lt $h) {
            $p = $bmp.GetPixel($x, $y)
            $ink = ($p.R -lt $InkThreshold -and $p.G -lt $InkThreshold -and $p.B -lt $InkThreshold)
        }
        if ($ink) {
            if ($run0 -lt 0) { $run0 = $y }
        }
        else {
            if ($run0 -ge 0) {
                $len = $y - $run0
                if ($len -ge 12) {
                    $segments.Add(@{ polyline = @(@([double]$x, [double]$run0), @([double]$x, [double]($y - 1))) })
                }
                $run0 = -1
            }
        }
    }
}
# Horizontal runs
for ($y = 0; $y -lt $h; $y++) {
    $run0 = -1
    for ($x = 0; $x -le $w; $x++) {
        $ink = $false
        if ($x -lt $w) {
            $p = $bmp.GetPixel($x, $y)
            $ink = ($p.R -lt $InkThreshold -and $p.G -lt $InkThreshold -and $p.B -lt $InkThreshold)
        }
        if ($ink) {
            if ($run0 -lt 0) { $run0 = $x }
        }
        else {
            if ($run0 -ge 0) {
                $len = $x - $run0
                if ($len -ge 12) {
                    $segments.Add(@{ polyline = @(@([double]$run0, [double]$y), @([double]($x - 1), [double]$y)) })
                }
                $run0 = -1
            }
        }
    }
}
$bmp.Dispose()

$minX = [double]::PositiveInfinity; $minY = [double]::PositiveInfinity
$maxX = [double]::NegativeInfinity; $maxY = [double]::NegativeInfinity
foreach ($s in $segments) {
    foreach ($pt in $s.polyline) {
        $minX = [Math]::Min($minX, $pt[0]); $maxX = [Math]::Max($maxX, $pt[0])
        $minY = [Math]::Min($minY, $pt[1]); $maxY = [Math]::Max($maxY, $pt[1])
    }
}
$cx = ($minX + $maxX) * 0.5
$cy = ($minY + $maxY) * 0.5
$bw = [Math]::Max($maxX - $minX, 1.0)
$scale = $TargetBodyWidth / $bw
$norm = @()
foreach ($s in $segments) {
    $poly = @()
    foreach ($pt in $s.polyline) {
        $poly += , @([Math]::Round(($pt[0] - $cx) * $scale, 2), [Math]::Round(($pt[1] - $cy) * $scale, 2))
    }
    $norm += @{ part = 'trace'; polyline = $poly }
}

$doc = @{
    id = 'cylinder.from_as_trace'
    source = @{ png = (Resolve-Path -LiteralPath $PngPath).Path; imported_at = (Get-Date).ToString('o') }
    strokes = $norm
    notes = @('Fallback ink trace. Prefer AS DXF export + import_dxf.ps1.')
}
[IO.File]::WriteAllText($OutJson, ($doc | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutJson ($($norm.Count) segments)"
