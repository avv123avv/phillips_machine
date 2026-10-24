"""Собирает инструкцию на двух языках: docs/instruction_ru.pdf и docs/instruction_en.pdf,
и рендерит страницы в docs/pages/<lang>/page_N.png для просмотра внутри Godot (F1 / Y).

Запуск:  python docs/build_instruction.py
Нужно:   pip install reportlab pypdfium2
Картинка на титуле — docs/screen_<lang>.png (скриншот программы на этом языке).
Числа в сценариях считает класс Economy ниже — копия economy.gd; меняете модель — меняйте обе.
"""
import copy
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
# Текст задач: чуть плотнее, чтобы каждая помещалась на страницу.
tight = ParagraphStyle("tight", parent=body, fontSize=11.5 * FONT_K, leading=14.5 * FONT_K, spaceAfter=4 * FONT_K)
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

# --- Задачи ------------------------------------------------------------------

def trace(changes: dict, times: tuple = (5, 10, 20, 30, 60, 120, 300)) -> tuple[float, dict]:
	"""Старт — warmed_up(), затем рычаги changes. Возвращает Y* и снимки модели в моменты times (с)."""
	e = warmed_up()
	for k, v in changes.items():
		setattr(e, k, v)
	y_star = e.equilibrium_y()
	snaps: dict = {}
	t0 = 0.0
	for t in times:
		e.advance(t - t0)
		t0 = t
		snaps[t] = copy.copy(e)
	return y_star, snaps


def problem(title_: str, task: str, setup: list[list[str]], solution: list[str]) -> list:
	out = [PageBreak(), p(title_, h2), p(L("<b>Постановка.</b> ", "<b>Problem.</b> ") + task, tight),
		   table([[L("Величина", "Quantity"), L("Расчёт", "Calculation"), L("На машине", "On the machine")]] + setup,
				 [52, 110, 105]), Spacer(1, 2 * mm)]
	out += [p((L("<b>Решение.</b> ", "<b>Solution.</b> ") if i == 0 else "") + t, tight) for i, t in enumerate(solution)]
	return out


