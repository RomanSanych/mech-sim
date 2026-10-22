class_name SimVis
extends RefCounted
## Визуализация симуляции: цвет давления, шарики расхода, тексты tip.

const ATM := 101325.0
## Минимальная шкала избытка, Па (~0.5 бар), чтобы не взрывать контраст при почти-атм.
const P_OVER_FLOOR := 0.5e5
## Шкала разряжения для красного, Па (~1 бар).
const P_UNDER_SCALE := 1.0e5
## Ниже ~0.3 Nl/мин конусы/стрелки гаснут. Раньше 2.5e-5 (~1.5 Nl/мин) — дозаряд при росте P уже «молчал».
const FLOW_DEAD := 5.0e-6


static func gauge_over(p_pa: float) -> float:
	return maxf(float(p_pa) - ATM, 0.0)


static func gauge_under(p_pa: float) -> float:
	return clampf((ATM - float(p_pa)) / P_UNDER_SCALE, 0.0, 1.0)


## Цвет по давлению относительно текущего max избытка (3D-шланги).
## 0 (ATM) → светло-серый; mid → яркий синий; max → тёмно-синий.
static func pressure_color(p_pa: float, base: Color = Color(0.80, 0.81, 0.82), max_over_pa: float = 0.0) -> Color:
	return _pressure_color_ramp(p_pa, base, max_over_pa, 2.15, 0.72)


## 2D-схема: тонкие линии на бумаге — нужна более линейная шкала и сильнее разнесённые ступени.
static func pressure_color_2d(p_pa: float, base: Color = Color(0.80, 0.81, 0.82), max_over_pa: float = 0.0) -> Color:
	return _pressure_color_ramp(p_pa, base, max_over_pa, 1.15, 0.52)


static func _pressure_color_ramp(
	p_pa: float,
	base: Color,
	max_over_pa: float,
	gamma: float,
	mid_stop: float
) -> Color:
	var under: float = gauge_under(p_pa)
	if under > 0.02:
		var deep_r := Color(0.85, 0.18, 0.14)
		return base.lerp(deep_r, clampf(0.45 + under * 0.55, 0.0, 1.0))
	var over: float = gauge_over(p_pa)
	if over < 500.0:
		return base
	var scale: float = maxf(float(max_over_pa), P_OVER_FLOOR)
	var t: float = clampf(over / scale, 0.0, 1.0)
	t = pow(t, gamma)
	var pale := Color(0.80, 0.81, 0.82)
	var mid := Color(0.05, 0.38, 1.0)
	var deep := Color(0.02, 0.14, 0.48)
	var stop: float = clampf(mid_stop, 0.2, 0.9)
	if t <= stop:
		return pale.lerp(mid, t / stop)
	return mid.lerp(deep, (t - stop) / (1.0 - stop))


static func pressure_color_fill(p_pa: float, max_over_pa: float = 0.0) -> Color:
	# Заливки УГО на схеме — та же 2D-шкала.
	var c: Color = pressure_color_2d(p_pa, Color(0.86, 0.87, 0.89), max_over_pa)
	var t: float = 0.0
	if max_over_pa > 1.0:
		t = clampf(gauge_over(p_pa) / maxf(max_over_pa, P_OVER_FLOOR), 0.0, 1.0)
	c.a = 0.22 + 0.62 * t
	return c


static func bar_gauge(p_pa: float) -> float:
	return (float(p_pa) - ATM) / 1.0e5


static func format_bar(p_pa: float) -> String:
	return "%.2f бар" % bar_gauge(p_pa)


## Объёмный расход м³/с → Nl/мин (норм. ≈ при ATM, 20°C).
static func m3s_to_nl_min(q_m3s: float) -> float:
	return float(q_m3s) * 60000.0


static func format_flow(q_m3s: float) -> String:
	var nl: float = m3s_to_nl_min(q_m3s)
	# нл/мин — нормальный литр в минуту (приведённый к норм. условиям).
	if absf(nl) < 0.05:
		return "0 нл/мин"
	return "%+.0f нл/мин" % nl


