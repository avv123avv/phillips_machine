class_name FlowChart
extends Control
## График Y, C, I, G во времени: скользящее окно последних MAX_POINTS отсчётов.

const MAX_POINTS := 240
const FS := 20
const PAD := Vector2(52, 50)
const SERIES := [
	["Y", MachineView.COL_Y],
	["C", MachineView.COL_C],
	["I", MachineView.COL_I],
	["G", MachineView.COL_G],
]

var sample_interval := 0.25
var data: Array[PackedFloat32Array] = []


func _init() -> void:
	clear()


func clear() -> void:
	data.clear()
	for s in SERIES:
		data.append(PackedFloat32Array())
	queue_redraw()


func push(values: Array) -> void:
	for i in data.size():
		data[i].append(float(values[i]))
		if data[i].size() > MAX_POINTS:
			data[i].remove_at(0)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.11, 0.13, 0.17))
	draw_rect(r, Color(0.3, 0.33, 0.38), false, 1.0)
	draw_string(font, Vector2(10, 24), I18n.t("Динамика потоков, ед/с"), HORIZONTAL_ALIGNMENT_LEFT, -1, FS, MachineView.TEXT)
	draw_string(font, Vector2(0, size.y - 8), I18n.t("последние %.0f с") % (MAX_POINTS * sample_interval),
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, FS, MachineView.DIM)
	# Легенда
	var lx := size.x - 10 - 58 * SERIES.size()
	for i in SERIES.size():
		var p := Vector2(lx + 58 * i, 14)
		draw_rect(Rect2(p, Vector2(18, 5)), SERIES[i][1])
		draw_string(font, p + Vector2(23, 9), SERIES[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, FS, SERIES[i][1])

	var plot := Rect2(PAD.x, PAD.y, size.x - PAD.x - 8, size.y - PAD.y - 32)
	var vmax := 10.0
	for s in data:
		for v in s:
			vmax = maxf(vmax, v)
	vmax = _nice_ceil(vmax * 1.1)
	for k in 5:
		var gy := plot.end.y - plot.size.y * k / 4.0
		draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), Color(1, 1, 1, 0.07), 1.0)
		draw_string(font, Vector2(0, gy + 4), "%.0f" % (vmax * k / 4.0), HORIZONTAL_ALIGNMENT_RIGHT, PAD.x - 4, FS - 2, MachineView.DIM)
	for i in data.size():
		var s := data[i]
		if s.size() < 2:
			continue
		var pts := PackedVector2Array()
		for j in s.size():
			var px := plot.position.x + plot.size.x * j / (MAX_POINTS - 1)
			pts.append(Vector2(px, plot.end.y - plot.size.y * clampf(s[j] / vmax, 0.0, 1.0)))
		draw_polyline(pts, SERIES[i][1], 2.0, true)


## Округление вверх до 1, 2 или 5 × 10^k — ровная шкала.
static func _nice_ceil(v: float) -> float:
	var p := pow(10.0, floorf(log(v) / log(10.0)))
	for k in [1.0, 2.0, 5.0, 10.0]:
		if v <= k * p:
			return k * p
	return 10.0 * p
