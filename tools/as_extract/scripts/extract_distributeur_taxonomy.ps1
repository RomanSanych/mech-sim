#Requires -Version 5.1
param(
    [string]$AsRoot = 'C:\Program Files\Famic Technologies\Automation Studio P7.0',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\out\taxonomy')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$portXml = Join-Path $AsRoot 'ValveConfigurator\PortConfiguration.xml'
$mainXml = Join-Path $AsRoot 'Main.xml'
if (-not (Test-Path -LiteralPath $portXml)) {
    throw "PortConfiguration.xml not found: $portXml"
}

Copy-Item -LiteralPath $portXml -Destination (Join-Path $OutDir 'PortConfiguration.xml') -Force

[xml]$px = Get-Content -LiteralPath $portXml
$families = @()
foreach ($t in $px.SelectNodes('//DISTRIBUTEUR[@type="Pneumatique"]/TIROIR')) {
    $p = $t.PARAMETRE
    $ports = @()
    foreach ($port in $t.PORT) {
        $ports += @{
            side = [string]$port.emplacement
            slot = [int]$port.position
            xml_nom = [string]$port.nom
        }
    }
    $families += @{
        id_famille_iso = [string]$p.IDFamilleISO
        taille_tiroir = [int]$p.tailleTiroir
        nom_tiroir = [string]$p.nomTiroir
        ports = $ports
    }
}

# Pneumatique xml noms are sequential; map to ISO 1219 numbers via hydraulic names of same slots.
$isoMap = @{
    VDT2 = @(
        @{ iso = '1'; side = 'BAS'; slot = 2 }
        @{ iso = '2'; side = 'HAUT'; slot = 2 }
    )
    VDT3 = @(
        @{ iso = '1'; side = 'BAS'; slot = 1 }
        @{ iso = '2'; side = 'HAUT'; slot = 1 }
        @{ iso = '3'; side = 'BAS'; slot = 3 }
    )
    VDT4 = @(
        @{ iso = '1'; side = 'BAS'; slot = 1 }
        @{ iso = '2'; side = 'HAUT'; slot = 1 }
        @{ iso = '4'; side = 'HAUT'; slot = 3 }
        @{ iso = '3'; side = 'BAS'; slot = 3 }
    )
    VDT5 = @(
        @{ iso = '3'; side = 'BAS'; slot = 1 }
        @{ iso = '2'; side = 'HAUT'; slot = 1 }
        @{ iso = '4'; side = 'HAUT'; slot = 5 }
        @{ iso = '5'; side = 'BAS'; slot = 5 }
        @{ iso = '1'; side = 'BAS'; slot = 3 }
    )
}

$dlls = @('CFGDistributeur.dll', 'CFGDistributeur2.dll', 'CFGDistributeur3.dll') |
    ForEach-Object { Join-Path $AsRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ }

$doc = [ordered]@{
    source = @{
        extracted_at = (Get-Date).ToString('o')
        as_root = $AsRoot
        port_configuration = 'ValveConfigurator/PortConfiguration.xml'
        configurator_dlls = $dlls
        spool_db = 'ValveConfigurator/ASSpoolPosition.db'
        note = 'AS ValveConfigurator composes concrete tiroir + commande symbols from BD. Do not parse occupied/locked BD. Port grid from PortConfiguration Pneumatique.'
    }
    pneumatique_families_raw = $families
    pneumatique_iso_ports = $isoMap
    slot_formula = 'x = xa + (slot / taille_tiroir) * square_w'
    center_types_as = @('NC', 'Float Type', 'Open Type', 'Tandem Type')
    center_map_mechsim = @{
        NC = 'closed'
        'Open Type' = 'exhausted'
        'Float Type' = 'floating'
        'Tandem Type' = 'exhausted'
        # pressurized (P→A,B) is a separate pneumatic centre; AS library often names it explicitly
    }
}
$doc | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutDir 'distributeur.json') -Encoding UTF8

if (Test-Path -LiteralPath $mainXml) {
    [xml]$xml = Get-Content -LiteralPath $mainXml -Encoding Default
    $valves = @()
    foreach ($n in $xml.SelectNodes('//Compo')) {
        $name = [string]$n.Name
        $type = [string]$n.ID_TYPE
        if ($name -match '^\d/\d' -or $type -match '^(269|280)') {
            $valves += @{
                name = $name
                atelier = [string]$n.ID_ATELIER
                famille = [string]$n.ID_FAMILLE
                type = $type
            }
        }
    }
    @{
        source = @{ main_xml = $mainXml; extracted_at = (Get-Date).ToString('o') }
        note = 'Prebuilt directional valve library recipes (concrete full UGO). Builder entries (#TtDirectionalValveBuilder*) compose via CFGDistributeur.'
        valves = $valves
    } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutDir 'distributeur_library.json') -Encoding UTF8
}

Write-Host "OK -> $OutDir\distributeur.json"
