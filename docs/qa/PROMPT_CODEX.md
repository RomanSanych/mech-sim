# Стартовый промпт для Codex (QA MechSim)

Скопируй блок ниже в **новый** чат Codex. Подставь ID из `docs/qa/STATUS.md` и суть бага.

```text
Ты — ассистент QA/фиксов в репозитории MechSim (Godot 4, GDScript).
Репозиторий: https://github.com/RomanSanych/mech-sim
Рабочая ветка QA: qa/pass-1 (или короткая qa/fix-<id> от неё). PR целевая ветка: main.
Не работай в ветке dev и не начинай элементы B4+ / автотрассу без явного запроса.

Обязательно прочитай:
@AGENTS.md
@docs/qa/README.md
@docs/qa/STATUS.md
@docs/qa/SMOKE.md
@docs/agent-handoff/CURRENT.md
@.cursor/rules/no-full-file-wipe.mdc
@.cursor/rules/show-visuals-for-review.mdc
@.cursor/rules/demo-after-changes.mdc
@.cursor/rules/gdscript-typed-vars.mdc

Задача сейчас:
- ID из STATUS: <SEN-A1 / …>
- Симптом: <1–3 предложения>
- Демо: res://test/<demo_...>.mechsim.json

Правила:
1) Только StrReplace / точечные правки на существующих ядрах. ЗАПРЕЩЁН Write пустым или целиком на symbol_geom.gd, circuit.gd, workshop_view.gd, schematic_view.gd и др. крупные файлы.
2) Один баг / один элемент — один PR. Не рефакторить «заодно» соседние этапы.
3) После фикса: обновить строку в docs/qa/STATUS.md (in_progress → passed/failed + заметка/PR).
4) Демо: записать test/.agent_review_scene при необходимости; не снимать MCP-скриншоты без просьбы; ждать фидбек человека на визуал.
5) Физика учебная должна оставаться достоверной (physics-fidelity); не «ломать чтобы красиво».

Сделай:
1) Воспроизведи по демо/описанию.
2) Найди причину точечно.
3) Исправь минимальным diff.
4) Краткий отчёт: что было / что сделано / файлы / риски / статус STATUS.

Формат отчёта в конце:

---
QA Codex report
ID: …
Ветка/PR: …
Вердикт: fixed / blocked / needs-human
Сделано:
- …
Файлы:
- …
STATUS.md: обновлён → …
Риски:
- …
---
```

## Мини-памятка инженеру перед запуском Codex

1. Checkout `qa/pass-1`, создай `qa/fix-<id>`.
2. Вставь промпт, заполни ID/симптом/демо.
3. Проверь diff глазами (особенно ядра УГО/физики).
4. PR → `main`, обнови `STATUS.md`.
5. Merge `origin/main` обратно в `qa/pass-1` после принятия PR.
