class_name DiyRigView
extends Control
## Схема домашней машины Филлипса: щит с контейнерами, помпой, делителями-лотками,
## плавающими заборниками, краниками и Arduino. Модель та же (Economy), здесь только
## пересчёт в физические величины стенда и отрисовка. Нумерация деталей = таблица в инструкции.
##
## Масштаб: 1 единица воды = ML_PER_UNIT мл, 1 с модели = TIME_SCALE с на стенде.

const ML_PER_UNIT := 2.0
const TIME_SCALE := 10.0
## Баки казны, сбережений и иностранных балансов: контейнер 2 л, дно 12,5 × 10 см.
const TANK_AREA_CM2 := 125.0
const TANK_H_CM := 16.0
## Нижний бак: 3 л, дно 20 × 10 см; под помпой — «мёртвый» запас, чтобы она не хватала воздух.
const SUMP_AREA_CM2 := 200.0
const SUMP_H_CM := 15.0
const SUMP_DEAD_ML := 500.0
## Ширина переливного порога в делителях.
const WEIR_MM := 60.0
## Краники G, I, X стоят на VALVE_DROP_CM ниже дна своих баков: напор = падение + уровень,
## расход ~ √напора, поэтому от пустого бака к полному он меняется лишь в head_ratio() раз —
## почти постоянный отток, как в модели.
const VALVE_DROP_CM := 40.0
## Помпа 12 В: подача при 100 % ШИМ (подбирается калибровкой).
const PUMP_MAX_L_H := 240.0

const DESIGN := MachineView.DESIGN
const FS := MachineView.FS
const FS_SMALL := MachineView.FS_SMALL
const PX_PER_CM := 10.0

const WOOD := Color(0.36, 0.29, 0.21)
const WOOD_EDGE := Color(0.5, 0.41, 0.3)
const HOSE := Color(0.78, 0.8, 0.84, 0.55)
const PLASTIC := Color(0.85, 0.88, 0.92)
const TAG := Color(0.95, 0.8, 0.3)
const PCB := Color(0.15, 0.45, 0.3)

const BOARD := Rect2(20, 20, 800, 720)
## Баки: левый нижний угол дна и размер в см (ширина спереди × высота).
const TANKS := {
	"treasury": [Vector2(110, 380), Vector2(12.5, TANK_H_CM)],
	"idle": [Vector2(545, 520), Vector2(12.5, TANK_H_CM)],
	"foreign": [Vector2(690, 520), Vector2(12.5, TANK_H_CM)],
	"sump": [Vector2(300, 715), Vector2(20.0, SUMP_H_CM)],
}
const WEIR1 := Rect2(380, 70, 90, 34)
const WEIR2 := Rect2(370, 200, 110, 34)
## Шланги: ломаная и ключ потока в Economy.
const HOSES := [
	[[Vector2(330, 700), Vector2(330, 540), Vector2(60, 540), Vector2(60, 45), Vector2(425, 45), Vector2(425, 70)], "y"],
	[[Vector2(390, 104), Vector2(390, 140), Vector2(180, 140), Vector2(180, 222)], "tax"],
	[[Vector2(455, 104), Vector2(455, 200)], "yd"],
	[[Vector2(470, 234), Vector2(470, 260), Vector2(605, 260), Vector2(605, 362)], "sav"],
	[[Vector2(478, 228), Vector2(750, 228), Vector2(750, 362)], "imp"],
	[[Vector2(425, 234), Vector2(425, 565)], "cons"],
	[[Vector2(180, 380), Vector2(180, 470), Vector2(350, 470), Vector2(350, 565)], "gov"],
	[[Vector2(605, 520), Vector2(605, 548), Vector2(470, 548), Vector2(470, 565)], "inv"],
	[[Vector2(750, 520), Vector2(750, 556), Vector2(490, 556), Vector2(490, 565)], "exp_"],
]
const VALVES := {"gov": Vector2(180, 440), "inv": Vector2(605, 536), "exp_": Vector2(750, 538)}

var econ: Economy
var _phase := 0.0


# --- Пересчёт модели в величины стенда --------------------------------------

