class_name HelpOverlay
extends Control
## Инструкция поверх экрана (F1 / Y на геймпаде).
## Godot не умеет показывать PDF, поэтому страницы заранее отрендерены
## в PNG скриптом docs/build_instruction.py. Ввод разбирает PhillipsMachine.

const HELP_PDF := "res://docs/instruction_%s.pdf"
const HELP_PAGE := "res://docs/pages/%s/page_%d.png"
const FS_SMALL := 20

var page := 0
var pages: Array[Texture2D] = []
var _lang := ""


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func open() -> void:
	_load()
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func flip(dir: int) -> void:
	page = clampi(page + dir, 0, maxi(pages.size() - 1, 0))
	queue_redraw()


func first() -> void:
	page = 0
	queue_redraw()


## В собранной игре PDF лежат рядом с .exe (их кладёт туда CI), в проекте — в docs/.
func pdf_path() -> String:
	if OS.has_feature("template"):
		var name := (HELP_PDF % I18n.current()).get_file()
		return OS.get_executable_path().get_base_dir().path_join(name)
	return ProjectSettings.globalize_path(HELP_PDF % I18n.current())


func _load() -> void:
	var lang := I18n.current()
	if _lang == lang:
		return
	_lang = lang
	pages.clear()
	page = 0
	var i := 1
	while ResourceLoader.exists(HELP_PAGE % [lang, i]):
		pages.append(load(HELP_PAGE % [lang, i]) as Texture2D)
		i += 1


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	match mouse.button_index:
		MOUSE_BUTTON_WHEEL_DOWN:
			flip(1)
		MOUSE_BUTTON_WHEEL_UP:
			flip(-1)
		MOUSE_BUTTON_LEFT:
			flip(1 if mouse.position.x > size.x * 0.5 else -1)
	accept_event()


func _draw() -> void:
	var font := get_theme_default_font()
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.05, 0.05, 0.06, 0.94))
	if pages.is_empty():
		draw_string(font, Vector2(0, view.y * 0.5), I18n.t("Нет страниц инструкции — запустите docs/build_instruction.py"),
				HORIZONTAL_ALIGNMENT_CENTER, view.x, 24, MachineView.TEXT)
		return
	var tex := pages[page]
	var tex_size := tex.get_size()
	var avail := Vector2(view.x, view.y - 26.0)
	var k := minf(1.0, minf(avail.x / tex_size.x, avail.y / tex_size.y))
	var draw_size := tex_size * k
	draw_texture_rect(tex, Rect2(Vector2((view.x - draw_size.x) * 0.5, 0.0), draw_size), false)
	var hint := I18n.t("стр. %d / %d     ← → / LB RB листать     O открыть PDF     F1 / Esc / B закрыть") % [page + 1, pages.size()]
	draw_string(font, Vector2(0, view.y - 4), hint, HORIZONTAL_ALIGNMENT_CENTER, view.x, FS_SMALL, MachineView.DIM)
