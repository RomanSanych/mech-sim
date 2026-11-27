# ONBOARDING — новый разработчик MechSim

Точка входа: подключение к git, запуск, проверка, безопасный workflow и промт для твоей нейросети.  
Владелец проекта: **Roman** (RomanSanych). Вопросы по «так задумано или баг» — к нему и в `docs/agent-handoff/CURRENT.md`.

## 1. Что это

**MechSim** — учебный симулятор пневмо- и электросхем: 2D-схема (УГО ISO 1219 + электро) + 3D-цех + физика (давление, золотники, штоки, сеть 24 V/220 V, датчики). Движок — **Godot 4.7**, репозиторий — https://github.com/RomanSanych/mech-sim (public).

До первого коммита прочитай: [`AGENTS.md`](../AGENTS.md), [`docs/agent-handoff/CURRENT.md`](agent-handoff/CURRENT.md), правила в [`.cursor/rules/`](../.cursor/rules/).

## 2. Подключение к git

Установи: **Git**, **Godot 4.7** (версия важна — проект привязан к 4.x), опционально **GitHub CLI** (`gh`) для работы с Issues.

```bash
git config --global user.name "Имя Фамилия"
git config --global user.email "you@example.com"

# Вариант A — Roman дал доступ к репозиторию:
git clone https://github.com/RomanSanych/mech-sim.git
cd mech-sim

# Вариант B — без доступа: сделай fork на GitHub, затем:
git clone https://github.com/<you>/mech-sim.git
cd mech-sim
git remote add upstream https://github.com/RomanSanych/mech-sim.git
```

Репозиторий ~350 МБ (CAD-референсы). Команды — из Git Bash / любого терминала.

## 3. Первый запуск и проверка

1. Godot → Import → папка клона → Run (F5). Откроется `scenes/main.tscn`. При первом запуске Godot создаст `.godot/` — он в `.gitignore`, **не коммитить**.
2. Открой демо-сцену: в приложении **Файл → Открыть**, или из терминала:
   `godot --path . -- --open=res://test/demo_sensor_inductive.mechsim.json`
3. Дымовые сцены (все в `res://test/`):

| Группа | Сцены |
|--------|-------|
| Датчики, принято (A1–B3) | `demo_sensor_inductive` / `_reed` / `_capacitive` / `_optical` / `_ultrasonic` / `_pressure_switch` / `_pressure_transmitter` / `_rtd` (суффикс `.mechsim.json`) |
| Электро / дверца | `demo_door_harness`, `bug3_door_wire` |
| Пневматика | `demo_air_motor_gear`, `demo_adapter` и остальные в `test/` |

4. Критерий «проект жив»: сцена открывается, Play запускает симуляцию (давление, золотники, LED датчиков, электросеть). Полный чек-лист — [`docs/qa/SMOKE.md`](qa/SMOKE.md).

## 4. Как работать, чтобы не уронить проект

Ветки: `main` — интеграция (**только через PR**), `dev` — разработка новых элементов, `qa/pass-1` — QA-фиксы принятого, `bug-inbox` — вложения баг-репортов из приложения.

Жёсткие правила:

1. **Никогда не пушь в `main`.** Одна задача/баг = одна ветка (фичи — от `dev`, QA-фиксы — от `qa/pass-1`) → PR в `main`.
2. Перед пушем: `git fetch` и подтяни базу (`git pull` / merge `origin/main`). Никакого force-push в общие ветки.
3. Не коммить служебное: `.godot/`, `exports/`, `tmp_*`, кэш `addons/godot_mcp/cache/` (он уже вычищается из репо).
4. Перед коммитом — `git status`: не должно быть логов, скриншотов, локальных маркеров (`test/.agent_review_scene` уже в `.gitignore`).
5. **Ядра не затирать целиком** — `scripts/domain/circuit.gd`, `scripts/view3d/workshop_view.gd`, `scripts/domain/symbol_geom.gd`, `scripts/app/main_shell.gd`: только точечные правки (правило `no-full-file-wipe.mdc`).
6. Не трогать без запроса Roman: электро-автотрасса, WIP-эталон кабинета.
7. Не начинай элементы из «очереди» handoff (B5, C1a…), пока Roman не попросил. Актуальный фокус — в `docs/agent-handoff/CURRENT.md`.
8. Баг из приложения: **Помощь → «Сообщить об ошибке…»** → GitHub Issue. Фикс = ветка + PR + сразу close Issue (правило `bug-fix-close-issue.mdc`). QA-процесс целиком — [`docs/qa/README.md`](qa/README.md).

