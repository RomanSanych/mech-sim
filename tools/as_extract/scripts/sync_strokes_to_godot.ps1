#Requires -Version 5.1
param(
    [string]$StrokesDir = (Join-Path $PSScriptRoot '..\out\strokes'),
    [string]$GodotDir = (Join-Path $PSScriptRoot '..\..\..\data\symbols'),
    # Default: only production symbol JSON (skip smoke_*/scratch)
    [string]$Filter = 'verin_default.json;cylinder.from_as*.json;cylinder_from_as*.json'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $GodotDir | Out-Null
$patterns = $Filter.Split(';') | Where-Object { $_ -ne '' }
Get-ChildItem -LiteralPath $StrokesDir -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.Name
    $ok = $false
    foreach ($pat in $patterns) {
        if ($name -like $pat) { $ok = $true; break }
    }
    if (-not $ok) {
        Write-Host "Skip $name"
        return
    }
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $GodotDir $_.Name) -Force
    Write-Host "Copied $name -> $GodotDir"
}
