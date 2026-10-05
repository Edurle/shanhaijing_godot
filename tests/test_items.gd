extends SceneTree
## 阶段 4 模型层测试：行囊/材料堆叠/拾取/消耗品/装备动作/参悟门槛。


func _init() -> void:
	var failed := 0
	var content = load("res://scripts/core/content_db.gd").new()
	var errors: PackedStringArray = content.load_all("res://data/content")
	if not errors.is_empty():
		print("FAIL 内容校验失败: " + "\n".join(errors))
		quit(1)
		return

	# 小场地引擎
	var state = load("res://scripts/core/world_state.gd").new()
	state.content = content
	var map = load("res://scripts/core/game_map.gd").new(21, 21, 8)
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 2)
	state.current = map
	state.player = content.build_player(["leifa", "fushi"], 10, 10)
	map.actors.append(state.player)
	var engine = load("res://scripts/core/turn_engine.gd").new(state, content)
	state.rng.seed = 7
	var player = state.player

	# ---- 行囊与材料堆叠 ----
	var inv = player.inventory
	var core1: Dictionary = content.build_item("mat_demon_core")
	core1["stack"] = 2
	var core2: Dictionary = content.build_item("mat_demon_core")
	core2["stack"] = 3
	inv.add(core1)
	inv.add(core2)
	failed += _check(inv.count_material("mat_demon_core") == 5, "材料堆叠计数 2+3=5")
	inv.take_material("mat_demon_core", 4)
	failed += _check(inv.count_material("mat_demon_core") == 1, "支取 4 后余 1")

	# ---- 拾取 ----
	var herb: Dictionary = content.build_item("lingzhi", 10, 10)  # 脚下灵芝（玩家 10,10）
	map.items.append(herb)
	player.fighter.hurt(20)  # 制造亏损便于验证治疗
	var hp_low: int = player.fighter.hp()
	failed += _check(engine.player_pickup(), "拾取成功")
	failed += _check(inv.items.size() == 2, "行囊=魔核堆×1+灵芝（%d 件）" % inv.items.size())

	# ---- 使用消耗品 ----
	var heal_item = null
	for item in inv.items:
		if item["id"] == "lingzhi":
			heal_item = item
			break
	failed += _check(heal_item != null, "灵芝在行囊")
	var use_error: String = engine.player_use_item(heal_item)
	failed += _check(use_error.is_empty(), "服用灵芝成功（%s）" % use_error)
	failed += _check(player.fighter.hp() > hp_low, "气血回升")

	# ---- 装备/卸下 ----
	var robe: Dictionary = content.build_item("a_bihuo")
	inv.add(robe)
	var def0: int = player.fighter.defense()
	failed += _check(engine.player_equip(robe).is_empty(), "穿上蔽火袍")
	failed += _check(player.fighter.defense() == def0 + 2, "防御+2（蔽火袍）")
	failed += _check(player.fighter.resistance("fire") == 40, "火抗 40（蔽火袍）")
	var sword: Dictionary = content.build_item("w_kunwu")
	inv.add(sword)
	engine.player_equip(sword)
	failed += _check(player.equipment.weapon_damage() == [5, "metal"], "昆吾刀武器面 物5金")
	engine.player_unequip("weapon")
	failed += _check(player.equipment.weapon_damage() == [0, ""], "卸下武器归零")

	# ---- 参悟：技能点 + 材料门槛 ----
	player.skill_points = 1
	var learn_error: String = engine.learn_skill("s_leifa_1")  # 掌心雷 cost1 无前置
	failed += _check(learn_error.is_empty(), "参悟掌心雷成功（%s）" % learn_error)
	failed += _check(player.skill_levels.has("s_leifa_1"), "技能等级表登记")
	failed += _check(player.skill_points == 0, "技能点扣除")
	# 大招门槛：万雷引（cost2）需魔核×1，行囊仅 1 → 可学；再验锁定链
	player.skill_points = 2
	var learn_locked: String = engine.learn_skill("s_leifa_8")  # 万雷引 前置天雷破
	failed += _check(not learn_locked.is_empty(), "前置未满足应拒绝（%s）" % learn_locked)
	inv.add(content.build_item("mat_demon_core"))
	player.skill_levels["s_leifa_7"] = 1  # 直接补前置（天雷破）
	var learn_ult: String = engine.learn_skill("s_leifa_8")
	failed += _check(learn_ult.is_empty(), "前置齐+魔核足时大招可学（%s）" % learn_ult)
	failed += _check(inv.count_material("mat_demon_core") == 1, "魔核消耗后余 1（先前剩 1+新 1-耗 1）")

	# ---- 套装：档位累积激活与回落 ----
	var boots: Dictionary = content.build_item("b_zhurilv")
	var charm: Dictionary = content.build_item("p_denglin")
	var staff: Dictionary = content.build_item("w_kuafu_zhang")
	inv.add(boots)
	engine.player_equip(boots)
	failed += _check(player.equipment.bonus("max_hp") == 6, "单件不成套：仅自带 血+6（实际 %d）" % player.equipment.bonus("max_hp"))
	inv.add(charm)
	engine.player_equip(charm)
	failed += _check(player.equipment.bonus("max_hp") == 6 + 4 + 10, "两件成套：并入档2 血+10（实际 %d）" % player.equipment.bonus("max_hp"))
	inv.add(staff)
	engine.player_equip(staff)
	failed += _check(player.equipment.bonus("power") == 2, "三件成套：并入档3 攻+2（实际 %d）" % player.equipment.bonus("power"))
	# 消息：套装觉醒日志 + 装备名分段（套装标记）
	var set_msg := ""
	for msg in engine.messages:
		if String(msg["kind"]) == "buff" and String(msg["text"]).contains("夸父"):
			set_msg = String(msg["text"])
	failed += _check(set_msg.contains("3/3"), "三件觉醒日志含 3/3（%s）" % set_msg)
	var equip_msg: Dictionary = {}
	for msg in engine.messages:
		if msg.has("segments") and String(msg["text"]).contains("夸父杖"):
			equip_msg = msg
			break
	failed += _check(not equip_msg.is_empty(), "装备日志应含夸父杖分段消息")
	var name_marked := false
	if equip_msg.has("segments"):
		for segment in equip_msg["segments"]:
			if String(segment.get("set_id", "")) == "kuafu" and String(segment.get("rarity", "")) == "rare":
				name_marked = true
	failed += _check(name_marked, "夸父杖名称段应带 rare+kuafu 标记")
	# 卸一件：档3 回落、档2 仍生效
	engine.player_unequip("amulet")
	failed += _check(player.equipment.bonus("max_hp") == 6 + 10, "卸一件后档2 仍生效（实际 %d）" % player.equipment.bonus("max_hp"))
	failed += _check(player.equipment.bonus("power") == 0, "卸一件后档3 应回落（实际 %d）" % player.equipment.bonus("power"))

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 阶段4模型层（行囊/拾取/消耗品/装备/参悟门槛）")
		quit(0)


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
