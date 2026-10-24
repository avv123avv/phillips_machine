class_name PhillipsMachine
extends Control
## Главный экран 1920×1080: строка статуса и меню сверху, схема машины слева,
## справа за разделителем — график, рычаги и пресеты, внизу подсказки и «F1 — инструкция».
## Интерфейс собирается в коде; навигация — фокус Godot (геймпад, клавиатура, мышь).

const SAMPLE_INTERVAL := 0.25

# Размеры шрифтов интерфейса (как в lukyanov_integrator).
const FS_SMALL := 20
const FS := 24
const FS_BIG := 30

# Разметка экрана
const MENU_Y := 62.0
const VIEW_RECT := Rect2(24, 124, 1270, 830)
const DIVIDER_X := 1316.0
const PANEL_RECT := Rect2(1340, 20, 556, 1040)

const COLOR_BTN := Color(0.24, 0.26, 0.3)
const COLOR_BTN_HOVER := Color(0.34, 0.37, 0.43)
const COLOR_HEAD := Color(0.95, 0.8, 0.3)

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
## Меню: ключ и подпись (подписи паузы, насоса и языка меняются в _refresh_texts).
const MENU := [
	["pause", "Пауза"],
	["slower", "− скорость"],
	["faster", "+ скорость"],
	["pump", "Насос"],
	["reset", "Сброс"],
	["view", "Схема сборки"],
	["help", "Инструкция"],
	["lang", "English"],
]

var econ := Economy.new()
var speed := 1.0
var paused := false
var view: MachineView
var diy: DiyRigView     ## схема домашнего стенда — вместо view, переключается кнопкой «Схема сборки»
var chart: FlowChart
var help: HelpOverlay
var sliders := {}        # ключ → HSlider
var value_labels := {}   # ключ → Label
var menu := {}           # ключ → Button
var _texts: Array = []   # [Control, русская строка] — переподписываются при смене языка
var _sample_acc := 0.0


func _ready() -> void:
	_setup_input()
	_build_ui()
	apply_preset("reset")
	# Аргумент запуска `-- --view=diy` сразу показывает схему сборки (для скриншотов).
	if "--view=diy" in OS.get_cmdline_user_args():
		set_diy(true)
	(sliders["t"] as Control).grab_focus.call_deferred()


func _process(delta: float) -> void:
	var sim_dt := 0.0 if paused else delta * speed
	econ.advance(sim_dt)
	view.advance(sim_dt, delta)
	diy.advance(sim_dt)
	_sample_acc += sim_dt
	while _sample_acc >= SAMPLE_INTERVAL:
		_sample_acc -= SAMPLE_INTERVAL
		chart.push([econ.y, econ.cons, econ.inv, econ.gov])
	queue_redraw()


