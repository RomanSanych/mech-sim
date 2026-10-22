class_name TubeFittingCatalog
extends RefCounted
## Каталог фитингов ПЦ и трубок: bore → допустимые фитинги → OD/ID.
## Ряды по мотивам ISO 15552 / Festo QS (учебный компактный набор, не полный SKU).

const Geom = preload("res://scripts/domain/symbol_geom.gd")


## Наружный Ø трубки → внутр. Ø для физики (типичная стенка PU/PA).
static func tube_id_mm(od_mm: float) -> float:
	var od: float = snap_tube_od(od_mm)
	match int(round(od)):
		4:
			return 2.5
		6:
			return 4.0
		8:
			return 5.5
		10:
			return 7.0
		12:
			return 9.0
		14:
			return 11.0
		16:
			return 12.0
		_:
			return maxf(od * 0.65, 2.0)


static func tube_od_catalog() -> Array:
	return [4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]


static func snap_tube_od(od_mm: float) -> float:
	var best: float = 6.0
	var best_d: float = 1.0e9
	for v in tube_od_catalog():
		var d: float = absf(float(v) - float(od_mm))
		if d < best_d:
			best_d = d
			best = float(v)
	return best


## Допустимые фитинги для диаметра поршня (thread + OD трубки).
## Список всегда по возрастанию OD.
static func fittings_for_bore(bore_mm: float) -> Array:
	var b: float = float(bore_mm)
	if b <= 16.0:
		return [
			_fit("M5_4", "M5", 4.0, "M5 · трубка Ø4"),
		]
	if b <= 32.0:
		return [
			_fit("G1/8_4", "G1/8", 4.0, "G1/8 · трубка Ø4"),
			_fit("G1/8_6", "G1/8", 6.0, "G1/8 · трубка Ø6"),
			_fit("G1/8_8", "G1/8", 8.0, "G1/8 · трубка Ø8"),
		]
	if b <= 50.0:
		return [
			_fit("G1/4_6", "G1/4", 6.0, "G1/4 · трубка Ø6"),
			_fit("G1/4_8", "G1/4", 8.0, "G1/4 · трубка Ø8"),
			_fit("G1/4_10", "G1/4", 10.0, "G1/4 · трубка Ø10"),
		]
	if b <= 80.0:
		return [
			_fit("G3/8_8", "G3/8", 8.0, "G3/8 · трубка Ø8"),
			_fit("G3/8_10", "G3/8", 10.0, "G3/8 · трубка Ø10"),
			_fit("G3/8_12", "G3/8", 12.0, "G3/8 · трубка Ø12"),
		]
	if b <= 125.0:
		return [
			_fit("G1/2_10", "G1/2", 10.0, "G1/2 · трубка Ø10"),
			_fit("G1/2_12", "G1/2", 12.0, "G1/2 · трубка Ø12"),
			_fit("G1/2_14", "G1/2", 14.0, "G1/2 · трубка Ø14"),
		]
	return [
		_fit("G3/4_12", "G3/4", 12.0, "G3/4 · трубка Ø12"),
		_fit("G3/4_14", "G3/4", 14.0, "G3/4 · трубка Ø14"),
		_fit("G3/4_16", "G3/4", 16.0, "G3/4 · трубка Ø16"),
	]


## Типовой OD для bore (не минимальный из ряда).
static func preferred_tube_od(bore_mm: float) -> float:
	var b: float = float(bore_mm)
	if b <= 16.0:
		return 4.0
	if b <= 32.0:
		return 6.0
	if b <= 50.0:
		return 8.0
	if b <= 80.0:
		return 10.0
	if b <= 125.0:
		return 12.0
	return 14.0


static func default_fitting(bore_mm: float) -> Dictionary:
	var list: Array = fittings_for_bore(bore_mm)
	if list.is_empty():
		return _fit("G1/8_6", "G1/8", 6.0, "G1/8 · трубка Ø6")
	var want: float = preferred_tube_od(bore_mm)
	for item in list:
		if absf(float(item.get("tube_od_mm", 0.0)) - want) < 0.15:
			return item as Dictionary
	# Средний элемент ряда, если точного OD нет.
	var mid: int = mini(list.size() - 1, int(list.size() / 2))
	return list[mid] as Dictionary


static func fitting_by_id(bore_mm: float, fitting_id: String) -> Dictionary:
	var want: String = str(fitting_id)
	for item in fittings_for_bore(bore_mm):
		if str(item.get("id", "")) == want:
			return item as Dictionary
	return {}


