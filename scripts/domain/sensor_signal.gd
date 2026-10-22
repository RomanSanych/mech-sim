class_name SensorSignal
extends RefCounted
## Модель сигнала датчика: дискретный + задел под аналог / ТС.


const OUT_CONTACT := "contact"
const OUT_NPN := "npn"
const OUT_PNP := "pnp"

const FORM_NO := "no"
const FORM_NC := "nc"

const SUPPLY_24DC := "24dc"
const SUPPLY_220AC := "220ac"

## Аналог (A6 УЗ / волна B).
const ANALOG_NONE := ""
const ANALOG_4_20MA := "4_20ma"
const ANALOG_0_10V := "0_10v"
const ANALOG_0_1V := "0_1v"
const ANALOG_RTD := "rtd"

## Схема ТС: 2 / 3 / 4 провода (B3).
const WIRE_2 := 2
const WIRE_3 := 3
const WIRE_4 := 4


static func normalize_analog(t: String) -> String:
	match str(t).to_lower():
		"4_20ma", "4-20ma", "4…20ma", "ma", "i":
			return ANALOG_4_20MA
		"0_1v", "0-1v", "0…1v":
			return ANALOG_0_1V
		"0_10v", "0-10v", "0…10v", "v", "u":
			return ANALOG_0_10V
		"rtd", "pt100", "tc":
			return ANALOG_RTD
		"":
			return ANALOG_NONE
		_:
			return ANALOG_NONE


static func analog_label(kind: String) -> String:
	match normalize_analog(kind):
		ANALOG_4_20MA:
			return "4…20 мА"
		ANALOG_0_1V:
			return "0…1 В"
		ANALOG_0_10V:
			return "0…10 В"
		ANALOG_RTD:
			return "ТС (сопротивление)"
		_:
			return "—"


## Шкала аналога: t∈[0..1] → физическая величина (В или мА). Без питания / вне диапазона — 0.
static func analog_from_norm(kind: String, t: float, valid: bool) -> float:
	if not valid:
		return 0.0
	var u: float = clampf(t, 0.0, 1.0)
	match normalize_analog(kind):
		ANALOG_4_20MA:
			return 4.0 + u * 16.0
		ANALOG_0_1V:
			return u * 1.0
		ANALOG_0_10V:
			return u * 10.0
		_:
			return u


static func analog_unit(kind: String) -> String:
	match normalize_analog(kind):
		ANALOG_4_20MA:
			return "мА"
		ANALOG_0_1V, ANALOG_0_10V:
			return "В"
		_:
			return ""


static func normalize_output(t: String) -> String:
	match str(t).to_lower():
		"pnp":
			return OUT_PNP
		"contact", "relay", "dry":
			return OUT_CONTACT
		_:
			return OUT_NPN


static func normalize_form(t: String) -> String:
	return FORM_NC if str(t).to_lower() == "nc" else FORM_NO


static func normalize_supply(t: String) -> String:
	var s: String = str(t).to_lower()
	if s in ["220ac", "220", "ac", "230ac"]:
		return SUPPLY_220AC
	return SUPPLY_24DC


static func supply_label(mode: String) -> String:
	return "~ 220 В" if normalize_supply(mode) == SUPPLY_220AC else "= 24 В"


static func port_plus_label(mode: String) -> String:
	return "L1" if normalize_supply(mode) == SUPPLY_220AC else "+24"


static func port_minus_label(mode: String) -> String:
	return "N" if normalize_supply(mode) == SUPPLY_220AC else "0V"


## Минимальный перепад для признания питания активной головки.
static func supply_need_v(mode: String) -> float:
	return 90.0 if normalize_supply(mode) == SUPPLY_220AC else 10.0


## Согласование типа выхода с типом входа прибора (учебное правило).
static func output_matches_input(output_type: String, input_type: String) -> bool:
	var o: String = normalize_output(output_type)
	var i: String = str(input_type).to_lower()
	if i == "" or i == "any":
		return true
	if o == OUT_CONTACT:
		return i in ["contact", "dry", "relay", "any"]
	if o == OUT_NPN:
		return i in ["npn", "sinking", "any"]
	if o == OUT_PNP:
		return i in ["pnp", "sourcing", "any"]
	return true
