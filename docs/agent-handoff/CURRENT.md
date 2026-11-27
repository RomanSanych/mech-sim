# CURRENT — точка продолжения

**Обновлено:** 2026-10-22  
**Этап плана:** датчики — **B4 термопара** + **QA pass-1** параллельно  
**GitHub:** https://github.com/RomanSanych/mech-sim (public) · Issues · ветка `bug-inbox`  
**Активный handoff:** `docs/agent-handoff/sensors.md`  
**QA:** `docs/qa/` — полный STATUS (все recipes) · SMOKE · bug-report in-app  
**Пауза:** электро автотрасса — `docs/agent-handoff/electro-autoroute.md`

## Ветки

| Ветка / tag | Назначение |
|-------------|------------|
| `main` | единственная рабочая линия (main-only), только PR |
| `bug-inbox` | вложения баг-репортов из приложения |
| `qa-baseline-2026-10-22` | tag старта QA |

Бывшие `dev` и `qa/pass-1` удалены (2026-11-27, переход на main-only). Фичи и фиксы — свежие ветки от `main` → PR в `main`.

## Сейчас

- A1–A6, B1–B3: **ПРИНЯТО** (B3 — оговорка детального ре-ревью; УЗ-точность отложена). Все в `docs/qa/STATUS.md` = **`qa_not_done`**.
- Тепловизор/КЗ, моторы, ППЦ — в STATUS как `qa_not_done`.
- **B4 термопара** — следующий на `dev` (не в первом QA).
- Правило wipe: `.cursor/rules/no-full-file-wipe.mdc`.
- **Issue #3** (дверца↔датчик / КК / НШВИ): **CLOSED** — фикс `d285ecd` на всех ветках. Демо: `res://test/bug3_door_wire.mechsim.json`.
- Правило: фикс бага → сразу close Issue (`.cursor/rules/bug-fix-close-issue.mdc`).

## Следующий шаг

1. Roman: ветка от `main` → MVP B4 (промпт оркестратора ранее).  
2. QA: clone → свежий `main` → [`docs/qa/README.md`](../qa/README.md) + Codex [`PROMPT_CODEX.md`](../qa/PROMPT_CODEX.md).

## Не трогать без запроса

- Автотрасса / WIP эталон; Write на ядра; смешивать QA-фиксы и B4 в одном PR.
