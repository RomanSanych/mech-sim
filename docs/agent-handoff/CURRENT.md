# CURRENT — точка продолжения

**Обновлено:** 2026-10-22  
**Этап плана:** датчики — **B4 термопара** (`dev`) + **QA pass-1** параллельно  
**GitHub:** https://github.com/RomanSanych/mech-sim (public) · Issues · ветка `bug-inbox`  
**Активный handoff:** `docs/agent-handoff/sensors.md`  
**QA:** `docs/qa/` — полный STATUS (все recipes) · SMOKE · bug-report in-app  
**Пауза:** электро автотрасса — `docs/agent-handoff/electro-autoroute.md`

## Ветки

| Ветка / tag | Назначение |
|-------------|------------|
| `main` | интеграция |
| `dev` | разработка (Roman), сейчас B4+ |
| `qa/pass-1` | QA + Codex по принятому |
| `qa-baseline-2026-10-22` | tag старта QA |

## Сейчас

- A1–A6, B1–B3: **ПРИНЯТО** (B3 — оговорка детального ре-ревью; УЗ-точность отложена). Все в `docs/qa/STATUS.md` = **`qa_not_done`**.
- Тепловизор/КЗ, моторы, ППЦ — в STATUS как `qa_not_done`.
- **B4 термопара** — следующий на `dev` (не в первом QA).
- Правило wipe: `.cursor/rules/no-full-file-wipe.mdc`.
- **Issue #3** (линия дверца↔датчик мимо КК/НШВИ): фикс `_wire_is_door_cabinet_span` на `main` — ждём визуальный фидбек. Демо: `res://test/bug3_door_wire.mechsim.json`.

## Следующий шаг

1. Roman: подтвердить #3 в 3D → закрыть issue.  
2. Roman: `dev` → MVP B4 (промпт оркестратора ранее).  
3. QA: clone → `qa/pass-1` → [`docs/qa/README.md`](../qa/README.md) + Codex [`PROMPT_CODEX.md`](../qa/PROMPT_CODEX.md).

## Не трогать без запроса

- Автотрасса / WIP эталон; Write на ядра; смешивать QA-фиксы и B4 в одном PR.
