# Handoff: поворотные ПЦ и пневмомоторы

## Цель этапа

Учебные поворотные пневмоцилиндры, затем пневмомоторы — по одному классу: демо → одобрение пользователя → дальше.

## Статус подэтапов

| Подэтап | Статус | Демо / якоря |
|---------|--------|----------------|
| ППЦ рейка–шестерня | Принят | `iso_rotary_rack.gd`, УГО вертикальные tips с DXF |
| ППЦ лопастной | Принят | `iso_rotary_vane.gd` |
| ПМ шестерённый (gear) | **Принят** | `demo_air_motor_gear.mechsim.json` — якорь stall, scale 3D, без пресетов-классов |
| ПМ лопастной (vane) | **Принят** | `demo_air_motor_vane.mechsim.json` — якорь stall, U-корпус, скользящие лопатки, без пресетов-классов |
| ПМ турбина | **Принят** | `demo_air_motor_turbine.mechsim.json` + `demo_air_motor_reverse.mechsim.json`; раздельные порты in/exhaust |

## Зафиксированные решения (не откатывать без причины)

### УГО пневмомотора (реверсивный)

- Источники: пользовательские DXF (`Проект1_Схема1.dxf` — треугольники; `123.dxf` — стрелка вокруг вала). Штрихи: `tools/as_extract/out/strokes/air_motor_*.json`, канон пропорций `data/symbols/air_motor_ugo.json`.
- Внутри круга: **два полых треугольника навстречу** (не дуга «нереверсивного» мотора).
- Вал **вверх**, неподвижный; при ω ≠ 0 — **дуга-стрелка вокруг вала**, вал не орбитирует.
- Tips на `SCH_GRID`; порты на **одной оси с центром круга** (не смещать круг относительно линии).
- Масштаб: tips ±40 (`4×SCH_GRID`), круг ~r=24.8.
- Bake-сигнатура УГО: `geom_ver` для air_motor в `schematic_ugo_layer.gd` (bump при смене штрихов).

### 3D шестерённый ПМ

- Файл: `scripts/view3d/iso_air_motor_gear.gd`.
- Корпус: stadium (прямоугольник + скругление коротких сторон по Z).
- Полости: два цилиндра (высота ≈ шестерни, Ø чуть больше).
- Каналы ±X к зацеплению; слева/справа штуцер или глушитель.
- Шестерни: геометрия как у рейка-ПЦ (`IsoRotaryRack._add_pinion` / `_add_output_shaft`); зацепление; шлиц вверх / вниз; оси валов ⊥ оси каналов, равноудалены от канала.
- Отверстия под валы + **подшипники** на выходах (не крутятся с валом).
- Глушитель: только `Parts.add_silencer` (широким к корпусу).
- Рентген: корпус `window`; после CSG-bake сбрасывать `xray_ok`.

### 3D лопастной ПМ

- Диспетчер: `scripts/view3d/iso_air_motor.gd` → gear / vane / turbine по `rotary_class`.
- Файл: `scripts/view3d/iso_air_motor_vane.gd`.
- Корпус сверху «перевёрнутая U»; верх/низ — один CSG `window` (без отдельной крышки).
- Полость: эксцентричная; t_min (ближний зазор) как у базы; ход (t_max−t_min) ×0.75.
- Штуцеры на плоской грани (−Z), ниже, оси в зону задвинутых лопаток; глушитель `Parts.add_silencer`.
- Ротор с пазами; лопатки фикс. длины = (t_min−clear)−дно_паза; сдвиг в пазу до стенки; каблук для чтения хода.
- Масштаб: `MotorCat.geom_scale` от stall.
- Физика угла 3D: `ANGLE_VIS` / `MotorCat.angle_vis_factor` в `_integrate_air_motor`.

### 3D турбинный ПМ

- Файл: `scripts/view3d/iso_air_motor_turbine.gd`.
- Корпус: цилиндр; камера CSG `window` по высоте колеса.
- Колесо: хаб + диск + радиальные лопатки (ковш); без TorusMesh-обода и без сопловых боксов.
- Каждый порт in/exhaust — глушитель (`Parts.add_silencer`) или штуцер; scale от stall.
- Вал: `Rack._add_output_shaft` (как у gear/vane).
- Каталог: те же якоря stall 1/2/4AM; free_rpm выше; Qn ≈0.6× vane (Deprag/Atlas ~+40% КПД).
- `angle_vis_factor` для турбины ∝ 1/free_rpm — учебный угол; ω для tip/Qn не ломается.

### Физика / свойства

- `circuit.gd`: `_integrate_air_motor` — реверс по знаку dp; ω в ±w_free.
- UI свойств: якорь **момент стоп @6 бар** (без выпадающего «класса/пресета»); rpm/Qn подставляются из таблицы при смене stall и остаются редактируемыми; присоединение; **порт in (`port_5`) и port exhaust (`port_3`)** — глушитель/штуцер по отдельности.
- Демо реверса/давления: `test/demo_air_motor_reverse.mechsim.json` (КР1→in, КР2→exhaust, оба штуцера).
- 3D-sig включает `torque_nm_at_6bar` → пересборка меша при смене stall; `MotorCat.geom_scale` масштабирует корпус+шестерни.
- Каталог (данные, не меню): `data/motor/recipes.json`, `motor_catalog.gd` (`apply_stall_anchor`), `motor_library.gd` (спавн из библиотеки).

### УГО / провода (фон этапа)

- Tips портов на сетке; короткие маршруты — учитывать соседние сегменты (`wire_router_2d`).
- Рентген: только окно над динамикой (`xray-window-only`).

## Ключевые файлы

```
scripts/domain/symbol_geom.gd          # УГО air_motor
scripts/domain/circuit.gd              # _integrate_air_motor, flow
scripts/domain/motor_catalog.gd
scripts/domain/motor_library.gd
scripts/view3d/iso_air_motor.gd        # диспетчер gear/vane/turbine
scripts/view3d/iso_air_motor_gear.gd
scripts/view3d/iso_air_motor_vane.gd
scripts/view3d/iso_air_motor_turbine.gd
scripts/view3d/iso_rotary_rack.gd      # шестерня/вал-донор
scripts/view3d/pneumo_parts.gd         # add_silencer
scripts/ui/schematic_view.gd           # _add_general_motor_params
scripts/ui/schematic_ugo_layer.gd      # bake sig am*
test/demo_air_motor_gear.mechsim.json
test/demo_air_motor_vane.mechsim.json
test/demo_air_motor_turbine.mechsim.json
data/symbols/air_motor_ugo.json
data/motor/recipes.json
```

## Камера демо

В `main_shell.gd` для path с `air_motor`: `aim_review_point` на мотор (не cabinet).

## Типичные ошибки (уже были)

- Вал УГО орбитирует / рисуется вниз при требовании «вверх».
- Смещение оси портов относительно центра круга.
- Глушитель узким к корпусу (самодельный CylinderMesh).
- Оценка 3D по MCP-скриншотам вместо фидбека пользователя.
- UI только «типоразмер» без рабочих параметров.
- Камера демо уезжает в щит без `aim_review_point` для air_motor.
