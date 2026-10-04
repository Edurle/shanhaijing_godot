extends SceneTree
## Headless 测试：godot --headless -s tests/test_monster_skills.gd --path <工程>
## 覆盖：怪物技能装配（mp/绑定）→ AI 施法（伤害/扣气/写冷却）→ 冷却期回落移动 →
## 耗尽回落 → heal 门控 → cast 冷却写入与回合递减。


func _init() -> void:
	var failed := 0
	var content = load("res://scripts/core/content_db.gd").new()
	var errors: PackedStringArray = content.load_all("res://data/content")
	if not errors.is_empty():
		print("FAIL 内容校验失败: " + "\n".join(errors))
		quit(1)
		return

	# ---- 1. 装配：蛊雕带 mp 与绑定，狌狌同理 ----
	var gudiao = content.build_monster("gudiao", 10, 10)
	failed += _check(gudiao.fighter.max_mp() == 8, "蛊雕真气池应为 8（实际 %d）" % gudiao.fighter.max_mp())
	failed += _check(gudiao.skill_ids == PackedStringArray(["m_leiyin_zhua"]), "蛊雕应绑定雷音爪")
	var plain = content.build_monster("jiuweihu", 10, 10)
	failed += _check(plain.fighter.max_mp() == 0 and plain.skill_ids.is_empty(), "未配置怪应为 0 气 0 技能")

	# ---- 2. 场地：怪距玩家 4 格，玩家 FOV 覆盖 ----
	var state = load("res://scripts/core/world_state.gd").new()
	state.content = content
	var map = load("res://scripts/core/game_map.gd").new(21, 21, 8)
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 2)
	state.current = map
	state.player = content.build_player(["leifa", "jianke"], 10, 10)
	map.actors.append(state.player)
	var engine = load("res://scripts/core/turn_engine.gd").new(state, content)
	state.rng.seed = 42
	engine.update_fov()

	var caster = content.build_monster("gudiao", 14, 10)
	map.actors.append(caster)
	var player = state.player
	player.fighter.base_max_hp = 500
	player.fighter.heal(500)
	var hp_before: int = player.fighter.hp()
	var mp_before: int = caster.fighter.mp()

	# ---- 3. AI 施法：伤害落地 + 扣气 + 冷却入账 + 施法日志 ----
	caster.ai.perform(engine)
	failed += _check(player.fighter.hp() < hp_before, "雷音爪应命中玩家（%d → %d）" % [hp_before, player.fighter.hp()])
	failed += _check(caster.fighter.mp() == mp_before - 4, "施法应扣 4 气（实际 %d）" % caster.fighter.mp())
	failed += _check(int(caster.skill_cooldowns.get("m_leiyin_zhua", 0)) == 3, "冷却应入账 3 回合")
	failed += _check(caster.fighter.hp() > 0 and player.fighter.hp() > 0, "双方存活")

	# ---- 4. 冷却期：不再施法（伤害不再增加，转为移动） ----
	var hp_after_cast: int = player.fighter.hp()
	var pos_before := Vector2i(caster.x, caster.y)
	caster.ai.perform(engine)
	failed += _check(player.fighter.hp() == hp_after_cast, "冷却期不应再施法掉血")
	failed += _check(Vector2i(caster.x, caster.y) != pos_before, "冷却期应转为移动（%s → %s）" % [pos_before, Vector2i(caster.x, caster.y)])
	failed += _check(int(caster.skill_cooldowns.get("m_leiyin_zhua", 0)) == 3, "AI 直调不递减冷却（结算才递减）")

	# ---- 5. 回合结算递减冷却 ----
	engine._settle_actor_turn(caster)
	failed += _check(int(caster.skill_cooldowns.get("m_leiyin_zhua", 0)) <= 2, "回合结算应递减冷却（实际 %d）" % int(caster.skill_cooldowns.get("m_leiyin_zhua", 0)))

	# ---- 6. 真气耗尽：不施法（回落移动），mp 不为负 ----
	map.actors.erase(caster)
	var drained = content.build_monster("gudiao", 14, 10)
	drained.fighter.spend_mp(drained.fighter.mp())
	map.actors.append(drained)
	var hp_before_drain: int = player.fighter.hp()
	drained.ai.perform(engine)
	failed += _check(player.fighter.hp() == hp_before_drain, "真气耗尽不应施法")
	failed += _check(drained.skill_cooldowns.is_empty(), "未施法则无冷却账目")

	# ---- 7. heal 门控：满血不放、半血放 ----
	var ai_probe = load("res://scripts/core/ai.gd").new(6)
	var heal_skill := {
		"id": "m_test_heal", "name": {"zh_CN": "test", "en_US": ""},
		"effect": {"type": "heal_self", "amount": 5, "scale": 0},
	}
	var heal_owner = content.build_monster("gudiao", 9, 9)
	ai_probe.owner = heal_owner
	var dummy_target = state.player
	failed += _check(not ai_probe._wants_cast(heal_skill, dummy_target), "满血不应放自愈")
	heal_owner.fighter.hurt(heal_owner.fighter.hp() - 2)
	failed += _check(ai_probe._wants_cast(heal_skill, dummy_target), "半血应放自愈")

	# ---- 8. cast 冷却写入（无冷却字段的职业技能不写账） ----
	var player_skill: Dictionary = content.skill_by_id("s_leifa_1")
	failed += _check(not player_skill.has("cooldown"), "职业技能不带冷却字段")
	var cooldown_before: int = player.skill_cooldowns.size()
	var cast_error: String = load("res://scripts/core/skills.gd").cast(engine, player, player_skill, drained)
	failed += _check(cast_error == "", "玩家施法应成功（错误串：%s）" % cast_error)
	failed += _check(player.skill_cooldowns.size() == cooldown_before, "无冷却字段的技能不写冷却账")

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 怪物技能系统全部测试")
		quit(0)


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
