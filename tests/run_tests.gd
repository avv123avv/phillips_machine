extends SceneTree
## Автотесты: godot --headless --path . -s tests/run_tests.gd
## Код выхода 0 — всё прошло, 1 — есть провалы (так их видит CI).

const SETTINGS := "user://settings.cfg"

var _failed := 0
var _passed := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok   ", what)
	else:
		_failed += 1
		printerr("  FAIL ", what)


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


## Русские строки из I18n.t("…") в исходниках и из таблиц подписей, которых нет в I18n.EN.
func _missing_translations() -> Array:
	var keys: Array = []
	var re := RegEx.create_from_string(r'I18n\.t\("((?:[^"\\]|\\.)*)"\)')
	for file in DirAccess.get_files_at("res://"):
		if file.ends_with(".gd"):
			for m in re.search_all(FileAccess.get_file_as_string("res://" + file)):
				keys.append(m.get_string(1).c_unescape())
	for d in PhillipsMachine.SLIDERS + PhillipsMachine.PRESET_BUTTONS + PhillipsMachine.MENU:
		keys.append(d[1])
	keys.append_array(MachineView.TANK_NAMES.values())
	var out: Array = []
	for k in keys:
		if k != "English" and not I18n.EN.has(k) and k not in out:
			out.append(k)
	return out


