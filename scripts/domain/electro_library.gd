class_name ElectroLibrary
extends RefCounted
## Каталог электроавтоматики (ГОСТ 2.755 / 2.756 / 2.709).
## data/electric/recipes.json

const RECIPES_PATH := "res://data/electric/recipes.json"
const Geom = preload("res://scripts/domain/symbol_geom.gd")
const WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")

const CATEGORY_ORDER := ["supply", "door", "relay", "power", "protection", "terminals"]
const CATEGORY_TITLE := {
	"supply": "Источники и цепи",
	"door": "На дверцу щита",
	"relay": "Реле и логика",
	"power": "Силовые (DIN)",
	"protection": "Защита (DIN)",
	"terminals": "Клеммники и соединения",
	# Старые ключи → новые (сохранённые схемы / кэш).
	"din_misc": "Клеммники и соединения",
}

static var _ready := false
static var _recipes: Dictionary = {}
static var _recipe_order: PackedStringArray = PackedStringArray()


static func ensure_loaded() -> void:
	if _ready:
		# Подхватить правки recipes.json без перезапуска редактора.
		if (
			not _recipes.has("timer_relay")
			or _recipes.has("timer_on")
			or not _recipes.has("mcb_1p")
			or _recipes.has("mcb_1p_c16")
		):
			_load_recipes()
		return
	_ready = true
	_load_recipes()


static func reload() -> void:
	_ready = false
	ensure_loaded()


static func recipe(id: String) -> Dictionary:
	ensure_loaded()
	if _recipes.has(id):
		return (_recipes[id] as Dictionary).duplicate(true)
	return {}


static func all_recipes() -> Array:
	reload()
	var out: Array = []
	for id in _recipe_order:
		var rec: Dictionary = recipe(id)
		var cls: String = str(rec.get("electro_class", ""))
		# Концевой упор / розетка — только 3D; шина временно скрыта из каталога.
		if cls in ["din_stop", "din_socket", "busbar"]:
			continue
		# Старый category din_misc → terminals.
		if str(rec.get("category", "")) == "din_misc":
			rec["category"] = "terminals"
		out.append(rec)
	return out


static func _resolve_recipe_id(id: String) -> String:
	# Старые id lamp_white/red/... → одна позиция «lamp»; цвет из суффикса.
	if id.begins_with("lamp_"):
		return "lamp"
	# Старые АВ с номиналом в id → АВ 1P/2P/3P.
	if id.begins_with("mcb_1p"):
		return "mcb_1p"
	if id.begins_with("mcb_2p"):
		return "mcb_2p"
	if id.begins_with("mcb_3p"):
		return "mcb_3p"
	# Старые УЗО/АВДТ → 1P+N / 3P+N.
	if id.begins_with("rcd_2p") or id == "rcd_1pn":
		return "rcd_1pn"
	if id.begins_with("rcd_4p") or id == "rcd_3pn":
		return "rcd_3pn"
	if id.begins_with("rcbo_1p") or id == "rcbo_1pn":
		return "rcbo_1pn"
	if id.begins_with("rcbo_3p") or id == "rcbo_3pn":
		return "rcbo_3pn"
	match id:
		"bus_n", "bus_pe":
			return "bus_bar"
		"supply_in":
			return "supply_1ph"
		"term_l", "term_n", "term_pe":
			return "term_block_4"
		"timer_on", "timer_off":
			return "timer_relay"
		_:
			return id


## Типовая линейка In модульных АВ (IEC 60898), А.
const MCB_RATINGS_A: Array = [6.0, 10.0, 13.0, 16.0, 20.0, 25.0, 32.0, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0]
## Типовая отключающая способность Icu, кА.
const MCB_ICU_KA: Array = [4.5, 6.0, 10.0, 15.0, 20.0, 25.0]
## Типовые IΔn УЗО/АВДТ, мА.
const RCD_IDELTA_MA: Array = [10.0, 30.0, 100.0, 300.0]


static func mcb_snap_rating(a: float) -> float:
	var best: float = float(MCB_RATINGS_A[0])
	var best_d: float = absf(a - best)
	for v in MCB_RATINGS_A:
		var d: float = absf(a - float(v))
		if d < best_d:
			best_d = d
			best = float(v)
	return best


static func mcb_snap_icu(ka: float) -> float:
	var best: float = float(MCB_ICU_KA[0])
	var best_d: float = absf(ka - best)
	for v in MCB_ICU_KA:
		var d: float = absf(ka - float(v))
		if d < best_d:
			best_d = d
			best = float(v)
	return best


static func rcd_snap_idelta(ma: float) -> float:
	var best: float = float(RCD_IDELTA_MA[0])
	var best_d: float = absf(ma - best)
	for v in RCD_IDELTA_MA:
		var d: float = absf(ma - float(v))
		if d < best_d:
			best_d = d
			best = float(v)
	return best


static func _legacy_lamp_color(id: String) -> String:
	if id.begins_with("lamp_"):
		var c := id.substr(5)
		if c in ["white", "red", "green", "yellow"]:
			return c
	return ""


static func timer_unit_scale(unit: int) -> float:
	# Уставка в единицах шкалы → секунды.
	match clampi(unit, 0, 2):
		0:
			return 0.001
		2:
			return 60.0
		_:
			return 1.0


static func timer_unit_label(unit: int) -> String:
	match clampi(unit, 0, 2):
		0:
			return "мс"
		2:
			return "мин"
		_:
			return "с"


## Мин/макс уставки по размерности: мс 1…999, с/мин 1…59.
static func timer_value_limits(unit: int) -> Vector2:
	if clampi(unit, 0, 2) == 0:
		return Vector2(1.0, 999.0)
	return Vector2(1.0, 59.0)


static func timer_clamp_value(el) -> void:
	if el == null:
		return
	el.timer_unit = clampi(int(el.timer_unit), 0, 2)
	var lim: Vector2 = timer_value_limits(int(el.timer_unit))
	el.timer_value = clampf(roundf(float(el.timer_value)), lim.x, lim.y)


static func timer_mode_label(mode: String) -> String:
	match str(mode):
		"off":
			return "Отключения"
		"both":
			return "Вкл/Выкл"
		_:
			return "Включения"


static func timer_sync_delays(el) -> void:
	if el == null:
		return
	timer_clamp_value(el)
	var mode: String = str(el.timer_mode)
	if mode not in ["on", "off", "both"]:
		mode = "on"
		el.timer_mode = mode
	var sec: float = float(el.timer_value) * timer_unit_scale(int(el.timer_unit))
	match mode:
		"off":
			el.delay_on = 0.0
			el.delay_off = sec
		"both":
			el.delay_on = sec
			el.delay_off = sec
		_:
			el.delay_on = sec
			el.delay_off = 0.0


static func timer_format_value(el) -> String:
	if el == null:
		return "—"
	timer_clamp_value(el)
	return "%.0f %s" % [float(el.timer_value), timer_unit_label(int(el.timer_unit))]


static func timer_contact_defs() -> Array:
	return [
		{"name": "COM", "type": "co"},
		{"name": "NC", "type": "nc"},
		{"name": "NO", "type": "no"},
	]


