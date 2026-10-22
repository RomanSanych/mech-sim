#Requires -Version 5.1
<#
.SYNOPSIS
  Import Automation Studio diagram export (DXF) into MechSim stroke JSON.

.DESCRIPTION
  AS File → Export diagram → DXF (or EMF). Drawing IL is Sec-protected; this is the
  supported extraction path. Parses LINE / LWPOLYLINE / POLYLINE entities.
#>
param(
    [Parameter(Mandatory = $true)][string]$DxfPath,
    [string]$OutJson = '',
    [string]$Id = 'cylinder.from_as_dxf'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $DxfPath)) { throw "DXF not found: $DxfPath" }
if ($OutJson -eq '') {
    $base = [IO.Path]::GetFileNameWithoutExtension($DxfPath)
    $OutJson = Join-Path (Join-Path $PSScriptRoot '..\out\strokes') ($base + '.json')
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutJson) | Out-Null

$lines = Get-Content -LiteralPath $DxfPath
$strokes = New-Object System.Collections.Generic.List[object]
$i = 0
function NextPair([ref]$idx) {
    if ($idx.Value + 1 -ge $script:lines.Count) { return $null }
    $code = $script:lines[$idx.Value].Trim()
    $val = $script:lines[$idx.Value + 1].Trim()
    $idx.Value += 2
    return @{ c = $code; v = $val }
}

while ($i -lt $lines.Count) {
    $p = NextPair ([ref]$i)
    if ($null -eq $p) { break }
    if ($p.c -ne '0') { continue }
    $ent = $p.v.ToUpperInvariant()

    if ($ent -eq 'LINE') {
        $x1 = $null; $y1 = $null; $x2 = $null; $y2 = $null
        while ($i -lt $lines.Count) {
            $q = NextPair ([ref]$i)
            if ($null -eq $q) { break }
            if ($q.c -eq '0') { $i -= 2; break }
            switch ($q.c) {
                '10' { $x1 = [double]$q.v }
                '20' { $y1 = [double]$q.v }
                '11' { $x2 = [double]$q.v }
                '21' { $y2 = [double]$q.v }
            }
        }
        if ($null -ne $x1 -and $null -ne $x2) {
            $strokes.Add(@{ part = 'line'; polyline = @(@($x1, $y1), @($x2, $y2)) })
        }
    }
    elseif ($ent -eq 'LWPOLYLINE') {
        $pts = New-Object System.Collections.Generic.List[object]
        $closed = $false
        $pendingX = $null
        while ($i -lt $lines.Count) {
            $q = NextPair ([ref]$i)
            if ($null -eq $q) { break }
            if ($q.c -eq '0') { $i -= 2; break }
            switch ($q.c) {
                '70' { if (([int]$q.v -band 1) -ne 0) { $closed = $true } }
                '10' { $pendingX = [double]$q.v }
                '20' {
                    if ($null -ne $pendingX) {
                        $pts.Add(@($pendingX, [double]$q.v))
                        $pendingX = $null
                    }
                }
            }
        }
        if ($pts.Count -ge 2) {
            for ($k = 0; $k -lt $pts.Count - 1; $k++) {
                $strokes.Add(@{ part = 'poly'; polyline = @($pts[$k], $pts[$k + 1]) })
            }
            if ($closed) {
                $strokes.Add(@{ part = 'poly'; polyline = @($pts[$pts.Count - 1], $pts[0]) })
            }
        }
    }
}

# Normalize: center on bbox, flip Y (DXF Y-up → our Y-down), optional scale
$minX = [double]::PositiveInfinity; $minY = [double]::PositiveInfinity
$maxX = [double]::NegativeInfinity; $maxY = [double]::NegativeInfinity
foreach ($s in $strokes) {
    foreach ($pt in $s.polyline) {
        $minX = [Math]::Min($minX, $pt[0]); $maxX = [Math]::Max($maxX, $pt[0])
        $minY = [Math]::Min($minY, $pt[1]); $maxY = [Math]::Max($maxY, $pt[1])
    }
}
$cx = ($minX + $maxX) * 0.5
$cy = ($minY + $maxY) * 0.5
$bw = [Math]::Max($maxX - $minX, 1.0)
# Target body width ~160 local units (AS-like)
$scale = 160.0 / $bw
$norm = @()
foreach ($s in $strokes) {
    $poly = @()
    foreach ($pt in $s.polyline) {
        $lx = ($pt[0] - $cx) * $scale
        $ly = -(($pt[1] - $cy) * $scale) # flip Y
        $poly += , @([Math]::Round($lx, 2), [Math]::Round($ly, 2))
    }
    $norm += @{ part = $s.part; polyline = $poly }
}

$doc = @{
    id = $Id
    norm = 'ISO1219-1-2012'
    source = @{
        dxf = (Resolve-Path -LiteralPath $DxfPath).Path
        imported_at = (Get-Date).ToString('o')
        raw_stroke_count = $strokes.Count
    }
    layout = @{
        body_l = [Math]::Round(($minX - $cx) * $scale, 2)
        body_r = [Math]::Round(($maxX - $cx) * $scale, 2)
        body_t = [Math]::Round(-(($maxY - $cy) * $scale), 2)
        body_b = [Math]::Round(-(($minY - $cy) * $scale), 2)
    }
    strokes = $norm
    notes = @(
        'Imported from AS diagram DXF export (File > Export diagram > DXF).'
        'AS drawing IL is Sec-protected; DXF/EMF export is the extraction path.'
    )
}

[IO.File]::WriteAllText($OutJson, ($doc | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutJson ($($norm.Count) segments)"
