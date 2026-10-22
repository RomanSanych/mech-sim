class_name RtdNsx
extends RefCounted
## НСХ термопреобразователей сопротивления + схемы 2/3/4-провод (методичка ТСА).
## Pt100: IEC 60751 (α=0.00385). 100П: ГОСТ 6651-класс (α=0.00391).
## Возбуждение вторички (учебные константы): ~40 мкА / 10 В — не моделируем током в сети.


## Удельное сопротивление меди при ~20 °C, Ом·мм²/м (методичка).
const RHO_CU := 0.0175
## Ток возбуждения вторичного прибора, А (учебная константа).
const EXCITE_A := 40.0e-6
## Напряжение генератора вторички, В (учебная константа).
const EXCITE_V := 10.0


static func normalize_type(t: String) -> String:
	match str(t).to_lower():
		"100p", "100п", "pt100_gost", "tsp100", "gost":
			return "100p"
		"cu100", "м100", "m100":
			return "cu100"
		"cu50", "м50", "m50":
			return "cu50"
		_:
			return "pt100"


static func type_label(t: String) -> String:
	match normalize_type(t):
		"100p":
			return "100П (ГОСТ)"
		"cu100":
			return "Cu100"
		"cu50":
			return "Cu50"
		_:
			return "Pt100 (IEC 60751)"


static func r0_ohm(t: String) -> float:
	match normalize_type(t):
		"cu50":
			return 50.0
		_:
			return 100.0


## α при 0 °C (1/°C): Pt100 IEC / 100П / Cu.
static func alpha(t: String) -> float:
	match normalize_type(t):
		"100p":
			return 0.00391
		"cu100", "cu50":
			return 0.00428
		_:
			return 0.00385


## R(T) по НСХ. T в °C. Диапазон учебный −50…+400 °C.
static func resistance_ohm(t_c: float, rtd_type: String = "pt100") -> float:
	var t: float = clampf(t_c, -50.0, 400.0)
	var typ: String = normalize_type(rtd_type)
	var r0: float = r0_ohm(typ)
	if typ.begins_with("cu"):
		# Линейная аппроксимация Cu (учебная).
		return r0 * (1.0 + alpha(typ) * t)
	# Callendar–Van Dusen (IEC 60751), A/B стандартные для Pt100.
	var a: float = 3.9083e-3
	var b: float = -5.775e-7
	if typ == "100p":
		# ГОСТ: чуть больший α — масштабируем линейный член.
		a = alpha(typ)
		b = -5.775e-7
	if t >= 0.0:
		return r0 * (1.0 + a * t + b * t * t)
	# Ниже 0 °C: + C·(t−100)·t³ (IEC).
	var c: float = -4.183e-12
	return r0 * (1.0 + a * t + b * t * t + c * (t - 100.0) * t * t * t)


## Обратная НСХ: R → T (°C). Итерация Ньютона / биссекция.
static func temperature_c(r_ohm: float, rtd_type: String = "pt100") -> float:
	var typ: String = normalize_type(rtd_type)
	var r0: float = r0_ohm(typ)
	if r_ohm <= 0.1:
		return -50.0
	if typ.begins_with("cu"):
		return clampf((r_ohm / r0 - 1.0) / alpha(typ), -50.0, 400.0)
	# Старт: линейная оценка.
	var t: float = (r_ohm / r0 - 1.0) / alpha(typ)
	t = clampf(t, -50.0, 400.0)
	for _i in 12:
		var r: float = resistance_ohm(t, typ)
		var r1: float = resistance_ohm(t + 0.05, typ)
		var dr: float = (r1 - r) / 0.05
		if absf(dr) < 1.0e-6:
			break
		var dt: float = (r_ohm - r) / dr
		t = clampf(t + dt, -50.0, 400.0)
		if absf(dt) < 0.001:
			break
	return t


## Сопротивление одной жилы, Ом. L — м, S — мм².
static func lead_ohm(length_m: float, section_mm2: float) -> float:
	var l: float = maxf(length_m, 0.0)
	var s: float = maxf(section_mm2, 0.1)
	return RHO_CU * l / s


## Rизм по схеме подключения (равные плечи кабеля).
## 2-провод: Rдат + 2·Rжилы (погрешность сразу).
## 3-провод: при равных плечах — полная компенсация (учебный идеал равных жил).
## 4-провод: полная компенсация.
static func measured_ohm(r_sensor: float, r_lead: float, wire_scheme: int) -> float:
	var rs: float = maxf(r_sensor, 0.0)
	var rl: float = maxf(r_lead, 0.0)
	match clampi(wire_scheme, 2, 4):
		2:
			return rs + 2.0 * rl
		3:
			# Мост/3-провод: при R1=R2=R3 остаток ≈ 0.
			return rs
		_:
			return rs


static func wire_scheme_label(n: int) -> String:
	match clampi(n, 2, 4):
		2:
			return "2-провод"
		3:
			return "3-провод"
		_:
			return "4-провод"


## Имена жил / клемм ТС по числу проводов.
static func core_names(wire_scheme: int) -> PackedStringArray:
	match clampi(wire_scheme, 2, 4):
		2:
			return PackedStringArray(["1", "2"])
		3:
			return PackedStringArray(["1", "2", "3"])
		_:
			return PackedStringArray(["1", "2", "3", "4"])
