#Requires -Version 5.1
param(
    [string]$AsRoot = 'C:\Program Files\Famic Technologies\Automation Studio P7.0',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\out\il')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ilDumpDir = Join-Path $PSScriptRoot '..\il_dump'
$proj = Join-Path $ilDumpDir 'il_dump.csproj'
if (-not (Test-Path -LiteralPath $proj)) {
    throw "Missing il_dump project. Run setup from tools/as_extract/il_dump first."
}

$verinDll = Join-Path $AsRoot 'ASCFGVerin.dll'
$baseDll = Join-Path $AsRoot 'ASCFGBase.dll'

Push-Location $ilDumpDir
dotnet build -v q
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'il_dump build failed' }
Pop-Location

dotnet run --project $proj --no-build -- $verinDll $baseDll $OutDir
Write-Host "IL dump in $OutDir"
