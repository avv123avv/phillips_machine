class_name MachineView
extends Control
## Схема машины: резервуары с водой, трубы с бегущим потоком, клапаны и подписи.
## Рисуется в координатах макета DESIGN и масштабируется под размер контрола.

const DESIGN := Vector2(760, 760)
const FS := 15
const FS_SMALL := 13

const WATER := Color(0.22, 0.52, 0.95)
const WATER_LIGHT := Color(0.62, 0.84, 1.0)
const PIPE := Color(0.2, 0.22, 0.26)
const TANK_BG := Color(0.11, 0.13, 0.17)
const GLASS := Color(0.72, 0.78, 0.86)
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.62, 0.67, 0.74)
const VALVE := Color(0.88, 0.7, 0.25)
const OFF := Color(0.9, 0.3, 0.3)

# Цвета серий — те же, что на графике.
const COL_Y := Color(1.0, 0.85, 0.3)
const COL_C := Color(0.4, 0.9, 0.5)
const COL_I := Color(1.0, 0.55, 0.25)
const COL_G := Color(0.85, 0.45, 0.95)

## Резервуар: прямоугольник в макете и ёмкость для отображения уровня.
const TANKS := {
	"treasury": [Rect2(100, 170, 160, 190), 500.0],
	"idle": [Rect2(462, 300, 126, 180), 500.0],
	"foreign": [Rect2(617, 300, 126, 180), 500.0],
	"sump": [Rect2(110, 600, 620, 140), 700.0],
}
const TANK_NAMES := {
	"treasury": "Казначейство",
	"idle": "Сбережения",
	"foreign": "Иностр. балансы",
	"sump": "Резервуар расходов",
}

## Трубы: ломаная в макете. Вода бежит от первой точки к последней.
const PIPES := {
	"pump": [Vector2(110, 715), Vector2(45, 715), Vector2(45, 50), Vector2(380, 50), Vector2(380, 120)],
	"tax": [Vector2(380, 120), Vector2(180, 120), Vector2(180, 170)],
	"yd": [Vector2(380, 120), Vector2(380, 230)],
	"imp": [Vector2(380, 230), Vector2(680, 230), Vector2(680, 300)],
	"yd2": [Vector2(380, 230), Vector2(380, 260)],
	"sav": [Vector2(380, 260), Vector2(525, 260), Vector2(525, 300)],
	"cons": [Vector2(380, 260), Vector2(380, 600)],
	"gov": [Vector2(180, 360), Vector2(180, 600)],
	"inv": [Vector2(525, 480), Vector2(525, 600)],
	"exp": [Vector2(680, 480), Vector2(680, 600)],
}
const PUMP_POS := Vector2(45, 400)
const DOT_SPACING := 22.0

var econ: Economy
var _phase := {}
var _pump_angle := 0.0
var _wave := 0.0


func _flows() -> Dictionary:
	return {
		"pump": econ.y, "tax": econ.tax, "yd": econ.yd, "imp": econ.imp,
		"yd2": econ.yd - econ.imp, "sav": econ.sav, "cons": econ.cons,
		"gov": econ.gov, "inv": econ.inv, "exp": econ.exp_,
	}


## Сдвиг анимации на sim_dt секунд модельного времени.
func advance(sim_dt: float, real_dt: float) -> void:
	if econ == null:
		return
	var flows := _flows()
	for key in PIPES:
		_phase[key] = fmod(float(_phase.get(key, 0.0)) + float(flows[key]) * sim_dt * 0.6, 1e6)
	_pump_angle = fmod(_pump_angle + econ.y * sim_dt * 0.03, TAU)
	_wave += real_dt
	queue_redraw()


func _draw() -> void:
	if econ == null:
		return
	var sc := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	draw_set_transform((size - DESIGN * sc) * 0.5, 0.0, Vector2(sc, sc))
	var font := get_theme_default_font()
	var flows := _flows()

	for key in PIPES:
		_draw_pipe_shell(PIPES[key])
	for key in TANKS:
		_draw_tank(font, key)
	for key in PIPES:
		_draw_pipe_water(PIPES[key], float(flows[key]), float(_phase.get(key, 0.0)))
	_draw_pump(font)

	# Клапаны: открытие 0..1 показано поворотом заслонки.
	_draw_valve(font, Vector2(290, 120), econ.t / 0.6, "t = %.2f" % econ.t, Vector2(-30, 30))
	_draw_valve(font, Vector2(600, 230), econ.m / 0.5, "m = %.2f" % econ.m, Vector2(-30, -20))
	_draw_valve(font, Vector2(455, 260), econ.s / 0.5, "s = %.2f" % econ.s, Vector2(-30, 32))
	_draw_valve(font, Vector2(180, 480), econ.g / 120.0, "G = %.0f" % econ.g, Vector2(16, 5))
	_draw_valve(font, Vector2(525, 540), econ.investment_demand() / Economy.INV_MAX,
			"r = %.1f%%" % econ.r, Vector2(16, 5))
	_draw_valve(font, Vector2(680, 540), econ.x / 100.0, "X = %.0f" % econ.x, Vector2(-70, -16))

	# Подписи потоков
	_label(font, Vector2(150, 40), "Y = %.1f" % econ.y, COL_Y, FS)
	_label(font, Vector2(190, 110), "T = %.1f" % econ.tax, TEXT, FS_SMALL)
	_label(font, Vector2(390, 180), "Yd = %.1f" % econ.yd, TEXT, FS_SMALL)
	_label(font, Vector2(395, 222), "M = %.1f" % econ.imp, TEXT, FS_SMALL)
	_label(font, Vector2(300, 292), "S = %.1f" % econ.sav, TEXT, FS_SMALL)
	_label(font, Vector2(390, 430), "C = %.1f" % econ.cons, COL_C, FS)
	_label(font, Vector2(190, 420), "G = %.1f" % econ.gov, COL_G, FS)
	_label(font, Vector2(535, 590), "I = %.1f" % econ.inv, COL_I, FS)
	_label(font, Vector2(690, 590), "X = %.1f" % econ.exp_, TEXT, FS_SMALL)

	# Сводка
	var lines := [
		I18n.t("Бюджет T − G: %+.1f") % (econ.tax - econ.gov),
		I18n.t("Сальдо X − M: %+.1f") % (econ.exp_ - econ.imp),
		I18n.t("Мультипликатор: %.2f") % econ.multiplier(),
		I18n.t("Равновесный Y*: %.0f") % econ.equilibrium_y(),
		I18n.t("Вода всего: %.1f") % econ.total_water(),
		I18n.t("Время: %.0f с") % econ.time,
	]
	var box := Rect2(475, 66, 275, 18 * lines.size() + 12)
	draw_rect(box, Color(0.13, 0.15, 0.19))
	draw_rect(box, Color(0.3, 0.33, 0.38), false, 1.0)
	for i in lines.size():
		_label(font, box.position + Vector2(10, 20 + 18 * i), lines[i], DIM, FS_SMALL)
	draw_set_transform(Vector2.ZERO)