static func _init_timer_fields(el, rec: Dictionary, raw_id: String) -> void:
	var mode: String = str(rec.get("timer_mode", ""))
	if mode == "":
		if raw_id.find("off") >= 0:
			mode = "off"
		elif float(rec.get("delay_on", 0.0)) > 0.001 and float(rec.get("delay_off", 0.0)) > 0.001:
			mode = "both"
		elif float(rec.get("delay_off", 0.0)) > 0.001:
			mode = "off"
		else:
			mode = "on"
	el.timer_mode = mode
	if rec.has("timer_unit"):
		el.timer_unit = clampi(int(rec.get("timer_unit", 1)), 0, 2)
	else:
		el.timer_unit = 1
	if rec.has("timer_value"):
		el.timer_value = float(rec.get("timer_value", 1.0))
	else:
		var sec: float = maxf(float(rec.get("delay_on", 0.0)), float(rec.get("delay_off", 0.0)))
		if sec <= 0.0:
			sec = 1.0
		el.timer_unit = 1
		el.timer_value = sec
	el.contact_defs = timer_contact_defs()
	el.group_template = "timer"
	timer_sync_delays(el)


## Нормализация KT после загрузки старых сцен (timer_on/off, 15/16/18).
static func normalize_timer_relay(el) -> void:
	if el == null or str(el.electro_class) != "timer_relay":
		return
	if str(el.member_role) == "contact":
		return
	var rid: String = str(el.recipe_id)
	if rid in ["timer_on", "timer_off"] or rid == "":
		el.recipe_id = "timer_relay"
		el.catalog_id = "timer_relay"
	var mode: String = str(el.timer_mode)
	if mode not in ["on", "off", "both"]:
		if rid.find("off") >= 0:
			mode = "off"
		elif float(el.delay_on) > 0.001 and float(el.delay_off) > 0.001:
			mode = "both"
		elif float(el.delay_off) > 0.001:
			mode = "off"
		else:
			mode = "on"
		el.timer_mode = mode
	if float(el.timer_value) <= 0.0 and (float(el.delay_on) > 0.0 or float(el.delay_off) > 0.0):
		var sec: float = maxf(float(el.delay_on), float(el.delay_off))
		if sec < 1.0:
			el.timer_unit = 0
			el.timer_value = sec * 1000.0
		elif sec < 60.0:
			el.timer_unit = 1
			el.timer_value = sec
		else:
			el.timer_unit = 2
			el.timer_value = sec / 60.0
	el.contact_defs = timer_contact_defs()
	if str(el.group_template) in ["", "timer_on", "timer_off"]:
		el.group_template = "timer"
	timer_sync_delays(el)


static func apply_recipe(el, id: String) -> bool:
	ensure_loaded()
	var legacy_color: String = _legacy_lamp_color(id)
	var rid: String = _resolve_recipe_id(id)
	var rec := recipe(rid)
	if rec.is_empty():
		return false
	# Концевой упор — не элемент схемы; в 3D ставит IsoCabinet._ensure_din_stops.
	if str(rec.get("electro_class", "")) == "din_stop":
		return false
	el.kind = "electro"
	el.recipe_id = str(rec.get("id", rid))
	el.catalog_id = el.recipe_id
	el.electro_class = str(rec.get("electro_class", "terminal"))
	el.electro_mount = str(rec.get("electro_mount", "din"))
	el.tag_prefix = str(rec.get("tag_prefix", "E"))
	el.lamp_color = legacy_color if legacy_color != "" else str(rec.get("lamp_color", "white"))
	el.delay_on = float(rec.get("delay_on", 0.0))
	el.delay_off = float(rec.get("delay_off", 0.0))
	if str(rec.get("electro_class", "")) == "timer_relay":
		_init_timer_fields(el, rec, id)
	el.poles = int(rec.get("poles", 1))
	el.curve = str(rec.get("curve", "C"))
	el.rating_a = float(rec.get("rating_a", 16.0))
	el.i_delta_ma = float(rec.get("i_delta_ma", 30.0))
	el.u_min = float(rec.get("u_min", 180.0))
	# Для АВ/УЗО u_max = Icu, кА (по умолчанию 6); иначе порог реле напряжения.
	var default_umax: float = 6.0 if str(rec.get("electro_class", "")) in ["mcb", "rcd", "rcbo"] else 260.0
	el.u_max = float(rec.get("u_max", default_umax))
	if str(el.electro_class) == "mcb":
		el.rating_a = mcb_snap_rating(float(el.rating_a))
		el.u_max = mcb_snap_icu(float(el.u_max))
		var cu: String = str(el.curve).to_upper()
		el.curve = cu if cu in ["B", "C", "D"] else "C"
	elif str(el.electro_class) == "rcd":
		el.rating_a = mcb_snap_rating(float(el.rating_a))
		el.i_delta_ma = rcd_snap_idelta(float(el.i_delta_ma))
	elif str(el.electro_class) == "rcbo":
		el.rating_a = mcb_snap_rating(float(el.rating_a))
		el.u_max = mcb_snap_icu(float(el.u_max))
		el.i_delta_ma = rcd_snap_idelta(float(el.i_delta_ma))
		var cu2: String = str(el.curve).to_upper()
		el.curve = cu2 if cu2 in ["B", "C", "D"] else "C"
	el.phase = str(rec.get("phase", ""))
	if str(rec.get("electro_class", "")) in ["rcd", "rcbo"] and el.phase == "":
		el.phase = "AC"
	var default_u: float = 220.0 if str(rec.get("electro_class", "")) == "lamp" else 230.0
	if str(rec.get("electro_class", "")) in ["relay", "timer_relay", "contactor", "solenoid_coil"]:
		default_u = 230.0
	el.voltage = float(rec.get("voltage", default_u))
	if str(rec.get("electro_class", "")) in ["relay", "timer_relay", "contactor"] and float(rec.get("rating_a", 0.0)) > 0.0:
		el.rating_a = float(rec.get("rating_a", 10.0))
	el.link_valve = bool(rec.get("link_valve", false))
	el.group_template = str(rec.get("group_template", ""))
	if str(el.electro_class) == "switch":
		el.group_template = "" # таблица замыканий на самом УГО
	el.electro_ports = _to_array(rec.get("ports", []))
	el.coil_ports = _to_string_array(rec.get("coil_ports", []))
	el.contact_defs = _to_array(rec.get("contacts", []))
	el.switch_positions = maxi(int(rec.get("switch_positions", 2)), 2)
	el.switch_pos = 0
	el.switch_map = []
	el.switch_labels = PackedStringArray()
	el.btn_color = "red" if str(el.electro_class) == "e_stop" else str(rec.get("btn_color", "white"))
	el.caption = str(rec.get("caption", ""))
	# Наследие bus_n / bus_pe → цвет пяток и подпись (после caption из рецепта).
	if id == "bus_n":
		el.phase = "N"
		el.caption = "N"
	elif id == "bus_pe":
		el.phase = "PE"
		el.caption = "PE"
	el.door_xy = Vector2(-1, -1)
	# Состояния по умолчанию.
	el.energized = false
	el.pressed = false
	el.latching = bool(rec.get("latching", str(rec.get("electro_class", "")) == "e_stop"))
	# АВ/УЗО/АВДТ на схеме — в исходном разомкнутом (OFF); рычаг I включает.
	if str(el.electro_class) in ["mcb", "rcd", "rcbo"]:
		el.closed = false
	else:
		el.closed = true
	el.lit = false
	el.timer_armed = false
	el.timer_elapsed = 0.0
	el.detached = false
	el.member_role = "device"
	el.member_index = 0
	el.group_id = -1
	el.group_tag = ""
	el.linked_valve_side = ""
	if str(el.electro_class) == "terminal":
		el.terminal_bus = bool(rec.get("terminal_bus", false))
		el.color_id = str(rec.get("color_id", ""))
		el.terminal_port_scheme = 2
		normalize_terminal(el)
	if str(el.electro_class) == "switch":
		ensure_switch(el)
	return true


