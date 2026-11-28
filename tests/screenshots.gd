extends Node
## 화면 캡처 도구: xvfb-run godot --path . res://tests/screenshots.tscn -- <출력폴더>

var out := "user://shots"
var main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("saved ", name)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func tap(action: String, hold := 2) -> void:
	Input.action_press(action); await frames(hold); Input.action_release(action)

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(30)
	var pd: PlayerData = Game.data
	var pl: Player = Game.player
	await shot("01_start")
	DebugConsole.run("learn sword 1")
	DebugConsole.run("learn chrono 1")
	DebugConsole.run("give ar_patrol_helm")
	DebugConsole.run("give ar_patrol_mail")
	DebugConsole.run("give sword_aurelian_royal")
	DebugConsole.run("give gs_doomsday_hand")
	DebugConsole.run("give bw_meteor_shower")
	DebugConsole.run("book old sword 2")
	DebugConsole.run("give potion")
	DebugConsole.run("give herb_bundle 5")
	DebugConsole.run("give slime_goo 12")
	pd.level = 20; pd.stat_points = 95; pd.changed.emit("stats")
	# 허수아비 쪽으로 걸어가 콤보
	Input.action_press("move_right"); Input.action_press("move_up")
	await frames(40)
	Input.action_release("move_up"); await frames(20); Input.action_release("move_right")
	pl.global_position = Game.world.entities.get_children().filter(func(n): return n is Enemy and n.kind == "dummy")[0].global_position + Vector2(-18, 2)
	pl.facing = Vector2.RIGHT
	for i in 3:
		await tap("attack"); await frames(6)
	await shot("02_combo")
	await frames(20)
	SkillExecutor.try_start(pl, "sw_whirl", "slot_skill_1")
	await frames(14)
	await shot("03_skill_whirl")
	await frames(60)
	# 테스트 몬스터와 싸우기
	pl.global_position = Vector2(34 * 16, 20 * 16)
	await frames(50)
	await shot("04_monster_telegraph")
	for i in 30:
		await frames(4)
		var e = Game.enemies().filter(func(x): return x.kind == "test_brute")[0]
		if e.ai == Enemy.A.TELEGRAPH: break
	await frames(8)
	await shot("05_fight")
	Game.ui.window("inventory").open_window()
	Game.ui.window("equipment").open_window()
	await frames(20)
	await shot("06_inventory_equipment")
	pd.equip_from_inventory(0)
	pd.equip_from_inventory(1)
	DebugConsole.run("chrono 320")
	await frames(10)
	Game.ui.window("equipment").refresh()
	await frames(10)
	await shot("07_equipped_crystal")
	Game.ui.window("inventory").close_window(); Game.ui.window("equipment").close_window()
	Game.ui.window("stats").open_window()
	await frames(20)
	await shot("08_stats")
	Game.ui.window("stats").close_window()
	Game.ui.window("skills").open_window()
	await frames(20)
	await shot("09_skills")
	Game.ui.window("skills").close_window()
	Game.ui.window("keyconfig").open_window()
	await frames(20)
	await shot("10_keyconfig")
	Game.ui.window("keyconfig").close_window()
	await frames(10)
	Game.ui.read_skillbook("old:sword")
	await frames(40)
	await shot("11_skillbook_cards")
	Game.ui.picker.choose(0)
	await frames(40)
	Game.ui.pause_menu.open()
	await frames(10)
	await shot("12_pause")
	Game.ui.pause_menu.close()
	DebugConsole.toggle()
	DebugConsole.run("help")
	DebugConsole.out(DebugConsole.run("help"))
	await frames(10)
	await shot("13_console")
	get_tree().quit()
