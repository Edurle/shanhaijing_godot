extends SceneTree
## 机制对齐测试：DOT 击杀经验语义 / 怪物掉落 / 副职业技能页 / 效果摘要。


func _init() -> void:
	var failed := 0
	var content = load("res://scripts/core/content_db.gd").new()
	var errors: PackedStringArray = content.load_all("res://data/content")
	if not errors.is_empty():
		print("FAIL 内容校验失败: " + "\n".join(errors))
		quit(1)
		return

	var state = load("res://scripts/core/world_state.gd").new()
	state.content = content
	var map = load("res://scripts/core/game_map.gd").new(21, 21, 8)
	map.floor_number = 6
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 2)
	state.current = map
	state.player = content.build_player(["leifa", "fushi"], 10, 10)
	map.actors.append(state.player)
	var engine = load("res://scripts/core/turn_engine.gd").new(state, content)
	state.rng.seed = 4242
	var player = state.player

	var put = func(mid: String, x: int, y: int):
		var monster = content.build_monster(mid, x, y)
		map.actors.append(monster)
		return monster

	# ---- 1. DOT 击杀也归玩家经验（Python 语义：die() 无条件 add_xp） ----
	var weak = put.call("xingxing", 12, 10)
	weak.fighter.base_max_hp = 5
	weak.fighter.heal(5)
	var xp0: int = player.level.current_xp
	weak.fighter.apply_dot("wood", 99, 2)
	for _i in range(3):
		if weak.is_alive():
			engine._settle_actor_turn(weak)
	failed += _check(not weak.is_alive(), "弱怪被蛊毒致死")
	failed += _check(player.level.current_xp > xp0, "DOT 击杀也获得经验（%d → %d）" % [xp0, player.level.current_xp])

	# ---- 2. 掉落：多杀必出物（装备 22% + tags 炼材） ----
	var items0: int = map.items.size()
	for i in range(40):
		var victim = put.call("xingxing", 12 + i % 3, 10 + i % 2)
		engine._apply_damage(player, victim, 999)
	failed += _check(map.items.size() > items0, "40 次击杀应产生地面掉落（+%d 件）" % (map.items.size() - items0))

	# ---- 3. BOSS 必掉魔核 ----
	var boss = put.call("boss_mingshe", 13, 12)
	var cores0 := _count_items(map, "mat_demon_core")
	engine._apply_damage(player, boss, 9999)
	failed += _check(_count_items(map, "mat_demon_core") > cores0, "BOSS 击杀必掉魔核")

	# ---- 4. 掉落表内容级校验 ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var dragon_drop := ""
	for i in range(50):  # chance 0.9：50 次内必命中
		dragon_drop = content.roll_material_drop(["dragon"], rng)
		if dragon_drop != "":
			break
	failed += _check(dragon_drop == "mat_dragon_scale", "dragon tag 掉龙鳞（实际 %s）" % dragon_drop)
	var equip20: String = content.random_equipment_id(20, rng)
	failed += _check(equip20 != "" and int(content.items[equip20].get("tier", 1)) <= 7, "难度 20 掉落 tier≤7（%s）" % equip20)
	var equip0: String = content.random_equipment_id(0, rng)
	failed += _check(equip0 != "" and int(content.items[equip0].get("tier", 1)) <= 2, "难度 0 掉落 tier≤2（%s）" % equip0)

	# ---- 5. 技能栏自由编排施法 ----
	player.skill_points = 1
	var learn_error: String = engine.learn_skill("s_fushi_1")  # 火符（副职业 slot1）
	failed += _check(learn_error.is_empty(), "参悟副职业技能（%s）" % learn_error)
	failed += _check(String(player.skill_bar[0]) == "", "参悟后不自动入槽")
	var reject_error: String = engine.bind_skill(1, "s_fushi_2")  # 未参悟技能
	failed += _check(not reject_error.is_empty(), "未参悟技能拒绝绑定（%s）" % reject_error)
	failed += _check(String(player.skill_bar[0]) == "", "拒绝后槽保持为空")
	var bind_error: String = engine.bind_skill(1, "s_fushi_1")  # 自由编排：槽1 绑火符
	failed += _check(bind_error.is_empty() and String(player.skill_bar[0]) == "s_fushi_1", "已参悟技能可绑定（%s）" % bind_error)
	var mp0: int = player.fighter.mp()
	player.fighter.base_max_mp = 50
	player.fighter.restore_mp(50)
	var fox = put.call("jiuweihu", 11, 10)  # 本命火
	fox.fighter.base_max_hp = 300
	fox.fighter.heal(300)
	var hp0: int = fox.fighter.hp()
	var cast_error: String = engine.execute_bound_skill(1, fox)
	failed += _check(cast_error.is_empty(), "绑定施放火符（%s）" % cast_error)
	failed += _check(fox.fighter.hp() < hp0, "火符造成伤害（%d → %d）" % [hp0, fox.fighter.hp()])
	failed += _check(player.fighter.mp() < player.fighter.max_mp(), "扣真气")

	# ---- 6. 技能效果摘要非空 ----
	var skill1: Dictionary = content.skill_for_slot("leifa", 1)
	var summary: String = Skills.summary(engine, player, skill1)
	failed += _check(summary != "" and summary.find("伤") >= 0, "掌心雷摘要含伤害（%s）" % summary)
	var dot_skill: Dictionary = content.skill_by_id("s_wuzhu_2")  # 蚀心蛊
	player.class_ids = ["wuzhu", "jianke"]
	player.skill_levels[dot_skill["id"]] = 1
	var dot_summary: String = Skills.summary(engine, player, dot_skill)
	failed += _check(dot_summary.find("蛊毒") >= 0, "元素 DOT 摘要含状态名（%s）" % dot_summary)

	# ---- 状态抗性两段式+边际递减：点数经护甲式折算（50点→33%），先掷免疫再折减效果 ----
	var roll := RandomNumberGenerator.new()
	roll.seed = 20261004
	var resist_case = load("res://scripts/core/fighter.gd").new(20, 5, 0)
	resist_case.base_resistances = {"stun": 0, "root": 50, "sunder": 40, "daunt": 60, "knockback": 50}
	resist_case.apply_stun(3, roll)
	failed += _check(resist_case.stun_turns == 3, "定力0：必不免疫且不折减（实际 %d）" % resist_case.stun_turns)
	var legacy = load("res://scripts/core/fighter.gd").new(20, 5, 0)
	failed += _check(legacy.apply_root(4) and legacy.rooted_turns == 4 and legacy.reduce_push(3) == 3,
		"无抗性缺省掷骰：旧调用路径效果不变")
	var landed := 0
	var resisted := 0
	var bad_outcome := 0
	for _i in range(80):
		resist_case.rooted_turns = 0
		if resist_case.apply_root(4, roll):
			landed += 1
			bad_outcome += 0 if resist_case.rooted_turns == 2 else 1
		else:
			resisted += 1
			bad_outcome += 0 if resist_case.rooted_turns == 0 else 1
	failed += _check(landed > 10 and resisted > 10, "身法50：免疫与落地两类均出现（%d/%d）" % [landed, resisted])
	failed += _check(bad_outcome == 0, "身法50：落地必缩为2回合、抵御必为0")
	var daunt_outcomes := {}
	for _i in range(60):
		daunt_outcomes[resist_case.apply_daunt(3, 3, roll)] = true
	failed += _check(daunt_outcomes.has(0) and daunt_outcomes.has(2),
		"心志60：挫锐3只出 0（免疫）或 2（折算37.5%）（%s）" % str(daunt_outcomes.keys()))
	var push_outcomes := {}
	for _i in range(60):
		push_outcomes[resist_case.reduce_push(3, roll)] = true
	failed += _check(push_outcomes.has(0) and push_outcomes.has(2),
		"沉劲50：击退3只出 0（免疫）或 2（折减）（%s）" % str(push_outcomes.keys()))

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 机制对齐（DOT经验/掉落/BOSS魔核/掉落表/副职业页/摘要）")
		quit(0)


func _count_items(map, item_id: String) -> int:
	var n := 0
	for item in map.items:
		if item["id"] == item_id:
			n += 1
	return n


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