func _draw_pipe_shell(pts: Array) -> void:
	var p := PackedVector2Array(pts)
	draw_polyline(p, PIPE, 16.0)
	for v in p:
		draw_circle(v, 8.0, PIPE)


func _draw_pipe_water(pts: Array, flow: float, phase: float) -> void:
	if flow < 0.05:
		return
	var p := PackedVector2Array(pts)
	var w := clampf(2.0 + sqrt(flow) * 0.75, 2.0, 12.0)
	draw_polyline(p, WATER, w)
	for v in p:
		draw_circle(v, w * 0.5, WATER)
	var total := 0.0
	for i in range(1, p.size()):
		total += p[i - 1].distance_to(p[i])
	var d := fmod(phase, DOT_SPACING)
	while d < total:
		draw_circle(_point_at(p, d), maxf(w * 0.28, 1.2), WATER_LIGHT)
		d += DOT_SPACING


static func _point_at(p: PackedVector2Array, d: float) -> Vector2:
	for i in range(1, p.size()):
		var seg := p[i - 1].distance_to(p[i])
		if d <= seg:
			return p[i - 1].lerp(p[i], d / seg)
		d -= seg
	return p[p.size() - 1]


func _draw_tank(font: Font, key: String) -> void:
	var rect: Rect2 = TANKS[key][0]
	var cap: float = TANKS[key][1]
	var level: float = econ.get(key)
	draw_rect(rect, TANK_BG)
	var h := rect.size.y * clampf(level / cap, 0.0, 1.0)
	if h > 0.5:
		var top := rect.end.y - h
		var poly := PackedVector2Array()
		var steps := 16
		for i in steps + 1:
			var px := rect.position.x + rect.size.x * i / steps
			var wave := sin(_wave * 2.2 + px * 0.06) * minf(2.0, h * 0.5)
			poly.append(Vector2(px, clampf(top + wave, rect.position.y, rect.end.y)))
		poly.append(rect.end)
		poly.append(Vector2(rect.position.x, rect.end.y))
		draw_colored_polygon(poly, WATER.darkened(0.15))
	draw_rect(rect, GLASS, false, 2.5)
	var w := rect.size.x
	draw_string(font, rect.position + Vector2(0, 18), I18n.t(TANK_NAMES[key]),
			HORIZONTAL_ALIGNMENT_CENTER, w, FS_SMALL, TEXT)
	draw_string(font, rect.position + Vector2(0, 36), "%.0f" % level,
			HORIZONTAL_ALIGNMENT_CENTER, w, FS, TEXT)


func _draw_pump(font: Font) -> void:
	var col := VALVE if econ.pump_on else OFF
	draw_circle(PUMP_POS, 24.0, Color(0.15, 0.17, 0.21))
	draw_arc(PUMP_POS, 24.0, 0.0, TAU, 32, col, 3.0)
	for k in 4:
		var a := _pump_angle + k * PI / 2.0
		draw_line(PUMP_POS, PUMP_POS + Vector2.from_angle(a) * 18.0, col, 3.0)
	draw_string(font, PUMP_POS + Vector2(-40, 44), I18n.t("Насос"), HORIZONTAL_ALIGNMENT_CENTER, 80, FS_SMALL, TEXT)
	if not econ.pump_on:
		draw_string(font, PUMP_POS + Vector2(-40, 60), I18n.t("ВЫКЛ"), HORIZONTAL_ALIGNMENT_CENTER, 80, FS_SMALL, OFF)


func _draw_valve(font: Font, pos: Vector2, opening: float, text: String, text_off: Vector2) -> void:
	opening = clampf(opening, 0.0, 1.0)
	draw_circle(pos, 11.0, Color(0.15, 0.17, 0.21))
	draw_arc(pos, 11.0, 0.0, TAU, 24, VALVE, 2.0)
	# Заслонка: поперёк трубы — закрыт, вдоль — открыт.
	var a := (1.0 - opening) * PI / 2.0 + PI / 4.0
	var dir := Vector2.from_angle(a) * 9.0
	draw_line(pos - dir, pos + dir, VALVE, 3.0)
	_label(font, pos + text_off, text, VALVE, FS_SMALL)


func _label(font: Font, pos: Vector2, text: String, col: Color, fs: int) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