static func flow_arrow(q_m3s: float) -> String:
	if absf(q_m3s) < FLOW_DEAD:
		return "—"
	return "→" if q_m3s > 0.0 else "←"


## Значение в подсказке — полужирное (BBCode для RichTextLabel).
static func tip_b(value: String) -> String:
	return "[b]%s[/b]" % str(value)


## Убрать BBCode — для Label / строки статуса.
static func tip_plain(bb: String) -> String:
	return str(bb).replace("[b]", "").replace("[/b]", "")


## Строка «Имя (X) значение» — значение полужирное.
static func tip_kv(name: String, value: String) -> String:
	return "%s %s" % [name, tip_b(value)]


## Давление и расход — каждая величина с новой строки.
static func format_pressure_flow(p_pa: float, q_m3s: float) -> String:
	var q_s: String = "%s %s" % [format_flow(q_m3s), flow_arrow(q_m3s)]
	return "%s\n%s" % [tip_kv("Давление (P)", format_bar(p_pa)), tip_kv("Расход (Q)", q_s)]


## Число конусов по |Q| (м³/с) — 3D/короткие эффекты. 1 = слабый дозаряд.
static func puff_count(q_abs: float) -> int:
	if q_abs < FLOW_DEAD:
		return 0
	if q_abs < 2.0e-5:
		return 1
	if q_abs < 6.0e-5:
		return 2
	if q_abs < 1.5e-4:
		return 3
	if q_abs < 4.0e-4:
		return 4
	return 5


## Статичные шевроны на 2D: 1 / 2 / 3 по |Q| (≈ Nl/мин = Q·60000).
static func chevron_count(q_abs: float) -> int:
	if q_abs < FLOW_DEAD:
		return 0
	# < ~4 Nl/мин → ▶; < ~12 → ▶▶; иначе ▶▶▶
	if q_abs < 6.5e-5:
		return 1
	if q_abs < 2.0e-4:
		return 2
	return 3


## Шаг шариков на 2D-схеме (world px): плотность≈равномерная, чуть гуще при большем |Q|.
static func flow_spacing_2d(q_abs: float) -> float:
	var tier: int = puff_count(q_abs)
	if tier <= 0:
		return 999.0
	return clampf(32.0 / (0.75 + float(tier) * 0.14), 18.0, 36.0)


## Скорость анимации ∝ |Q|/area. lo низкий — дозаряд ползёт, не зависает.
static func puff_speed(q_m3s: float, area_m2: float, lo: float = 0.035, hi: float = 2.6) -> float:
	var a: float = maxf(area_m2, 1.0e-8)
	var v: float = absf(q_m3s) / a
	# Типичный пневмопоток в трубке Ø4–6 → v порядка единиц м/с; сжимаем в анимацию.
	# Чуть выше коэффициент — мелкий Q заметнее по скорости конусов.
	return clampf(v * 0.16, lo, hi) * signf(q_m3s)


static func puff_speed_2d(q_m3s: float, area_m2: float) -> float:
	var a: float = maxf(area_m2, 1.0e-8)
	var v: float = absf(q_m3s) / a
	return clampf(v * 8.0, 24.0, 200.0)


static func is_sim_control(el) -> bool:
	if el == null:
		return false
	var kind: String = str(el.kind)
	if kind == "valve":
		return true # органы рисуются отдельно чёрным; корпус серый
	if kind != "electro":
		return false
	var cls: String = str(el.electro_class)
	return cls in ["button", "e_stop", "switch", "mcb", "rcd", "rcbo", "thermal"]


static func sim_dim_ink(dark: bool = false) -> Color:
	if dark:
		return Color(0.52, 0.55, 0.58)
	return Color(0.72, 0.74, 0.76)


static func sim_control_ink(dark: bool = false) -> Color:
	if dark:
		return Color(0.94, 0.96, 0.98)
	return Color(0.08, 0.11, 0.15)
