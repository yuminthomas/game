class_name UIRoot
extends CanvasLayer
## UI 총괄: HUD, 창들, 툴팁, 알림, 스킬서 카드, 일시정지 메뉴. 창 단축키도 여기서 처리한다.

var root: Control
var hud: HUD
var windows := {}
var tooltip: PanelContainer
var tooltip_box: VBoxContainer
var picker: SkillbookPicker
var pause_menu: PauseMenu
var notice: Label
var _notice_t := 0.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.ui = self
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	add_child(root)
	hud = HUD.new()
	hud.ui = self
	root.add_child(hud)
	_add_window(InventoryWindow.new())
	_add_window(EquipmentWindow.new())
	_add_window(StatsWindow.new())
	_add_window(SkillsWindow.new())
	_add_window(KeyConfigWindow.new())
	notice = UITheme.label("", 12, Color.WHITE)
	notice.add_theme_color_override("font_outline_color", Color.BLACK)
	notice.add_theme_constant_override("outline_size", 4)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.position = Vector2(0, 286)
	notice.size = Vector2(640, 16)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notice)
	picker = SkillbookPicker.new()
	picker.ui = self
	root.add_child(picker)
	pause_menu = PauseMenu.new()
	pause_menu.ui = self
	root.add_child(pause_menu)
	tooltip = PanelContainer.new()
	tooltip.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.05, 0.1, 0.96), UITheme.GOLD, 1, 4))
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	tooltip_box = VBoxContainer.new()
	tooltip_box.add_theme_constant_override("separation", 1)
	tooltip.add_child(tooltip_box)
	root.add_child(tooltip)
	Game.message.connect(show_notice)
	Game.data.item_logged.connect(func(t, c): hud.log_item(t, c))

func _add_window(w: GameWindow) -> void:
	w.ui = self
	windows[w.window_id] = w
	root.add_child(w)

func window(id: String) -> GameWindow:
	return windows.get(id)

func _process(delta: float) -> void:
	if _notice_t > 0:
		_notice_t -= delta
		notice.modulate.a = clampf(_notice_t, 0, 1)
	if tooltip.visible:
		var m := root.get_global_mouse_position()
		var p := m + Vector2(10, 10)
		if p.x + tooltip.size.x > 640: p.x = m.x - tooltip.size.x - 6
		if p.y + tooltip.size.y > 360: p.y = 360 - tooltip.size.y
		tooltip.position = p.round()
	if picker.visible or DebugConsole.panel.visible: return
	if InputManager.consume("menu"):
		if pause_menu.visible: pause_menu.close()
		elif not _close_top_window(): pause_menu.open()
		return
	if get_tree().paused: return
	for pair in [["win_inventory", "inventory"], ["win_equipment", "equipment"], ["win_stats", "stats"], ["win_skills", "skills"], ["win_keyconfig", "keyconfig"]]:
		if InputManager.consume(pair[0]): windows[pair[1]].toggle()
	if InputManager.consume("win_worldmap"): show_notice("월드맵은 4단계(구역·포탈)에서 추가됩니다", UITheme.TEXT_DIM)
	if InputManager.consume("win_codex"): show_notice("도감은 이후 단계에서 추가됩니다", UITheme.TEXT_DIM)
	if InputManager.consume("minimap"): hud.toggle_minimap()

func _close_top_window() -> bool:
	var top: GameWindow = null
	for c in root.get_children():
		if c is GameWindow and c.visible: top = c
	if top:
		top.close_window()
		return true
	return false

func show_tooltip(lines: Array) -> void:
	for c in tooltip_box.get_children(): c.queue_free()
	for i in lines.size():
		var ln = lines[i]
		var l = UITheme.label(ln[0], 12 if i == 0 else 10, ln[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 150
		tooltip_box.add_child(l)
	tooltip.size = Vector2.ZERO
	tooltip.visible = true
	tooltip.move_to_front()

func hide_tooltip() -> void:
	tooltip.visible = false

func show_notice(text: String, color := Color.WHITE) -> void:
	notice.text = text
	notice.add_theme_color_override("font_color", color)
	_notice_t = 3.0
	notice.modulate.a = 1.0

## 스킬서 읽기 (인벤토리에서)
func read_skillbook(key: String) -> void:
	var pd := Game.data
	var need := pd.book_tier_level(key)
	if pd.level < need:
		show_notice("레벨 %d 부터 읽을 수 있습니다" % need, UITheme.RED); return
	var offers := pd.skillbook_offers(key)
	if offers.is_empty():
		show_notice("더 배울 수 있는 스킬이 없습니다", UITheme.TEXT_DIM); return
	pd.inv_books[key] -= 1
	if pd.inv_books[key] <= 0: pd.inv_books.erase(key)
	pd.changed.emit("inventory")
	picker.open(offers)
