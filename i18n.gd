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
	"Геймпад: стик — выбор, ←/→ — значение, A — нажать, X — пауза, Start — насос, Select — язык, LB/RB — скорость, L3 — схема.":
		"Gamepad: stick — select, ←/→ — value, A — press, X — pause, Start — pump, Select — language, LB/RB — speed, L3 — scheme.",
	"Клавиатура: Tab/стрелки, Enter — нажать, Пробел — пауза, P — насос, [ ] — скорость, V — схема, R — сброс, L — язык.":
		"Keyboard: Tab/arrows, Enter — press, Space — pause, P — pump, [ ] — speed, V — scheme, R — reset, L — language.",
	"Схема сборки": "Build scheme",
	"Схема машины": "Machine scheme",
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
	# diy_rig.gd — схема домашнего стенда
	"%.1f см · %.0f мл": "%.1f cm · %.0f ml",
	"пластины %s: %s мм": "plates %s: %s mm",
	"БП 12 В": "PSU 12 V",
	"Помпа: ШИМ %.0f %% · %.0f л/ч": "Pump: PWM %.0f %% · %.0f L/h",
	"Краник G: %.0f мл/мин": "Valve G: %.0f ml/min",
	"Краник I: %.0f мл/мин": "Valve I: %.0f ml/min",
	"Краник X: %.0f мл/мин": "Valve X: %.0f ml/min",
	"#Детали стенда": "#Rig parts",
	"1  Нижний бак 3 л": "1  Bottom tank 3 L",
	"2  Баки 2 л — 3 шт.": "2  2 L tanks — 3 pcs",
	"3  Помпа 12 В, 240 л/ч": "3  12 V pump, 240 L/h",
	"4  Делитель t (лоток)": "4  Splitter t (trough)",
	"5  Делитель s, m (лоток)": "5  Splitter s, m (trough)",
	"6  Штуцер в дне бака — 3": "6  Tank bulkhead fitting — 3",
	"7  Аквариумный краник — 3": "7  Aquarium valve — 3",
	"8  Силиконовая трубка 8 мм": "8  Silicone tube 8 mm",
	"9  Датчик уровня HC-SR04": "9  HC-SR04 level sensor",
	"10 Arduino Nano + MOSFET": "10 Arduino Nano + MOSFET",
	"11 Блок питания 12 В 2 А": "11 12 V 2 A power supply",
	"12 Щит 80 × 75 см, полка": "12 Board 80 × 75 cm, shelf",
	"#Масштаб": "#Scale",
	"1 ед. воды = %.0f мл": "1 water unit = %.0f ml",
	"1 с модели = %.0f с стенда": "1 model s = %.0f rig s",
	"Вода всего: %.1f л": "Total water: %.1f L",
	"F1 — сборка и калибровка": "F1 — assembly and calibration",
	# chart.gd
	"Динамика потоков, ед/с": "Flows over time, units/s",
	"последние %.0f с": "last %.0f s",
	"доход страны (ВВП)": "national income (GDP)",
	"покупки населения": "consumer spending",
	"вложения бизнеса": "business investment",
	"расходы государства": "government spending",
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
