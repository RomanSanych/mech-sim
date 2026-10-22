#Requires -Version 5.1
<#
.SYNOPSIS
  Import Automation Studio diagram export (EMF) into MechSim stroke JSON.

.DESCRIPTION
  Parses GDI EMR records from File > Export diagram > EMF.
  Handles EMR_MOVETOEX, EMR_LINETO, EMR_POLYLINE, EMR_POLYGON, EMR_POLYLINETO, EMR_RECTANGLE.
#>
param(
    [Parameter(Mandatory = $true)][string]$EmfPath,
    [string]$OutJson = '',
    [string]$Id = 'cylinder.from_as_emf'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $EmfPath)) { throw "EMF not found: $EmfPath" }
if ($OutJson -eq '') {
    $base = [IO.Path]::GetFileNameWithoutExtension($EmfPath)
    $OutJson = Join-Path (Join-Path $PSScriptRoot '..\out\strokes') ($base + '.json')
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutJson) | Out-Null

# EMR type constants (wingdi.h)
$EMR_POLYGON = 3
$EMR_POLYLINE = 4
$EMR_POLYLINETO = 6
$EMR_EOF = 14
$EMR_MOVETOEX = 27
$EMR_RECTANGLE = 43
$EMR_LINETO = 54
$EMR_POLYGON16 = 86
$EMR_POLYLINE16 = 87
$EMR_POLYLINETO16 = 89

$bytes = [IO.File]::ReadAllBytes($EmfPath)
if ($bytes.Length -lt 88) { throw 'EMF too small' }

function Read-Int32([byte[]]$b, [int]$o) { [BitConverter]::ToInt32($b, $o) }
function Read-UInt32([byte[]]$b, [int]$o) { [BitConverter]::ToUInt32($b, $o) }
function Read-Int16([byte[]]$b, [int]$o) { [BitConverter]::ToInt16($b, $o) }

function Add-PolySegments(
    [System.Collections.Generic.List[object]]$dst,
    [System.Collections.Generic.List[object]]$pts,
    [bool]$closed,
    [bool]$fromPen,
    [ref]$penX,
    [ref]$penY
) {
    if ($pts.Count -lt 1) { return }
    if ($fromPen) {
        $dst.Add(@{ part = 'poly'; polyline = @(@($penX.Value, $penY.Value), $pts[0]) })
    }
    for ($k = 0; $k -lt $pts.Count - 1; $k++) {
        $dst.Add(@{ part = 'poly'; polyline = @($pts[$k], $pts[$k + 1]) })
    }
    if ($closed -and $pts.Count -ge 2) {
        $dst.Add(@{ part = 'poly'; polyline = @($pts[$pts.Count - 1], $pts[0]) })
    }
    $last = $pts[$pts.Count - 1]
    $penX.Value = $last[0]
    $penY.Value = $last[1]
}

$offset = 0
if ($bytes.Length -ge 22 -and [BitConverter]::ToUInt32($bytes, 0) -eq 0x9AC6CDD7) {
    $offset = 22
}

$strokes = New-Object System.Collections.Generic.List[object]
$penX = 0.0
$penY = 0.0
$i = $offset
$recordCount = 0