## Число рядов (полюсов) клеммника.
static func terminal_row_count(el) -> int:
	if el == null:
		return 1
	if str(el.phase) != "":
		return 1
	return maxi(el.electro_ports.size(), 1)


static func terminal_left_name(row: int) -> String:
	return str(int(row) * 2 + 1)


static func terminal_right_name(row: int) -> String:
	return str(int(row) * 2 + 2)


## Ряд по имени порта (1/2 → 0, 3/4 → 1; наследие «1b» → ряд 0).
static func terminal_row_of_port(port: String) -> int:
	var p: String = str(port)
	if p.ends_with("b") and p.length() > 1:
		var base: String = p.substr(0, p.length() - 1)
		if base.is_valid_int():
			return maxi(int(base) - 1, 0)
	if p.is_valid_int():
		var n: int = int(p)
		if n <= 0:
			return 0
		return int((n - 1) / 2)
	return 0


## Макс. символов подписи ряда на схеме/3D (площадка клеммы); полный текст — в данных/tooltip.
const TERM_ROW_LABEL_MAX := 6


static func terminal_row_label(el, row: int) -> String:
	if el == null or row < 0:
		return ""
	if str(el.phase) != "":
		return str(el.phase)
	var defs: Array = el.electro_ports if typeof(el.electro_ports) == TYPE_ARRAY else []
	if row >= defs.size() or typeof(defs[row]) != TYPE_DICTIONARY:
		return ""
	var d: Dictionary = defs[row]
	var lab: String = str(d.get("label", "")).strip_edges()
	if lab != "":
		return lab
	# Старые сцены: уникальная подпись могла лежать в name.
	var nm: String = str(d.get("name", "")).strip_edges()
	if nm != "" and not nm.is_valid_int():
		return nm
	return ""


## Отображение: усечение + «…»; данные не трогает.
static func terminal_row_label_fit(text: String) -> String:
	var t: String = text.strip_edges()
	if t.length() <= TERM_ROW_LABEL_MAX:
		return t
	if TERM_ROW_LABEL_MAX <= 1:
		return "…"
	return t.substr(0, TERM_ROW_LABEL_MAX - 1) + "…"


static func terminal_port_label(el, port: String) -> String:
	return terminal_row_label(el, terminal_row_of_port(port))


## Роль полюса УЗО/АВДТ: N / L1 / L2 / L3 (для скобок в тултипе и подписей).
static func port_diff_line_role(el, port_name: String) -> String:
	if el == null:
		return ""
	var cls: String = str(el.electro_class)
	if cls not in ["rcd", "rcbo"]:
		return ""
	var nm: String = str(port_name)
	if not nm.is_valid_int():
		return ""
	var pn: int = int(nm)
	if pn < 1:
		return ""
	var col: int = (pn - 1) / 2
	var poles: int = clampi(maxi(int(el.poles), 2), 2, 4)
	if col < 0 or col >= poles:
		return ""
	if cls == "rcd":
		# N слева, затем L1…L3.
		if col == 0:
			return "N"
		return "L%d" % col
	# АВДТ: фазы слева, N справа.
	if col == poles - 1:
		return "N"
	return "L%d" % (col + 1)


## Роль контактной клеммы: COM / NO / NC / N / L1… / "" (для подписей провода и кембрика).
## Только электро. Пневмопорты 1/2/3 и силовые клеммы без contact_defs — без скобок.
static func port_contact_role(el, port_name: String) -> String:
	var nm: String = str(port_name)
	if nm == "A1" or nm == "A2":
		return ""
	if el == null or str(el.kind) != "electro":
		return ""
	if typeof(el.contact_defs) == TYPE_ARRAY:
		for d in el.contact_defs:
			if typeof(d) != TYPE_DICTIONARY:
				continue
			if str(d.get("name", "")) != nm:
				continue
			var t: String = str(d.get("type", ""))
			if t == "co":
				return "COM"
			if t == "nc":
				return "NC"
			if t == "no":
				return "NO"
	# УЗО/АВДТ: важно N vs L1… — не COM/NC.
	var diff: String = port_diff_line_role(el, nm)
	if diff != "":
		return diff
	# Силовые/защитные клеммы (АВ 1/2 и т.п.) — не контактные COM/NC.
	if str(el.electro_class) in [
		"mcb", "rcd", "rcbo", "busbar", "terminal", "supply", "lamp", "thermal",
		"psu", "din_stop", "solenoid_coil",
	]:
		return ""
	# IEC …1 COM / …2 NC / …3|4 NO — только у контактных единиц (не у пневмо и не у катушки/силовых).
	var is_contact_unit: bool = str(el.member_role) == "contact"
	var is_contact_device: bool = str(el.electro_class) in ["button", "e_stop", "contact", "switch"]
	if not is_contact_unit and not is_contact_device:
		return ""
	if nm.is_valid_int():
		var dig: int = int(nm) % 10
		if dig == 1:
			return "COM"
		if dig == 2:
			return "NC"
		if dig == 3 or dig == 4:
			return "NO"
	return ""


## Подпись наведения: XT1:1 или XT1:1(+24В).
static func terminal_format_tip(el, port: String) -> String:
	if el == null:
		return str(port)
	var tag: String = str(el.tag)
	var p: String = str(port)
	var lab: String = terminal_port_label(el, p)
	if lab != "":
		return "%s:%s(%s)" % [tag, p, lab]
	return "%s:%s" % [tag, p]


static func terminal_row_color_id(el, row: int) -> String:
	if el == null:
		return ""
	if bool(el.terminal_bus) or str(el.phase) != "":
		var cid: String = str(el.color_id)
		if cid != "":
			return cid
		# phase → цвет как у шины.
		match str(el.phase):
			"PE", "green":
				return "pe"
			"+", "plus", "red":
				return "red"
			"-", "minus", "black", "L2":
				return "black"
			"L1", "L", "brown":
				return "brown"
			"L3", "gray", "grey":
				return "grey"
			"N":
				return "lightblue"
			_:
				return cid
	var defs: Array = el.electro_ports if typeof(el.electro_ports) == TYPE_ARRAY else []
	if row >= 0 and row < defs.size() and typeof(defs[row]) == TYPE_DICTIONARY:
		var rc: String = str(defs[row].get("color_id", "")).strip_edges()
		if rc != "":
			return rc
	return str(el.color_id)


## Нормализация рядов: label/color_id; имена портов не храним (считаются).
static func normalize_terminal(el) -> void:
	if el == null or str(el.electro_class) != "terminal":
		return
	var n: int = maxi(el.electro_ports.size(), 1)
	var rows: Array = []
	for i in n:
		var lab: String = ""
		var cid: String = ""
		if i < el.electro_ports.size() and typeof(el.electro_ports[i]) == TYPE_DICTIONARY:
			var d: Dictionary = el.electro_ports[i]
			lab = str(d.get("label", "")).strip_edges()
			if lab == "":
				var nm: String = str(d.get("name", "")).strip_edges()
				if nm != "" and not nm.is_valid_int():
					lab = nm
			cid = str(d.get("color_id", "")).strip_edges()
		if bool(el.terminal_bus) and str(el.color_id) != "":
			cid = str(el.color_id)
		rows.append({"label": lab, "color_id": cid, "type": "line"})
	el.electro_ports = rows
	el.terminal_port_scheme = 2


