extends PanelContainer
## Выпадающая панель параметров элемента/линии (в том же _ctx, что и меню частей).

const Catalog = preload("res://scripts/domain/cylinder_catalog.gd")

var circuit = null
var target_kind := "" # element | wire
var target_id := -1
var _lock := false
var _box: VBoxContainer
var _live: Label
var _force: Label
var _calc: Label
var _warn: Label
var _spin_stroke: SpinBox
var _closed: Callable = Callable()


func _ready() -> void:
	custom_minimum_size = Vector2(280, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	margin.add_child(_box)


func open_target(kind: String, id: int) -> void:
	target_kind = kind
	target_id = id
	_rebuild()


func set_on_close(cb: Callable) -> void:
	_closed = cb


func _process(_dt: float) -> void:
	if not visible or circuit == null or not is_inside_tree():
		return
	if target_kind == "wire":
		var wire = circuit.get_wire(target_id)
		if wire == null:
			_request_close()
			return
		if _live:
			_live.text = "Сейчас: %.2f бар, расход %.1f л/мин" % [
				(wire.pressure - 101325.0) / 1.0e5, wire.flow_m3s * 60000.0,
			]
		return
	var el = circuit.get_element(target_id) if target_kind == "element" else null
	if el == null:
		_request_close()
		return
	if el.kind == "cylinder" and _live:
		var p_cap = el.p_cap if circuit.has_channel(el, "cap") else 101325.0
		var p_rod = el.p_rod if circuit.has_channel(el, "rod") else 101325.0
		_live.text = "Ход %.1f мм · v %.2f м/с\nPп %.2f бар · Pш %.2f бар" % [
			el.x * 1000.0, el.v,
			(p_cap - 101325.0) / 1.0e5, (p_rod - 101325.0) / 1.0e5,
		]
		if _force:
			_force.text = circuit.explain_force(el)
		if _calc:
			_calc.text = Catalog.card(el)


func _rebuild() -> void:
	_lock = true
	while _box.get_child_count() > 0:
		var child := _box.get_child(0)
		_box.remove_child(child)
		child.free()
	_live = null
	_force = null
	_calc = null
	_warn = null
	_spin_stroke = null
	if target_kind == "wire":
		_build_wire()
	else:
		var el = circuit.get_element(target_id)
		if el == null:
			_lock = false
			_request_close()
			return
		_build_element(el)
	_lock = false


func _build_element(el) -> void:
	var title := Label.new()
	title.text = el.tag if el.tag != "" else ("Цилиндр" if el.kind == "cylinder" else "Источник")
	title.add_theme_color_override("font_color", Color(0.10, 0.14, 0.18))
	_box.add_child(title)
	_box.add_child(_rule())
	var tag := LineEdit.new()
	tag.text = el.tag
	tag.placeholder_text = "Обозначение"
	tag.text_changed.connect(func(value):
		if _lock:
			return
		el.tag = value.strip_edges()
		title.text = el.tag if el.tag != "" else title.text
	)
	_box.add_child(_labeled("Обозначение", tag))
	if el.kind == "source":
		_build_source(el)
		return
	var geom_note: String = circuit.retune_geometry(el)
	_box.add_child(_warning_label())
	if geom_note != "":
		_set_warn(geom_note)
	var bore_box := OptionButton.new()
	var bore_index := 0
	var bore_i := 0
	for bore in Catalog.bores():
		bore_box.add_item("∅ %.0f мм" % float(bore))
		bore_box.set_item_metadata(bore_i, float(bore))
		if absf(float(bore) - float(el.bore_mm)) < 0.1:
			bore_index = bore_i
		bore_i += 1
	bore_box.selected = bore_index
	bore_box.item_selected.connect(func(idx: int):
		if _lock:
			return
		el.bore_mm = float(bore_box.get_item_metadata(idx))
		_commit_cylinder(el)
		call_deferred("_rebuild")
	)
	_box.add_child(_labeled("Диаметр поршня", bore_box))
	var row: Dictionary = Catalog.bore_row(float(el.bore_mm))
	var rod_box := OptionButton.new()
	var rod_index := 0
	var rod_i := 0
	for rod in row["rods"]:
		rod_box.add_item(Catalog.rod_label(float(el.bore_mm), float(rod)))
		rod_box.set_item_metadata(rod_i, float(rod))
		if absf(float(rod) - float(el.rod_mm)) < 0.1:
			rod_index = rod_i
		rod_i += 1
	rod_box.selected = rod_index
	rod_box.disabled = str(el.rod_mode) == "rodless"
	rod_box.item_selected.connect(func(idx: int):
		if _lock:
			return
		el.rod_mm = float(rod_box.get_item_metadata(idx))
		if str(el.rod_mode) == "rodless":
			el.rod_mode = "single"
		_commit_cylinder(el)
		call_deferred("_rebuild")
	)
	_box.add_child(_labeled("Диаметр штока", rod_box))
	var hi := float(row["smax"])
	_spin_stroke = _spin(el.stroke_mm, 5, hi, 1, func(v):
		el.stroke_mm = v
		_commit_cylinder(el)
	)
	_box.add_child(_labeled("Ход, мм", _spin_stroke))
	_box.add_child(_labeled("Нагрузка, Н", _spin(el.load_n, -2000, 8000, 5, func(v): el.load_n = v)))
	_box.add_child(_check("Неподключённый канал → атмосфера", el.open_ports, func(v): el.open_ports = v))
	_calc = Label.new()
	_calc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_calc.add_theme_font_size_override("font_size", 11)
	_box.add_child(_calc)
	_force = Label.new()
	_force.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_force.add_theme_font_size_override("font_size", 11)
	_box.add_child(_force)
	_live = Label.new()
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live.add_theme_font_size_override("font_size", 11)
	_box.add_child(_live)
	_box.add_child(_rule())
	_box.add_child(_close_button())


func _build_source(el) -> void:
	var pressure: SpinBox
	pressure = _spin(el.pressure_bar, 0, 16, 0.1, func(v):
		el.pressure_bar = v
		_set_warn(circuit.retune_source(el))
		_lock = true
		pressure.set_value_no_signal(el.pressure_bar)
		_lock = false
	)
	var temp: SpinBox
	temp = _spin(el.temperature_c, -20, 80, 1, func(v):
		el.temperature_c = v
		_set_warn(circuit.retune_source(el))
		_lock = true
		temp.set_value_no_signal(el.temperature_c)
		_lock = false
	)
	_box.add_child(_warning_label())
	_box.add_child(_labeled("Давление, бар (изб.)", pressure))
	_box.add_child(_labeled("Температура, °C", temp))
	_box.add_child(_close_button())


func _build_wire() -> void:
	var wire = circuit.get_wire(target_id)
	var title := Label.new()
	title.text = "Линия"
	title.add_theme_color_override("font_color", Color(0.10, 0.14, 0.18))
	_box.add_child(title)
	_box.add_child(_rule())
	if wire == null:
		return
	var diameter: SpinBox
	diameter = _spin(wire.id_mm, 1.5, 16, 0.5, func(v):
		wire.id_mm = v
		circuit.retune_wire(wire)
		_lock = true
		diameter.set_value_no_signal(wire.id_mm)
		_lock = false
	)
	_box.add_child(_labeled("Внутр. диаметр, мм", diameter))
	_live = Label.new()
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live.add_theme_font_size_override("font_size", 11)
	_box.add_child(_live)
	_box.add_child(_close_button())


func _close_button() -> Button:
	var button := Button.new()
	button.text = "Закрыть"
	button.custom_minimum_size = Vector2(0, 28)
	button.pressed.connect(_request_close)
	return button


func _request_close() -> void:
	if _closed.is_valid():
		_closed.call()
	elif get_parent():
		visible = false


func _rule() -> Control:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(0.78, 0.82, 0.86)
	return rule


func _labeled(caption: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 11)
	box.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return box


func _spin(value: float, lo: float, hi: float, step: float, apply: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = value
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v):
		if _lock:
			return
		apply.call(v)
	)
	return spin


func _warning_label() -> Label:
	_warn = Label.new()
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.add_theme_color_override("font_color", Color(0.70, 0.28, 0.06))
	_warn.add_theme_font_size_override("font_size", 11)
	_warn.visible = false
	return _warn


func _set_warn(msg: String) -> void:
	if _warn == null:
		return
	_warn.text = msg
	_warn.visible = msg != ""
	if msg != "" and circuit:
		circuit.notify(msg)


func _commit_cylinder(el) -> void:
	var msg: String = circuit.retune_geometry(el)
	_lock = true
	if _spin_stroke:
		_spin_stroke.set_value_no_signal(el.stroke_mm)
	_lock = false
	_set_warn(msg)


func _check(caption: String, value: bool, apply: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = caption
	box.button_pressed = value
	box.toggled.connect(func(v):
		if _lock:
			return
		apply.call(v)
	)
	return box
