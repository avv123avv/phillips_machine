"""Собирает инструкцию на двух языках: docs/instruction_ru.pdf и docs/instruction_en.pdf,
и рендерит страницы в docs/pages/<lang>/page_N.png для просмотра внутри Godot (F1 / Y).

Запуск:  python docs/build_instruction.py
Нужно:   pip install reportlab pypdfium2
Картинка на титуле — docs/screen_<lang>.png (скриншот программы на этом языке).
Числа в сценариях считает класс Economy ниже — копия economy.gd; меняете модель — меняйте обе.
"""
import math
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (CondPageBreak, Image, PageBreak, Paragraph,
                                SimpleDocTemplate, Spacer, Table, TableStyle)

DOCS = Path(__file__).resolve().parent
LANGS = ("ru", "en")
# Высота картинки страницы = высота окна Godot минус строка подсказки, чтобы показывать 1:1.
PAGE_PX_HEIGHT = 1054
# Множитель всех размеров шрифта.
FONT_K = 1.4

FONTS = Path("C:/Windows/Fonts")
pdfmetrics.registerFont(TTFont("Arial", str(FONTS / "arial.ttf")))
pdfmetrics.registerFont(TTFont("Arial-Bold", str(FONTS / "arialbd.ttf")))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="Arial-Bold")

INK = colors.HexColor("#1f2328")
ACCENT = colors.HexColor("#2f6db5")
SOFT = colors.HexColor("#eef3f9")
LINE = colors.HexColor("#b8c4d2")

body = ParagraphStyle("body", fontName="Arial", fontSize=12 * FONT_K, leading=16 * FONT_K, textColor=INK, spaceAfter=5 * FONT_K)
small = ParagraphStyle("small", parent=body, fontSize=10.5 * FONT_K, leading=13.5 * FONT_K)
cell = ParagraphStyle("cell", parent=body, fontSize=11 * FONT_K, leading=14 * FONT_K, spaceAfter=0)
cell_b = ParagraphStyle("cell_b", parent=cell, fontName="Arial-Bold")
h1 = ParagraphStyle("h1", parent=body, fontName="Arial-Bold", fontSize=20 * FONT_K, leading=24 * FONT_K, textColor=ACCENT, spaceAfter=8 * FONT_K, keepWithNext=1)
h2 = ParagraphStyle("h2", parent=body, fontName="Arial-Bold", fontSize=14 * FONT_K, leading=18 * FONT_K, textColor=ACCENT, spaceBefore=6 * FONT_K, spaceAfter=4 * FONT_K, keepWithNext=1)
title = ParagraphStyle("title", parent=h1, fontSize=26 * FONT_K, leading=31 * FONT_K, alignment=TA_CENTER, spaceAfter=4 * FONT_K)
subtitle = ParagraphStyle("subtitle", parent=body, fontSize=14 * FONT_K, leading=18 * FONT_K, alignment=TA_CENTER, textColor=colors.HexColor("#555"))
caption = ParagraphStyle("caption", parent=small, alignment=TA_CENTER, textColor=colors.HexColor("#555"))
formula = ParagraphStyle("formula", parent=body, alignment=TA_CENTER, fontName="Arial-Bold", spaceBefore=2 * FONT_K, spaceAfter=6 * FONT_K)

# Текущий язык сборки; меняется в main.
LANG = "ru"


def L(ru: str, en: str) -> str:
	return ru if LANG == "ru" else en


def f(x: float, d: int = 1) -> str:
	"""Число с d знаками: в русском — десятичная запятая."""
	s = f"{x:.{d}f}"
	return s.replace(".", ",") if LANG == "ru" else s


def p(text: str, style=body) -> Paragraph:
	return Paragraph(text, style)


def table(rows: list[list[str]], widths_mm: list[float]) -> Table:
	data = [[p(c, cell_b if r == 0 else cell) for c in row] for r, row in enumerate(rows)]
	t = Table(data, colWidths=[w * mm for w in widths_mm], repeatRows=1)
	t.setStyle(TableStyle([
		("BACKGROUND", (0, 0), (-1, 0), SOFT),
		("LINEBELOW", (0, 0), (-1, 0), 1, ACCENT),
		("LINEBELOW", (0, 1), (-1, -1), 0.4, LINE),
		("VALIGN", (0, 0), (-1, -1), "TOP"),
		("TOPPADDING", (0, 0), (-1, -1), 3),
		("BOTTOMPADDING", (0, 0), (-1, -1), 4),
	]))
	return t


