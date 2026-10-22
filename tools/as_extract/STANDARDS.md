# Fluid-power UGO standards map (MechSim)

Automation Studio (Famic) declares pneumatic/hydraulic libraries compliant with
**ISO 1219-1** (symbols) and **ISO 1219-2** (circuit diagrams / functional groups).
MechSim cylinder УГО is rebuilt from that family.

## Primary (what AS uses)

| Standard | Role |
|----------|------|
| **ISO 1219-1:2012** (+ Amd.1:2016) | Graphical symbols for fluid power; fixed CAD dimensions (Annex A) |
| **ISO 1219-2** | Circuit diagrams, functional groups |
| **DIN ISO 1219-1:2019** | German adoption of ISO 1219-1:2012 + Amd.1 |

## Related

| Standard | Role |
|----------|------|
| ISO 14617 | General graphical symbols; ISO 1219-1 is a collective application of this series |
| CETOP | European fluid-power symbols; effectively follows ISO 1219 |
| GOST 2.782-96 | ЕСКД cylinders / pumps / motors (machines) |
| GOST 2.781-96 | ЕСКД valves / controls (aligned with ISO 1219-91) |
| GOST 2.780-96 | Pipelines / connections (used in MechSim library notes) |

## Open geometry source

Wikimedia Commons [Category:ISO 1219](https://commons.wikimedia.org/wiki/Category:ISO_1219)
(CC-BY-SA). Import:

```powershell
cd tools/as_extract
.\scripts\import_iso1219_svg.ps1 -SvgPath .\out\iso1219_svg\double_acting.svg
```

Committed default: `data/symbols/verin_default.json` (double-acting ISO geometry).