## Применить фитинг к ПЦ; возвращает краткую заметку или "".
static func apply_fitting(el, fitting_id: String) -> String:
	if el == null or str(el.kind) != "cylinder":
		return ""
	var fit: Dictionary = fitting_by_id(float(el.bore_mm), fitting_id)
	var note: String = ""
	if fit.is_empty():
		fit = default_fitting(float(el.bore_mm))
		note = "Фитинг приведён к допустимому для ∅%.0f: %s." % [float(el.bore_mm), str(fit.get("label", ""))]
	el.fitting_id = str(fit.get("id", ""))
	el.port_name = str(fit.get("thread", "G1/8"))
	el.tube_od_mm = float(fit.get("tube_od_mm", 6.0))
	return note


## После смены bore: сохранить фитинг, если ещё допустим; иначе default.
static func conform_cylinder_fitting(el) -> String:
	if el == null or str(el.kind) != "cylinder":
		return ""
	var cur: String = str(el.get("fitting_id") if el.get("fitting_id") != null else "")
	if cur != "" and not fitting_by_id(float(el.bore_mm), cur).is_empty():
		return apply_fitting(el, cur)
	var d: Dictionary = default_fitting(float(el.bore_mm))
	return apply_fitting(el, str(d.get("id", "")))


## OD, задаваемый портом элемента (ПЦ, распред, арматура, переходник).
static func port_tube_od(el, port: String = "") -> float:
	if el == null:
		return 0.0
	if str(el.kind) == "cylinder":
		var od: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0
		if od < 1.0:
			var d: Dictionary = default_fitting(float(el.bore_mm))
			return float(d.get("tube_od_mm", 6.0))
		return snap_tube_od(od)
	if str(el.kind) == "valve":
		var vod: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0
		if vod >= 1.0:
			return snap_tube_od(vod)
		var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
		var row: Dictionary = ValveCat.size_by_id(ValveCat.default_size_id(int(el.valve_ways)))
		return float(row.get("tube_od_mm", 6.0))
	# Переходник: порт 1 = tube_od_mm, порт 2 = tube_od_b_mm.
	if str(el.kind) == "junction" and str(el.get("junction_style") if el.get("junction_style") != null else "") == "adapter":
		var side: String = str(port)
		if side == "2" or side == "b" or side == "R":
			var odb: float = float(el.tube_od_b_mm) if el.get("tube_od_b_mm") != null else 0.0
			return snap_tube_od(odb) if odb >= 1.0 else 8.0
		var oda: float = float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0
		return snap_tube_od(oda) if oda >= 1.0 else 6.0
	# Арматура / тройник: свой tube_od_mm, если задан.
	if el.get("tube_od_mm") != null and float(el.tube_od_mm) >= 1.0:
		return snap_tube_od(float(el.tube_od_mm))
	return 0.0


static func apply_tube_od_to_wire(wire, od_mm: float) -> void:
	if wire == null:
		return
	var od: float = snap_tube_od(od_mm)
	wire.od_mm = od
	wire.id_mm = tube_id_mm(od)


## Масштаб 3D-фитинга относительно G1/8·Ø6.
static func fitting_scale(thread: String, tube_od_mm: float) -> float:
	var t: float = 1.0
	match str(thread):
		"M5":
			t = 0.72
		"G1/8":
			t = 1.0
		"G1/4":
			t = 1.22
		"G3/8":
			t = 1.45
		"G1/2":
			t = 1.7
		"G3/4":
			t = 2.05
		_:
			t = 1.0
	var od_f: float = clampf(snap_tube_od(tube_od_mm) / 6.0, 0.7, 1.55)
	return clampf(t * (0.55 + 0.45 * od_f), 0.65, 2.2)


## Типовая резьба/порт под пуш-фитинг по OD трубки (учебный ряд).
static func thread_for_tube_od(od_mm: float) -> String:
	match int(round(snap_tube_od(od_mm))):
		4:
			return "M5"
		6:
			return "G1/8"
		8:
			return "G1/4"
		10:
			return "G3/8"
		12:
			return "G1/2"
		_:
			return "G3/4"


## Масштаб корпуса арматуры (тройник / дроссель / ОК) относительно Ø6.
static func armature_body_scale(tube_od_mm: float) -> float:
	var od: float = snap_tube_od(tube_od_mm) if tube_od_mm >= 1.0 else 6.0
	return clampf(od / 6.0, 0.72, 2.0)


## Задать OD арматуры (тройник / аксессуар); 0 = авто по трубке.
static func apply_armature_od(el, od_mm: float) -> void:
	if el == null:
		return
	var kind: String = str(el.kind)
	if kind != "junction" and kind != "accessory":
		return
	if od_mm < 1.0:
		el.tube_od_mm = 0.0
		return
	var od: float = snap_tube_od(od_mm)
	el.tube_od_mm = od
	el.port_name = thread_for_tube_od(od)
	el.fitting_id = "%s_%.0f" % [str(el.port_name).replace("/", ""), od]


static func _fit(id: String, thread: String, tube_od: float, label: String) -> Dictionary:
	return {
		"id": id,
		"thread": thread,
		"tube_od_mm": tube_od,
		"label": label,
	}
