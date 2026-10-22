# Perf: плотный щит — корневые причины и рычаги

**Обновлено:** 2026-10-15  
**Демо:** `res://test/demo_cabinet_dense.mechsim.json`

## Диагноз

- Physics ~0 ms — узкое место **GPU draw calls** (Compatibility) + **CPU Base/WireRouter**.
- Каждый `Parts.box` / кембрик / НШВИ ≈ 1 DC.
- Раньше ~3800 DC / ~37 FPS; каналы → MultiMesh; tube batch; Label3D off.

## Сделано в этом проходе

1. Edit hover → **только Live** (не полный Base).
2. Dense: **MultiMesh** кембриков / колпачков / гильз НШВИ (`_sync_dense_tip_batch`).
3. Dense: merge **shell**-mesh модуля в 1–N ArrayMesh (`_merge_dense_module_shells`, cab_ver 25).
4. Без `stretch_shrink` (мыло откатили).

## Следующие рычаги

- Дальше резать internal/control MI у клемм/АВ, если FPS < 60.
- Пространственный индекс pick / `_element_hits`.
- Texture/decal вместо Label3D на кембрике (когда снова включим номера).