## Пересобрать число рядов, сохранив подписи/цвета.
static func terminal_set_rows(el, count: int) -> void:
	if el == null:
		return
	var n: int = clampi(count, 1, 12)
	var old: Array = el.electro_ports.duplicate(true) if typeof(el.electro_ports) == TYPE_ARRAY else []
	var rows: Array = []
	for i in n:
		var lab: String = ""
		var cid: String = str(el.color_id) if bool(el.terminal_bus) else ""
		if i < old.size() and typeof(old[i]) == TYPE_DICTIONARY:
			var d: Dictionary = old[i]
			lab = str(d.get("label", "")).strip_edges()
			if lab == "":
				var nm: String = str(d.get("name", "")).strip_edges()
				if nm != "" and not nm.is_valid_int():
					lab = nm
			if not bool(el.terminal_bus):
				cid = str(d.get("color_id", "")).strip_edges()
		rows.append({"label": lab, "color_id": cid, "type": "line"})
	el.electro_ports = rows
	el.terminal_port_scheme = 2


## Старое имя порта 1/1b → 1/2, 2/2b → 3/4.
static func migrate_terminal_port_name(port: String) -> String:
	var p: String = str(port)
	if p.ends_with("b") and p.length() > 1:
		var base: String = p.substr(0, p.length() - 1)
		if base.is_valid_int():
			return str(int(base) * 2)
		return p
	if p.is_valid_int():
		return str(int(p) * 2 - 1)
	return p


## После загрузки сцены: порты 1/1b → нечёт/чёт.
static func migrate_terminal_wires(circuit) -> void:
	if circuit == null:
		return
	for el in circuit.elements:
		if str(el.kind) != "electro" or str(el.electro_class) != "terminal":
			continue
		if int(el.terminal_port_scheme) >= 2:
			normalize_terminal(el)
			continue
		normalize_terminal(el)
		var eid: int = int(el.id)
		for wire in circuit.wires:
			if int(wire.a_id) == eid:
				wire.a_port = migrate_terminal_port_name(str(wire.a_port))
			if int(wire.b_id) == eid:
				wire.b_port = migrate_terminal_port_name(str(wire.b_port))
		el.terminal_port_scheme = 2


## Число горизонтальных цепей переключателя (пар портов).
static func switch_row_count(el) -> int:
	if el == null:
		return 1
	return maxi(int(ceil(float(maxi(el.contact_defs.size(), 2)) / 2.0)), 1)


## Установить положение SA напрямую (не только +1 по кругу).
static func set_switch_pos(el, pos: int) -> void:
	if el == null or str(el.electro_class) != "switch":
		return
	ensure_switch(el)
	var npos: int = maxi(int(el.switch_positions), 2)
	el.switch_pos = clampi(pos, 0, npos - 1)
	el.pressed = int(el.switch_pos) > 0


## Привести switch_map / contact_defs к npos × nrows (по умолчанию диагональ 0↔ряд).
static func ensure_switch(el) -> void:
	if el == null or str(el.electro_class) != "switch":
		return
	var npos: int = maxi(int(el.switch_positions), 2)
	el.switch_positions = npos
	var nrows: int = switch_row_count(el)
	# Добить пары имён портов.
	while el.contact_defs.size() < nrows * 2:
		var i: int = int(el.contact_defs.size() / 2) + 1
		el.contact_defs.append({"name": str(i * 2 - 1), "type": "no"})
		el.contact_defs.append({"name": str(i * 2), "type": "no"})
	if el.contact_defs.size() > nrows * 2:
		el.contact_defs.resize(nrows * 2)
	var old: Array = el.switch_map if typeof(el.switch_map) == TYPE_ARRAY else []
	var neu: Array = []
	for ri in nrows:
		var row: Array = []
		var src: Array = old[ri] if ri < old.size() and typeof(old[ri]) == TYPE_ARRAY else []
		for pi in npos:
			var v: bool = false
			if pi < src.size():
				v = bool(src[pi])
			elif src.is_empty():
				# Типовая схема: ряд i замкнут в положении i % npos.
				v = (pi == (ri % npos))
			row.append(v)
		neu.append(row)
	el.switch_map = neu
	el.switch_pos = clampi(int(el.switch_pos), 0, npos - 1)
	_ensure_switch_labels(el, npos)


static func _ensure_switch_labels(el, npos: int) -> void:
	var labels := PackedStringArray()
	var old: PackedStringArray = el.switch_labels if el.switch_labels is PackedStringArray else PackedStringArray()
	for i in npos:
		var lab := str(old[i]).strip_edges() if i < old.size() else ""
		if lab == "":
			lab = str(i)
		labels.append(lab)
	el.switch_labels = labels


static func switch_label(el, pos: int) -> String:
	if el == null:
		return str(pos)
	var labels: PackedStringArray = el.switch_labels if el.switch_labels is PackedStringArray else PackedStringArray()
	if pos >= 0 and pos < labels.size():
		var lab := str(labels[pos]).strip_edges()
		if lab != "":
			return lab
	return str(pos)


static func resize_switch(el, npos: int, nrows: int) -> void:
	if el == null:
		return
	el.switch_positions = clampi(npos, 2, 6)
	nrows = clampi(nrows, 1, 8)
	var need: int = nrows * 2
	while el.contact_defs.size() < need:
		var i2: int = int(el.contact_defs.size() / 2) + 1
		el.contact_defs.append({"name": str(i2 * 2 - 1), "type": "no"})
		el.contact_defs.append({"name": str(i2 * 2), "type": "no"})
	if el.contact_defs.size() > need:
		el.contact_defs.resize(need)
	ensure_switch(el)


static func switch_closed_at(el, row: int, pos: int) -> bool:
	if el == null:
		return false
	var map: Array = el.switch_map
	if row < 0 or row >= map.size():
		return false
	var r = map[row]
	if typeof(r) != TYPE_ARRAY or pos < 0 or pos >= r.size():
		return false
	return bool(r[pos])


## Создаёт дополнительные элементы группы (контакты) рядом с катушкой/кнопкой.
static func spawn_group_members(circuit, primary, origin: Vector2) -> Array:
	var created: Array = []
	if primary == null or str(primary.kind) != "electro":
		return created
	var tmpl := str(primary.group_template)
	if tmpl == "":
		return created
	var gid: int = int(primary.id)
	primary.group_id = gid
	primary.group_tag = str(primary.tag)
	primary.member_role = "main"
	primary.member_index = 0
	primary.detached = false
	var contacts: Array = primary.contact_defs
	if contacts.is_empty():
		return created
	var units: Array = _contact_units(contacts)
	var is_btn: bool = str(primary.electro_class) in ["button", "e_stop"]
	var is_coil: bool = str(primary.electro_class) in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]
	var idx := 1
	var grid: float = ElectroSymbols.SCH_GRID
	for ui in units.size():
		var unit: Array = units[ui]
		# Кнопка: столбик; катушка/КМ/KK: справа на сетке; точный layout ниже.
		var pos: Vector2
		if is_btn:
			pos = origin + Vector2(0.0, float(ui) * grid * 2.0)
		else:
			# Столбик под катушкой (точный Y задаёт layout_coil_contacts).
			pos = (origin + Vector2(0.0, float(ui + 2) * grid * 2.0)).snapped(Vector2(grid, grid))
		var child = circuit.add_element_raw("electro", pos)
		if child == null:
			continue
		child.recipe_id = str(primary.recipe_id)
		child.catalog_id = child.recipe_id
		child.electro_class = "contact"
		# Контакты группы — только на схеме; 3D-модуль у primary (кнопка/катушка).
		child.electro_mount = "none"
		child.tag_prefix = str(primary.tag_prefix)
		child.contact_defs = unit
		child.delay_on = float(primary.delay_on)
		child.delay_off = float(primary.delay_off)
		child.timer_mode = str(primary.timer_mode)
		child.timer_unit = int(primary.timer_unit)
		child.timer_value = float(primary.timer_value)
		child.group_id = gid
		child.group_tag = str(primary.tag)
		child.member_role = "contact"
		child.member_index = idx
		child.detached = false
		child.energized = false
		child.pressed = false
		child.tag = "%s.%d" % [primary.tag, idx]
		created.append(child)
		idx += 1
	if is_btn:
		# Схема контактов остаётся на primary для ПКМ; порты/рёбра — у членов.
		layout_button_contacts(circuit, primary)
	elif is_coil:
		layout_coil_contacts(circuit, primary)
	return created