while ($i + 8 -le $bytes.Length) {
    $type = Read-UInt32 $bytes $i
    $size = Read-UInt32 $bytes ($i + 4)
    if ($size -lt 8 -or ($i + [int64]$size) -gt $bytes.Length) { break }
    $recordCount++

    if ($type -eq $EMR_EOF) { break }

    if ($type -eq $EMR_MOVETOEX -and $size -ge 16) {
        $penX = [double](Read-Int32 $bytes ($i + 8))
        $penY = [double](Read-Int32 $bytes ($i + 12))
    }
    elseif ($type -eq $EMR_LINETO -and $size -ge 16) {
        $x = [double](Read-Int32 $bytes ($i + 8))
        $y = [double](Read-Int32 $bytes ($i + 12))
        $strokes.Add(@{ part = 'line'; polyline = @(@($penX, $penY), @($x, $y)) })
        $penX = $x; $penY = $y
    }
    elseif ($type -eq $EMR_RECTANGLE -and $size -ge 24) {
        $l = [double](Read-Int32 $bytes ($i + 8))
        $t = [double](Read-Int32 $bytes ($i + 12))
        $r = [double](Read-Int32 $bytes ($i + 16))
        $b = [double](Read-Int32 $bytes ($i + 20))
        $rectPts = New-Object System.Collections.Generic.List[object]
        $null = $rectPts.Add(@($l, $t)); $null = $rectPts.Add(@($r, $t))
        $null = $rectPts.Add(@($r, $b)); $null = $rectPts.Add(@($l, $b))
        Add-PolySegments $strokes $rectPts $true $false ([ref]$penX) ([ref]$penY)
    }
    elseif (($type -eq $EMR_POLYLINE -or $type -eq $EMR_POLYGON -or $type -eq $EMR_POLYLINETO) -and $size -ge 28) {
        $cptl = Read-UInt32 $bytes ($i + 8 + 16)
        $pts = New-Object System.Collections.Generic.List[object]
        $po = $i + 8 + 16 + 4
        for ($k = 0; $k -lt $cptl; $k++) {
            if ($po + 8 -gt $i + $size) { break }
            $null = $pts.Add(@([double](Read-Int32 $bytes $po), [double](Read-Int32 $bytes ($po + 4))))
            $po += 8
        }
        Add-PolySegments $strokes $pts ($type -eq $EMR_POLYGON) ($type -eq $EMR_POLYLINETO) ([ref]$penX) ([ref]$penY)
    }
    elseif (($type -eq $EMR_POLYGON16 -or $type -eq $EMR_POLYLINE16 -or $type -eq $EMR_POLYLINETO16) -and $size -ge 28) {
        $cpts = Read-UInt32 $bytes ($i + 8 + 16)
        $pts = New-Object System.Collections.Generic.List[object]
        $po = $i + 8 + 16 + 4
        for ($k = 0; $k -lt $cpts; $k++) {
            if ($po + 4 -gt $i + $size) { break }
            $null = $pts.Add(@([double](Read-Int16 $bytes $po), [double](Read-Int16 $bytes ($po + 2))))
            $po += 4
        }
        Add-PolySegments $strokes $pts ($type -eq $EMR_POLYGON16) ($type -eq $EMR_POLYLINETO16) ([ref]$penX) ([ref]$penY)
    }

    $i += [int]$size
}

if ($strokes.Count -eq 0) {
    throw "No vector strokes parsed from EMF ($recordCount records). File may be EMF+ only or rasterized."
}

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
$scale = 160.0 / $bw
$norm = @()
foreach ($s in $strokes) {
    $poly = @()
    foreach ($pt in $s.polyline) {
        $lx = ($pt[0] - $cx) * $scale
        $ly = ($pt[1] - $cy) * $scale
        $poly += , @([Math]::Round($lx, 2), [Math]::Round($ly, 2))
    }
    $norm += @{ part = $s.part; polyline = $poly }
}

$doc = @{
    id = $Id
    norm = 'ISO1219-1-2012'
    source = @{
        emf = (Resolve-Path -LiteralPath $EmfPath).Path
        imported_at = (Get-Date).ToString('o')
        raw_stroke_count = $strokes.Count
        emr_records = $recordCount
    }
    layout = @{
        body_l = [Math]::Round(($minX - $cx) * $scale, 2)
        body_r = [Math]::Round(($maxX - $cx) * $scale, 2)
        body_t = [Math]::Round(($minY - $cy) * $scale, 2)
        body_b = [Math]::Round(($maxY - $cy) * $scale, 2)
    }
    strokes = $norm
    notes = @(
        'Imported from AS diagram EMF export (File > Export diagram > EMF).'
        'AS drawing IL is Sec-protected; DXF/EMF export is the extraction path.'
    )
}

[IO.File]::WriteAllText($OutJson, ($doc | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutJson ($($norm.Count) segments from $recordCount EMR records)"
