class_name PhillipsMachine
extends Control
## Главный экран: схема машины слева, график и рычаги справа.
## Интерфейс собирается в коде; навигация — фокус Godot (геймпад, клавиатура, мышь).

const SAMPLE_INTERVAL := 0.25
const FS := 15

## Рычаги: ключ, подпись, мин, макс, шаг, формат значения.
const SLIDERS := [
	["t", "Налоговая ставка t", 0.0, 0.6, 0.01, "%.2f"],
	["s", "Склонность к сбережению s", 0.0, 0.5, 0.01, "%.2f"],
	["m", "Склонность к импорту m", 0.0, 0.5, 0.01, "%.2f"],
	["g", "Госрасходы G", 0.0, 120.0, 1.0, "%.0f"],
	["x", "Экспорт X", 0.0, 100.0, 1.0, "%.0f"],
	["r", "Процентная ставка r, %", 0.0, 12.0, 0.1, "%.1f"],
	["speed", "Скорость симуляции", 0.25, 8.0, 0.25, "×%.2f"],
]

## Пресеты меняют только перечисленные рычаги; «Сброс» возвращает всё и уровни воды.
const PRESETS := {
	"stimulus": {"t": 0.18, "g": 85.0, "r": 1.5},
	"austerity": {"t": 0.38, "g": 20.0},
	"recession": {"s": 0.32, "r": 9.0, "x": 8.0},
}
const PRESET_BUTTONS := [
	["stimulus", "Стимулирование"],
	["austerity", "Жёсткая экономия"],
	["recession", "Рецессия"],
	["reset", "Сброс"],
]

var econ := Economy.new()
var speed := 1.0
var view: MachineView
var chart: FlowChart
var sliders := {}        # ключ → HSlider
var value_labels := {}   # ключ → Label
var pump_button: Button
var lang_button: Button
var _texts: Array = []   # [Control, русская строка] — переподписываются при смене языка
var _hint: Label
var _sample_acc := 0.0


func _ready() -> void:
	_setup_input()
	_build_ui()
	apply_preset("reset")
	_refresh_texts()
	(sliders["t"] as Control).grab_focus.call_deferred()


func _process(delta: float) -> void:
	var sim_dt := delta * speed
	econ.advance(sim_dt)
	view.advance(sim_dt, delta)
	_sample_acc += sim_dt
	while _sample_acc >= SAMPLE_INTERVAL:
		_sample_acc -= SAMPLE_INTERVAL
		chart.push([econ.y, econ.cons, econ.inv, econ.gov])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pump"):
		pump_button.button_pressed = not pump_button.button_pressed
	elif event.is_action_pressed("toggle_lang"):
		_toggle_lang()
	elif event.is_action_pressed("speed_down"):
		(sliders["speed"] as HSlider).value /= 2.0
	elif event.is_action_pressed("speed_up"):
		(sliders["speed"] as HSlider).value *= 2.0
	elif event.is_action_pressed("reset_sim"):
		apply_preset("reset")
	else:
		return
	get_viewport().set_input_as_handled()


## Пресет: задаёт рычаги через слайдеры, чтобы подписи и модель обновились одинаково.
func apply_preset(id: String) -> void:
	if id == "reset":
		econ.reset()
		for key in Economy.DEFAULTS:
			(sliders[key] as HSlider).value = Economy.DEFAULTS[key]
		(sliders["speed"] as HSlider).value = 1.0
		pump_button.button_pressed = true
		# value_changed не приходит, если значение не изменилось, — обновляем явно.
		for key in sliders:
			_on_slider((sliders[key] as HSlider).value, key)
		chart.clear()
		_sample_acc = 0.0
		_refresh_texts()
		return
	var p: Dictionary = PRESETS[id]
	for key in p:
		(sliders[key] as HSlider).value = p[key]


func _on_slider(value: float, key: String) -> void:
	if key == "speed":
		speed = value
	else:
		econ.set(key, value)
	var fmt: String = _slider_def(key)[5]
	(value_labels[key] as Label).text = fmt % value


## Шаг с геймпада/клавиатуры крупнее шага слайдера: ~40 нажатий на всю шкалу.
## Сигнал gui_input приходит раньше встроенной обработки, accept_event() её отменяет.
func _on_slider_input(event: InputEvent, sl: HSlider, big_step: float) -> void:
	var dir := 0.0
	if event.is_action_pressed("ui_left", true):
		dir = -1.0
	elif event.is_action_pressed("ui_right", true):
		dir = 1.0
	if dir != 0.0:
		sl.value += dir * big_step
		sl.accept_event()


func _on_pump_toggled(on: bool) -> void:
	econ.pump_on = on
	_refresh_texts()


