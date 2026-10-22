---
name: as-extract
description: Extract Automation Studio P7.0 / ISO 1219 schematic symbol taxonomy and geometry for MechSim. Use when drawing UGO, configurator parts, or integrating Famic cylinder/valve symbols. Prefer ISO 1219 Commons SVG via import_iso1219_svg.ps1; AS DXF/EMF as alternate. Read STANDARDS.md, out/taxonomy, data/symbols JSON.
---

# AS / ISO 1219 extract pipeline

## What Automation Studio uses

Famic documents **ISO 1219-1** (symbols) and **ISO 1219-2** (circuits).
See `tools/as_extract/STANDARDS.md`.

## Preferred geometry: ISO 1219 open SVG

```powershell
cd tools/as_extract
.\scripts\import_iso1219_svg.ps1 -SvgPath .\out\iso1219_svg\double_acting.svg
```

Source: [Wikimedia Commons ISO 1219](https://commons.wikimedia.org/wiki/Category:ISO_1219) (CC-BY-SA).
Default bake: `data/symbols/verin_default.json` → `symbol_geom.gd` constants/layout.

## Alternate: AS official export

DXF/EMF Export diagram or clipboard EMF (`capture_clipboard_emf.ps1`) →
`import_dxf.ps1` / `import_emf.ps1` → `promote_import.ps1`.

Do **not** decrypt `AS.Sec.Controller` or locked `BD/*.db`.

## Taxonomy

```powershell
.\scripts\extract_taxonomy.ps1
.\scripts\extract_picker_index.ps1
```

## Godot

- `symbol_strokes.gd` loads `res://data/symbols/verin_default.json`
- Parametric draw uses ISO layout; top-level `strokes[]` only for AS DXF/EMF bake