## Статус, версия, разделитель и подвал рисуются прямо на корневом контроле, под дочерними.
func _draw() -> void:
	var font := get_theme_default_font()
	var status := I18n.t("t = %.0f с    скорость ×%s    Y = %.1f%s") % [
		econ.time, str(speed), econ.y, I18n.t("    [ПАУЗА]") if paused else ""]
	draw_string(font, Vector2(24, 44), status, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_BIG, MachineView.TEXT)
	# Версия: в репозитории "dev", в релизе её проставляет CI (application/config/version).
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	draw_string(font, Vector2(DIVIDER_X - 324, 40), version if version == "dev" else "v" + version,
			HORIZONTAL_ALIGNMENT_RIGHT, 300, FS_SMALL, MachineView.DIM)
	draw_line(Vector2(DIVIDER_X, 16), Vector2(DIVIDER_X, 1064), Color(0.3, 0.32, 0.36), 2.0)
	draw_string(font, Vector2(24, 1000), I18n.t("Клавиатура: Tab/стрелки, Enter — нажать, Пробел — пауза, P — насос, [ ] — скорость, V — схема, R — сброс, L — язык."),
			HORIZONTAL_ALIGNMENT_LEFT, DIVIDER_X - 40, FS_SMALL, MachineView.DIM)
	draw_string(font, Vector2(24, 1056), I18n.t("F1 / Y — инструкция: устройство машины, формулы, сценарии"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_BIG, COLOR_HEAD)


# --- Ввод -----------------------------------------------------------------------

## Пока открыта инструкция, она забирает весь ввод; пауза — до GUI, иначе Пробел нажмёт кнопку в фокусе.
func _input(event: InputEvent) -> void:
	if help.visible:
		if not event is InputEventMouse:
			_help_input(event)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_pause"):
		_press_menu("pause")
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_press_menu("help")
	elif event.is_action_pressed("toggle_pump"):
		_press_menu("pump")
	elif event.is_action_pressed("toggle_lang"):
		_press_menu("lang")
	elif event.is_action_pressed("speed_down"):
		_press_menu("slower")
	elif event.is_action_pressed("speed_up"):
		_press_menu("faster")
	elif event.is_action_pressed("reset_sim"):
		_press_menu("reset")
	elif event.is_action_pressed("toggle_view"):
		_press_menu("view")
	else:
		return
	get_viewport().set_input_as_handled()


func _help_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help") or event.is_action_pressed("ui_cancel"):
		set_help(false)
	elif event.is_action_pressed("ui_right", true) or event.is_action_pressed("speed_up", true) \
			or event.is_action_pressed("ui_down", true) or event.is_action_pressed("ui_page_down", true):
		help.flip(1)
	elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("speed_down", true) \
			or event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_page_up", true):
		help.flip(-1)
	elif event.is_action_pressed("ui_home"):
		help.first()
	elif event.is_action_pressed("open_pdf"):
		OS.shell_open(help.pdf_path())


func set_help(open: bool) -> void:
	if open:
		help.open()
	else:
		help.close()
		(menu["help"] as Control).grab_focus()


func set_diy(show: bool) -> void:
	diy.visible = show
	view.visible = not show
	_refresh_texts()


## Кнопки меню; так же их нажимают горячие клавиши и кнопки геймпада.
func _press_menu(id: String) -> void:
	match id:
		"pause":
			paused = not paused
		"slower":
			(sliders["speed"] as HSlider).value = speed / 2.0
		"faster":
			(sliders["speed"] as HSlider).value = speed * 2.0
		"pump":
			econ.pump_on = not econ.pump_on
		"reset":
			apply_preset("reset")
		"view":
			set_diy(not diy.visible)
		"help":
			set_help(not help.visible)
		"lang":
			I18n.toggle()
	_refresh_texts()


## Пресет: задаёт рычаги через слайдеры, чтобы подписи и модель обновились одинаково.
func apply_preset(id: String) -> void:
	if id == "reset":
		econ.reset()
		paused = false
		for key in Economy.DEFAULTS:
			(sliders[key] as HSlider).value = Economy.DEFAULTS[key]
		(sliders["speed"] as HSlider).value = 1.0
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


func _refresh_texts() -> void:
	for item in _texts:
		item[0].text = I18n.t(item[1])
	var pause_btn: Button = menu["pause"]
	pause_btn.text = I18n.t("Пуск") if paused else I18n.t("Пауза")
	pause_btn.set_pressed_no_signal(paused)
	var pump_btn: Button = menu["pump"]
	pump_btn.text = I18n.t("Насос: ВКЛ") if econ.pump_on else I18n.t("Насос: ВЫКЛ")
	pump_btn.set_pressed_no_signal(not econ.pump_on)
	# Кнопка показывает язык, на который переключит.
	(menu["lang"] as Button).text = "English" if I18n.current() == "ru" else "Русский"
	(menu["view"] as Button).text = I18n.t("Схема машины") if diy.visible else I18n.t("Схема сборки")
	view.queue_redraw()
	diy.queue_redraw()
	chart.queue_redraw()
	help.queue_redraw()
	queue_redraw()


func _slider_def(key: String) -> Array:
	for d in SLIDERS:
		if d[0] == key:
			return d
	return []


# --- Построение интерфейса ---------------------------------------------------

func _build_ui() -> void:
	theme = _make_theme()

	var menu_row := HBoxContainer.new()
	menu_row.position = Vector2(24, MENU_Y)
	menu_row.add_theme_constant_override("separation", 8)
	add_child(menu_row)
	for d in MENU:
		var btn := Button.new()
		btn.custom_minimum_size.y = 44
		# Пауза и насос подсвечиваются жёлтой рамкой в «особом» состоянии (пауза, насос выключен).
		btn.toggle_mode = d[0] in ["pause", "pump"]
		btn.pressed.connect(_press_menu.bind(d[0]))
		if d[0] not in ["pause", "pump", "lang", "view"]:
			_texts.append([btn, d[1]])
		menu_row.add_child(btn)
		menu[d[0]] = btn

	view = MachineView.new()
	view.econ = econ
	view.position = VIEW_RECT.position
	view.size = VIEW_RECT.size
	add_child(view)
	diy = DiyRigView.new()
	diy.econ = econ
	diy.position = VIEW_RECT.position
	diy.size = VIEW_RECT.size
	diy.visible = false
	add_child(diy)

	var panel := VBoxContainer.new()
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.add_theme_constant_override("separation", 10)
	add_child(panel)

	chart = FlowChart.new()
	chart.sample_interval = SAMPLE_INTERVAL
	chart.custom_minimum_size.y = 420
	panel.add_child(chart)

	panel.add_child(_header("Рычаги"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	panel.add_child(grid)
	for d in SLIDERS:
		var key: String = d[0]
		var name_label := Label.new()
		name_label.custom_minimum_size.x = 290
		_texts.append([name_label, d[1]])
		grid.add_child(name_label)
		var sl := HSlider.new()
		sl.min_value = d[2]
		sl.max_value = d[3]
		sl.step = d[4]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size.y = 30
		sl.value_changed.connect(_on_slider.bind(key))
		sl.gui_input.connect(_on_slider_input.bind(sl, maxf(snappedf((d[3] - d[2]) / 40.0, d[4]), d[4])))
		grid.add_child(sl)
		sliders[key] = sl
		var val := Label.new()
		val.custom_minimum_size.x = 76
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
		value_labels[key] = val

	panel.add_child(_header("Пресеты"))
	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pgrid.add_theme_constant_override("h_separation", 10)
	pgrid.add_theme_constant_override("v_separation", 10)
	panel.add_child(pgrid)
	for b in PRESET_BUTTONS:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 48
		btn.pressed.connect(apply_preset.bind(b[0]))
		_texts.append([btn, b[1]])
		pgrid.add_child(btn)

	help = HelpOverlay.new()
	add_child(help)


func _header(text: String) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", FS_BIG)
	l.add_theme_color_override("font_color", COLOR_HEAD)
	_texts.append([l, text])
	return l


## Тема в стиле lukyanov_integrator: плоские кнопки, жёлтая рамка — фокус и «включено».
func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = FS
	th.set_color("font_color", "Label", MachineView.TEXT)
	var normal := _box(COLOR_BTN, MachineView.DIM, 1)
	var hover := _box(COLOR_BTN_HOVER, MachineView.DIM, 1)
	var on := _box(COLOR_BTN, COLOR_HEAD, 2)
	var on_hover := _box(COLOR_BTN_HOVER, COLOR_HEAD, 2)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = COLOR_HEAD
	focus.set_border_width_all(3)
	focus.set_expand_margin_all(3)
	for k in ["normal", "disabled"]:
		th.set_stylebox(k, "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", on)
	th.set_stylebox("hover_pressed", "Button", on_hover)
	th.set_stylebox("focus", "Button", focus)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(k, "Button", MachineView.TEXT)
	# Слайдер: толстая дорожка и крупный ползунок — под палец и стик Steam Deck.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.2, 0.22, 0.26)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = MachineView.WATER
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_stylebox("focus", "HSlider", focus)
	th.set_icon("grabber", "HSlider", _circle(26, MachineView.TEXT))
	th.set_icon("grabber_highlight", "HSlider", _circle(26, COLOR_HEAD))
	return th


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.content_margin_left = 11
	b.content_margin_right = 11
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	return b


static func _circle(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for yy in d:
		for xx in d:
			var a := clampf(c + 0.5 - Vector2(xx - c, yy - c).length(), 0.0, 1.0)
			img.set_pixel(xx, yy, Color(col, a))
	return ImageTexture.create_from_image(img)


# --- Управление ---------------------------------------------------------------

## Действия создаются в коде, чтобы не держать сериализованные события в project.godot.
func _setup_input() -> void:
	_add_action("toggle_pause", [_key(KEY_SPACE), _joy(JOY_BUTTON_X)])
	_add_action("toggle_help", [_key(KEY_F1), _joy(JOY_BUTTON_Y)])
	_add_action("toggle_pump", [_key(KEY_P), _joy(JOY_BUTTON_START)])
	_add_action("toggle_lang", [_key(KEY_L), _joy(JOY_BUTTON_BACK)])
	_add_action("speed_down", [_key(KEY_BRACKETLEFT), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_add_action("speed_up", [_key(KEY_BRACKETRIGHT), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("reset_sim", [_key(KEY_R)])
	_add_action("open_pdf", [_key(KEY_O)])
	_add_action("toggle_view", [_key(KEY_V), _joy(JOY_BUTTON_LEFT_STICK)])
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
