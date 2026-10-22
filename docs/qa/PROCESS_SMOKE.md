# Smoke самой QA-системы (не элементов)

Цель: за 15–20 минут убедиться, что ветки, STATUS и цикл «баг → PR → main» живы.  
Берём **одно простое** из STATUS, например `SEN-A1` / `demo_sensor_inductive.mechsim.json`.

## 1. Клон и ветки (оба)

- [ ] `git clone https://github.com/RomanSanych/mech-sim.git` → открывается в Godot 4
- [ ] Есть remote-ветки: `main`, `dev`, `qa/pass-1`
- [ ] Есть tag: `qa-baseline-2026-10-22` (`git fetch --tags && git show qa-baseline-2026-10-22`)

## 2. Роли не пересекаются

- [ ] **Roman:** `git checkout dev` — можно коммитить «фейковую» строку в черновик (или просто убедиться, что ветка есть)
- [ ] **QA:** `git checkout qa/pass-1` — видит `docs/qa/STATUS.md`, у SEN-A1 стоит `qa_not_done`

## 3. Мини-цикл QA (один человек или QA+Codex)

- [ ] От `qa/pass-1`: `git checkout -b qa/fix-process-smoke`
- [ ] Открыть демо индуктивного → Run (сцена вообще стартует)
- [ ] Сделать **крошечный** безопасный diff (например заметка в `STATUS.md`: SEN-A1 → `in_progress`, потом `passed` с текстом «process smoke»)  
  **Не** трогать `symbol_geom.gd` ради этого теста
- [ ] PR: `qa/fix-process-smoke` → **`main`** (не в `dev`)
- [ ] Merge PR на GitHub
- [ ] На `qa/pass-1`: `git merge origin/main` — подтянулся STATUS

## 4. Codex (опционально, 5 мин)

- [ ] Вставить промпт из `PROMPT_CODEX.md` с ID=`SEN-A1`, симптом=«process smoke only, update STATUS note»
- [ ] Модель **не** предлагает Write целиком на ядра; предлагает точечный diff / STATUS

## 5. Критерий «система ок»

| Ок | Провал |
|----|--------|
| Clone + Godot + три ветки + tag | Нет ветки/tag на remote |
| PR в `main` мержится | PR по ошибке в `dev` / конфликты без sync |
| STATUS обновляется в `main` и доезжает в `qa/pass-1` | STATUS только локально, remote пустой |
| Codex уважает no-wipe | Codex хочет переписать `symbol_geom` целиком |

Если всё зелёное — рабочий процесс готов; дальше настоящий QA по `SMOKE.md`.
