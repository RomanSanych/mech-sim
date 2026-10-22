#Requires -Version 5.1
<#
.SYNOPSIS
  Promote an imported AS DXF/EMF stroke JSON into data/symbols/verin_default.json shape.
#>
param(
    [Parameter(Mandatory = $true)][string]$ImportJson,
    [string]$OutJson = (Join-Path $PSScriptRoot '..\out\strokes\verin_default.json'),
    [string]$Id = 'cylinder.from_as_import'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ImportJson)) { throw "Missing $ImportJson" }

$src = Get-Content -LiteralPath $ImportJson -Raw | ConvertFrom-Json
$layout = @{}
if ($src.layout) {
    foreach ($p in $src.layout.PSObject.Properties) { $layout[$p.Name] = $p.Value }
}
# Keep existing parametric keys if absent
$defaults = @{
    body_l = -80; body_r = 80; body_t = -36; body_b = 36
    rod_x = 132; piston_a = -27; piston_b = 50; piston_gap = 35
    port_cap_x = -71; port_rod_x = 70; port_drop = 36; rod_gap = 9
}
foreach ($k in $defaults.Keys) {
    if (-not $layout.ContainsKey($k)) { $layout[$k] = $defaults[$k] }
}

$flat = @()
if ($src.strokes) {
    foreach ($s in $src.strokes) {
        $flat += , @{ part = [string]$s.part; polyline = $s.polyline }
    }
}

$doc = @{
    id = $Id
    norm = 'ISO1219-1-2012'
    source = $src.source
    layout = $layout
    # Flat imported geometry for exact AS overlay / rebuild
    strokes = $flat
    # Keep empty layers until segments are labeled by part
    layers = @{}
    hit_zones = @(
        @{ id = 'piston'; rect = @(-66, -36, 47, 72) }
        @{ id = 'cush_cap'; rect = @(-80, -36, 22, 72) }
        @{ id = 'cush_rod'; rect = @(58, -36, 22, 72) }
        @{ id = 'spring'; rect = @(-20, -36, 78, 72) }
        @{ id = 'port_cap'; rect = @(-85, 36, 28, 42) }
        @{ id = 'port_rod'; rect = @(56, 36, 28, 42) }
        @{ id = 'rod'; rect = @(80, -11, 52, 22) }
        @{ id = 'tip'; rect = @(124, -14, 28, 28) }
        @{ id = 'brake'; rect = @(84, -56, 50, 36) }
        @{ id = 'carriage'; rect = @(-80, -64, 70, 26) }
    )
    notes = @(
        'Promoted from AS DXF/EMF import. Label strokes into layers.* when classifying parts.'
    )
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutJson) | Out-Null
[IO.File]::WriteAllText($OutJson, ($doc | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutJson ($($flat.Count) flat strokes)"
& (Join-Path $PSScriptRoot 'sync_strokes_to_godot.ps1')
