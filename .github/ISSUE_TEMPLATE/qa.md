---
name: QA-проверка элемента
about: Прогон строки из docs/qa/STATUS.md
title: "[QA] "
labels: type:qa
---

## Элемент

<строка из STATUS.md, напр. A1 индуктивный БВ>

## Демо

`res://test/<сцена>.mechsim.json`

## Чек-лист

- [ ] Сцена открывается, симуляция запускается
- [ ] УГО на сетке, tips на SCH_GRID
- [ ] 3D / рентген / зоны корректны
- [ ] Электрика/пневматика по handoff

## Результат

- [ ] `passed` — обновить STATUS.md
- [ ] `failed` — завести Issue на каждый баг, STATUS.md → `failed`
