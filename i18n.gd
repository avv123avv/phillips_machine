class_name I18n
extends RefCounted
## Переводы интерфейса: ru (исходный) и en.
## Ключ — русская строка как в коде; нет перевода — показывается русская.
## Язык: аргумент запуска `-- --lang=en`, иначе сохранённый выбор, иначе язык системы.

const LANGS: PackedStringArray = ["ru", "en"]
const SETTINGS_PATH := "user://settings.cfg"

const EN := {
	# phillips_machine.gd — статус и меню
	"t = %.0f с    скорость ×%s    Y = %.1f%s": "t = %.0f s    speed ×%s    Y = %.1f%s",
	"    [ПАУЗА]": "    [PAUSED]",
	"Пауза": "Pause",
	"Пуск": "Run",
	"− скорость": "− speed",
	"+ скорость": "+ speed",
	"Инструкция": "Manual",
	"Рычаги": "Levers",
	"Геймпад: стик — выбор, ←/→ — значение, A — нажать, X — пауза, Start — насос, Select — язык, LB/RB — скорость.":
		"Gamepad: stick — select, ←/→ — value, A — press, X — pause, Start — pump, Select — language, LB/RB — speed.",
	"Клавиатура: Tab/стрелки, Enter — нажать, Пробел — пауза, P — насос, [ ] — скорость, R — сброс, L — язык.":
		"Keyboard: Tab/arrows, Enter — press, Space — pause, P — pump, [ ] — speed, R — reset, L — language.",
	"F1 / Y — инструкция: устройство машины, формулы, сценарии": "F1 / Y — manual: how the machine works, formulas, scenarios",
	# help_overlay.gd
	"Нет страниц инструкции — запустите docs/build_instruction.py": "No manual pages — run docs/build_instruction.py",
	"стр. %d / %d     ← → / LB RB листать     O открыть PDF     F1 / Esc / B закрыть":
		"page %d / %d     ← → / LB RB flip     O open PDF     F1 / Esc / B close",
	# phillips_machine.gd — панель
	"Налоговая ставка t": "Tax rate t",
	"Склонность к сбережению s": "Propensity to save s",
	"Склонность к импорту m": "Propensity to import m",
	"Госрасходы G": "Government spending G",
	"Экспорт X": "Exports X",
	"Процентная ставка r, %": "Interest rate r, %",
	"Скорость симуляции": "Simulation speed",
	"Насос: ВКЛ": "Pump: ON",
	"Насос: ВЫКЛ": "Pump: OFF",
	"Пресеты": "Presets",
	"Стимулирование": "Stimulus",
	"Жёсткая экономия": "Austerity",
	"Рецессия": "Recession",
	"Сброс": "Reset",
	# machine_view.gd — схема
	"Казначейство": "Treasury",
	"Сбережения": "Idle balances",
	"Иностр. балансы": "Foreign balances",
	"Резервуар расходов": "Expenditure sump",
	"Насос": "Pump",
	"ВЫКЛ": "OFF",
	"Бюджет T − G: %+.1f": "Budget T − G: %+.1f",
	"Сальдо X − M: %+.1f": "Trade X − M: %+.1f",
	"Мультипликатор: %.2f": "Multiplier: %.2f",
	"Равновесный Y*: %.0f": "Equilibrium Y*: %.0f",
	"Вода всего: %.1f": "Total water: %.1f",
	"Время: %.0f с": "Time: %.0f s",
	# chart.gd
	"Динамика потоков, ед/с": "Flows over time, units/s",
	"последние %.0f с": "last %.0f s",
}

static var lang := ""


static func t(text: String) -> String:
	_ensure_loaded()
	if lang == "en":
		return EN.get(text, text)
	return text


static func current() -> String:
	_ensure_loaded()
	return lang


static func toggle() -> void:
	_ensure_loaded()
	set_lang(LANGS[(LANGS.find(lang) + 1) % LANGS.size()])


static func set_lang(code: String) -> void:
	lang = code if code in LANGS else "en"
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "lang", lang)
	cfg.save(SETTINGS_PATH)


static func _ensure_loaded() -> void:
	if lang != "":
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			lang = arg.substr(7)
			if lang in LANGS:
				return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		lang = str(cfg.get_value("ui", "lang", ""))
		if lang in LANGS:
			return
	lang = "ru" if OS.get_locale_language() == "ru" else "en"
