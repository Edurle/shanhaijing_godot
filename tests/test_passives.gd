extends SceneTree
## Headless 机制测试：godot --headless -s tests/test_passives.gd --path <工程>
## 覆盖：氏族/职业双被动（收集、常驻并入、普攻吸血、击杀增益）+ 冲锋斩 + 被动摘要。


func _init() -> void:
	var failed := 0
	var content = load("res://scripts/core/content_db.gd").new()
	var errors: PackedStringArray = content.load_all("res://data/content")
	if not errors.is_empty():
		print("FAIL 内容校验失败: " + "\n".join(errors))
		quit(1)
		return

	# ---- 1. build_player：自选氏族 + 职业，双被动收集（职业被动在前、氏族被动在后） ----
	var jianke = content.build_player("jianke", 10, 10, "chiyou")
	failed += _check(jianke.clan_id == "chiyou", "剑士自择蚩尤氏")
	failed += _check(jianke.passives.size() == 2, "双被动收集（实际 %d）" % jianke.passives.size())
	failed += _check(String(jianke.passives[0]["effect"]["type"]) == "melee_lifesteal", "职业被动在前（剑锋饮血）")
	failed += _check(String(jianke.passives[1]["effect"]["type"]) == "kill_rally", "氏族被动在后（兵主血勇）")
	failed += _check(jianke.fighter.max_hp() == 36, "剑士无常驻加成：气血 36（实际 %d）" % jianke.fighter.max_hp())
	# 自由组合：任意氏族 × 任意职业（巫祝 + 蚩尤氏 = 医系职业吃击杀增益）
	var cross = content.build_player("wuzhu", 10, 10, "chiyou")
	failed += _check(cross.passives.size() == 2, "跨组合也可集齐双被动（巫祝×蚩尤氏，实际 %d）" % cross.passives.size())
	failed += _check(String(cross.passives[1]["effect"]["type"]) == "kill_rally", "巫祝亦可承兵主血勇")
	failed += _check(content.build_player("leifa", 10, 10).passives.size() == 1, "不择氏族仅职业被动（兼容旧调用）")

	# ---- 2. stat_aura 常驻并入基础值 + 开局满状态 ----
	var leifa = content.build_player("leifa", 10, 10, "fuxi")
	failed += _check(leifa.fighter.max_mp() == 14 + 3 + 3, "雷法×伏羲 真气 14+职3+族3=20（实际 %d）" % leifa.fighter.max_mp())
	failed += _check(leifa.fighter.mp() == leifa.fighter.max_mp(), "开局满状态")
	var wuzhu = content.build_player("wuzhu", 10, 10, "nuwa")
	failed += _check(wuzhu.fighter.max_hp() == 30 + 4 + 3, "巫祝×女娲 气血 30+族4+职3=37（实际 %d）" % wuzhu.fighter.max_hp())
	failed += _check(wuzhu.fighter.resistance("wood") == 8, "女娲氏木抗+8（实际 %d）" % wuzhu.fighter.resistance("wood"))
	var yishe = content.build_player("yishe", 10, 10, "yi")
	failed += _check(yishe.fighter.power() == 6 + 1 + 1, "羿射×羿氏 攻 6+族1+职1=8（实际 %d）" % yishe.fighter.power())

	# ---- 3. 被动数值摘要（选职界面/角色面板用） ----
	failed += _check(
		Passives.summary(content, leifa.passives[0]) == content.text("bon_max_mp").format({"v": 3}),
		"stat_aura 摘要复用 bon_* 文案（%s）" % Passives.summary(content, leifa.passives[0])
	)
	failed += _check(
		Passives.summary(content, jianke.passives[0]).contains("2"),
		"吸血摘要应含回血量（%s）" % Passives.summary(content, jianke.passives[0])
	)

	# ---- 战斗侧装配 ----
	var state = load("res://scripts/core/world_state.gd").new()
	state.content = content
	var map = load("res://scripts/core/game_map.gd").new(21, 21, 8)
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 2)
	state.current = map
	state.player = jianke
	map.actors.append(jianke)
	var engine = load("res://scripts/core/turn_engine.gd").new(state, content)
	state.rng.seed = 4242

	# ---- 4. 剑锋饮血：普攻命中回血（怪物无被动空转） ----
	jianke.fighter.hurt(8)  # 36 → 28
	var dummy = content.build_monster("xingxing", 10, 12)  # 南侧木桩（勿占东向冲锋走廊）
	dummy.fighter.base_max_hp = 80
	dummy.fighter.heal(80)
	map.actors.append(dummy)
	engine.melee_attack(jianke, dummy)
	failed += _check(jianke.fighter.hp() == 30, "普攻吸血 +2（28 → 30，实际 %d）" % jianke.fighter.hp())

	# ---- 5. 兵主血勇：玩家直接击杀后 攻+2×3 回合，出战斗日志 ----
	var weak = content.build_monster("xingxing", 10, 14)
	map.actors.append(weak)
	engine._apply_damage(jianke, weak, 9999)
	failed += _check(not weak.is_alive(), "弱怪被击杀")
	failed += _check(jianke.fighter.buff_amount("power") == 2, "血勇：攻+2（实际 %d）" % jianke.fighter.buff_amount("power"))
	var rally_turns: int = jianke.fighter.buffs.get("power", [0, 0])[1]
	failed += _check(rally_turns == 3, "血勇持续 3 回合（实际 %d）" % rally_turns)
	var rally_log_hit := false
	for msg in engine.messages:
		if String(msg.get("text", "")).contains("兵主血勇"):
			rally_log_hit = true
	failed += _check(rally_log_hit, "血勇发动应有战斗日志")

	# ---- 6. 冲锋斩：3 格外冲至敌前一格出剑，耗气 8 ----
	var far = content.build_monster("xingxing", 13, 10)
	far.fighter.base_max_hp = 80
	far.fighter.heal(80)
	map.actors.append(far)
	jianke.fighter.restore_mp(99)
	var hp_far: int = far.fighter.hp()
	var dash_error: String = Skills.cast(engine, jianke, content.skill_by_id("s_jianke_6"), Vector2i(1, 0))
	failed += _check(dash_error.is_empty(), "冲锋斩应成功（%s）" % dash_error)
	failed += _check(Vector2i(jianke.x, jianke.y) == Vector2i(12, 10),
		"冲锋落位于敌前一格（实际 %s）" % str(Vector2i(jianke.x, jianke.y)))
	failed += _check(far.fighter.hp() < hp_far, "冲锋斩应造成伤害")
	failed += _check(jianke.fighter.mp() == 0, "冲锋斩耗气 8（实际余 %d）" % jianke.fighter.mp())

	# ---- 7. 冲锋斩边界：起步即堵报错；一路无敌则纯位移 ----
	var dash_skill: Dictionary = content.skill_by_id("s_jianke_6")
	map.set_tile(12, 11, GameMap.T_MOUNTAIN)  # 玩家（12,10）南侧堵死
	jianke.fighter.restore_mp(99)
	var blocked: String = Skills.cast(engine, jianke, dash_skill, Vector2i(0, 1))
	failed += _check(blocked == content.text("dash_blocked"), "起步即堵应报 dash_blocked（%s）" % blocked)
	map.set_tile(12, 11, 2)
	var move_only: String = Skills.cast(engine, jianke, dash_skill, Vector2i(0, -1))
	failed += _check(move_only.is_empty(), "纯位移冲锋应成功（%s）" % move_only)
	failed += _check(Vector2i(jianke.x, jianke.y) == Vector2i(12, 7),
		"纯位移 3 格落位（实际 %s）" % str(Vector2i(jianke.x, jianke.y)))

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 被动机制与冲锋斩全部测试")
		quit(0)


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
