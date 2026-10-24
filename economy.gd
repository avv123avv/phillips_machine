class_name Economy
extends RefCounted
## Модель машины Филлипса (MONIAC): запасы воды в резервуарах и потоки между ними.
## Вода только переливается между резервуарами — её общее количество сохраняется точно.
## Отрисовки здесь нет, чтобы модель можно было гонять в тестах без экрана.

const TOTAL_WATER := 1000.0
## Насос: Y = PUMP_K · уровень в резервуаре расходов (1/с).
const PUMP_K := 0.5
## Ниже этого уровня отток из резервуара пережимается (пустой бак не может отдавать воду).
const OUTLET_SOFT := 40.0
## Инвестиции: I = INV_MAX · exp(−INV_R_SENS · r), r в процентах.
const INV_MAX := 45.0
const INV_R_SENS := 0.15
## Максимальный шаг интегрирования, с: PUMP_K · dt ≤ 0,05.
const MAX_DT := 0.1

const DEFAULTS := {
	"t": 0.25, "s": 0.15, "m": 0.15, "g": 50.0, "x": 22.0, "r": 4.0,
}

# Параметры (рычаги)
var t := 0.25  ## налоговая ставка
var s := 0.15  ## склонность к сбережению (от располагаемого дохода)
var m := 0.15  ## склонность к импорту (от располагаемого дохода)
var g := 50.0  ## госрасходы, ед/с (заданные, клапан казначейства)
var x := 22.0  ## экспорт, ед/с (заданный, клапан иностранных балансов)
var r := 4.0   ## процентная ставка, %
var pump_on := true

# Запасы воды, ед
var sump := 0.0
var treasury := 0.0
var idle := 0.0
var foreign := 0.0

# Текущие потоки, ед/с
var y := 0.0       ## национальный доход (подача насоса)
var tax := 0.0     ## T = t·Y
var yd := 0.0      ## Yd = Y − T
var sav := 0.0     ## S = s·Yd
var imp := 0.0     ## M = m·Yd
var cons := 0.0    ## C = Yd − S − M
var gov := 0.0     ## G, фактически вытекает из казначейства
var inv := 0.0     ## I, из сбережений
var exp_ := 0.0    ## X, из иностранных балансов

var time := 0.0


func _init() -> void:
	reset()


func reset() -> void:
	for key in DEFAULTS:
		set(key, DEFAULTS[key])
	pump_on = true
	reset_levels()


func reset_levels() -> void:
	sump = 400.0
	treasury = 200.0
	idle = 200.0
	foreign = 200.0
	time = 0.0
	_update_flows()


func total_water() -> float:
	return sump + treasury + idle + foreign


## Спрос на инвестиции при текущей ставке (до ограничения уровнем в баке сбережений).
func investment_demand() -> float:
	return INV_MAX * exp(-INV_R_SENS * r)


## Мультипликатор: Y* = (G + I + X) / (1 − (1 − t)(1 − s − m)).
func multiplier() -> float:
	var leak := 1.0 - (1.0 - t) * (1.0 - minf(s + m, 1.0))
	return 1.0 / maxf(leak, 1e-6)


## Равновесный доход при текущих G, I(r), X, если ни один резервуар не пуст.
func equilibrium_y() -> float:
	return (g + investment_demand() + x) * multiplier()


## Шаг по времени; большие dt дробятся на подшаги.
func advance(dt: float) -> void:
	var n := maxi(1, ceili(dt / MAX_DT))
	var h := dt / n
	for i in n:
		_step(h)


func _step(dt: float) -> void:
	_update_flows()
	# Отток не может быть больше, чем есть в баке.
	gov = minf(gov, treasury / dt)
	inv = minf(inv, idle / dt)
	exp_ = minf(exp_, foreign / dt)
	sump += (cons + gov + inv + exp_ - y) * dt
	treasury += (tax - gov) * dt
	idle += (sav - inv) * dt
	foreign += (imp - exp_) * dt
	time += dt


func _update_flows() -> void:
	y = PUMP_K * sump if pump_on else 0.0
	tax = t * y
	yd = y - tax
	var leak := s + m
	var k := 1.0 if leak <= 1.0 else 1.0 / leak  # s + m > 1 — делим Yd пропорционально
	sav = s * yd * k
	imp = m * yd * k
	cons = maxf(yd - sav - imp, 0.0)
	gov = g * _choke(treasury)
	inv = investment_demand() * _choke(idle)
	exp_ = x * _choke(foreign)


static func _choke(level: float) -> float:
	return clampf(level / OUTLET_SOFT, 0.0, 1.0)