## Есть ли у ввода уже ноги L/N/PE.
static func supply_has_legs(circuit, primary) -> bool:
	if primary == null or circuit == null:
		return false
	if str(primary.electro_class) != "supply":
		return false
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) == "supply_leg":
			return true
	return false


## Нога ввода по имени порта (L / N / PE / L1…).
static func supply_leg_by_port(circuit, primary, port_name: String):
	if primary == null or circuit == null:
		return null
	var want: String = str(port_name)
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) != "supply_leg":
			continue
		if str(m.phase) == want or str(m.caption) == want:
			return m
		var ports: Array = m.electro_ports if typeof(m.electro_ports) == TYPE_ARRAY else []
		for p in ports:
			if typeof(p) == TYPE_DICTIONARY and str(p.get("name", "")) == want:
				return m
	return null


## Имя базовой фазы на теле XS (L или L1) — не отцепляется.
static func supply_base_name(primary) -> String:
	if primary == null:
		return "L"
	var names: PackedStringArray = ElectroSymbols._supply_names(primary)
	if names.is_empty():
		return "L"
	return str(names[0])


## Элемент с tip порта ввода: база L на primary, остальные — supply_leg.
static func supply_endpoint_for_port(circuit, primary, port_name: String):
	if primary == null:
		return null
	var want: String = str(port_name)
	if want == "" or want == supply_base_name(primary):
		return primary
	var leg = supply_leg_by_port(circuit, primary, want)
	return leg if leg != null else primary


## Нога L (если ещё есть в старых сценах) — неотделимая база, как 1-й контакт кнопки.
static func is_supply_fixed_leg(circuit, el) -> bool:
	if el == null or circuit == null or str(el.member_role) != "supply_leg":
		return false
	var primary = circuit.get_element(int(el.group_id))
	if primary == null or str(primary.electro_class) != "supply":
		return false
	var nm: String = str(el.phase) if str(el.phase) != "" else str(el.caption)
	return nm == supply_base_name(primary)


## Создать отцепляемые ноги (N/PE или L2…N); база L остаётся на primary.
static func spawn_supply_legs(circuit, primary, origin: Vector2) -> Array:
	var created: Array = []
	if primary == null or circuit == null or str(primary.electro_class) != "supply":
		return created
	if supply_has_legs(circuit, primary):
		_fold_base_leg_into_primary(circuit, primary)
		layout_supply_legs(circuit, primary)
		return created
	var names: PackedStringArray = ElectroSymbols._supply_names(primary)
	if names.is_empty():
		return created
	var base_nm: String = str(names[0])
	var gid: int = int(primary.id)
	primary.group_id = gid
	primary.group_tag = str(primary.tag)
	primary.member_role = "main"
	primary.member_index = 0
	primary.detached = false
	primary.phase = base_nm
	primary.electro_ports = [{"name": base_nm, "type": "source"}]
	var grid: float = ElectroSymbols.SCH_GRID
	var row_h: float = ElectroSymbols.ROW_H
	var idx: int = 1
	# names[0] = база на primary; дальше — отцепляемые ноги.
	for i in range(1, names.size()):
		var nm: String = str(names[i])
		var pos: Vector2 = (origin + Vector2(0.0, float(i) * row_h)).snapped(Vector2(grid, grid))
		var child = circuit.add_element_raw("electro", pos)
		if child == null:
			continue
		child.recipe_id = str(primary.recipe_id)
		child.catalog_id = child.recipe_id
		child.electro_class = "supply_leg"
		child.electro_mount = "none"
		child.tag_prefix = str(primary.tag_prefix)
		child.voltage = float(primary.voltage)
		child.poles = int(primary.poles)
		child.phase = nm
		child.caption = nm
		child.electro_ports = [{"name": nm, "type": "source"}]
		child.group_id = gid
		child.group_tag = str(primary.tag)
		child.member_role = "supply_leg"
		child.member_index = idx
		child.detached = false
		child.tag = "%s.%s" % [primary.tag, nm]
		created.append(child)
		idx += 1
	layout_supply_legs(circuit, primary)
	return created


## Неотцепленные ноги — столбик под базой L (сам primary).
static func layout_supply_legs(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.electro_class) != "supply":
		return
	var attached: Array = []
	for el in circuit.elements:
		if str(el.kind) != "electro" or int(el.group_id) != int(primary.id):
			continue
		if str(el.member_role) != "supply_leg":
			continue
		if is_supply_fixed_leg(circuit, el):
			el.detached = false
			# Старая нога L — совместить с primary (база).
			el.position = primary.position
			el.rotation_quad = int(primary.rotation_quad)
			continue
		if bool(el.detached):
			continue
		attached.append(el)
	attached.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	var grid: float = ElectroSymbols.SCH_GRID
	var row_h: float = ElectroSymbols.ROW_H
	var ang: float = float(primary.rotation_quad) * PI * 0.5
	var pq: int = int(primary.rotation_quad)
	# Первая отцепляемая нога — сразу под рядом L.
	var y0: float = row_h
	for i in attached.size():
		var m = attached[i]
		m.rotation_quad = pq
		var want: Vector2 = (primary.position + Vector2(0.0, y0 + float(i) * row_h).rotated(ang)).snapped(Vector2(grid, grid))
		m.position = want


## Старые сцены: L на primary, N/PE — ноги; провода с primary на отцепляемые порты → ноги.
static func ensure_supply_legs(circuit, primary) -> int:
	if primary == null or circuit == null:
		return 0
	if str(primary.electro_class) != "supply" or str(primary.member_role) == "supply_leg":
		return 0
	if supply_has_legs(circuit, primary):
		var folded: int = _fold_base_leg_into_primary(circuit, primary)
		layout_supply_legs(circuit, primary)
		return folded
	var names: PackedStringArray = ElectroSymbols._supply_names(primary)
	var base_nm: String = supply_base_name(primary)
	var created: Array = spawn_supply_legs(circuit, primary, primary.position)
	if created.is_empty() and names.size() <= 1:
		primary.electro_ports = [{"name": base_nm, "type": "source"}]
		return 0
	# Провода primary → нога только для отцепляемых портов (не база L).
	var n_remap: int = 0
	for w in circuit.wires:
		for end in ["a", "b"]:
			var eid: int = int(w.a_id) if end == "a" else int(w.b_id)
			if eid != int(primary.id):
				continue
			var pn: String = str(w.a_port) if end == "a" else str(w.b_port)
			if pn == base_nm:
				continue
			var leg = supply_leg_by_port(circuit, primary, pn)
			if leg == null:
				continue
			if end == "a":
				w.a_id = int(leg.id)
			else:
				w.b_id = int(leg.id)
			n_remap += 1
	primary.electro_ports = [{"name": base_nm, "type": "source"}]
	primary.phase = base_nm
	return created.size() + n_remap


