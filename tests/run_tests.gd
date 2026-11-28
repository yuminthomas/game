extends Node
## 자동 테스트: godot --headless --path . res://tests/run_tests.tscn
## 데이터 검증, 공식, 무기 6군 공격, 스킬 54개 시전(Lv1·Lv5), 패링·저스트 회피, 스킬서, 키 배치를 확인한다.

var fails := 0
var passes := 0
var main: Node

func check(cond: bool, name: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("  FAIL: " + name)

func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var Data = get_tree().root.get_node("Data")
	var IM = get_tree().root.get_node("InputManager")
	var Game = get_tree().root.get_node("Game")
	print("== 데이터 검증")
	check(Data.errors.is_empty(), "데이터 오류 없음: %s" % str(Data.errors))
	check(Data.weapons.size() == 54, "무기 54종")
	check(Data.skills.size() == 54, "스킬 54개")
	print("== 공식")
	check(PlayerData.exp_to_next(1) == 40, "Lv1→2 경험치 40")
	check(absf(PlayerData.exp_to_next(10) - 2004) < 2, "Lv10→11 약 2,000 (%d)" % PlayerData.exp_to_next(10))
	check(absf(PlayerData.exp_to_next(30) - 13000) < 600, "Lv30→31 약 13,000 (%d)" % PlayerData.exp_to_next(30))
	var hp10 := 40.0 * pow(1.22, 9)
	check(absf(hp10 - 240) < 2, "몬스터 Lv10 HP 약 240 (%d)" % hp10)
	check(Data.weapon_attack_formula(1, "common", "sword") == 12, "낡은 메리디안검 공식 12")
	check(PlayerData.monster_exp(10, "normal", 20) < PlayerData.monster_exp(10, "normal", 10), "레벨 차 경험치 감소")
	var pd: PlayerData = Game.data
	check(int(pd.max_hp()) == 100 + 20 + 50, "시작 최대 HP 170 (%d)" % pd.max_hp())
	check(absf(pd.crit_chance() - 0.055) < 0.0001, "치명타 5.5%")
	print("== 아이템")
	for g in ["common", "rare", "epic", "legendary", "mythic"]:
		var w = null
		for x in Data.weapons.values():
			if x.grade == g: w = x; break
		var it := Items.make_weapon(w.id)
		check(it.options.size() == int(Data.grades[g].options), "%s 옵션 %d개" % [g, Data.grades[g].options])
	var ring := Items.make_armor("ac_wildflower_ring")
	check(ring.options.size() == 1, "일반 반지 옵션 1개 (장신구 +1)")
	check(Items.armor_defense(Items.make_armor("ar_wanderer_vest")) == 6, "갑옷 Lv1 일반 방어력 (3+0.8)×1.5≈6")
	print("== 스킬서")
	var offers := pd.skillbook_offers("old:sword")
	check(offers.size() == 2, "낡은 검술서: 낡은 등급 스킬 2개뿐이라 2장 (%d)" % offers.size())
	var offers2 := pd.skillbook_offers("trainee:dagger")
	check(offers2.size() == 3, "수련자 단검술서 3장")
	check(offers2.any(func(o): return Data.skills[o.id].tier == "trainee"), "최고 등급 최소 1장")
	print("== 키 배치")
	var m := {KEY_X: "attack", KEY_Z: "dash"}
	InputManager.assign(m, KEY_Z, "attack")
	check(m[KEY_Z] == "attack" and m[KEY_X] == "dash", "이미 배정된 키에 놓으면 서로 교체")
	check(InputManager.missing_required({KEY_X: "attack"}).size() == 2, "필수 키 누락 검출")

	print("== 게임 실행")
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(10)
	var pl: Player = Game.player
	check(pl != null, "플레이어 생성")
	Game.god_mode = true
	pd.level = 70
	var dummy: Enemy = null
	for e in Game.enemies():
		if e.kind == "dummy": dummy = e; break
	for e in Game.enemies():
		if e.kind == "test_brute": e.process_mode = Node.PROCESS_MODE_DISABLED
	var commons := {"sword": "sword_old_meridian", "greatsword": "gs_iron_slab", "dagger": "dg_hunting", "spear": "sp_farmer_fork", "bow": "bw_hunter_short", "staff": "st_apprentice"}
	for cls in commons:
		print("== 무기군: " + cls)
		pd.equipment.weapon = Items.make_weapon(commons[cls])
		pd.changed.emit("equipment")
		pl.global_position = dummy.global_position + Vector2(-20 if cls in ["sword", "greatsword", "dagger", "spear"] else -60, 0)
		pl.facing = Vector2.RIGHT; pl.aim_dir = Vector2.RIGHT
		pl.set_state(Player.S.IDLE)
		dummy.dps_log.clear()
		for i in 6:
			Input.action_press("attack"); await frames(2); Input.action_release("attack")
			await frames(14)
		await frames(30)
		check(dummy.dps_log.size() > 0, "%s 기본 콤보 적중 (%d회)" % [cls, dummy.dps_log.size()])
		# 차지
		dummy.dps_log.clear()
		pl.global_position = dummy.global_position + Vector2(-20 if cls in ["sword", "greatsword", "dagger", "spear"] else -60, 0)
		Input.action_press("attack"); await frames(50); Input.action_release("attack")
		await frames(50)
		check(dummy.dps_log.size() > 0, "%s 차지 공격 적중" % cls)
		# 대시 + 대시 공격
		pl.global_position = dummy.global_position + Vector2(-70, 0)
		pl.dash_charges = 3
		Input.action_press("move_right"); await frames(1)
		Input.action_press("dash"); await frames(2); Input.action_release("dash")
		await frames(8)
		Input.action_release("move_right")
		Input.action_press("attack"); await frames(2); Input.action_release("attack")
		await frames(40)
		check(pl.state == Player.S.IDLE or pl.state == Player.S.MOVE, "%s 대시·대시공격 후 대기 복귀 (state %d)" % [cls, pl.state])
		# 패링 키
		pl.set_state(Player.S.IDLE); pl.parry_cd = 0
		Input.action_press("parry"); await frames(2); Input.action_release("parry")
		await frames(40)
		# 스킬 전부 Lv1, Lv5
		for lv in [1, 5]:
			for s in Data.skills_of(cls) + Data.skills_of("chrono"):
				pd.skills[s.id] = lv
				pl.cooldowns.clear(); pl.skill_charges.clear()
				pd.stamina = 100
				pl.set_state(Player.S.IDLE)
				pl.global_position = dummy.global_position + Vector2(-40, 0)
				pl.facing = Vector2.RIGHT; pl.aim_dir = Vector2.RIGHT
				var err := SkillExecutor.try_start(pl, s.id, "slot_skill_1")
				check(err == "" or (s.behavior.type == "teleport_behind" and err == ""), "%s Lv%d 시전 (%s)" % [s.name, lv, err])
				if pl.recast.has(s.id): await frames(20); pl.recast[s.id].call(); pl.recast.erase(s.id)
				await frames(150 if s.behavior.type in ["charge_slam", "aimed_shot"] else 70)
				check(not pl.dead, "%s 후 생존" % s.name)
		pl.frozen_left = 0; pl.release_frozen_arrows()
		pl.echo_left = 0
		pl.buffs.clear(); pl._sync_buff_mods()
		await frames(30)

	print("== 패링·저스트 회피")
	Game.god_mode = false
	pd.equipment.weapon = Items.make_weapon("sword_old_meridian"); pd.changed.emit("equipment")
	pl.max_hp = 99999; pl.hp = 99999
	var brute: Enemy = Game.world.spawn_enemy("test_brute", pl.global_position + Vector2(30, 0), 1)
	brute.respawn = false
	var parried := [false]
	var dodged := [false]
	pl.parried.connect(func(): parried[0] = true)
	pl.just_dodged.connect(func(): dodged[0] = true)
	for i in 600:
		await get_tree().physics_frame
		if pl.state == Player.S.HIT: pl.set_state(Player.S.IDLE)
		var eta := brute.threat_eta(pl)
		if eta < 0.09 and brute.cur_attack.get("parry", false) and not parried[0] and pl.parry_cd <= 0:
			pl.start_parry()
		elif eta < 0.09 and parried[0] and not dodged[0] and pl.dash_charges >= 1:
			pl.start_dash(Vector2.LEFT)
		if parried[0] and dodged[0]: break
	check(parried[0], "패링 성공")
	check(dodged[0], "저스트 회피 발동")
	print("== 경험치")
	var lv0: int = pd.level
	pd.level = 1; pd.exp = 0
	pd.gain_exp(45)
	check(pd.level == 2 and pd.stat_points >= 5, "레벨업과 스탯 포인트")
	print("== 디버그 콘솔")
	var dc = get_tree().root.get_node("DebugConsole")
	check(dc.run("give sword_dusk_oath").begins_with("황혼"), "give 명령")
	check(dc.run("spawn test_brute 3 elite").begins_with("소환"), "spawn 명령")
	check(dc.run("chrono 160").contains("2단계"), "크로노포스 → 결정 무늬 단계")
	await frames(30)
	print("\n결과: %d 통과, %d 실패" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
