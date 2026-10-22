# QA status registry

**Ветка QA:** qa/pass-1 · **tag старта:** qa-baseline-2026-10-22
**Легенда:** qa_not_done | in_progress | passed | ailed

Полный перечень элементов из data/*/recipes.json + системные функции. Старт: **qa_not_done**.

| ID | Область | Элемент / тема | Демо (якорь) | QA | Заметки |
|----|---------|----------------|--------------|-----|---------|
| FEAT-CABINET | система | Щит управления / кабинет | demo_door_harness.mechsim.json | qa_not_done | |
| FEAT-DOOR | система | Дверца щита / harness | demo_door_harness.mechsim.json | qa_not_done | |
| FEAT-UNDO3D | система | Undo 3D гизмо (move/rotate) | — | qa_not_done | |
| FEAT-THERMAL | система | Тепловизор 3D | demo_thermal_viz.mechsim.json | qa_not_done | |
| FEAT-SHORT | система | КЗ / нагрев жил | demo_thermal_short.mechsim.json | qa_not_done | |
| FEAT-SENSOR-ZONES | система | Режим «Зоны» (sensor_field_viz) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| FEAT-PRESSURE-VIZ | система | Режим «Давление» | — | qa_not_done | |
| FEAT-XRAY | система | Рентген | — | qa_not_done | |
| FEAT-BUGREPORT | система | Сообщить об ошибке → GitHub Issues | — | qa_not_done | |
| CYL-da_basic | cylinders | Двустороннего действия | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-da_magnetic | cylinders | Двусторонний, магнитный поршень | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-da_ppv | cylinders | Двусторонний с регулируемой амортизацией | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-da_pps | cylinders | Двусторонний с самонастраивающейся амортизацией | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-sa_return | cylinders | Односторонний, пружина втягивает | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-sa_extend | cylinders | Односторонний, пружина выдвигает | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-thr_basic | cylinders | Со сквозным штоком | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-thr_magnetic | cylinders | Сквозной шток, магнитный поршень | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-rodless_slot | cylinders | Бесштоковый щелевой | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-rodless_magnetic | cylinders | Бесштоковый с магнитной кареткой | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-rodless_ysr | cylinders | Бесштоковый с упорами YSR | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-brake_nc | cylinders | Двусторонний с зажимом штока (NC) | demo_pneumo_all.mechsim.json | qa_not_done | |
| CYL-brake_end | cylinders | Двусторонний со стопором в конце хода | demo_pneumo_all.mechsim.json | qa_not_done | |
| ROT-rack_pinion_90 | rotary | Поворотный поршневой 90° | demo_rotary_rack.mechsim.json | qa_not_done | |
| ROT-rack_pinion_180 | rotary | Поворотный поршневой 180° | demo_rotary_rack.mechsim.json | qa_not_done | |
| ROT-rack_pinion_270 | rotary | Поворотный поршневой 270° | demo_rotary_rack.mechsim.json | qa_not_done | |
| ROT-rack_pinion_360 | rotary | Поворотный поршневой 360° | demo_rotary_rack.mechsim.json | qa_not_done | |
| ROT-vane_90 | rotary | Лопастной 90° (DSM) | demo_rotary_rack.mechsim.json | qa_not_done | |
| ROT-vane_180 | rotary | Лопастной 180° (DSM) | demo_rotary_rack.mechsim.json | qa_not_done | |
| ROT-vane_270 | rotary | Лопастной 270° (DSM) | demo_rotary_rack.mechsim.json | qa_not_done | |
| VLV-2_2_nc_sol_spring | valves | 2/2 NC ЭМ / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-2_2_no_sol_spring | valves | 2/2 NO ЭМ / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-3_2_nc_sol_spring | valves | 3/2 NC ЭМ / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-3_2_no_sol_spring | valves | 3/2 NO ЭМ / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-3_2_nc_button_spring | valves | 3/2 NC кнопка / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-3_2_nc_roller_spring | valves | 3/2 NC ролик / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-3_2_nc_pilot_spring | valves | 3/2 NC пневмопилот / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-4_2_sol_spring | valves | 4/2 ЭМ / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-5_2_sol_spring | valves | 5/2 ЭМ / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-5_2_button_spring | valves | 5/2 кнопка / пружина | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-5_2_dual_sol | valves | 5/2 бистабил ЭМ / ЭМ | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-5_3_closed_dual_sol | valves | 5/3 закрытый центр ЭМ / ЭМ | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-5_3_exhausted_dual_sol | valves | 5/3 выхлопной центр ЭМ / ЭМ | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-5_3_pressurized_dual_sol | valves | 5/3 напорный центр ЭМ / ЭМ | demo_valve_sizes.mechsim.json | qa_not_done | |
| VLV-5_3_floating_dual_sol | valves | 5/3 плавающий центр ЭМ / ЭМ | demo_valve_sizes.mechsim.json | qa_not_done | |
| ACC-throttle | accessories | Дроссель регулируемый | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-throttle_fixed | accessories | Дроссель нерегулируемый | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-check | accessories | Обратный клапан | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-throttle_check | accessories | Дроссель с обратным клапаном | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-throttle_check_fixed | accessories | Дроссель с ОК (нерегулируемый) | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-reservoir | accessories | Пневмоаккумулятор (ресивер) | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-regulator | accessories | Редукционный клапан | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-frl | accessories | Блок подготовки воздуха (FRL) | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-shuttle | accessories | Клапан «ИЛИ» (shuttle) | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-and_valve | accessories | Клапан «И» (dual-pressure) | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-quick_exhaust | accessories | Клапан быстрого выхлопа | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-shutoff | accessories | Отсечной кран (шаровой) | demo_pneumo_all.mechsim.json | qa_not_done | |
| ACC-relief | accessories | Предохранительный клапан | demo_pneumo_all.mechsim.json | qa_not_done | |
| MOT-gear_1am | motor | Шестерённый ПМ (класс 1AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-gear_2am | motor | Шестерённый ПМ (класс 2AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-gear_4am | motor | Шестерённый ПМ (класс 4AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-vane_1am | motor | Лопастной ПМ (класс 1AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-vane_2am | motor | Лопастной ПМ (класс 2AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-vane_4am | motor | Лопастной ПМ (класс 4AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-turbine_1am | motor | Турбинный ПМ (класс 1AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-turbine_2am | motor | Турбинный ПМ (класс 2AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| MOT-turbine_4am | motor | Турбинный ПМ (класс 4AM) | demo_air_motor_gear.mechsim.json | qa_not_done | |
| ELC-bus_bar | electric | Шина (универсальная) | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-supply_1ph | electric | Ввод питания 1ф (L/N/PE) | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-supply_3ph | electric | Ввод питания 3ф (L1/L2/L3/N) | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-supply_3ph_pe | electric | Ввод питания 3ф (L1/L2/L3/N/PE) | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-psu_24 | electric | Блок питания 24В | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-lamp | electric | Лампа сигнальная | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-btn_no | electric | Кнопка НО | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-btn_nc | electric | Кнопка НЗ | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-btn_no_nc | electric | Кнопка НО+НЗ | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-btn_co | electric | Кнопка с перекидным контактом | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-switch_2pos | electric | Переключатель 2 положения | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-estop_nc | electric | Аварийная кнопка НЗ | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-relay_4c | electric | Реле промежуточное 4 перекидных | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-relay_2c | electric | Реле промежуточное 2 перекидных | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-relay_1c | electric | Реле промежуточное 1 перекидной | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-timer_relay | electric | Реле времени | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-solenoid_coil | electric | Катушка ЭМ (для ПР) | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-mcb_1p | electric | Автомат 1P | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-mcb_2p | electric | Автомат 2P | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-mcb_3p | electric | Автомат 3P | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-rcd_1pn | electric | УЗО 1P+N | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-rcd_3pn | electric | УЗО 3P+N | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-rcbo_1pn | electric | АВДТ 1P+N | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-rcbo_3pn | electric | АВДТ 3P+N | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-contactor_3p | electric | Контактор 3P | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-contactor_3p_aux | electric | Контактор 3P + вспом. контакты | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-thermal_relay | electric | Тепловое реле | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-term_block_1 | electric | Клемма DIN 1-полюсная | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-term_block_4 | electric | Клеммник 4-полюсный | demo_door_harness.mechsim.json | qa_not_done | |
| ELC-din_stop | electric | Концевой упор DIN | demo_door_harness.mechsim.json | qa_not_done | |
| SEN-inductive_m12 | sensors | Индуктивный БВ M12 (Sn 4 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-inductive_m18 | sensors | Индуктивный БВ M18 (Sn 8 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-inductive_m30 | sensors | Индуктивный БВ M30 (Sn 15 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-reed_t_slot | sensors | Геркон Т-паз НО (SME-класс) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-reed_t_slot_nc | sensors | Геркон Т-паз НЗ (SME-класс) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-reed_tie_rod | sensors | Геркон на тягу (D-A93-класс) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-capacitive_m12 | sensors | Ёмкостный БВ M12 (Sn 4 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-capacitive_m18 | sensors | Ёмкостный БВ M18 (Sn 8 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-capacitive_m18_12 | sensors | Ёмкостный БВ M18 (Sn 12 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-capacitive_m30 | sensors | Ёмкостный БВ M30 (Sn 15 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-optical_fiber_100 | sensors | Оптический усилитель FD3 (волокно · Sn 100 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-optical_fiber_200 | sensors | Оптический усилитель FD3 (волокно · Sn 200 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-optical_compact_m18 | sensors | Оптический датчик M18 (диффуз · Sn 100 мм) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-ultrasonic_m18_500 | sensors | УЗ датчик M18 (50…500 мм · 0–10 В) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-ultrasonic_m30_1000 | sensors | УЗ датчик M30 (100…1000 мм · 0–10 В) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-ultrasonic_m30_2000 | sensors | УЗ датчик M30 (200…2000 мм · 4–20 мА) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-pressure_switch_pev_10 | sensors | Реле давления 1…10 бар (PEV-класс) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-pressure_switch_pev_10_nc | sensors | Реле давления 1…10 бар НЗ (PEV-класс) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-pressure_switch_low_6 | sensors | Реле давления 0.2…6 бар (мембрана) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-pressure_tx_10_420 | sensors | Датчик давления 0…10 бар (4–20 мА) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-pressure_tx_10_010 | sensors | Датчик давления 0…10 бар (0–10 В) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-pressure_tx_16_420 | sensors | Датчик давления 0…16 бар (4–20 мА) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-rtd_pt100 | sensors | ТСП Pt100 (IEC 60751) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-rtd_100p | sensors | ТСП 100П (ГОСТ) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-rtd_cu100 | sensors | ТСМ Cu100 | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-opto_tip_emitter | sensors | Оптонаконечник · излучатель (T) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-opto_tip_receiver | sensors | Оптонаконечник · приёмник (T) | demo_sensor_inductive.mechsim.json | qa_not_done | |
| SEN-opto_tip_head | sensors | Оптонаконечник · диффуз/рефлектор (D/R) | demo_sensor_inductive.mechsim.json | qa_not_done | |

### Вне первого прохода / пауза

| ID | Тема | Почему |
|----|------|--------|
| SEN-B4+ | Термопара и далее | В разработке на dev |
| EL-AUTOROUTE | Автотрасса электро | Пауза |
| US-ACCURACY | Точность модели УЗ | Отложено |
| B3-DEEP | Детальный ре-ревью Pt100 | Оговорка владельца |

### Как обновлять

В PR фикса: QA → in_progress / passed / ailed + ссылка на PR/Issue.
Баг из приложения «Сообщить об ошибке» → GitHub Issues (ug-reports/ + issue).
