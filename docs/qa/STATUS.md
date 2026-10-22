# QA status registry

**Baseline tag:** `qa-baseline-2026-10-22`  
**Ветка QA:** `qa/pass-1`  
**Легенда:** `qa_not_done` | `in_progress` | `passed` | `failed`

Все строки ниже на старте: **QA не проводился**.

| ID | Область | Элемент / тема | Демо (якорь) | QA | Заметки |
|----|---------|----------------|--------------|-----|---------|
| SEN-A1 | датчики | Индуктивный БВ | `demo_sensor_inductive.mechsim.json` | `qa_not_done` | |
| SEN-A2 | датчики | Геркон на ПЦ | `demo_sensor_reed.mechsim.json` | `qa_not_done` | |
| SEN-A3 | датчики | Ёмкостный БВ | `demo_sensor_capacitive.mechsim.json` | `qa_not_done` | |
| SEN-A4 | датчики | Оптика fiber/compact | `demo_sensor_optical.mechsim.json` | `qa_not_done` | |
| SEN-A6 | датчики | УЗ аналог + дисплей | `demo_sensor_ultrasonic.mechsim.json` | `qa_not_done` | Точность УЗ-волн — отдельный долг этапа, не блокер MVP |
| SEN-B1 | датчики | Реле давления | `demo_sensor_pressure_switch.mechsim.json` | `qa_not_done` | |
| SEN-B2 | датчики | ПИП давления (аналог) | `demo_sensor_pressure_transmitter.mechsim.json` | `qa_not_done` | |
| SEN-B3 | датчики | Pt100 / ТСП 2/3/4 | `demo_sensor_rtd.mechsim.json` | `qa_not_done` | Принято с оговоркой: детальный ре-ревью позже |
| MOT-GEAR | моторы | ПМ шестерённый | `demo_air_motor_gear.mechsim.json` | `qa_not_done` | |
| MOT-VANE | моторы | ПМ лопастной | `demo_air_motor_vane.mechsim.json` | `qa_not_done` | |
| MOT-TURB | моторы | ПМ турбина | `demo_air_motor_turbine.mechsim.json` | `qa_not_done` | |
| MOT-REV | моторы | Реверс/скорость ПМ | `demo_air_motor_reverse.mechsim.json` | `qa_not_done` | |
| ROT-RACK | ППЦ | Рейка–шестерня | `demo_rotary_rack.mechsim.json` | `qa_not_done` | |
| ROT-VANE | ППЦ | Лопастной | `demo_rotary_vane.mechsim.json` | `qa_not_done` | |
| THM-VIZ | тепло | Тепловизор 3D | `demo_thermal_viz.mechsim.json` | `qa_not_done` | MVP «в целом нормально» |
| THM-SHORT | тепло | КЗ в щите | `demo_thermal_short.mechsim.json` | `qa_not_done` | |
| CAB-DOOR | щит | Дверца / harness | `demo_door_harness.mechsim.json` | `qa_not_done` | |
| PNE-ALL | пневмо | Сводное демо | `demo_pneumo_all.mechsim.json` | `qa_not_done` | Широкий smoke |
| UX-UNDO | UX | Undo 3D гизмо | (любая сцена с элементом) | `qa_not_done` | Ctrl+Z после move/rotate |

### Вне первого прохода QA (не стартовать без запроса)

| ID | Тема | Почему |
|----|------|--------|
| SEN-B4+ | Термопара и далее | Ещё в разработке на `dev` |
| EL-AUTOROUTE | Автотрасса электро | Пауза, эталон WIP |
| US-ACCURACY | Точность модели УЗ | Отложено после линейки датчиков |
| B3-DEEP | Детальный ре-ревью Pt100 | Отмечено владельцем продукта |

### Как обновлять

В PR фикса: измени `QA` на `in_progress` → `passed`/`failed`, добавь ссылку на PR/issue в «Заметки».
