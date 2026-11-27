# Сообщить об ошибке (in-app)

## Для пользователя / QA

1. Установите [GitHub CLI](https://cli.github.com/) и выполните `gh auth login` (доступ к `RomanSanych/mech-sim`).
2. В MechSim: **Помощь → Сообщить об ошибке…**
3. Опишите проблему → **Отправить**.
4. На GitHub появится Issue со ссылками на скриншот и `.mechsim.json` (ветка `bug-inbox`).

Локальная копия пакета: `%APPDATA%/Godot/app_userdata/<project>/bugreports/` (путь `user://bugreports/`).

## Для разработчика / агента

- Да: Issues можно разбирать и чинить (ветка от `main` → PR в `main`).
- Код: `scripts/app/bug_report.gd`, пункт меню в `main_shell.gd`.
- **После фикса:** комментарий в Issue + **сразу `gh issue close`** (Completed) — не ждать визуального OK. Правило: `.cursor/rules/bug-fix-close-issue.mdc`.