## Сцены со старым XS1.L: перенести tip на primary и убрать ногу L.
static func _fold_base_leg_into_primary(circuit, primary) -> int:
	if primary == null or circuit == null:
		return 0
	var base_nm: String = supply_base_name(primary)
	var leg = supply_leg_by_port(circuit, primary, base_nm)
	if leg == null:
		# Уже без ноги L — только выставить порт базы.
		var defs: Array = primary.electro_ports if typeof(primary.electro_ports) == TYPE_ARRAY else []
		if defs.is_empty():
			primary.electro_ports = [{"name": base_nm, "type": "source"}]
			primary.phase = base_nm
		return 0
	var n: int = 0
	var leg_id: int = int(leg.id)
	for w in circuit.wires:
		if int(w.a_id) == leg_id:
			w.a_id = int(primary.id)
			w.a_port = base_nm
			n += 1
		if int(w.b_id) == leg_id:
			w.b_id = int(primary.id)
			w.b_port = base_nm
			n += 1
	primary.electro_ports = [{"name": base_nm, "type": "source"}]
	primary.phase = base_nm
	# Без history/touch — вызывается из ensure при load.
	circuit._remove_element(leg_id, false)
	return n + 1


## Первый контакт кнопки (мин. member_index) не отделяется от актуатора.
static func is_button_fixed_contact(circuit, el) -> bool:
	if el == null or circuit == null or str(el.member_role) != "contact":
		return false
	var primary = circuit.get_element(int(el.group_id))
	if primary == null or str(primary.electro_class) not in ["button", "e_stop"]:
		return false
	var min_idx: int = 999999
	var found: bool = false
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.kind) != "electro" or str(m.member_role) != "contact":
			continue
		found = true
		min_idx = mini(min_idx, int(m.member_index))
	return found and int(el.member_index) == min_idx


## Выстраивает неотцепленные контакты кнопки в столбик под primary.
static func layout_button_contacts(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.electro_class) not in ["button", "e_stop"]:
		return
	var attached: Array = []
	for el in circuit.elements:
		if str(el.kind) != "electro" or int(el.group_id) != int(primary.id):
			continue
		if str(el.member_role) != "contact":
			continue
		# Первый контакт всегда привязан.
		if is_button_fixed_contact(circuit, el):
			el.detached = false
		elif bool(el.detached):
			continue
		attached.append(el)
	attached.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	# Шаг = ceil((низ текущего + верх следующего) / сетка) — ровно чтобы не пересекаться.
	# Столбик вдоль локального +Y primary (учитывает rotation_quad).
	var y: float = 0.0
	# Первый перекидной чуть ниже — иначе верхний НЗ врезается в скобу кнопки.
	if not attached.is_empty() and ElectroSymbols.contact_unit_type(attached[0]) == "co":
		y = ElectroSymbols.changeover_under_actuator_offset()
	var grid: float = ElectroSymbols.SCH_GRID
	var ang: float = float(primary.rotation_quad) * PI * 0.5
	var pq: int = int(primary.rotation_quad)
	for i in attached.size():
		var m = attached[i]
		m.rotation_quad = pq
		m.position = (primary.position + Vector2(0.0, y).rotated(ang)).snapped(Vector2(grid, grid))
		if i + 1 >= attached.size():
			break
		y += ElectroSymbols.button_contact_step(m, attached[i + 1])


## Выстраивает неотцепленные контакты катушки/КМ/KK столбцом ПОД primary (как у кнопки).
static func layout_coil_contacts(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.electro_class) not in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
		return
	var attached: Array = []
	for el in circuit.elements:
		if str(el.kind) != "electro" or int(el.group_id) != int(primary.id):
			continue
		if str(el.member_role) != "contact" or bool(el.detached):
			continue
		if coil_contact_hidden_on_scheme(circuit, el):
			continue
		attached.append(el)
	attached.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	var grid: float = ElectroSymbols.SCH_GRID
	var ang: float = float(primary.rotation_quad) * PI * 0.5
	var pq: int = int(primary.rotation_quad)
	# Под катушкой: от нижней грани корпуса + выступ первого контакта + ≥1 клетка.
	var first = attached[0] if not attached.is_empty() else null
	var y: float = ElectroSymbols.coil_contact_stack_y0(primary, first)
	for i in attached.size():
		var m = attached[i]
		m.rotation_quad = pq
		m.position = (primary.position + Vector2(0.0, y).rotated(ang)).snapped(Vector2(grid, grid))
		if i + 1 >= attached.size():
			break
		y += ElectroSymbols.button_contact_step(m, attached[i + 1])


## Первый контакт группы катушки/реле (мин. member_index).
static func is_coil_first_contact(circuit, el) -> bool:
	if el == null or circuit == null or str(el.member_role) != "contact":
		return false
	var primary = circuit.get_element(int(el.group_id))
	if primary == null:
		return false
	if str(primary.electro_class) not in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
		return false
	var min_idx: int = 999999
	var found: bool = false
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.kind) != "electro" or str(m.member_role) != "contact":
			continue
		found = true
		min_idx = mini(min_idx, int(m.member_index))
	return found and int(el.member_index) == min_idx


## Есть ли провод хотя бы на одном порту контакта.
static func contact_has_any_wire(circuit, el) -> bool:
	if el == null or circuit == null:
		return false
	var ports: Array = ElectroSymbols.ports(el)
	for p in ports:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var nm: String = str(p.get("name", ""))
		if nm != "" and circuit.wire_on(int(el.id), nm) != null:
			return true
	return false


## Не рисуем / не кликаем на схеме (только авто-3D или служебное).
static func hidden_on_scheme(el) -> bool:
	if el == null:
		return false
	# Концевой упор DIN — только авто в 3D по краям плотных групп, без УГО.
	if str(el.kind) == "electro" and str(el.electro_class) == "din_stop":
		return true
	# Оптонаконечники — только 3D; на схеме остаётся УГО усилителя/датчика.
	if str(el.kind) == "opto_tip":
		return true
	return false


## Скрыть на 2D: флаг primary + нет проводов + не первый контакт.
static func coil_contact_hidden_on_scheme(circuit, el) -> bool:
	if hidden_on_scheme(el):
		return true
	if el == null or circuit == null or str(el.member_role) != "contact":
		return false
	var primary = circuit.get_element(int(el.group_id))
	if primary == null or not bool(primary.hide_unused_contacts):
		return false
	if str(primary.electro_class) not in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
		return false
	if is_coil_first_contact(circuit, el):
		return false
	if bool(el.detached):
		# Вынесенный без проводов тоже прячем — иначе «висит» пустым.
		return not contact_has_any_wire(circuit, el)
	return not contact_has_any_wire(circuit, el)