def steps(items: list[str]) -> list[Paragraph]:
	return [p(f"<b>{i}.</b> {t}", ParagraphStyle(f"s{i}", parent=body, leftIndent=16 * FONT_K, firstLineIndent=-16 * FONT_K))
			for i, t in enumerate(items, 1)]


# --- Копия модели economy.gd ------------------------------------------------

class Economy:
	TOTAL_WATER = 1000.0
	PUMP_K = 0.5
	OUTLET_SOFT = 40.0
	INV_MAX = 45.0
	INV_R_SENS = 0.15
	MAX_DT = 0.1
	DEFAULTS = {"t": 0.25, "s": 0.15, "m": 0.15, "g": 50.0, "x": 22.0, "r": 4.0}

	def __init__(self) -> None:
		self.reset()

	def reset(self) -> None:
		for k, v in self.DEFAULTS.items():
			setattr(self, k, v)
		self.pump_on = True
		self.sump, self.treasury, self.idle, self.foreign = 400.0, 200.0, 200.0, 200.0
		self.time = 0.0
		self._update_flows()

	def investment_demand(self) -> float:
		return self.INV_MAX * math.exp(-self.INV_R_SENS * self.r)

	def multiplier(self) -> float:
		leak = 1.0 - (1.0 - self.t) * (1.0 - min(self.s + self.m, 1.0))
		return 1.0 / max(leak, 1e-6)

	def equilibrium_y(self) -> float:
		return (self.g + self.investment_demand() + self.x) * self.multiplier()

	def advance(self, dt: float) -> None:
		n = max(1, math.ceil(dt / self.MAX_DT - 1e-9))
		for _ in range(n):
			self._step(dt / n)

	def _step(self, dt: float) -> None:
		self._update_flows()
		self.gov = min(self.gov, self.treasury / dt)
		self.inv = min(self.inv, self.idle / dt)
		self.exp_ = min(self.exp_, self.foreign / dt)
		self.sump += (self.cons + self.gov + self.inv + self.exp_ - self.y) * dt
		self.treasury += (self.tax - self.gov) * dt
		self.idle += (self.sav - self.inv) * dt
		self.foreign += (self.imp - self.exp_) * dt
		self.time += dt

	def _update_flows(self) -> None:
		self.y = self.PUMP_K * self.sump if self.pump_on else 0.0
		self.tax = self.t * self.y
		self.yd = self.y - self.tax
		leak = self.s + self.m
		k = 1.0 if leak <= 1.0 else 1.0 / leak
		self.sav = self.s * self.yd * k
		self.imp = self.m * self.yd * k
		self.cons = max(self.yd - self.sav - self.imp, 0.0)
		choke = lambda level: min(max(level / self.OUTLET_SOFT, 0.0), 1.0)
		self.gov = self.g * choke(self.treasury)
		self.inv = self.investment_demand() * choke(self.idle)
		self.exp_ = self.x * choke(self.foreign)


PRESETS = {
	"stimulus": {"t": 0.18, "g": 85.0, "r": 1.5},
	"austerity": {"t": 0.38, "g": 20.0},
	"recession": {"s": 0.32, "r": 9.0, "x": 8.0},
}


def warmed_up() -> Economy:
	"""Состояние после сброса и 60 с при рычагах по умолчанию — от него стартуют все сценарии."""
	e = Economy()
	e.advance(60.0)
	return e


def run_preset(name: str) -> dict:
	e = warmed_up()
	out = {"y0": e.y}
	for k, v in PRESETS[name].items():
		setattr(e, k, v)
	out["y_star"] = e.equilibrium_y()
	for t in (10, 30, 120):
		e.advance(t - (e.time - 60.0))
		out[t] = (e.y, e.treasury, e.idle, e.foreign)
	return out


def time_until(e: Economy, cond, limit: float = 600.0, dt: float = 0.1) -> float | None:
	start = e.time
	while e.time - start < limit:
		if cond(e):
			return e.time - start
		e.advance(dt)
	return None


# --- Текст -------------------------------------------------------------------

def footer(canvas, doc) -> None:
	canvas.saveState()
	canvas.setFont("Arial", 9 * FONT_K)
	canvas.setFillColor(colors.HexColor("#777"))
	w, _ = landscape(A4)
	canvas.drawString(15 * mm, 8 * mm, L("Машина Филлипса (MONIAC) — инструкция", "Phillips Machine (MONIAC) — manual"))
	canvas.drawRightString(w - 15 * mm, 8 * mm, L("стр. ", "p. ") + str(doc.page))
	canvas.restoreState()


