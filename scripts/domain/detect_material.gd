class_name DetectMaterial
extends RefCounted
## Маркировка материала / detect-свойств для датчиков.
## Датчики фильтруют цели по физике, не по type==target.


## Чёрный металл (ферромагнетик) — номинал для индуктивных.
const STEEL := "steel"
## Цветные металлы — ослабленная зона Sn у индуктивных.
const ALUMINUM := "aluminum"
const BRASS := "brass"
const COPPER := "copper"
const STAINLESS := "stainless"
## Не металл / диэлектрики (ёмкостный БВ).
const PLASTIC := "plastic"
const DIELECTRIC := "dielectric"
const PAPER := "paper"
const WOOD := "wood"
const GLASS := "glass"
const WATER := "water"
const LIQUID := "liquid"
## Источники полей (геркон / магнит) — A2.
const MAGNET := "magnet"
## Оптика — задел под A4.
const REFLECTOR := "reflector"


static func normalize(tag: String) -> String:
	var t: String = str(tag).strip_edges().to_lower()
	match t:
		"fe", "ferrous", "iron", "чёрный", "черный", "сталь":
			return STEEL
		"al", "aluminium", "алюминий":
			return ALUMINUM
		"cu", "медь":
			return COPPER
		"ms", "латунь":
			return BRASS
		"ss", "нерж", "нержавейка":
			return STAINLESS
		"plastic", "пластмасса", "abs", "pa", "fitting", "упаковка", "packaging":
			return PLASTIC
		"dielectric", "диэлектрик":
			return DIELECTRIC
		"paper", "бумага", "картон", "cardboard":
			return PAPER
		"wood", "дерево", "древесина":
			return WOOD
		"glass", "стекло":
			return GLASS
		"water", "вода":
			return WATER
		"liquid", "жидкость", "oil", "масло":
			return LIQUID
		"magnet", "магнит":
			return MAGNET
		"reflector", "отражатель":
			return REFLECTOR
		"":
			return ""
		_:
			return t


static func is_metal(tag: String) -> bool:
	var t: String = normalize(tag)
	return t in [STEEL, ALUMINUM, BRASS, COPPER, STAINLESS]


static func is_ferrous(tag: String) -> bool:
	return normalize(tag) == STEEL


## Коэффициент дальности индуктивного БВ (1.0 = номинал Sn для стали).
static func inductive_range_factor(tag: String) -> float:
	match normalize(tag):
		STEEL:
			return 1.0
		STAINLESS:
			return 0.7
		ALUMINUM:
			# Каталог ~0.35–0.45 Sn; чуть мягче для учебного зазора «перед корпусом ПЦ».
			return 0.5
		BRASS:
			return 0.45
		COPPER:
			return 0.35
		_:
			return 0.0


## Коэффициент дальности ёмкостного БВ (1.0 ≈ номинал Sn по воде / сильному диэлектрику).
## Учебная модель: диэлектрики/жидкости/упаковка — основные цели; металл тоже
## поднимает C, но иначе, чем индуктивный Sn по стали (не путать).
static func capacitive_range_factor(tag: String) -> float:
	match normalize(tag):
		WATER, LIQUID:
			return 1.0
		DIELECTRIC:
			return 0.95
		PLASTIC:
			return 0.85
		GLASS:
			return 0.65
		WOOD:
			return 0.55
		PAPER:
			return 0.5
		STEEL, STAINLESS:
			return 0.7
		ALUMINUM, BRASS:
			return 0.55
		COPPER:
			return 0.5
		MAGNET, REFLECTOR:
			return 0.0
		_:
			return 0.0


## Перекрывает луч (барьер / путь к рефлектору). Почти всё непрозрачно.
static func optical_occludes(tag: String) -> bool:
	var t: String = normalize(tag)
	if t == "":
		return true
	return true


## Коэффициент диффузного отражения (1.0 ≈ белая карта / рефлектор).
static func optical_diffuse_factor(tag: String) -> float:
	match normalize(tag):
		REFLECTOR:
			return 1.0
		STEEL, STAINLESS, ALUMINUM:
			return 0.85
		BRASS, COPPER:
			return 0.75
		PLASTIC, PAPER:
			return 0.7
		WOOD:
			return 0.55
		GLASS:
			return 0.25
		WATER, LIQUID, DIELECTRIC:
			return 0.35
		MAGNET:
			return 0.6
		_:
			return 0.5


static func is_reflector(tag: String) -> bool:
	return normalize(tag) == REFLECTOR


## Коэффициент эха УЗ (1.0 ≈ твёрдая плоская поверхность перпендикулярно оси).
## Почти все твёрдые тела отражают; мягкие/пористые — слабее (учебная модель).
static func ultrasonic_echo_factor(tag: String) -> float:
	match normalize(tag):
		STEEL, STAINLESS, ALUMINUM, BRASS, COPPER:
			return 1.0
		PLASTIC, DIELECTRIC, GLASS, WOOD, PAPER:
			return 0.9
		WATER, LIQUID:
			return 0.85
		REFLECTOR:
			return 1.0
		MAGNET:
			return 0.8
		"":
			return 0.75
		_:
			return 0.7


static func is_dielectric(tag: String) -> bool:
	var t: String = normalize(tag)
	return t in [PLASTIC, DIELECTRIC, PAPER, WOOD, GLASS, WATER, LIQUID]


## Материал по умолчанию для корпуса элемента (если detect_material пуст).
## ПЦ: алюминиевый корпус; фитинги — пластик (отдельно на мешах).
static func default_for_element(el) -> String:
	if el == null:
		return ""
	var override: String = ""
	if "detect_material" in el:
		override = normalize(str(el.detect_material))
	if override != "":
		return override
	match str(el.kind):
		"cylinder", "rotary_cylinder":
			return ALUMINUM
		"air_motor", "valve", "source":
			return ALUMINUM
		"junction":
			# Фитинги / тройники — пластик (цанги).
			return PLASTIC
		"accessory":
			var cls: String = str(el.accessory_class)
			if cls in ["reservoir"]:
				return ALUMINUM
			# Корпуса арматуры — металл; учебный дефолт алюминий.
			return ALUMINUM
		"sensor", "electro", "rail", "coil", "opto_tip":
			return PLASTIC
		_:
			return ALUMINUM


## Тег detect у узла меша (meta) или у элемента.
static func tag_of_node(node: Node, el = null) -> String:
	if node != null and node.has_meta("detect_material"):
		return normalize(str(node.get_meta("detect_material")))
	return default_for_element(el)