## Копия контакта: добавить единицу в contact_defs primary и синхронизировать члены.
static func adopt_pasted_coil_contact(circuit, primary, contact_el) -> void:
	if primary == null or contact_el == null or circuit == null:
		return
	# KT: только один фиксированный перекидной — не раздувать contact_defs.
	if str(primary.electro_class) == "timer_relay":
		normalize_timer_relay(primary)
		sync_coil_contact_members(circuit, primary)
		return
	var kind: String = ElectroSymbols.contact_unit_type(contact_el)
	var kinds: Array = coil_aux_contact_kinds(primary)
	kinds.append(kind)
	primary.contact_defs = make_coil_contact_defs(primary, kinds)
	if str(primary.group_template) == "":
		primary.group_template = "coil"
	# Вставленный — в конец списка единиц.
	contact_el.member_index = 100000
	sync_coil_contact_members(circuit, primary)


## Сопоставить члены-контакты единицам primary.contact_defs (по member_index).
static func sync_coil_contact_members(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	var units: Array = _contact_units(primary.contact_defs)
	var members: Array = []
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.member_role) == "contact":
			members.append(m)
	members.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	var n: int = mini(members.size(), units.size())
	for i in n:
		var unit: Array = units[i]
		var m = members[i]
		m.contact_defs = []
		for d in unit:
			if typeof(d) == TYPE_DICTIONARY:
				m.contact_defs.append((d as Dictionary).duplicate(true))
		m.member_index = i + 1
		m.group_id = int(primary.id)
		m.group_tag = str(primary.tag)


## Пересобрать члены-контакты кнопки по contact_defs primary (провода сохраняются).
static func rebuild_button_contacts(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.electro_class) not in ["button", "e_stop"]:
		return
	var gid: int = int(primary.id)
	primary.group_id = gid
	primary.member_role = "main"
	primary.group_template = "button"
	_rebuild_group_contacts_keep_wires(circuit, primary)


## Убрать единицу контакта из перечня кнопки и перенумеровать оставшихся членов.
static func drop_button_contact_unit(circuit, primary, member_index: int) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.electro_class) not in ["button", "e_stop"]:
		return
	var kinds: Array = button_contact_kinds(primary)
	var unit_i: int = int(member_index) - 1
	if unit_i < 0 or unit_i >= kinds.size():
		return
	# Последний/единственный ключ не выкидываем из перечня отдельно.
	if kinds.size() <= 1:
		return
	kinds.remove_at(unit_i)
	primary.contact_defs = make_button_contact_defs(kinds)
	primary.group_template = "button"
	var members: Array = []
	for m in circuit.electro_group_members(int(primary.id)):
		if str(m.kind) != "electro" or str(m.member_role) != "contact":
			continue
		members.append(m)
	members.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	var units: Array = _contact_units(primary.contact_defs)
	for i in members.size():
		var m = members[i]
		m.member_index = i + 1
		m.group_id = int(primary.id)
		m.group_tag = str(primary.tag)
		if i < units.size():
			m.contact_defs = (units[i] as Array).duplicate(true)
	layout_button_contacts(circuit, primary)


## Пересобрать контакты реле/контактора/теплового по contact_defs primary (провода сохраняются).
static func rebuild_coil_contacts(circuit, primary) -> void:
	if primary == null or circuit == null:
		return
	if str(primary.electro_class) not in ["relay", "timer_relay", "contactor", "thermal", "voltage_relay"]:
		return
	var gid: int = int(primary.id)
	primary.group_id = gid
	primary.member_role = "main"
	if str(primary.group_template) == "":
		primary.group_template = "coil"
	_rebuild_group_contacts_keep_wires(circuit, primary)


## Снимок / перенос жил при пересборке контактов группы (по member_index + индекс порта).
static func _rebuild_group_contacts_keep_wires(circuit, primary) -> void:
	var gid: int = int(primary.id)
	var old_members: Array = []
	for el in circuit.elements:
		if str(el.kind) != "electro" or int(el.group_id) != gid:
			continue
		if str(el.member_role) != "contact":
			continue
		old_members.append(el)
	old_members.sort_custom(func(a, b): return int(a.member_index) < int(b.member_index))
	# mi -> {id, ports: PackedStringArray в порядке УГО}
	var old_meta: Dictionary = {}
	var doomed: Dictionary = {}
	for m in old_members:
		var mi: int = int(m.member_index)
		var ports: PackedStringArray = PackedStringArray()
		for p in ElectroSymbols.ports(m):
			ports.append(str(p.get("name", "")))
		old_meta[mi] = {"id": int(m.id), "ports": ports, "detached": bool(m.detached), "pos": m.position}
		doomed[int(m.id)] = mi
	# Снимки жил к контактам (до удаления).
	var snaps: Array = []
	for w in circuit.wires:
		var aid: int = int(w.a_id)
		var bid: int = int(w.b_id)
		var a_mi: int = int(doomed.get(aid, -1))
		var b_mi: int = int(doomed.get(bid, -1))
		if a_mi < 0 and b_mi < 0:
			continue
		var joints_copy: Array = []
		if typeof(w.joints) == TYPE_ARRAY:
			joints_copy = (w.joints as Array).duplicate(true)
		snaps.append({
			"a_id": aid, "a_port": str(w.a_port), "a_mi": a_mi,
			"b_id": bid, "b_port": str(w.b_port), "b_mi": b_mi,
			"joints": joints_copy,
			"broken": bool(w.broken),
			"num": int(w.num),
			"color_id": str(w.color_id),
			"id_mm": float(w.id_mm),
			"od_mm": float(w.od_mm),
			"num_offset": w.num_offset,
			"num_offset_b": w.num_offset_b,
		})
	# Мягкое удаление контактов (жилы к ним выкидываем — вернём после spawn).
	for mi2 in old_meta.keys():
		var oid: int = int((old_meta[mi2] as Dictionary)["id"])
		circuit._remove_element(oid, false, {
			"promote_fixed_button": false,
			"sync_button_defs": false,
		})
	spawn_group_members(circuit, primary, primary.position)
	# mi -> new contact
	var new_by_mi: Dictionary = {}
	for m2 in circuit.electro_group_members(gid):
		if str(m2.member_role) != "contact":
			continue
		new_by_mi[int(m2.member_index)] = m2
		var prev: Dictionary = old_meta.get(int(m2.member_index), {}) as Dictionary
		if not prev.is_empty():
			if bool(prev.get("detached", false)):
				m2.detached = true
				m2.position = prev.get("pos", m2.position)
	# Восстановить жилы: тот же member_index, порт по индексу в списке портов.
	var restored: int = 0
	for s in snaps:
		var sd: Dictionary = s as Dictionary
		var na: int = int(sd["a_id"])
		var nb: int = int(sd["b_id"])
		var pa: String = str(sd["a_port"])
		var pb: String = str(sd["b_port"])
		var ami: int = int(sd["a_mi"])
		var bmi: int = int(sd["b_mi"])
		if ami >= 0:
			var nm_a = new_by_mi.get(ami)
			if nm_a == null:
				continue
			pa = _remap_contact_port_name(old_meta.get(ami, {}), nm_a, pa)
			na = int(nm_a.id)
		if bmi >= 0:
			var nm_b = new_by_mi.get(bmi)
			if nm_b == null:
				continue
			pb = _remap_contact_port_name(old_meta.get(bmi, {}), nm_b, pb)
			nb = int(nm_b.id)
		if circuit.get_element(na) == null or circuit.get_element(nb) == null:
			continue
		if Geom.port_by_name(circuit.get_element(na), pa).is_empty():
			continue
		if Geom.port_by_name(circuit.get_element(nb), pb).is_empty():
			continue
		var joints_r: Array = sd.get("joints", []) as Array
		if circuit._add_wire_raw_ex(na, pa, nb, pb, joints_r):
			var nw = circuit.wires[circuit.wires.size() - 1]
			nw.broken = bool(sd.get("broken", false))
			if int(sd.get("num", 0)) > 0:
				nw.num = int(sd["num"])
			nw.color_id = str(sd.get("color_id", nw.color_id))
			nw.id_mm = float(sd.get("id_mm", nw.id_mm))
			nw.od_mm = float(sd.get("od_mm", nw.od_mm))
			nw.num_offset = sd.get("num_offset", Vector2.ZERO)
			nw.num_offset_b = sd.get("num_offset_b", Vector2.ZERO)
			WireRouter2D.invalidate_wire(int(nw.id))
			restored += 1
	if not snaps.is_empty() and restored == 0:
		# Не трогали жилы чужих элементов — точечный invalidate достаточeн.
		pass
	# Без полного WireRouter2D.invalidate() — иначе фриз на плотной схеме.
	circuit.invalidate_port_wire_index()


