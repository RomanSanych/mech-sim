# MechSim — вход для агентов

Читай **в этом порядке** при старте чата/задачи:

1. Этот файл (обзор).
2. `docs/agent-handoff/CURRENT.md` — где остановились.
3. Handoff нужного этапа из `docs/agent-handoff/`.
4. Правила в `.cursor/rules/` (подхватываются автоматически; ниже — оглавление).

Работаем **только в этом репозитории**. Не начинай этап «с нуля» игнорируя handoff.

## Как стартовать задачу

В первом ответе, если цель неочевидна, спроси коротко:

- что считать готовым в этом ходе;
- продолжать чат или открыть **новый** (см. `.cursor/rules/agent-workflow.mdc`);
- какая демо-сцена.

Шаблон старта нового чата (скопируй пользователю при необходимости):

```text
Продолжаем MechSim по handoff.
@AGENTS.md @docs/agent-handoff/CURRENT.md @docs/agent-handoff/<этап>.md
Задача: <одна фраза>
Демо: <res://test/...>
Не оценивай визуал скриншотами — жду мой фидбек.
```

## Правила (`.cursor/rules/`)

| Файл | Суть |
|------|------|
| `agent-workflow.mdc` | Новый чат / уточнения / токены / обновление handoff |
| `show-visuals-for-review.mdc` | Правка → демо → фидбек пользователя; без цикла скриншотов |
| `demo-after-changes.mdc` | `.agent_review_scene` + `run_scene` |
| `ugo-ports-on-grid.mdc` | Tips портов на `SCH_GRID` |
| `xray-window-only.mdc` | Рентген только над динамикой |
| `physics-fidelity.mdc` | Физика, не «красивая» анимация |
| `manufacturer-params.mdc` | Параметры из каталогов / рабочие величины |
| `muffler-wide-to-body.mdc` | Глушитель широким к корпусу (`Parts.add_silencer`) |
| `pneumo-one-port-one-tube.mdc` | Один пневмопорт — одна трубка |
| `gdscript-typed-vars.mdc` | Явные типы из Variant |
| `ask-before-searching.mdc` | УГО: as-extract / taxonomy; не гадать |
| `no-full-file-wipe.mdc` | **Запрет** `Write` целиком/пустым на существующие ядра (инцидент symbol_geom) |

Skill УГО: `.cursor/skills/as-extract/SKILL.md`.

## Где код и демо

- УГО: `scripts/domain/symbol_geom.gd`, `data/symbols/*.json`
- 3D: `scripts/view3d/iso_*.gd`, `pneumo_parts.gd`
- Физика: `scripts/domain/circuit.gd`, каталоги `*_catalog.gd`
- Демо: `test/*.mechsim.json`, маркер `test/.agent_review_scene`

## Токены (кратко)

Сделал → открыл демо → написал что изменилось → **стоп**. Визуал оценивает пользователь. Не крутить MCP-скриншоты без прямого «сделай скрин».