def story() -> list:
	s: list = []
	e0 = warmed_up()

	# --- Титул -------------------------------------------------------------
	s += [
		Spacer(1, 2 * mm),
		p(L("Машина Филлипса (MONIAC)", "The Phillips Machine (MONIAC)"), title),
		p(L("Гидравлическая модель экономики: устройство, формулы, сценарии",
			"A hydraulic model of the economy: how it works, formulas, scenarios"), subtitle),
		Spacer(1, 4 * mm),
		Image(str(DOCS / f"screen_{LANG}.png"), width=225 * mm, height=225 * mm * 1080 / 1920),
		p(L("Экран программы. F1 или Y на геймпаде — открыть/закрыть инструкцию, ← / → или LB / RB — листать.",
			"The program screen. F1 or Y on the gamepad opens/closes this manual, ← / → or LB / RB flip pages."), caption),
		PageBreak(),
	]

	# --- 1. История --------------------------------------------------------
	s += [
		p(L("1. Что это", "1. What it is"), h1),
		p(L("В 1949 году новозеландский инженер и экономист Билл Филлипс, тогда студент Лондонской школы "
			"экономики, вместе с Уолтером Ньюлином собрал из оргстекла, насоса и клапанов машину, которая "
			"показывала кейнсианскую модель экономики водой. Деньги в ней — вода: она циркулирует по трубам, "
			"копится в баках и утекает из оборота. Машину назвали MONIAC (Monetary National Income Analogue "
			"Computer); её экземпляры использовались для преподавания в университетах нескольких стран, "
			"сохранившиеся машины стоят в музеях, например в Музее науки в Лондоне и в Резервном банке Новой Зеландии.",
			"In 1949 the New Zealand engineer and economist Bill Phillips, then a student at the London School of "
			"Economics, built together with Walter Newlyn a machine of perspex tanks, a pump and valves that showed "
			"a Keynesian model of the economy with water. Money is water: it circulates through pipes, collects in "
			"tanks and leaks out of circulation. The machine was called MONIAC (Monetary National Income Analogue "
			"Computer); copies were used for teaching at universities in several countries, and surviving machines "
			"are kept in museums, e.g. the Science Museum in London and the Reserve Bank of New Zealand.")),
		p(L("Машина не решает уравнения на бумаге — она их «проживает»: стоит повернуть клапан, и все потоки "
			"перестраиваются сами. Эта программа — цифровая модель такой машины с упрощённой, но полностью "
			"открытой математикой (раздел 3).",
			"The machine does not solve equations on paper — it lives them: turn a valve and every flow readjusts "
			"by itself. This program is a digital model of such a machine with simplified but fully open maths "
			"(section 3).")),
		p(L("Главный принцип: вода никуда не исчезает и ниоткуда не берётся. Её общее количество (1000 единиц) "
			"сохраняется точно — это видно в строке «Вода всего» на экране.",
			"The key principle: water is never created or destroyed. Its total amount (1000 units) is conserved "
			"exactly — see the “Total water” line on screen.")),
		CondPageBreak(70 * mm),
	]

	# --- 2. Устройство -----------------------------------------------------
	s += [
		p(L("2. Резервуары и потоки", "2. Tanks and flows"), h1),
		table([
			[L("Резервуар", "Tank"), L("Втекает", "Inflow"), L("Вытекает", "Outflow"), L("Смысл в экономике", "Economic meaning")],
			[L("Резервуар расходов (внизу)", "Expenditure sump (bottom)"), "C, G, I, X", L("насос → Y", "pump → Y"),
			 L("Совокупный спрос: всё, что тратится на товары и услуги страны", "Aggregate demand: everything spent on the country's goods and services")],
			[L("Казначейство", "Treasury"), "T = t·Y", L("G — клапан госрасходов", "G — government spending valve"),
			 L("Бюджет: налоги приходят, госрасходы уходят. Уровень растёт при профиците, падает при дефиците",
			   "The budget: taxes come in, spending goes out. The level rises with a surplus and falls with a deficit")],
			[L("Сбережения (idle balances)", "Idle balances"), "S = s·Yd", L("I — зависит от ставки r", "I — depends on the rate r"),
			 L("Деньги, отложенные домохозяйствами; бизнес берёт их на инвестиции", "Money set aside by households; business takes it to invest")],
			[L("Иностранные балансы", "Foreign balances"), "M = m·Yd", L("X — клапан экспорта", "X — exports valve"),
			 L("Деньги, ушедшие за границу за импорт; возвращаются, когда за границей покупают наш экспорт",
			   "Money that went abroad for imports; it comes back when foreigners buy our exports")],
		], [52, 32, 52, 131]),
		Spacer(1, 3 * mm),
		p(L("Насос поднимает воду из нижнего резервуара наверх — это национальный доход Y. Сверху поток "
			"делится: часть уходит в казначейство (налоги T), остаток — располагаемый доход Yd. Из него часть "
			"уходит в сбережения (S) и за границу (M), а потребление C сразу стекает обратно вниз. "
			"Вниз же возвращаются госрасходы G, инвестиции I и экспорт X.",
			"The pump lifts water from the bottom tank to the top — this is national income Y. At the top the flow "
			"splits: part goes to the Treasury (taxes T), the rest is disposable income Yd. Part of it goes to "
			"savings (S) and abroad (M), while consumption C drains straight back down. Government spending G, "
			"investment I and exports X return to the bottom too.")),
		p(L("На схеме: толщина воды в трубе и скорость бегущих точек — величина потока; клапаны (жёлтые круги) "
			"показывают положение рычага: заслонка вдоль трубы — клапан открыт, поперёк — закрыт.",
			"On the scheme: the thickness of water in a pipe and the speed of the moving dots show the flow; "
			"the valves (yellow circles) show the lever: the flap along the pipe means open, across means closed.")),
		CondPageBreak(70 * mm),
	]

	# --- 3. Формулы --------------------------------------------------------
	k = e0.multiplier()
	s += [
		p(L("3. Формулы модели", "3. Model formulas"), h1),
		table([
			[L("Величина", "Quantity"), L("Формула", "Formula"), L("По умолчанию", "Default")],
			[L("Доход (подача насоса)", "Income (pump output)"), L("Y = 0,5 · уровень резервуара расходов", "Y = 0.5 · sump level"), f(e0.y)],
			[L("Налоги", "Taxes"), "T = t · Y", f"t = {f(0.25, 2)}"],
			[L("Располагаемый доход", "Disposable income"), "Yd = Y − T", ""],
			[L("Сбережения", "Saving"), "S = s · Yd", f"s = {f(0.15, 2)}"],
			[L("Импорт", "Imports"), "M = m · Yd", f"m = {f(0.15, 2)}"],
			[L("Потребление", "Consumption"), "C = Yd − S − M", ""],
			[L("Госрасходы", "Government spending"), L("G — задаёт рычаг", "G — set by the lever"), "50"],
			[L("Инвестиции", "Investment"), "I = 45 · e<super>−0,15·r</super>" if LANG == "ru" else "I = 45 · e<super>−0.15·r</super>",
			 f"r = 4 % → I = {f(e0.investment_demand())}"],
			[L("Экспорт", "Exports"), L("X — задаёт рычаг", "X — set by the lever"), "22"],
		], [70, 120, 77]),
		Spacer(1, 3 * mm),
		p(L("Уровни резервуаров меняются как «приток минус отток», например у казначейства "
			"d(уровень)/dt = T − G. Пока бак не пуст, из него вытекает заданный поток; когда уровень падает "
			"ниже 40 единиц, отток плавно пережимается — из пустого бака не нальёшь.",
			"Each tank level changes as “inflow minus outflow”, e.g. for the Treasury d(level)/dt = T − G. While a tank "
			"is not empty its outflow is the set value; below 40 units the outflow is gradually choked — you cannot pour "
			"from an empty tank.")),
		p(L("Мультипликатор", "The multiplier"), h2),
		p(L("Если ни один бак не пуст, в равновесии насос перекачивает ровно столько, сколько стекает вниз: "
			"Y = C + G + I + X. Подставив C = (1 − t)(1 − s − m)·Y, получаем",
			"If no tank is empty, at equilibrium the pump lifts exactly as much as drains down: Y = C + G + I + X. "
			"Substituting C = (1 − t)(1 − s − m)·Y gives")),
		p("Y* = (G + I + X) · k,     k = 1 / (1 − (1 − t)(1 − s − m))", formula),
		p(L(f"При рычагах по умолчанию k = {f(k, 2)}, Y* = {f(e0.equilibrium_y(), 0)}: каждая лишняя единица "
			f"госрасходов в итоге даёт {f(k, 2)} единицы дохода. Мультипликатор и Y* показаны в сводке на экране. "
			"Чем больше утечки (t, s, m), тем меньше мультипликатор.",
			f"With the default levers k = {f(k, 2)}, Y* = {f(e0.equilibrium_y(), 0)}: every extra unit of government "
			f"spending ends up as {f(k, 2)} units of income. The multiplier and Y* are shown in the on-screen summary. "
			"The bigger the leakages (t, s, m), the smaller the multiplier.")),
		p(L("Y приходит к Y* не мгновенно: постоянная времени около 1 / (0,5 · (1 − (1 − t)(1 − s − m))) ≈ "
			f"{f(1 / (0.5 / k), 1)} с модельного времени. А пока Y = Y*, баки могут медленно наполняться или пустеть — "
			"тогда равновесие сдвигается (раздел 6).",
			"Y does not jump to Y* at once: the time constant is about 1 / (0.5 · (1 − (1 − t)(1 − s − m))) ≈ "
			f"{f(1 / (0.5 / k), 1)} s of model time. And while Y = Y*, the tanks may slowly fill or drain — then the "
			"equilibrium moves (section 6).")),
		CondPageBreak(70 * mm),
	]

	# --- 4. Управление -----------------------------------------------------
	s += [
		p(L("4. Экран и управление", "4. Screen and controls"), h1),
		p(L("Сверху — время, скорость и Y, ниже меню. Слева — машина, справа — график Y, C, I, G за последние "
			"60 секунд, рычаги и пресеты. В сводке на схеме: бюджет T − G (плюс — профицит), торговое сальдо X − M, "
			"мультипликатор, равновесный Y*, вся вода и время.",
			"At the top: time, speed and Y, then the menu. Left: the machine; right: a chart of Y, C, I, G over the last "
			"60 seconds, the levers and presets. The summary box on the scheme shows the budget T − G (plus = surplus), "
			"the trade balance X − M, the multiplier, the equilibrium Y*, total water and time.")),
		table([
			[L("Геймпад (Steam Deck)", "Gamepad (Steam Deck)"), L("Клавиатура", "Keyboard"), L("Действие", "Action")],
			[L("крестовина / левый стик", "D-pad / left stick"), L("стрелки, Tab", "arrows, Tab"), L("переход между кнопками и слайдерами", "move between buttons and sliders")],
			[L("← / → на слайдере", "← / → on a slider"), "← / →", L("изменить рычаг (1/40 шкалы за нажатие)", "change a lever (1/40 of the scale per press)")],
			["A", "Enter", L("нажать кнопку", "press a button")],
			["X", L("Пробел", "Space"), L("пауза / пуск", "pause / run")],
			["Y", "F1", L("инструкция", "manual")],
			["Start", "P", L("насос вкл / выкл", "pump on / off")],
			["Select", "L", L("язык", "language")],
			["LB / RB", "[ / ]", L("скорость ÷2 / ×2", "speed ÷2 / ×2")],
			["—", "R", L("сброс", "reset")],
			[L("в инструкции: ← → LB RB, B", "in the manual: ← → LB RB, B"), L("← →, PgUp/PgDn, Home, O, Esc", "← →, PgUp/PgDn, Home, O, Esc"),
			 L("листать, в начало, открыть PDF, закрыть", "flip, first page, open the PDF, close")],
		], [75, 75, 117]),
		Spacer(1, 3 * mm),
		p(L("Мышью можно нажимать кнопки и тянуть слайдеры. Язык при первом запуске — как в системе, выбор "
			"запоминается.",
			"With a mouse you can click buttons and drag sliders. The language follows the system on first launch; "
			"the choice is remembered.")),
		CondPageBreak(70 * mm),
	]

	# --- 5. Пресеты --------------------------------------------------------
	names = {"stimulus": L("Стимулирование", "Stimulus"), "austerity": L("Жёсткая экономия", "Austerity"),
			 "recession": L("Рецессия", "Recession")}
	changes = {"stimulus": "t = 0,18, G = 85, r = 1,5 %" if LANG == "ru" else "t = 0.18, G = 85, r = 1.5%",
			   "austerity": "t = 0,38, G = 20" if LANG == "ru" else "t = 0.38, G = 20",
			   "recession": "s = 0,32, r = 9 %, X = 8" if LANG == "ru" else "s = 0.32, r = 9%, X = 8"}
	rows = [[L("Пресет", "Preset"), L("Рычаги", "Levers"), "Y*", L("Y через 10 с", "Y after 10 s"),
			 L("Y через 30 с", "Y after 30 s"), L("Y через 120 с", "Y after 120 s"), L("Казна через 120 с", "Treasury after 120 s")]]
	for name in PRESETS:
		r = run_preset(name)
		rows.append([names[name], changes[name], f(r["y_star"], 0), f(r[10][0], 0), f(r[30][0], 0), f(r[120][0], 0), f(r[120][1], 0)])
	s += [
		p(L("5. Пресеты", "5. Presets"), h1),
		p(L(f"Пресет меняет только свои рычаги, уровни воды остаются. В таблице старт — после сброса и 60 с "
			f"при рычагах по умолчанию (Y = {f(e0.y, 0)}), затем включён пресет; время — модельное (скорость ×1).",
			f"A preset changes only its own levers; water levels stay. In the table the start is after a reset and 60 s "
			f"with the default levers (Y = {f(e0.y, 0)}), then the preset is applied; times are model time (speed ×1).")),
		table(rows, [50, 62, 18, 32, 32, 34, 39]),
		Spacer(1, 3 * mm),
		p(L("<b>Стимулирование.</b> Налоги ниже, госрасходы выше, деньги дешевле — Y быстро растёт к новому Y*. "
			"Но T − G становится отрицательным: казначейство пустеет, и когда воды в нём не остаётся, G падает "
			"до уровня налогов — стимул выдыхается. Это видно по графику G и последнему столбцу таблицы.",
			"<b>Stimulus.</b> Lower taxes, higher spending, cheap money — Y quickly rises towards the new Y*. But "
			"T − G turns negative: the Treasury drains, and once it is empty G falls to the level of taxes — the "
			"stimulus runs out. Watch the G line on the chart and the last column of the table.")),
		p(L("<b>Жёсткая экономия.</b> Налоги выше, госрасходы ниже: бюджет в профиците, вода копится в "
			"казначействе — и выпадает из оборота. Y и потребление падают.",
			"<b>Austerity.</b> Higher taxes, lower spending: the budget is in surplus, water piles up in the Treasury — "
			"and drops out of circulation. Y and consumption fall.")),
		p(L("<b>Рецессия.</b> Домохозяйства больше копят, кредит дорогой, экспорт упал: утечки выросли, "
			"возврат воды вниз сократился — Y проваливается.",
			"<b>Recession.</b> Households save more, credit is expensive, exports have collapsed: leakages grew, "
			"less water comes back down — Y slumps.")),
		p(L("<b>Сброс</b> возвращает все рычаги, уровни воды, скорость и график.",
			"<b>Reset</b> restores all levers, water levels, the speed and the chart.")),
		CondPageBreak(70 * mm),
	]

	# --- 6. Опыты ----------------------------------------------------------
	e = warmed_up()
	y_before = e.y
	k_before = e.multiplier()
	e.g += 10
	e.advance(20.0)
	dy = e.y - y_before

	e = warmed_up()
	s_before = e.sav
	y_before_s = e.y
	e.s = 0.30
	e.advance(60.0)
	y_thrift, s_thrift = e.y, e.sav

	e = warmed_up()
	e.g = 120.0
	t_empty = time_until(e, lambda q: q.treasury < Economy.OUTLET_SOFT)
	e.advance(30.0)
	g_after, t_after = e.gov, e.tax

	e = warmed_up()
	e.pump_on = False
	t_dry = time_until(e, lambda q: q.treasury + q.idle + q.foreign < 10.0)

	s += [
		p(L("6. Опыты", "6. Experiments"), h1),
		p(L("Опыт 1. Мультипликатор", "Experiment 1. The multiplier"), h2),
		*steps([
			L("Нажмите «Сброс» и подождите 20–30 секунд, пока Y не установится.", "Press Reset and wait 20–30 seconds for Y to settle."),
			L("Поднимите G на 10 (с геймпада — 3–4 нажатия →).", "Raise G by 10 (3–4 presses of → on the gamepad)."),
			L(f"Через 20 с Y вырастет примерно на {f(dy, 0)} — близко к k·10 = {f(k_before * 10, 0)}.",
			  f"After 20 s Y grows by about {f(dy, 0)} — close to k·10 = {f(k_before * 10, 0)}."),
		]),
		p(L("Опыт 2. Парадокс бережливости", "Experiment 2. The paradox of thrift"), h2),
		*steps([
			L(f"После сброса S ≈ {f(s_before, 1)}, Y ≈ {f(y_before_s, 0)}.", f"After a reset S ≈ {f(s_before, 1)}, Y ≈ {f(y_before_s, 0)}."),
			L("Поднимите s до 0,30 — все решили копить вдвое больше.", "Raise s to 0.30 — everyone decides to save twice as much."),
			L(f"Через минуту Y ≈ {f(y_thrift, 0)}, а поток сбережений S ≈ {f(s_thrift, 1)}: доход упал, и копить "
			  "стали лишь чуть больше, чем раньше, хотя каждый откладывает вдвое большую долю.",
			  f"A minute later Y ≈ {f(y_thrift, 0)} and the saving flow S ≈ {f(s_thrift, 1)}: income fell, and saving grew "
			  "only a little, although everyone sets aside twice the share."),
		]),
		p(L("Опыт 3. Дефицит не вечен", "Experiment 3. A deficit does not last"), h2),
		*steps([
			L("После сброса поставьте G = 120.", "After a reset set G = 120."),
			L(f"Казначейство почти опустеет примерно за {f(t_empty or 0, 0)} с. После этого G падает до налоговых поступлений: "
			  f"через 30 с G ≈ {f(g_after, 0)} при T ≈ {f(t_after, 0)}.",
			  f"The Treasury is nearly empty in about {f(t_empty or 0, 0)} s. After that G falls to the tax income: 30 s later "
			  f"G ≈ {f(g_after, 0)} with T ≈ {f(t_after, 0)}."),
		]),
		p(L("Опыт 4. Остановка насоса", "Experiment 4. Stop the pump"), h2),
		*steps([
			L("Выключите насос (Start / P).", "Turn the pump off (Start / P)."),
			L(f"Доход Y = 0, а верхние баки стекают вниз: почти вся вода (кроме 10 единиц) окажется в нижнем резервуаре "
			  f"примерно за {f(t_dry or 0, 0)} с. Экономика без оборота денег стоит, хотя вся вода на месте.",
			  f"Income Y = 0 and the upper tanks drain down: almost all water (all but 10 units) is in the bottom tank in "
			  f"about {f(t_dry or 0, 0)} s. An economy without circulation stands still, although all the water is there."),
		]),
		Spacer(1, 3 * mm),
		p(L("Модель учебная: коэффициенты подобраны так, чтобы процессы шли секунды, а не годы, и чтобы при рычагах "
			"по умолчанию экономика была почти в равновесии. Реальная MONIAC имела ещё обратные связи — например, "
			"ставка зависела от уровня в баке сбережений; здесь ставка r задаётся рычагом.",
			"This is a teaching model: the coefficients are chosen so that processes take seconds, not years, and the "
			"economy is nearly balanced with the default levers. The real MONIAC had more feedback loops — e.g. the "
			"interest rate depended on the idle-balances level; here r is set by a lever."), small),
	]
	return s