Если локально что-то пошло не так — `git stash` или переклонирование. Удалённо сломать можно только force-push'ем, которого мы не делаем.

## 5. Промты для твоей нейросети

### 5.1 Стартовый промт (первый чат — развёртывание)

Создай новый чат в Kimi Code (или другом агенте) и вставь целиком:

```text
Ты — агент в проекте MechSim (учебный симулятор пневмо-/электросхем, Godot 4.7).
Задача этого чата: развернуть проект у меня локально и подготовить рабочее место.
Код пока НЕ меняем.

Шаги:
1. Спроси у меня: имя и email для git (настрой git config), папку для клона
   и моё короткое имя для ветки (согласуй с Roman, по умолчанию dev-<имя>).
2. Склонируй https://github.com/RomanSanych/mech-sim.git — у меня есть доступ
   collaborator. Проверь git status и ветки.
3. Создай мою ветку от dev: git checkout -b dev-<имя> origin/dev и запушь её
   (git push -u origin dev-<имя>). Работаем только в ней.
4. Проверь, что установлен Godot 4.7 (godot --version или спроси меня).
   Если нет — скажи установить с https://godotengine.org/download и жди.
5. Прочитай: AGENTS.md, docs/ONBOARDING.md, docs/agent-handoff/CURRENT.md,
   правила .cursor/rules/ (особенно no-full-file-wipe.mdc,
   show-visuals-for-review.mdc, bug-fix-close-issue.mdc).
6. Открой проект в Godot, запусти главную сцену и демо
   res://test/demo_sensor_inductive.mechsim.json — убедись, что симуляция
   запускается (давление, LED датчиков).
7. В конце напиши: что развернуто, какая ветка активна, какие правила усвоены.

Жёсткие правила с первого дня:
- Никогда не пушить в main. Одна задача = одна ветка от dev-<имя> → PR в main.
- Перед пушем: git fetch + merge origin/main, без force-push.
- Не затирать целиком scripts/domain/circuit.gd, scripts/view3d/workshop_view.gd,
  scripts/domain/symbol_geom.gd, scripts/app/main_shell.gd — только точечные правки.
- Не коммитить .godot/, exports/, tmp_*, addons/godot_mcp/cache/.
- Не трогать электро-автотрассу и WIP-эталон кабинета без запроса Roman.
- Визуал не оценивай скриншотами — покажи демо и жди мой фидбек.
```

### 5.2 Рабочий промт (каждая следующая задача — новый чат)

```text
Продолжаем MechSim по handoff.
@AGENTS.md @docs/agent-handoff/CURRENT.md @docs/agent-handoff/<этап>.md
Задача: <одна фраза>
Демо: <res://test/...>
Не оценивай визуал скриншотами — жду мой фидбек.
```

`<этап>.md` — файл handoff из `docs/agent-handoff/` (какой именно — смотри в `CURRENT.md`; сейчас актуален `sensors.md`).

Как пользоваться:

- **Стартовый промт — один раз** на машину; дальше — рабочий промт, **новый чат на каждую задачу** (правило `agent-workflow.mdc`).
- В handoff-файле этапа — требования и канон уже принятых решений: агент обязан его читать, а не изобретать заново.
- Цикл работы: агент сделал → сам открыл демо (маркер `test/.agent_review_scene`) → написал, что изменилось → **ты смотришь сцену в Godot и даёшь фидбек**. Не давай агенту крутить скриншоты самооценки.
- После приёмки этапа попроси агента обновить handoff и `CURRENT.md`.