## Уровень воды в см от дна бака (у нижнего — вместе с мёртвым запасом).
static func level_cm(key: String, units: float) -> float:
	if key == "sump":
		return (units * ML_PER_UNIT + SUMP_DEAD_ML) / SUMP_AREA_CM2
	return units * ML_PER_UNIT / TANK_AREA_CM2


static func volume_ml(units: float) -> float:
	return units * ML_PER_UNIT


## Поток модели (ед/с) → мл/мин на стенде.
static func flow_ml_min(units_per_s: float) -> float:
	return units_per_s * ML_PER_UNIT / TIME_SCALE * 60.0


## Положение пластины делителя от левого края порога, мм.
static func plate_mm(fraction: float) -> float:
	return clampf(fraction, 0.0, 1.0) * WEIR_MM


## Во сколько раз расход краника у полного бака больше, чем у почти пустого.
static func head_ratio() -> float:
	return sqrt((VALVE_DROP_CM + TANK_H_CM) / VALVE_DROP_CM)


## ШИМ помпы, %: подача Y в л/ч к максимальной.
static func pump_pwm(y_units_per_s: float) -> float:
	var l_h := flow_ml_min(y_units_per_s) * 60.0 / 1000.0
	return clampf(l_h / PUMP_MAX_L_H, 0.0, 1.0) * 100.0


func advance(sim_dt: float) -> void:
	_phase = fmod(_phase + sim_dt * 30.0, 1e6)
	queue_redraw()


func _draw() -> void:
	if econ == null:
		return
	var sc := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	draw_set_transform((size - DESIGN * sc) * 0.5, 0.0, Vector2(sc, sc))
	var font := get_theme_default_font()

	# Щит и полка
	draw_rect(BOARD, WOOD)
	draw_rect(BOARD, WOOD_EDGE, false, 3.0)
	draw_rect(Rect2(BOARD.position.x, 715, BOARD.size.x, 12), WOOD_EDGE)
	_draw_tag(font, Vector2(46, 700), 12)

	for h in HOSES:
		_draw_hose(h[0], econ.get(h[1]))
	for key in TANKS:
		_draw_tank(font, key)
	_draw_weir(font, WEIR1, [econ.t], "t", 4)
	_draw_weir(font, WEIR2, [econ.s, econ.m], "s, m", 5)
	_draw_valve(font, VALVES["gov"], "G", 7)
	_draw_valve(font, VALVES["inv"], "I", 0)
	_draw_valve(font, VALVES["exp_"], "X", 0)
	_draw_electronics(font)
	_draw_hose_tag(font)
	_draw_legend(font)
	draw_set_transform(Vector2.ZERO)


func _draw_hose(pts: Array, flow: float) -> void:
	var p := PackedVector2Array(pts)
	draw_polyline(p, HOSE, 9.0)
	if flow < 0.05:
		return
	draw_polyline(p, MachineView.WATER, 5.0)
	var total := 0.0
	for i in range(1, p.size()):
		total += p[i - 1].distance_to(p[i])
	var d := fmod(_phase * clampf(flow / 50.0, 0.2, 3.0), 24.0)
	while d < total:
		draw_circle(MachineView._point_at(p, d), 1.8, MachineView.WATER_LIGHT)
		d += 24.0


func _tank_rect(key: String) -> Rect2:
	var base: Vector2 = TANKS[key][0]
	var dim: Vector2 = TANKS[key][1] * PX_PER_CM
	return Rect2(base.x, base.y - dim.y, dim.x, dim.y)


