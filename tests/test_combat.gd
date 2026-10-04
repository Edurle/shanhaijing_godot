extends SceneTree
## Headless 战斗契约测试：Python 版 260 测试的关键子集移植。
## 覆盖：生克数学/武器伤害面/技能独立/DOT 多槽/控制/双资源/击杀升级。


func _init() -> void:
	var failed := 0
	var content = load("res://scripts/core/content_db.gd").new()
	var errors: PackedStringArray = content.load_all("res://data/content")
	if not errors.is_empty():
		print("FAIL 内容校验失败: " + "\n".join(errors))
		quit(1)
		return
	var Cb = load("res://scripts/core/content_db.gd")
	var FighterScript = load("res://scripts/core/fighter.gd")
	var ActorScript = load("res://scripts/core/actor.gd")
	var SkillsScript = load("res://scripts/core/skills.gd")

	# ---- 裸 Fighter：生克数学 ----
	var mk_fighter = func(element: String, resist := {}):
		var holder = ActorScript.new(0, 0, "测")
		holder.element = element
		var f = FighterScript.new(10, 1, 0, 0, 0, 0, resist)
		f.owner = holder
		return f

	var f_wood = mk_fighter.call("wood")
	failed += _check(f_wood.counter_multiplier(["metal"]) == 1.3, "金克木 ×1.30")
	failed += _check(f_wood.mitigate_incoming(100, ["metal"]) == 130, "克制折算 100→130")
	var f_metal = mk_fighter.call("metal")
	failed += _check(f_metal.counter_multiplier(["wood"]) == 0.75, "金克木（被克方）×0.75")
	failed += _check(f_metal.mitigate_incoming(100, ["wood"]) == 75, "被克折算 100→75")
	failed += _check(f_wood.counter_multiplier(["water"]) == 1.0, "水不克木 → 1.0")
	failed += _check(f_wood.counter_multiplier(["wood"]) == 1.0, "同属性 → 1.0")
	failed += _check(f_wood.counter_multiplier([]) == 1.0, "无元素 → 1.0")
	var f_none = mk_fighter.call("")
	failed += _check(f_none.counter_multiplier(["metal"]) == 1.0, "无本命（玩家）不受克")
	failed += _check(f_metal.mitigate_incoming(100, ["fire", "wood"]) == 130, "多 tag 取第一个：火克金 ×1.3")
	failed += _check(f_metal.mitigate_incoming(100, ["wood", "fire"]) == 75, "多 tag 取第一个：木在先被克 ×0.75")
	var f_resist = mk_fighter.call("wood", {"metal": 50})
	failed += _check(f_resist.mitigate_incoming(100, ["metal"]) == 65, "生克×抗性乘法叠加 100×1.3×0.5=65")
	var f_cap = FighterScript.new(10, 1, 0, 0, 0, 0, {"metal": 95})
	f_cap.owner = mk_fighter.call("wood").owner
	failed += _check(f_cap.resistance("metal") == 80, "抗性封顶 80")

	# ---- 引擎级：小场地 ----
	var state = load("res://scripts/core/world_state.gd").new()
	state.content = content
	var map = load("res://scripts/core/game_map.gd").new(21, 21, 8)
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 2)  # 平原
	state.current = map
	state.player = content.build_player(["leifa", "fushi"], 10, 10)
	map.actors.append(state.player)
	var engine = load("res://scripts/core/turn_engine.gd").new(state, content)
	state.rng.seed = 42
	var player = state.player

	var put = func(mid: String, x: int, y: int):
		var monster = content.build_monster(mid, x, y)
		map.actors.append(monster)
		return monster

	# ---- 武器伤害面 ----
	var give = func(iid: String):
		var item: Dictionary = content.build_item(iid)
		var old: Dictionary = player.equipment.equip(item)
		return item

	var qingtong = give.call("w_qingtong")  # 物5·无属性
	var zhulong = put.call("zhulong", 11, 10)  # 金抗60 本命火
	zhulong.fighter.base_max_hp = 500
	zhulong.fighter.heal(500)
	player.fighter.base_power = 50
	var hp0: int = zhulong.fighter.hp()
	engine.melee_attack(player, zhulong)
	var dealt: int = hp0 - zhulong.fighter.hp()
	failed += _check(dealt >= 50 + 5 - zhulong.fighter.defense() - 1 and dealt <= 50 + 5 - zhulong.fighter.defense() + 2, "无属性武器：纯物理不吃金抗（实际 %d）" % dealt)
	map.actors.erase(zhulong)

	var kunwu = give.call("w_kunwu")  # 物5·金
	var xingxing = put.call("xingxing", 11, 10)  # 本命木 无金抗
	xingxing.fighter.base_max_hp = 500
	xingxing.fighter.heal(500)
	hp0 = xingxing.fighter.hp()
	engine.melee_attack(player, xingxing)
	dealt = hp0 - xingxing.fighter.hp()
	var expect_lo: int = maxi(1, int(round((50 + 5 - xingxing.fighter.defense() - 1) * 1.3)))
	var expect_hi: int = maxi(1, int(round((50 + 5 - xingxing.fighter.defense() + 2) * 1.3)))
	failed += _check(dealt >= expect_lo and dealt <= expect_hi, "金武器克木本命 ×1.3（实际 %d，期望 %d~%d）" % [dealt, expect_lo, expect_hi])
	map.actors.erase(xingxing)

	# ---- 技能伤害不受武器影响 ----
	var skill1: Dictionary = content.skill_for_slot("leifa", 1)  # 掌心雷
	player.skill_levels[skill1["id"]] = 1
	var bare_damage: int = SkillsScript.compute_damage(player, skill1)
	give.call("w_xuanyuan")  # 换轩辕剑（物13 金）
	failed += _check(SkillsScript.compute_damage(player, skill1) == bare_damage, "技能伤害不受武器影响")

	# ---- DOT 多槽 ----
	var dot_target = put.call("xingxing", 12, 10)
	dot_target.fighter.base_max_hp = 500
	dot_target.fighter.heal(500)
	dot_target.fighter.apply_dot("wood", 4, 5)
	dot_target.fighter.apply_dot("fire", 3, 4)
	failed += _check(dot_target.fighter.dots.size() == 2, "异元素 DOT 共存")
	dot_target.fighter.apply_dot("wood", 6, 2)
	failed += _check(int(dot_target.fighter.dots["wood"][0]) == 6, "同元素 DOT 覆盖")
	var settled: Array = dot_target.fighter.tick_dots()
	failed += _check(settled.size() == 2, "两 DOT 同回合各跳一次")
	map.actors.erase(dot_target)

	# ---- 控制：定力缩短 ----
	var fox = put.call("jiuweihu", 12, 10)  # 定力 50
	fox.fighter.apply_stun(1)
	failed += _check(fox.fighter.stun_turns == 0, "定力 50 完全抵抗 1 回合眩晕")
	fox.fighter.apply_root(2)
	failed += _check(fox.fighter.rooted_turns == 1, "定力 50 缠绕 2→1 回合")
	map.actors.erase(fox)

	# ---- 破甲/挫锐随怪回合衰减 ----
	var sunder_target = put.call("xingxing", 12, 10)
	var def0: int = sunder_target.fighter.defense()
	sunder_target.fighter.apply_buff("defense", -3, 2)
	failed += _check(sunder_target.fighter.defense() == def0 - 3, "破甲生效 防-3")
	engine._settle_actor_turn(sunder_target)
	engine._settle_actor_turn(sunder_target)
	failed += _check(sunder_target.fighter.defense() == def0, "破甲两回合后到期恢复")
	map.actors.erase(sunder_target)

	# ---- 击退：同伴挡路 ----
	var m1 = put.call("xingxing", 13, 10)
	put.call("xingxing", 14, 10)
	failed += _check(engine.push_actor(m1, 1, 0, 3) == 0, "前方被同伴占据推不动")
	map.actors.erase(m1)

	# ---- 双资源：技能扣气+扣灵 ----
	player.fighter.base_max_mp = 50
	player.fighter.restore_mp(50)
	player.fighter.base_max_sp = 20
	player.fighter.restore_sp(20)
	var buff_skill: Dictionary = content.skill_for_slot("leifa", 4)  # 引雷符 mp5
	buff_skill["sp"] = 5
	var mp0: int = player.fighter.mp()
	var sp0: int = player.fighter.sp()
	var cast_error: String = SkillsScript.cast(engine, player, buff_skill)
	failed += _check(cast_error.is_empty(), "引雷符+灵力耗施放成功（%s）" % cast_error)
	failed += _check(player.fighter.mp() == mp0 - 5, "扣真气 5")
	failed += _check(player.fighter.sp() == sp0 - 5, "扣灵力 5")
	buff_skill["sp"] = 99
	var mp_guard: int = player.fighter.mp()
	var sp_guard: int = player.fighter.sp()
	failed += _check(not SkillsScript.cast(engine, player, buff_skill).is_empty(), "灵力不足拒绝施放")
	failed += _check(player.fighter.mp() == mp_guard and player.fighter.sp() == sp_guard, "失败不扣资源")

	# ---- 击杀：经验与移除 ----
	var weak = put.call("xingxing", 10, 9)
	weak.fighter.base_max_hp = 1
	weak.fighter.heal(1)
	player.fighter.base_power = 99
	engine.melee_attack(player, weak)
	failed += _check(not weak.is_alive(), "弱怪被击杀")
	failed += _check(not map.actors.has(weak), "尸体移出 actors")
	var level0: int = player.level.current_level
	player.level.add_xp(player.level.experience_to_next() + 1, true)
	failed += _check(player.level.current_level == level0 + 1, "经验升级")
	failed += _check(player.fighter.max_hp() > 1 + 26 + 8 - 8, "升级气血上限成长")

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 战斗契约子集（生克/武器面/技能独立/DOT/控制/双资源/击杀升级）")
		quit(0)


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