func _initialize() -> void:
	var had_settings := FileAccess.file_exists(SETTINGS)
	var saved_settings := FileAccess.get_file_as_string(SETTINGS) if had_settings else ""

	print("Модель")
	var e := Economy.new()
	_check(is_equal_approx(e.total_water(), Economy.TOTAL_WATER), "начальная вода = %.0f" % Economy.TOTAL_WATER)
	e.advance(120.0)
	_check(absf(e.total_water() - Economy.TOTAL_WATER) < 1e-6, "вода сохраняется за 120 с (%.9f)" % e.total_water())
	e._update_flows()
	_check(is_equal_approx(e.tax + e.sav + e.imp + e.cons, e.y), "T + S + M + C = Y")
	_check(is_equal_approx(e.tax, e.t * e.y) and is_equal_approx(e.sav, e.s * e.yd), "T = t·Y, S = s·Yd")
	var ok_levels := e.sump >= 0.0 and e.treasury >= 0.0 and e.idle >= 0.0 and e.foreign >= 0.0
	_check(ok_levels, "уровни не уходят ниже нуля")

	# Полные баки, оттоки не пережаты → Y сходится к равновесию мультипликатора.
	e.reset()
	e.sump = 100.0
	e.treasury = 300.0
	e.idle = 300.0
	e.foreign = 300.0
	e.advance(30.0)
	var err := absf(e.y - e.equilibrium_y()) / e.equilibrium_y()
	_check(err < 0.01, "Y → (G + I + X)·k (ошибка %.4f)" % err)
	_check(is_equal_approx(e.multiplier(), 1.0 / (1.0 - 0.75 * 0.7)), "мультипликатор при t=.25, s=m=.15")

	e.reset()
	var i_lo := e.investment_demand()
	e.r = 10.0
	_check(e.investment_demand() < i_lo, "выше ставка r → меньше инвестиций")

	e.reset()
	e.pump_on = false
	e.advance(200.0)
	_check(e.y == 0.0 and e.treasury < 1.0 and e.idle < 1.0 and e.foreign < 1.0,
			"насос выключен → вся вода стекает в нижний резервуар")
	_check(absf(e.sump - Economy.TOTAL_WATER) < 1.0, "… и там вся вода (%.2f)" % e.sump)

	e.reset()
	e.s = 0.6
	e.m = 0.6
	e._update_flows()
	_check(e.cons >= 0.0 and is_equal_approx(e.sav + e.imp, e.yd), "s + m > 1: C = 0, Yd делится на S и M")

	e.reset()
	e.g = 120.0
	e.advance(300.0)
	_check(e.treasury >= 0.0 and e.gov <= e.g, "дефицит: казначейство не уходит в минус, G ограничен")

	print("Интерфейс")
	I18n.lang = "ru"
	var main: PhillipsMachine = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.apply_preset("stimulus")
	_check(is_equal_approx(main.econ.g, 85.0) and is_equal_approx(main.econ.t, 0.18), "пресет «Стимулирование»")
	main.apply_preset("austerity")
	_check(is_equal_approx(main.econ.g, 20.0) and is_equal_approx(main.econ.t, 0.38), "пресет «Жёсткая экономия»")
	main.apply_preset("recession")
	_check(is_equal_approx(main.econ.s, 0.32) and is_equal_approx(main.econ.r, 9.0), "пресет «Рецессия»")
	main.apply_preset("reset")
	_check(is_equal_approx(main.econ.g, Economy.DEFAULTS["g"]) and main.econ.time == 0.0, "«Сброс» — рычаги и уровни")
	(main.sliders["g"] as HSlider).value = 70.0
	_check(is_equal_approx(main.econ.g, 70.0) and main.value_labels["g"].text == "70", "слайдер G → модель и подпись")
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	main._on_slider_input(right, main.sliders["g"], 3.0)
	_check(is_equal_approx(main.econ.g, 73.0), "←/→ на слайдере — крупный шаг для геймпада")
	main._press_menu("pump")
	_check(not main.econ.pump_on and main.menu["pump"].text == "Насос: ВЫКЛ", "кнопка насоса")
	main._press_menu("lang")
	_check(I18n.current() == "en" and main.menu["pump"].text == "Pump: OFF" and main.menu["lang"].text == "Русский",
			"смена языка ru → en")
	main._press_menu("lang")
	_check(main.menu["lang"].text == "English", "смена языка en → ru")
	main._unhandled_input(_action("toggle_pump"))
	_check(main.econ.pump_on, "действие toggle_pump (Start / P)")
	_check(InputMap.action_has_event("toggle_pump", PhillipsMachine._joy(JOY_BUTTON_START)), "Start привязан к насосу")
	main._press_menu("faster")
	_check(is_equal_approx(main.speed, 2.0), "«+ скорость» ×2")
	main._unhandled_input(_action("speed_down"))
	_check(is_equal_approx(main.speed, 1.0), "LB / [ — скорость ÷2")
	for i in 30:
		await process_frame
	_check(main.econ.time > 0.0, "симуляция идёт в _process")
	main._input(_action("toggle_pause"))
	var t_paused := main.econ.time
	for i in 10:
		await process_frame
	_check(main.paused and main.econ.time == t_paused and main.menu["pause"].text == "Пуск", "пауза (Пробел / X) останавливает время")
	main._press_menu("pause")
	_check(not main.paused, "«Пуск» снимает паузу")

	print("Инструкция")
	main._unhandled_input(_action("toggle_help"))
	_check(main.help.visible, "F1 / Y открывает инструкцию")
	var ru_pages := main.help.pages.size()
	main._input(_action("ui_right"))
	_check(main.help.page == mini(1, ru_pages - 1), "→ листает вперёд")
	main._input(_action("speed_down"))
	_check(main.help.page == 0, "LB листает назад")
	main._input(_action("toggle_pump"))
	_check(main.econ.pump_on, "открытая инструкция забирает ввод")
	main._input(_action("ui_cancel"))
	_check(not main.help.visible, "Esc / B закрывает")
	I18n.lang = "en"
	main.set_help(true)
	var en_pages := main.help.pages.size()
	main.set_help(false)
	I18n.lang = "ru"
	_check(ru_pages > 0 and en_pages > 0, "страницы инструкции есть: ru %d, en %d" % [ru_pages, en_pages])
	_check(FileAccess.file_exists("res://docs/instruction_ru.pdf") and FileAccess.file_exists("res://docs/instruction_en.pdf"),
			"PDF инструкции на обоих языках в docs/")
	main.queue_free()

	print("Переводы")
	var missing := _missing_translations()
	_check(missing.is_empty(), "у всех строк интерфейса есть английский перевод %s" % [missing])

	# Тест не должен менять сохранённый выбор языка пользователя.
	if had_settings:
		var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
		f.store_string(saved_settings)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))

	print("Итого: %d ok, %d fail" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