func _draw_tank(font: Font, key: String) -> void:
	var r := _tank_rect(key)
	var units: float = econ.get(key)
	var h_cm := level_cm(key, units)
	var cap_cm: float = TANKS[key][1].y
	draw_rect(r, Color(0.12, 0.14, 0.18, 0.85))
	var wh := r.size.y * clampf(h_cm / cap_cm, 0.0, 1.0)
	draw_rect(Rect2(r.position.x, r.end.y - wh, r.size.x, wh), MachineView.WATER.darkened(0.1))
	# Шкала через 2 см
	for c in range(0, int(cap_cm) + 1, 2):
		var y := r.end.y - c * PX_PER_CM
		draw_line(Vector2(r.end.x - 10, y), Vector2(r.end.x, y), PLASTIC, 1.0)
	draw_rect(r, PLASTIC, false, 2.0)
	if key == "sump":
		# Помпа на дне и мёртвый запас
		var dead_y := r.end.y - SUMP_DEAD_ML / SUMP_AREA_CM2 * PX_PER_CM
		draw_dashes(Vector2(r.position.x, dead_y), Vector2(r.end.x, dead_y), MachineView.DIM)
		draw_rect(Rect2(r.position.x + 14, r.end.y - 26, 34, 24), Color(0.2, 0.2, 0.22))
		draw_rect(Rect2(r.position.x + 14, r.end.y - 26, 34, 24), PLASTIC, false, 1.5)
		_draw_tag(font, Vector2(r.position.x + 60, r.end.y - 14), 3)
		_draw_tag(font, Vector2(r.end.x + 16, r.position.y + 16), 1)
	else:
		# Штуцер в дне бака — к нему снизу шланг на краник
		var fx := r.position.x + r.size.x * 0.5
		draw_rect(Rect2(fx - 9, r.end.y - 4, 18, 12), Color(0.95, 0.6, 0.3))
		_draw_tag(font, Vector2(r.position.x + 14, r.position.y - 16), 2)
		if key == "treasury":  # номер детали — один раз, как в схеме шприцев
			_draw_tag(font, Vector2(fx + 26, r.end.y + 12), 6)
	var name := I18n.t(MachineView.TANK_NAMES[key])
	draw_string(font, Vector2(r.position.x - 10, r.position.y + 22), name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 20, FS_SMALL - 2, MachineView.TEXT)
	draw_string(font, Vector2(r.position.x - 10, r.position.y + 44), I18n.t("%.1f см · %.0f мл") % [h_cm, volume_ml(units)],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 20, FS_SMALL - 2, MachineView.WATER_LIGHT)


func draw_dashes(a: Vector2, b: Vector2, col: Color) -> void:
	draw_dashed_line(a, b, col, 1.5, 6.0)


