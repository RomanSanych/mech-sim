# Извлечение УГО из Automation Studio P7.0 / ISO 1219

Пайплайн для **собранного** символа на схеме, не для иконок окна выбора.

Automation Studio заявляет соответствие **ISO 1219-1 / 1219-2**.
Сводка стандартов: [`STANDARDS.md`](STANDARDS.md).

## Предпочтительный путь сейчас: ISO 1219 SVG

Открытая геометрия (Wikimedia Commons, CC-BY-SA), тот же стандарт, что у AS:

```powershell
cd D:\mech-sim\tools\as_extract
.\scripts\import_iso1219_svg.ps1 -SvgPath .\out\iso1219_svg\double_acting.svg
# результат → out/strokes/*_iso1219.json; default уже в data/symbols/verin_default.json
```

## Почему не IL / BD AS

- `Dessiner*` защищены `AS.Sec.Controller` (заглушки `ret`).
- `BD/ASComponents.db` — закрытый формат; занятые БД не разбираем.

## Альтернатива: векторы из AS

Export diagram → DXF/EMF, или Ctrl+C → `capture_clipboard_emf.ps1`, затем
`import_dxf.ps1` / `import_emf.ps1` + `promote_import.ps1`.

## Таксономия AS (без геометрии)

```powershell
.\scripts\extract_taxonomy.ps1
.\scripts\extract_picker_index.ps1
.\scripts\extract_distributeur_taxonomy.ps1
```

Пневмораспределитель: `CFGDistributeur*.dll` + `ValveConfigurator/PortConfiguration.xml`
(готовые УГО в библиотеке Main.xml; слоты портов HAUT/BAS → `out/taxonomy/distributeur.json`).
`ASSpoolPosition.db` не разбираем.

## Godot

- `symbol_strokes.gd` → `res://data/symbols/verin_default.json`
- параметрическая отрисовка в `symbol_geom.gd` по layout ISO 1219
- плоский `strokes[]` (DXF/EMF bake) — только если импортирован отдельно

## Запреты

- Не копировать PNG/BAML/DLL AS в `res://`
- Не использовать picker-иконки как эталон штрихов
- Не обходить `AS.Sec.Controller`
- Не опираться на `.prx` и занятые `BD/*.db`
