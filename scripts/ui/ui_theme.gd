class_name UITheme
## UI 스타일 (GDD 12-1): 어둡고 반투명한 남색 패널 + 옅은 금색 테두리 + 청백색 결정 포인트.

const BG := Color(0.07, 0.08, 0.16, 0.9)
const BG2 := Color(0.11, 0.13, 0.24, 0.95)
const GOLD := Color(0.68, 0.58, 0.38)
const GOLD_DIM := Color(0.45, 0.39, 0.27)
const CRYSTAL := Color(0.75, 0.95, 1.0)
const TEXT := Color(0.92, 0.9, 0.85)
const TEXT_DIM := Color(0.62, 0.62, 0.68)
const RED := Color(0.95, 0.35, 0.35)
const GREEN := Color(0.5, 1.0, 0.55)

static var font: Font
static var font_small: Font
static var _theme: Theme

static func fonts() -> void:
	if font == null:
		font = load("res://assets/fonts/Galmuri11.ttf")
		font_small = load("res://assets/fonts/Galmuri9.ttf")

static func box(bg := BG, border := GOLD, width := 1, margin := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_content_margin_all(margin)
	s.anti_aliasing = false
	return s

static func theme() -> Theme:
	if _theme: return _theme
	fonts()
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 12
	t.set_stylebox("panel", "PanelContainer", box())
	t.set_stylebox("panel", "Panel", box())
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_stylebox("normal", "Button", box(BG2, GOLD_DIM, 1, 3))
	t.set_stylebox("hover", "Button", box(Color(0.18, 0.22, 0.38), GOLD, 1, 3))
	t.set_stylebox("pressed", "Button", box(Color(0.25, 0.3, 0.48), CRYSTAL, 1, 3))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), CRYSTAL, 1, 3))
	t.set_stylebox("disabled", "Button", box(Color(0.08, 0.08, 0.12), Color(0.25, 0.25, 0.3), 1, 3))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", CRYSTAL)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_font_size("font_size", "Button", 12)
	t.set_stylebox("tab_selected", "TabBar", box(Color(0.2, 0.24, 0.4), GOLD, 1, 3))
	t.set_stylebox("tab_unselected", "TabBar", box(BG2, GOLD_DIM, 1, 3))
	t.set_stylebox("tab_hovered", "TabBar", box(Color(0.16, 0.19, 0.33), GOLD, 1, 3))
	t.set_color("font_selected_color", "TabBar", CRYSTAL)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_font_size("font_size", "TabBar", 11)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.04, 0.05, 0.1, 0.96), GOLD))
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.04, 0.08), GOLD_DIM, 1, 3))
	t.set_stylebox("slider", "HSlider", box(Color(0.15, 0.17, 0.28), GOLD_DIM, 1, 1))
	t.set_stylebox("grabber_area", "HSlider", box(CRYSTAL.darkened(0.3), CRYSTAL, 1, 1))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(CRYSTAL, CRYSTAL, 1, 1))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_font_size("font_size", "CheckBox", 11)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t

static func label(text: String, size := 12, color := TEXT) -> Label:
	fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if size >= 11 else font_small)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, cb: Callable, size := 11) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if size < 11:
		fonts(); b.add_theme_font_override("font", font_small)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

static func bar(fill: Color, bg := Color(0, 0, 0, 0.6)) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	var f := StyleBoxFlat.new(); f.bg_color = fill
	var b := StyleBoxFlat.new(); b.bg_color = bg; b.border_color = GOLD_DIM; b.set_border_width_all(1)
	p.add_theme_stylebox_override("fill", f)
	p.add_theme_stylebox_override("background", b)
	return p