## Делитель: лоток с порогом шириной WEIR_MM и подвижными пластинами (доли слева направо).
func _draw_weir(font: Font, r: Rect2, fractions: Array, label: String, tag: int) -> void:
	draw_rect(r, Color(0.2, 0.22, 0.26))
	draw_rect(r, PLASTIC, false, 2.0)
	var x := r.position.x
	var parts: PackedStringArray = []
	for f in fractions:
		x += r.size.x * clampf(float(f), 0.0, 1.0)
		draw_line(Vector2(x, r.position.y - 6), Vector2(x, r.end.y + 6), MachineView.VALVE, 3.0)
		parts.append("%.0f" % plate_mm(float(f)))
	draw_string(font, Vector2(r.end.x + 12, r.position.y + 14), I18n.t("пластины %s: %s мм") % [label, ", ".join(parts)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL, MachineView.VALVE)
	_draw_tag(font, Vector2(r.position.x - 16, r.position.y + 16), tag)


## tag = 0 — без номерка (номер детали показан у первого краника).
func _draw_valve(font: Font, pos: Vector2, label: String, tag: int) -> void:
	draw_rect(Rect2(pos - Vector2(10, 7), Vector2(20, 14)), Color(0.3, 0.6, 0.4))
	draw_line(pos, pos + Vector2(14, -10), MachineView.VALVE, 3.0)
	draw_string(font, pos + Vector2(16, 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL, MachineView.VALVE)
	if tag > 0:
		_draw_tag(font, pos + Vector2(-26, 0), tag)


func _draw_electronics(font: Font) -> void:
	var sump := _tank_rect("sump")
	# Ультразвуковой датчик над нижним баком
	var sensor := Rect2(sump.position.x + 130, sump.position.y - 26, 48, 18)
	draw_rect(sensor, PCB)
	draw_circle(sensor.position + Vector2(12, 9), 6, PLASTIC)
	draw_circle(sensor.position + Vector2(36, 9), 6, PLASTIC)
	_draw_tag(font, sensor.position + Vector2(64, 4), 9)
	# Arduino + MOSFET и блок питания — слева от нижнего бака
	var ard := Rect2(80, 600, 90, 44)
	var psu := Rect2(186, 600, 100, 44)
	draw_rect(ard, PCB)
	draw_string(font, ard.position + Vector2(0, 28), "Arduino", HORIZONTAL_ALIGNMENT_CENTER, ard.size.x, FS_SMALL - 2, MachineView.TEXT)
	draw_rect(psu, Color(0.22, 0.22, 0.25))
	draw_string(font, psu.position + Vector2(0, 28), I18n.t("БП 12 В"), HORIZONTAL_ALIGNMENT_CENTER, psu.size.x, FS_SMALL - 2, MachineView.TEXT)
	var wire := Color(0.9, 0.3, 0.3)
	var sx := sensor.position.x + 24
	draw_polyline(PackedVector2Array([Vector2(sx, sensor.position.y), Vector2(sx, 505), Vector2(125, 505), Vector2(125, 600)]), wire, 2.0)
	draw_line(Vector2(170, 622), Vector2(186, 622), wire, 2.0)
	draw_polyline(PackedVector2Array([Vector2(125, 644), Vector2(125, 670), Vector2(310, 670), Vector2(310, 700)]), wire, 2.0)
	_draw_tag(font, ard.position + Vector2(-14, -14), 10)
	_draw_tag(font, psu.position + Vector2(psu.size.x, -14), 11)

	# Показания стенда
	var pwm := pump_pwm(econ.y) if econ.pump_on else 0.0
	var lines := [
		[I18n.t("Помпа: ШИМ %.0f %% · %.0f л/ч") % [pwm, pwm / 100.0 * PUMP_MAX_L_H], MachineView.COL_Y],
		[I18n.t("Краник G: %.0f мл/мин") % flow_ml_min(econ.gov), MachineView.COL_G],
		[I18n.t("Краник I: %.0f мл/мин") % flow_ml_min(econ.inv), MachineView.COL_I],
		[I18n.t("Краник X: %.0f мл/мин") % flow_ml_min(econ.exp_), MachineView.TEXT],
	]
	for i in lines.size():
		draw_string(font, Vector2(530, 610 + 26 * i), lines[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL, lines[i][1])


func _draw_hose_tag(font: Font) -> void:
	_draw_tag(font, Vector2(60, 300), 8)


## Список деталей справа от щита; номера совпадают с таблицей в инструкции.
func _draw_legend(font: Font) -> void:
	var lines := [
		I18n.t("#Детали стенда"),
		I18n.t("1  Нижний бак 3 л"),
		I18n.t("2  Баки 2 л — 3 шт."),
		I18n.t("3  Помпа 12 В, 240 л/ч"),
		I18n.t("4  Делитель t (лоток)"),
		I18n.t("5  Делитель s, m (лоток)"),
		I18n.t("6  Штуцер в дне бака — 3"),
		I18n.t("7  Аквариумный краник — 3"),
		I18n.t("8  Силиконовая трубка 8 мм"),
		I18n.t("9  Датчик уровня HC-SR04"),
		I18n.t("10 Arduino Nano + MOSFET"),
		I18n.t("11 Блок питания 12 В 2 А"),
		I18n.t("12 Щит 80 × 75 см, полка"),
		"",
		I18n.t("#Масштаб"),
		I18n.t("1 ед. воды = %.0f мл") % ML_PER_UNIT,
		I18n.t("1 с модели = %.0f с стенда") % TIME_SCALE,
		I18n.t("Вода всего: %.1f л") % (econ.total_water() * ML_PER_UNIT / 1000.0 + SUMP_DEAD_ML / 1000.0),
		"",
		I18n.t("F1 — сборка и калибровка"),
	]
	var y := 40.0
	for line in lines:
		var text: String = line
		var head := text.begins_with("#")
		if head:
			text = text.substr(1)
		draw_string(font, Vector2(842, y), text, HORIZONTAL_ALIGNMENT_LEFT, 310,
				FS if head else FS_SMALL, TAG if head else MachineView.TEXT)
		y += 30.0 if head else 25.0


func _draw_tag(font: Font, pos: Vector2, n: int) -> void:
	draw_circle(pos, 12.0, TAG)
	draw_string(font, pos + Vector2(-14, 6), str(n), HORIZONTAL_ALIGNMENT_CENTER, 28, FS_SMALL - 2, Color.BLACK)