def render_pages(pdf: Path, pages: Path) -> int:
	import pypdfium2 as pdfium
	pages.mkdir(parents=True, exist_ok=True)
	# Вместе с .import, иначе Godot продолжит видеть удалённые страницы.
	for old in [*pages.glob("page_*.png"), *pages.glob("page_*.png.import")]:
		old.unlink()
	doc = pdfium.PdfDocument(str(pdf))
	for i, page in enumerate(doc, 1):
		scale = PAGE_PX_HEIGHT / page.get_height()
		page.render(scale=scale).to_pil().save(pages / f"page_{i}.png")
	return len(doc)


if __name__ == "__main__":
	for LANG in LANGS:
		pdf = DOCS / f"instruction_{LANG}.pdf"
		SimpleDocTemplate(
			str(pdf), pagesize=landscape(A4),
			leftMargin=15 * mm, rightMargin=15 * mm, topMargin=12 * mm, bottomMargin=14 * mm,
			title=L("Машина Филлипса (MONIAC) — инструкция", "Phillips Machine (MONIAC) — manual"),
			author="phillips_machine",
		).build(story(), onFirstPage=footer, onLaterPages=footer)
		n = render_pages(pdf, DOCS / "pages" / LANG)
		print(f"{LANG}: {pdf.name}, {n} pages")
