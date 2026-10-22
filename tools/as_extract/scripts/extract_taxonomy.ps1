#Requires -Version 5.1
param(
    [string]$AsRoot = 'C:\Program Files\Famic Technologies\Automation Studio P7.0',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\out\taxonomy')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$verinDll = Join-Path $AsRoot 'ASCFGVerin.dll'
$mainXml = Join-Path $AsRoot 'Main.xml'

if (-not (Test-Path -LiteralPath $verinDll)) {
    throw "ASCFGVerin.dll not found: $verinDll"
}

function Get-EnumMap {
    param([Reflection.Assembly]$Asm, [string]$EnumName)
    $t = $Asm.GetTypes() | Where-Object { $_.Name -eq $EnumName } | Select-Object -First 1
    if (-not $t) { return @{} }
    $map = @{}
    foreach ($n in [enum]::GetNames($t)) {
        $map[$n] = [int][enum]::Parse($t, $n)
    }
    return $map
}

$ver = [Reflection.Assembly]::LoadFrom($verinDll)

$drawMethods = @()
$symType = $ver.GetType('ASCFGVerin.View.Symbols')
if ($symType) {
    $symType.GetMethods([Reflection.BindingFlags]'Public,NonPublic,Instance,Static,DeclaredOnly') |
        Where-Object { $_.Name -match '^Dessiner|^Draw' } |
        ForEach-Object { $drawMethods += $_.Name }
}

$resourceNames = @()
$stream = $ver.GetManifestResourceStream('ASCFGVerin.g.resources')
if ($stream) {
    $rr = New-Object System.Resources.ResourceReader($stream)
    $e = $rr.GetEnumerator()
    while ($e.MoveNext()) { $resourceNames += [string]$e.Key }
    $rr.Close()
}

$cylinders = @()
if (Test-Path -LiteralPath $mainXml) {
    [xml]$xml = Get-Content -LiteralPath $mainXml -Encoding Default
    $nodes = $xml.SelectNodes('//Compo[contains(@Name,"Cylinder") or contains(@Name,"cylinder")]')
    foreach ($n in $nodes) {
        $cylinders += @{
            name = [string]$n.Name
            id_atelier = [string]$n.ID_ATELIER
            id_famille = [string]$n.ID_FAMILLE
            id_type = [string]$n.ID_TYPE
        }
    }
}

$mechSimFields = @{
    piston_kind = @{
        field = 'piston_kind'
        options = @(
            @{ as = 'ePSimple'; id = 'simple' }
            @{ as = 'ePDouble'; id = 'double' }
            @{ as = 'ePLarge'; id = 'wide' }
            @{ as = 'ePMagnetic'; id = 'magnetic' }
            @{ as = 'ePSimplifie'; id = 'simplified' }
        )
    }
    cush_cap = @{
        field = 'cush_cap'
        side = 'cap'
        options = @(
            @{ as = 'eASans'; id = 'none' }
            @{ as = 'eAGaucheFixe'; id = 'fixed' }
            @{ as = 'eAGaucheReglable'; id = 'adjustable' }
        )
    }
    cush_rod = @{
        field = 'cush_rod'
        side = 'rod'
        options = @(
            @{ as = 'eASans'; id = 'none' }
            @{ as = 'eADroiteFixe'; id = 'fixed' }
            @{ as = 'eADroiteReglable'; id = 'adjustable' }
        )
    }
    spring = @{
        field = 'spring_side'
        options = @(
            @{ as = 'leftspring'; id = 'cap' }
            @{ as = 'rightspring'; id = 'rod' }
            @{ as = 'none'; id = 'none' }
        )
    }
    port = @{
        fields = @('port_cap', 'port_rod')
        options = @(
            @{ as = 'eESSans'; id = 'connect' }
            @{ as = 'eESTriangle'; id = 'exhaust' }
        )
    }
    rod_mode = @{
        field = 'rod_mode'
        from_ETypeVerin = @{
            eVDoubleEffet = 'single'
            eVDoubleTige = 'through'
            eVSansTige = 'rodless'
            eVSimpleEffet = 'single'
            eVSimpleEffetInverse = 'single'
        }
    }
    brake = @{
        field = 'brake'
        options = @(
            @{ as = 'eFSans'; id = 'none' }
            @{ as = 'eFNormalementOuvert'; id = 'no' }
            @{ as = 'eFNormalementFerme'; id = 'nc' }
            @{ as = 'eFDoubleEffet'; id = 'double' }
        )
    }
    carriage = @{
        field = 'carriage'
        options = @(
            @{ as = 'eESans'; id = 'none' }
            @{ as = 'eEChariot'; id = 'plain' }
            @{ as = 'eEMagnetique'; id = 'magnetic' }
        )
    }
    rod_end = @{
        field = 'rod_end'
        options = @(
            @{ as = 'eESans'; id = 'plain' }
            @{ as = 'eEFiletageExt'; id = 'male' }
            @{ as = 'eEFiletageInt'; id = 'female' }
            @{ as = 'eEGalet'; id = 'roller' }
            @{ as = 'eEPelle'; id = 'clevis' }
        )
    }
}

$doc = @{
    source = @{
        verin_dll = $verinDll
        main_xml = $mainXml
        extracted_at = (Get-Date).ToString('o')
    }
    assembly = @{
        draw_methods = ($drawMethods | Sort-Object -Unique)
        type_symbol_enum = (Get-EnumMap $ver 'TypeSymbolEnum')
        type_verin_enum = (Get-EnumMap $ver 'ETypeVerin')
    }
    enums = @{
        EPiston = (Get-EnumMap $ver 'EPiston')
        EAmortissement = (Get-EnumMap $ver 'EAmortissement')
        EEchappement = (Get-EnumMap $ver 'EEchappement')
        EFrein = (Get-EnumMap $ver 'EFrein')
        EChariot = (Get-EnumMap $ver 'EChariot')
        EEmbout = (Get-EnumMap $ver 'EEmbout')
    }
    main_library_cylinders = $cylinders
    picker_resource_keys = ($resourceNames | Sort-Object)
    mech_sim_mapping = $mechSimFields
    notes = @(
        'Picker PNG keys are UI only, not assembled symbol strokes.'
        'Assembled UGO is drawn by ASCFGVerin.View.Symbols Dessiner* and SymbolBase.OnRender.'
    )
}

$outPath = Join-Path $OutDir 'verin.json'
[System.IO.File]::WriteAllText($outPath, ($doc | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $outPath"