def problems() -> list:
	e0 = warmed_up()
	k0 = e0.multiplier()
	sec = L(" с", " s")
	s: list = [
		CondPageBreak(90 * mm),
		p(L("7. Задачи: от реальной ситуации к рычагам машины", "7. Problems: from a real situation to the machine's levers"), h1),
		p(L("Каждая задача начинается с одного и того же состояния: «Сброс», затем минута при рычагах по умолчанию "
			f"(Y ≈ {f(e0.y, 0)}, казначейство ≈ {f(e0.treasury, 0)}, сбережения ≈ {f(e0.idle, 0)}, иностранные балансы ≈ "
			f"{f(e0.foreign, 0)}). Потом меняются рычаги, время отсчитывается от этого момента, скорость ×1. "
			"Все числа посчитаны той же моделью, что в программе, — их можно проверить на экране.",
			"Every problem starts from the same state: Reset, then a minute with the default levers "
			f"(Y ≈ {f(e0.y, 0)}, Treasury ≈ {f(e0.treasury, 0)}, idle balances ≈ {f(e0.idle, 0)}, foreign balances ≈ "
			f"{f(e0.foreign, 0)}). Then the levers are changed, time is counted from that moment, speed ×1. "
			"All numbers come from the same model as the program — you can check them on screen.")),
		p(L("<b>Общий порядок.</b> 1) Перевести событие на язык рычагов: что изменилось — налоги, расходы, ставка, "
			"склонности, экспорт. 2) Посчитать равновесие Y* = (G + I + X)·k — это ответ «на короткий срок». "
			"3) Посмотреть, какие баки при этом пустеют или переполняются: из-за них равновесие со временем "
			"сдвигается — это ответ «на долгий срок». Экономические единицы здесь условные: важны направления и "
			"пропорции, а не абсолютные числа.",
			"<b>General procedure.</b> 1) Translate the event into levers: what changed — taxes, spending, the rate, "
			"propensities, exports. 2) Compute the equilibrium Y* = (G + I + X)·k — the “short run” answer. "
			"3) Watch which tanks drain or overfill meanwhile: they shift the equilibrium over time — the “long run” "
			"answer. The units are notional: directions and proportions matter, not absolute numbers.")),
	]

	# 1. Снижение налогов
	ys, tr = trace({"t": 0.20})
	t_drain = next(t for t in tr if tr[t].gov < 49.0)
	s += problem(
		L("Задача 1. Снижение налогов (США, 1964)", "Problem 1. A tax cut (USA, 1964)"),
		L("В 1964 году в США по плану администрации Кеннеди снизили подоходный налог, чтобы подстегнуть рост. "
		  "Госрасходы не сокращали. Насколько вырастет доход? Окупится ли снижение — вырастут ли налоговые "
		  "поступления? Что будет с казной?",
		  "In 1964 the USA cut income tax, following the Kennedy administration's plan, to speed up growth. "
		  "Spending was not cut. How much will income grow? Does the cut pay for itself — will tax revenue rise? "
		  "What happens to the Treasury?"),
		[
			[L("Изменение", "Change"), L("Ставка налога 0,25 → 0,20", "Tax rate 0.25 → 0.20"), L("слайдер t = 0,20", "slider t = 0.20")],
			[L("Мультипликатор", "Multiplier"), f"k = 1 / (1 − 0,80·0,70) = {f(1 / (1 - 0.8 * 0.7), 2)}" if LANG == "ru"
			 else f"k = 1 / (1 − 0.80·0.70) = {f(1 / (1 - 0.8 * 0.7), 2)}", L("строка «Мультипликатор»", "“Multiplier” line")],
			[L("Равновесие", "Equilibrium"), f"Y* = ({f(e0.g, 0)} + {f(e0.inv)} + {f(e0.x, 0)})·k = {f(ys)}", L("строка «Равновесный Y*»", "“Equilibrium Y*” line")],
			[L("Налоги", "Taxes"), f"T = 0,20 · {f(ys)} = {f(0.2 * ys)}" if LANG == "ru" else f"T = 0.20 · {f(ys)} = {f(0.2 * ys)}",
			 L(f"было {f(e0.tax)}", f"was {f(e0.tax)}")],
			[L("Смотрим", "Watch"), L("Бюджет T − G и уровень казначейства", "Budget T − G and the Treasury level"), L("сводка, бак слева", "summary, left tank")],
		],
		[
			L(f"Доход быстро растёт: через 10 с Y = {f(tr[10].y)}, к 20 с — {f(tr[20].y)}, почти Y* = {f(ys)}. "
			  f"Но налоги падают с {f(e0.tax)} до {f(tr[20].tax)}: рост дохода не покрывает снижения ставки, "
			  f"бюджет уходит в дефицит T − G = {f(tr[20].tax - tr[20].gov)}.",
			  f"Income rises quickly: Y = {f(tr[10].y)} after 10 s and {f(tr[20].y)} by 20 s, almost Y* = {f(ys)}. "
			  f"But taxes fall from {f(e0.tax)} to {f(tr[20].tax)}: income growth does not make up for the lower rate, "
			  f"the budget goes into deficit T − G = {f(tr[20].tax - tr[20].gov)}."),
			L(f"Дефицит оплачивается из казны: её уровень падает с {f(e0.treasury, 0)} до {f(tr[30].treasury, 0)} за 30 с. "
			  f"Примерно к {t_drain}-й секунде бак почти пуст, клапан G пережимается до уровня налогов, и доход "
			  f"падает: через минуту Y = {f(tr[60].y)}, через 5 минут — {f(tr[300].y)}, <b>ниже исходного</b>.",
			  f"The deficit is paid from the Treasury: its level falls from {f(e0.treasury, 0)} to {f(tr[30].treasury, 0)} in 30 s. "
			  f"By about second {t_drain} the tank is nearly empty, the G valve is choked down to tax income and income "
			  f"falls: Y = {f(tr[60].y)} after a minute and {f(tr[300].y)} after 5 minutes, <b>below the start</b>."),
			L("Вывод: снижение налогов разгоняет доход, пока есть чем платить. Без сокращения расходов или займов "
			  "(в машине их нет — только запас в казначействе) эффект временный.",
			  "Conclusion: a tax cut boosts income while there is money to pay for it. Without spending cuts or borrowing "
			  "(the machine has none — only the Treasury's reserve) the effect is temporary."),
		],
	)

	# 2. Экспортный бум
	ys, tr = trace({"x": 40.0})
	peak = max(tr.values(), key=lambda q: q.y)
	s += problem(
		L("Задача 2. Экспортный бум (Новая Зеландия, 1950–1951)", "Problem 2. An export boom (New Zealand, 1950–1951)"),
		L("Во время Корейской войны мировые цены на шерсть — главный экспорт Новой Зеландии, родины Филлипса, — "
		  "выросли в несколько раз. Экспортная выручка резко выросла. Как изменится доход и надолго ли?",
		  "During the Korean War world wool prices — the main export of New Zealand, Phillips's home country — "
		  "rose several times over. Export earnings jumped. How does income change, and for how long?"),
		[
			[L("Изменение", "Change"), L("Экспорт 22 → 40", "Exports 22 → 40"), L("слайдер X = 40", "slider X = 40")],
			[L("Равновесие", "Equilibrium"), f"Y* = ({f(e0.g, 0)} + {f(e0.inv)} + 40)·{f(k0, 2)} = {f(ys)}", f"+{f(ys - e0.y)}"],
			[L("Импорт", "Imports"), f"M = m·(1 − t)·Y* = {f(0.15 * 0.75 * ys)}", L("меньше X — сальдо в плюсе", "less than X — trade surplus")],
			[L("Смотрим", "Watch"), L("Уровень иностранных балансов, сальдо X − M", "Foreign balances level, X − M"), L("бак справа, сводка", "right tank, summary")],
		],
		[
			L(f"Доход растёт быстро: максимум Y ≈ {f(peak.y)} около {f(peak.time - 60, 0)}-й секунды. Но вода для "
			  f"экспорта берётся из бака иностранных балансов — это деньги, которые иностранцы накопили, покупая наш импорт. "
			  f"X = 40 при M ≈ {f(tr[10].imp)}: бак пустеет с {f(e0.foreign, 0)} до {f(tr[20].foreign, 0)} за 20 с.",
			  f"Income rises fast: the peak Y ≈ {f(peak.y)} at about second {f(peak.time - 60, 0)}. But water for exports "
			  f"comes from the foreign balances tank — money foreigners collected by selling us imports. X = 40 with "
			  f"M ≈ {f(tr[10].imp)}: the tank drops from {f(e0.foreign, 0)} to {f(tr[20].foreign, 0)} in 20 s."),
			L(f"Когда бак почти пуст, экспорт ограничен импортом: X = M ≈ {f(tr[60].exp_)} через минуту. Доход "
			  f"возвращается: {f(tr[30].y)} через 30 с, {f(tr[120].y)} через 2 минуты. Зато бум оставил след в казне: "
			  f"на волне высоких доходов она выросла с {f(e0.treasury, 0)} до {f(tr[120].treasury, 0)}.",
			  f"Once the tank is nearly empty, exports are limited by imports: X = M ≈ {f(tr[60].exp_)} after a minute. "
			  f"Income comes back down: {f(tr[30].y)} after 30 s, {f(tr[120].y)} after 2 minutes. But the boom left a mark "
			  f"in the Treasury: riding on high incomes it grew from {f(e0.treasury, 0)} to {f(tr[120].treasury, 0)}."),
			L("Вывод: сырьевой бум даёт быстрый, но временный рост; долго держать сальдо в плюсе можно, только пока "
			  "у остального мира есть чем платить. Разумно отложить часть выручки — что здесь и сделала казна.",
			  "Conclusion: a commodity boom gives fast but temporary growth; a trade surplus lasts only while the rest "
			  "of the world has money to pay. It is wise to put part of the windfall aside — as the Treasury did here."),
		],
	)

	# 3. Шок Волкера
	ys, tr = trace({"r": 12.0})
	i_new = 45.0 * math.exp(-0.15 * 12)
	s += problem(
		L("Задача 3. Дорогие деньги (ФРС, 1979–1981)", "Problem 3. Tight money (the Fed, 1979–1981)"),
		L("Чтобы сбить инфляцию, ФРС США под руководством Пола Волкера подняла ставки почти до 20 %. "
		  "Что случится с инвестициями и доходом? Куда денутся деньги?",
		  "To break inflation, the US Federal Reserve under Paul Volcker raised rates to nearly 20%. "
		  "What happens to investment and income? Where does the money go?"),
		[
			[L("Изменение", "Change"), L("Ставка 4 % → 12 % (максимум шкалы)", "Rate 4% → 12% (top of the scale)"), L("слайдер r = 12", "slider r = 12")],
			[L("Инвестиции", "Investment"), f"I = 45·e<super>−0,15·12</super> = {f(i_new)}" if LANG == "ru" else f"I = 45·e<super>−0.15·12</super> = {f(i_new)}",
			 L(f"было {f(e0.inv)}", f"was {f(e0.inv)}")],
			[L("Равновесие", "Equilibrium"), f"Y* = ({f(e0.g, 0)} + {f(i_new)} + {f(e0.x, 0)})·{f(k0, 2)} = {f(ys)}", f"{f(ys - e0.y)}"],
			[L("Смотрим", "Watch"), L("Бак сбережений: S против I", "Idle balances tank: S versus I"), L("средний бак", "middle tank")],
		],
		[
			L(f"Доход падает до Y* за ~20 с: Y = {f(tr[20].y)}. Но сбережения S ≈ {f(tr[20].sav)} теперь больше "
			  f"инвестиций I = {f(i_new)}: разница оседает в баке сбережений. Он растёт с {f(e0.idle, 0)} до "
			  f"{f(tr[20].idle, 0)} за 20 с и {f(tr[60].idle, 0)} за минуту.",
			  f"Income falls to Y* in ~20 s: Y = {f(tr[20].y)}. But saving S ≈ {f(tr[20].sav)} now exceeds investment "
			  f"I = {f(i_new)}: the difference settles in the idle balances tank. It grows from {f(e0.idle, 0)} to "
			  f"{f(tr[20].idle, 0)} in 20 s and {f(tr[60].idle, 0)} in a minute."),
			L(f"Вода, застрявшая в сбережениях, выпала из оборота. Казна (дефицит из-за упавших налогов) и иностранные "
			  f"балансы пустеют, и доход проваливается ниже равновесия: {f(tr[60].y)} через минуту, {f(tr[300].y)} через 5 минут.",
			  f"Water stuck in idle balances has left circulation. The Treasury (in deficit because taxes fell) and foreign "
			  f"balances drain, and income slumps below the equilibrium: {f(tr[60].y)} after a minute, {f(tr[300].y)} after 5 minutes."),
			L("Вывод: высокая ставка не просто сокращает инвестиции — она заставляет деньги лежать без дела. Так "
			  "Волкер победил инфляцию ценой тяжёлого спада 1981–1982 годов. Верните r = 4 % и посмотрите, как "
			  "накопленная вода возвращается в оборот.",
			  "Conclusion: a high rate does not just cut investment — it makes money sit idle. This is how Volcker beat "
			  "inflation at the cost of the deep 1981–1982 recession. Set r back to 4% and watch the stored water "
			  "flow back into circulation."),
		],
	)

	# 4. Депрессия и «Новый курс»
	rec = {"s": 0.32, "r": 9.0, "x": 8.0}
	ys_rec, tr_rec = trace(rec)
	tmp = Economy()
	for k_, v in rec.items():
		setattr(tmp, k_, v)
	k_rec = tmp.multiplier()
	g_need = e0.y / k_rec - tmp.investment_demand() - tmp.x
	_, tr_g = trace(dict(rec, g=g_need))
	ys_mix, tr_mix = trace(dict(rec, r=0.0, g=80.0))
	s += problem(
		L("Задача 4. Великая депрессия и «Новый курс» (1930-е)", "Problem 4. The Great Depression and the New Deal (1930s)"),
		L("После краха 1929 года люди и банки копят, кредит дорог, мировая торговля рухнула (пресет «Рецессия»). "
		  "Какие госрасходы нужны, чтобы вернуть прежний доход? Хватит ли казны? Поможет ли дешёвый кредит?",
		  "After the 1929 crash people and banks hoard, credit is expensive, world trade has collapsed (the Recession "
		  "preset). What government spending would restore the previous income? Is the Treasury enough? Does cheap "
		  "credit help?"),
		[
			[L("Спад", "Slump"), L("s = 0,32, r = 9 %, X = 8", "s = 0.32, r = 9%, X = 8"),
			 L(f"пресет «Рецессия»: Y* = {f(ys_rec)}", f"Recession preset: Y* = {f(ys_rec)}")],
			[L("Мультипликатор", "Multiplier"), f"k = 1 / (1 − 0,75·0,53) = {f(k_rec, 2)}" if LANG == "ru" else f"k = 1 / (1 − 0.75·0.53) = {f(k_rec, 2)}",
			 L("утечки выросли — k меньше", "leakages grew — k is smaller")],
			[L("Нужные G", "Required G"), f"G = {f(e0.y, 0)} / {f(k_rec, 2)} − {f(tmp.investment_demand())} − 8 = {f(g_need, 0)}",
			 L(f"слайдер G = {f(g_need, 0)}", f"slider G = {f(g_need, 0)}")],
			[L("Смотрим", "Watch"), L("Казначейство, сбережения, иностранные балансы", "Treasury, idle and foreign balances"), L("все три бака", "all three tanks")],
		],
		[
			L(f"Без вмешательства доход падает до {f(tr_rec[20].y)} за 20 с и {f(tr_rec[60].y)} за минуту — ниже "
			  f"Y* = {f(ys_rec)}, потому что казна быстро пустеет, а вода копится в сбережениях ({f(tr_rec[60].idle, 0)}).",
			  f"Without action income falls to {f(tr_rec[20].y)} in 20 s and {f(tr_rec[60].y)} in a minute — below "
			  f"Y* = {f(ys_rec)}, because the Treasury drains fast and water piles up in idle balances ({f(tr_rec[60].idle, 0)})."),
			L(f"С G = {f(g_need, 0)} равновесие возвращается к {f(e0.y, 0)}, но дефицит огромен, и казна пуста уже "
			  f"через несколько секунд (через 5 с осталось {f(tr_g[5].treasury, 0)}). Доход успевает подняться только до "
			  f"{f(tr_g[5].y)}, через 30 с — снова {f(tr_g[30].y)}.",
			  f"With G = {f(g_need, 0)} the equilibrium returns to {f(e0.y, 0)}, but the deficit is huge and the Treasury "
			  f"is empty within seconds ({f(tr_g[5].treasury, 0)} left after 5 s). Income only gets up to {f(tr_g[5].y)}, "
			  f"and is back to {f(tr_g[30].y)} after 30 s."),
			L(f"Вместе с дешёвым кредитом (r = 0 %, G = 80) вода уходит из сбережений в инвестиции: Y = {f(tr_mix[10].y)} "
			  f"через 10 с. Но пока экспорт 8, а импорт больше, вода утекает за границу (иностранные балансы "
			  f"{f(tr_mix[60].foreign, 0)} через минуту), и доход снова сползает: {f(tr_mix[60].y)}.",
			  f"Combined with cheap credit (r = 0%, G = 80) water flows from idle balances into investment: Y = {f(tr_mix[10].y)} "
			  f"after 10 s. But while exports are 8 and imports are larger, water leaks abroad (foreign balances "
			  f"{f(tr_mix[60].foreign, 0)} after a minute) and income slides again: {f(tr_mix[60].y)}."),
			L("Вывод: в депрессии одна мера не работает — нужно закрыть все утечки сразу: расходы, ставку и "
			  "торговлю. Попробуйте подобрать набор рычагов, при котором Y держится около 200 хотя бы 2 минуты.",
			  "Conclusion: in a depression no single measure works — all the leaks must be closed at once: spending, the "
			  "rate and trade. Try to find a set of levers that keeps Y near 200 for at least 2 minutes."),
		],
	)

	# 5. Сбалансированный бюджет
	g_new = 70.0
	lo, hi = 0.0, 0.6
	for _ in range(60):
		mid = (lo + hi) / 2
		tmp = Economy()
		tmp.t, tmp.g = mid, g_new
		if mid * tmp.equilibrium_y() > g_new:
			hi = mid
		else:
			lo = mid
	t_bal = round(lo, 2)
	ys, tr = trace({"g": g_new, "t": t_bal})
	s += problem(
		L("Задача 5. Сбалансированный бюджет (Хаавельмо, 1945)", "Problem 5. A balanced budget (Haavelmo, 1945)"),
		L("Норвежский экономист Трюгве Хаавельмо показал: если государство тратит больше и ровно столько же "
		  "собирает налогами, доход всё равно растёт. Поднимите G на 20 и подберите налог t так, чтобы в новом "
		  "равновесии бюджет остался сбалансированным (T = G). На сколько вырастет доход?",
		  "The Norwegian economist Trygve Haavelmo showed that if the state spends more and collects exactly as much "
		  "in taxes, income still grows. Raise G by 20 and pick the tax rate t so that the budget stays balanced "
		  "(T = G) at the new equilibrium. How much does income grow?"),
		[
			[L("Изменение", "Change"), f"G = 50 → {f(g_new, 0)}", L(f"слайдер G = {f(g_new, 0)}", f"slider G = {f(g_new, 0)}")],
			[L("Условие", "Condition"), "t · Y*(t) = G", L("подбор: t, пока T − G ≈ 0", "adjust t until T − G ≈ 0")],
			[L("Ответ для t", "Answer for t"), L(f"t ≈ {f(t_bal, 2)} (решение подбором)", f"t ≈ {f(t_bal, 2)} (found by trial)"),
			 L(f"слайдер t = {f(t_bal, 2)}", f"slider t = {f(t_bal, 2)}")],
			[L("Равновесие", "Equilibrium"), f"Y* = {f(ys)}", f"+{f(ys - e0.y)}"],
		],
		[
			L(f"Через 20 с Y = {f(tr[20].y)}, бюджет T − G = {f(tr[20].tax - tr[20].gov)}: практически ноль. Доход вырос "
			  f"на {f(tr[20].y - e0.y)} — почти ровно на прирост расходов (20). Мультипликатор сбалансированного бюджета "
			  "близок к единице.",
			  f"After 20 s Y = {f(tr[20].y)}, budget T − G = {f(tr[20].tax - tr[20].gov)}: practically zero. Income grew by "
			  f"{f(tr[20].y - e0.y)} — almost exactly the extra spending (20). The balanced-budget multiplier is close to one."),
			L("Почему так: каждая единица налога уменьшает потребление только на долю (1 − s − m), а каждая единица "
			  "расходов тратится целиком. Разница и запускает мультипликатор.",
			  "Why: each unit of tax reduces consumption only by the share (1 − s − m), while each unit of spending is "
			  "spent in full. The difference drives the multiplier."),
			L(f"Это самый устойчивый из пяти сценариев: через 2 минуты Y = {f(tr[120].y)}. Медленный дрейф дальше "
			  f"({f(tr[300].y)} через 5 минут) — оттого что t округлено до сотых и бюджет в небольшом дефиците, а импорт "
			  f"чуть больше экспорта: казна понемногу пустеет ({f(tr[120].treasury, 0)} через 2 минуты), а иностранные "
			  "балансы наполняются.",
			  f"This is the most stable of the five scenarios: Y = {f(tr[120].y)} after 2 minutes. The slow drift later "
			  f"({f(tr[300].y)} after 5 minutes) is because t is rounded to hundredths and the budget runs a small deficit, "
			  f"while imports are slightly above exports: the Treasury slowly drains ({f(tr[120].treasury, 0)} after 2 minutes) "
			  "and foreign balances fill up."),
		],
	)
	return s


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
		*problems(),
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
