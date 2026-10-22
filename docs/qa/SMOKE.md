# QA smoke checklist

Открыть проект Godot 4 из корня репо. Для каждой строки: Run / Play → проверить 2D+3D+базовое поведение → отметить в [`STATUS.md`](STATUS.md).

## Датчики

- [ ] `res://test/demo_sensor_inductive.mechsim.json` — питание, зона («Зоны»), LED, металл корпуса, лампа
- [ ] `res://test/demo_sensor_reed.mechsim.json` — ход ПЦ, геркон без Uпит головки, поле магнита, лампа
- [ ] `res://test/demo_sensor_capacitive.mechsim.json` — диэлектрик/пластик в зоне, питание
- [ ] `res://test/demo_sensor_optical.mechsim.json` — fiber/compact, уставки, луч/барьер
- [ ] `res://test/demo_sensor_ultrasonic.mechsim.json` — дисплей мм, SET, аналог/дискрет (точность волн — не блокер)
- [ ] `res://test/demo_sensor_pressure_switch.mechsim.json` — уставка/hyst, контакт, LED
- [ ] `res://test/demo_sensor_pressure_transmitter.mechsim.json` — P линии → аналог, питание
- [ ] `res://test/demo_sensor_rtd.mechsim.json` — 2 vs 4-провод, погрешность 2-провод

## Моторы / ППЦ

- [ ] `res://test/demo_air_motor_gear.mechsim.json`
- [ ] `res://test/demo_air_motor_vane.mechsim.json`
- [ ] `res://test/demo_air_motor_turbine.mechsim.json`
- [ ] `res://test/demo_air_motor_reverse.mechsim.json`
- [ ] `res://test/demo_rotary_rack.mechsim.json`
- [ ] `res://test/demo_rotary_vane.mechsim.json`

## Тепло / щит

- [ ] `res://test/demo_thermal_viz.mechsim.json` — тепловизор + опц. рентген
- [ ] `res://test/demo_thermal_short.mechsim.json` — КЗ, нагрев жил, АВ
- [ ] `res://test/demo_door_harness.mechsim.json` — провода дверцы/щит

## UX

- [ ] Undo: сдвиг/поворот в 3D мышью → Ctrl+Z

## Сводно

- [ ] `res://test/demo_pneumo_all.mechsim.json` — нет явных падений / пустой схемы
