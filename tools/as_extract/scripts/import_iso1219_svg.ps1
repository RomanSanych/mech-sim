#Requires -Version 5.1
<#
.SYNOPSIS
  Convert ISO 1219 line-only SVG (Wikimedia Commons style) into MechSim stroke JSON.
#>
param(
    [Parameter(Mandatory = $true)][string]$SvgPath,
    [string]$OutJson = '',
    [string]$Id = 'cylinder.iso1219',
    [double]$TargetBodyWidth = 160.0
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SvgPath)) { throw "SVG not found: $SvgPath" }
if ($OutJson -eq '') {
    $base = [IO.Path]::GetFileNameWithoutExtension($SvgPath)
    $OutJson = Join-Path (Join-Path $PSScriptRoot '..\out\strokes') ($base + '_iso1219.json')
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutJson) | Out-Null

$raw = Get-Content -LiteralPath $SvgPath -Raw
$tx = 0.0; $ty = 0.0
$tm = [regex]::Match($raw, 'transform="translate\(([^,]+),([^\)]+)\)"')
if ($tm.Success) {
    $tx = [double]$tm.Groups[1].Value
    $ty = [double]$tm.Groups[2].Value
}

$segs = New-Object System.Collections.Generic.List[object]
foreach ($m in [regex]::Matches($raw, 'd="M\s+([-\d\.]+),([-\d\.]+)\s+L\s+([-\d\.]+),([-\d\.]+)"')) {
    $x1 = [double]$m.Groups[1].Value + $tx
    $y1 = [double]$m.Groups[2].Value + $ty
    $x2 = [double]$m.Groups[3].Value + $tx
    $y2 = [double]$m.Groups[4].Value + $ty
    $segs.Add(@{ polyline = @(@($x1, $y1), @($x2, $y2)) })
}
if ($segs.Count -eq 0) { throw "No M..L paths in $SvgPath" }

# Body bbox: longest horizontal span among nearly-horizontal segments near mid height
$minX = [double]::PositiveInfinity; $maxX = [double]::NegativeInfinity
$minY = [double]::PositiveInfinity; $maxY = [double]::NegativeInfinity
foreach ($s in $segs) {
    foreach ($pt in $s.polyline) {
        $minX = [Math]::Min($minX, $pt[0]); $maxX = [Math]::Max($maxX, $pt[0])
        $minY = [Math]::Min($minY, $pt[1]); $maxY = [Math]::Max($maxY, $pt[1])
    }
}
# Prefer body from longest horizontal stroke as width reference
$bodyL = $minX; $bodyR = $maxX; $bodyT = $minY; $bodyB = $maxY
$bestLen = 0.0
foreach ($s in $segs) {
    $a = $s.polyline[0]; $b = $s.polyline[1]
    $dx = [Math]::Abs($a[0] - $b[0]); $dy = [Math]::Abs($a[1] - $b[1])
    if ($dx -gt $dy -and $dx -gt $bestLen) {
        $bestLen = $dx
        $bodyL = [Math]::Min($a[0], $b[0])
        $bodyR = [Math]::Max($a[0], $b[0])
        # keep y of that line as bottom candidate later
    }
}
$cx = ($bodyL + $bodyR) * 0.5
$cy = ($bodyT + $bodyB) * 0.5
# Refine body top/bottom from vertical walls at bodyL/bodyR
$wallYs = @()
foreach ($s in $segs) {
    $a = $s.polyline[0]; $b = $s.polyline[1]
    $dx = [Math]::Abs($a[0] - $b[0]); $dy = [Math]::Abs($a[1] - $b[1])
    if ($dy -gt $dx) {
        $x = ($a[0] + $b[0]) * 0.5
        if ([Math]::Abs($x - $bodyL) -lt 2 -or [Math]::Abs($x - $bodyR) -lt 2) {
            $wallYs += $a[1]; $wallYs += $b[1]
        }
    }
}
if ($wallYs.Count -ge 2) {
    $bodyT = ($wallYs | Measure-Object -Minimum).Minimum
    $bodyB = ($wallYs | Measure-Object -Maximum).Maximum
    $cy = ($bodyT + $bodyB) * 0.5
}

$bw = [Math]::Max($bodyR - $bodyL, 1.0)
$scale = $TargetBodyWidth / $bw

function N([double]$x, [double]$y) {
    return @([Math]::Round(($x - $script:cx) * $script:scale, 2), [Math]::Round(($y - $script:cy) * $script:scale, 2))
}

$norm = @()
foreach ($s in $segs) {
    $a = $s.polyline[0]; $b = $s.polyline[1]
    $norm += @{ part = 'iso'; polyline = @( (N $a[0] $a[1]), (N $b[0] $b[1]) ) }
}

$layout = @{
    body_l = [Math]::Round(($bodyL - $cx) * $scale, 2)
    body_r = [Math]::Round(($bodyR - $cx) * $scale, 2)
    body_t = [Math]::Round(($bodyT - $cy) * $scale, 2)
    body_b = [Math]::Round(($bodyB - $cy) * $scale, 2)
}

$doc = @{
    id = $Id
    norm = 'ISO1219-1'
    source = @{
        svg = (Resolve-Path -LiteralPath $SvgPath).Path
        imported_at = (Get-Date).ToString('o')
        attribution = 'Geometry derived from Wikimedia Commons ISO 1219 SVGs (Marton Kiss-Albert), CC-BY-SA 2.5/3.0'
        commons_category = 'https://commons.wikimedia.org/wiki/Category:ISO_1219'
    }
    layout = $layout
    strokes = $norm
    notes = @(
        'ISO 1219 fluid-power graphical symbol (same family Automation Studio declares: ISO 1219-1 / 1219-2).'
        'Related: ISO 14617 (general), GOST 2.782-96 (cylinders), GOST 2.781-96 (valves, ISO 1219-91 based).'
    )
}

[IO.File]::WriteAllText($OutJson, ($doc | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutJson ($($norm.Count) segments) layout=$($layout | ConvertTo-Json -Compress)"
