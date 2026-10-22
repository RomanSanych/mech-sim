# CURRENT — точка продолжения

**Обновлено:** 2026-10-22  
**Этап плана:** датчики — **B4 термопара** (разработка на `dev`) + **QA pass-1** параллельно  
**GitHub:** https://github.com/RomanSanych/mech-sim (public)  
**Активный handoff:** `docs/agent-handoff/sensors.md`  
**QA:** `docs/qa/` — STATUS / SMOKE / README / PROMPT_CODEX  
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

## Следующий шаг

1. Roman: `dev` → MVP B4 (промпт оркестратора ранее).  
2. QA: clone → `qa/pass-1` → [`docs/qa/README.md`](../qa/README.md) + Codex [`PROMPT_CODEX.md`](../qa/PROMPT_CODEX.md).

## Не трогать без запроса

- Автотрасса / WIP эталон; Write на ядра; смешивать QA-фиксы и B4 в одном PR.