func _toggle_lang() -> void:
	I18n.toggle()
	_refresh_texts()


func _refresh_texts() -> void:
	for item in _texts:
		item[0].text = I18n.t(item[1])
	lang_button.text = I18n.t("English")
	pump_button.text = I18n.t("Насос: ВКЛ") if econ.pump_on else I18n.t("Насос: ВЫКЛ")
	view.queue_redraw()
	chart.queue_redraw()


func _slider_def(key: String) -> Array:
	for d in SLIDERS:
		if d[0] == key:
			return d
	return []


# --- Построение интерфейса ---------------------------------------------------

func _build_ui() -> void:
	var th := Theme.new()
	th.default_font_size = FS
	# Заметная рамка фокуса: на Steam Deck управляют без мыши.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MachineView.COL_Y
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	focus.set_expand_margin_all(3)
	for type in ["Button", "HSlider"]:
		th.set_stylebox("focus", type, focus)
	theme = th

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	view = MachineView.new()
	view.econ = econ
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_stretch_ratio = 1.5
	root.add_child(view)

	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	root.add_child(panel)

	var header := HBoxContainer.new()
	panel.add_child(header)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texts.append([title, "Машина Филлипса (MONIAC)"])
	header.add_child(title)
	var version := Label.new()
	var ver := str(ProjectSettings.get_setting("application/config/version", "dev"))
	version.text = ver if ver == "dev" else "v" + ver
	version.modulate = MachineView.DIM
	header.add_child(version)
	lang_button = Button.new()
	lang_button.custom_minimum_size.x = 96
	lang_button.pressed.connect(_toggle_lang)
	header.add_child(lang_button)

	chart = FlowChart.new()
	chart.sample_interval = SAMPLE_INTERVAL
	chart.custom_minimum_size.y = 230
	panel.add_child(chart)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(grid)
	for d in SLIDERS:
		var key: String = d[0]
		var name_label := Label.new()
		name_label.custom_minimum_size.x = 225
		_texts.append([name_label, d[1]])
		grid.add_child(name_label)
		var sl := HSlider.new()
		sl.min_value = d[2]
		sl.max_value = d[3]
		sl.step = d[4]
		sl.gui_input.connect(_on_slider_input.bind(sl, maxf(snappedf((d[3] - d[2]) / 40.0, d[4]), d[4])))
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size.y = 24
		sl.value_changed.connect(_on_slider.bind(key))
		grid.add_child(sl)
		sliders[key] = sl
		var val := Label.new()
		val.custom_minimum_size.x = 52
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
		value_labels[key] = val

	pump_button = Button.new()
	pump_button.toggle_mode = true
	pump_button.custom_minimum_size.y = 34
	pump_button.toggled.connect(_on_pump_toggled)
	panel.add_child(pump_button)

	var presets_label := Label.new()
	presets_label.modulate = MachineView.DIM
	_texts.append([presets_label, "Пресеты"])
	panel.add_child(presets_label)
	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pgrid.add_theme_constant_override("h_separation", 8)
	pgrid.add_theme_constant_override("v_separation", 8)
	panel.add_child(pgrid)
	for b in PRESET_BUTTONS:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 34
		btn.pressed.connect(apply_preset.bind(b[0]))
		_texts.append([btn, b[1]])
		pgrid.add_child(btn)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = MachineView.DIM
	_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_texts.append([_hint, "Геймпад: крестовина/стик — выбор, ←/→ — значение, A — нажать, Start — насос, Select — язык, LB/RB — скорость."])
	panel.add_child(_hint)
	var kb_hint := Label.new()
	kb_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kb_hint.add_theme_font_size_override("font_size", 12)
	kb_hint.modulate = MachineView.DIM
	_texts.append([kb_hint, "Клавиатура: Tab/стрелки, P — насос, L — язык, [ ] — скорость, R — сброс."])
	panel.add_child(kb_hint)


# --- Управление ---------------------------------------------------------------

## Действия создаются в коде, чтобы не держать сериализованные события в project.godot.
func _setup_input() -> void:
	_add_action("toggle_pump", [_key(KEY_P), _joy(JOY_BUTTON_START)])
	_add_action("toggle_lang", [_key(KEY_L), _joy(JOY_BUTTON_BACK)])
	_add_action("speed_down", [_key(KEY_BRACKETLEFT), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_add_action("speed_up", [_key(KEY_BRACKETRIGHT), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("reset_sim", [_key(KEY_R)])
	# Левый стик для навигации по фокусу (крестовина уже есть в ui_*).
	_add_action("ui_left", [_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("ui_right", [_axis(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("ui_up", [_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("ui_down", [_axis(JOY_AXIS_LEFT_Y, 1.0)])


static func _add_action(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for e in events:
		if not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e


static func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