static func _remap_contact_port_name(old_meta: Dictionary, new_el, old_port: String) -> String:
	var want: String = str(old_port)
	if new_el == null:
		return want
	if not Geom.port_by_name(new_el, want).is_empty():
		return want
	var old_ports: PackedStringArray = old_meta.get("ports", PackedStringArray()) as PackedStringArray
	var idx: int = -1
	for i in old_ports.size():
		if str(old_ports[i]) == want:
			idx = i
			break
	if idx < 0:
		return want
	var new_ports: Array = ElectroSymbols.ports(new_el)
	if idx < new_ports.size():
		return str((new_ports[idx] as Dictionary).get("name", want))
	if not new_ports.is_empty():
		return str((new_ports[0] as Dictionary).get("name", want))
	return want


## Типы единиц контактов реле/КМ/KK (без силовых 1…6 контактора).
static func coil_aux_contact_kinds(el) -> Array:
	var out: Array = []
	if el == null:
		return out
	for unit in _contact_units(el.contact_defs):
		if unit.is_empty() or typeof(unit[0]) != TYPE_DICTIONARY:
			continue
		var nm: String = str(unit[0].get("name", ""))
		# Силовые 1…6 контактора не трогаем в списке «вспомогательных».
		if nm in ["1", "2", "3", "4", "5", "6"]:
			continue
		var t := str(unit[0].get("type", "no"))
		if t == "co":
			out.append("co")
		elif t == "nc":
			out.append("nc")
		else:
			out.append("no")
	return out


## Силовые пары контактора (1-2, 3-4, 5-6), если есть.
static func coil_power_contact_defs(el) -> Array:
	var out: Array = []
	if el == null:
		return out
	for unit in _contact_units(el.contact_defs):
		if unit.is_empty() or typeof(unit[0]) != TYPE_DICTIONARY:
			continue
		var nm: String = str(unit[0].get("name", ""))
		if nm in ["1", "2", "3", "4", "5", "6"]:
			for p in unit:
				out.append(p)
	return out


## kinds вспом.: "no"|"nc"|"co" — собрать defs (силовые КМ сохраняются спереди).
## Нумерация по индексу единицы (11/21…), без коллизий при смеси НО+перекидной.
static func make_coil_contact_defs(el, aux_kinds: Array) -> Array:
	var out: Array = coil_power_contact_defs(el)
	for ui in aux_kinds.size():
		var kind: String = str(aux_kinds[ui])
		var base: int = 11 + ui * 10
		match kind:
			"nc":
				out.append({"name": str(base), "type": "nc"})
				out.append({"name": str(base + 1), "type": "nc"})
			"co":
				out.append({"name": str(base), "type": "co"})
				out.append({"name": str(base + 1), "type": "nc"})
				out.append({"name": str(base + 3), "type": "no"})
			_:
				out.append({"name": str(base + 2), "type": "no"})
				out.append({"name": str(base + 3), "type": "no"})
	return out


## kinds: "no" | "nc" | "co" — собрать contact_defs с ГОСТ-номерами.
static func make_button_contact_defs(kinds: Array) -> Array:
	var out: Array = []
	var no_i := 0
	var nc_i := 0
	var co_i := 0
	for k in kinds:
		var kind := str(k)
		match kind:
			"nc":
				var base: int = 11 + nc_i * 10
				out.append({"name": str(base), "type": "nc"})
				out.append({"name": str(base + 1), "type": "nc"})
				nc_i += 1
			"co":
				var base2: int = 11 + co_i * 10
				out.append({"name": str(base2), "type": "co"})
				out.append({"name": str(base2 + 1), "type": "nc"})
				out.append({"name": str(base2 + 3), "type": "no"})
				co_i += 1
			_:
				var base3: int = 13 + no_i * 10
				out.append({"name": str(base3), "type": "no"})
				out.append({"name": str(base3 + 1), "type": "no"})
				no_i += 1
	return out


## Типы единиц контактов кнопки из contact_defs primary.
static func button_contact_kinds(el) -> Array:
	var out: Array = []
	if el == null:
		return out
	for unit in _contact_units(el.contact_defs):
		if unit.is_empty():
			continue
		var a: Dictionary = unit[0] if typeof(unit[0]) == TYPE_DICTIONARY else {}
		var t := str(a.get("type", "no"))
		if t == "co":
			out.append("co")
		elif t == "nc":
			out.append("nc")
		else:
			out.append("no")
	return out


static func _contact_units(contacts: Array) -> Array:
	# Единицы: пара НО/НЗ (2) или перекидной (3: common + nc + no).
	var out: Array = []
	var i := 0
	while i < contacts.size():
		var a: Dictionary = contacts[i] if typeof(contacts[i]) == TYPE_DICTIONARY else {}
		var t := str(a.get("type", "no"))
		if t == "co":
			var unit: Array = [a]
			if i + 1 < contacts.size():
				unit.append(contacts[i + 1])
			if i + 2 < contacts.size():
				unit.append(contacts[i + 2])
			out.append(unit)
			i += unit.size()
			continue
		var unit2: Array = [a]
		if i + 1 < contacts.size():
			var b: Dictionary = contacts[i + 1] if typeof(contacts[i + 1]) == TYPE_DICTIONARY else {}
			if str(b.get("type", "")) == t:
				unit2.append(b)
				i += 2
			else:
				i += 1
		else:
			i += 1
		out.append(unit2)
	return out


static func _pair_contacts(contacts: Array) -> Array:
	return _contact_units(contacts)


static func _to_array(value) -> Array:
	var out: Array = []
	if value is Array:
		for x in value:
			if typeof(x) == TYPE_DICTIONARY:
				out.append((x as Dictionary).duplicate(true))
			else:
				out.append(x)
	return out


static func _to_string_array(value) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for x in value:
			out.append(str(x))
	return out


static func _load_recipes() -> void:
	_recipes.clear()
	_recipe_order = PackedStringArray()
	if not FileAccess.file_exists(RECIPES_PATH):
		push_warning("Electro recipes missing: %s" % RECIPES_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RECIPES_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid electro recipes JSON")
		return
	var list: Array = parsed.get("recipes", [])
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rid := str(item.get("id", ""))
		if rid == "":
			continue
		_recipes[rid] = item
		_recipe_order.append(rid)
