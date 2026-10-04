extends SceneTree
## UI 逻辑冒烟：headless 跑菜单重建/侧栏刷新/瞄准面板路径，
## 捕获"调用了不存在的方法"类运行时错误（编译检查对无类型参数无效）。


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
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 2)
	state.current = map
	state.player = content.build_player(["leifa", "fushi"], 10, 10)
	map.actors.append(state.player)
	var engine = load("res://scripts/core/turn_engine.gd").new(state, content)
	state.rng.seed = 5

	# ---- 参悟菜单：两页各 8 行，页眉含职业名 ----
	var learn = load("res://scripts/view/ui/menu_learn.gd").new()
	root.add_child.call_deferred(learn)  # 挂树获得 viewport（headless 回退基准尺寸）
	await process_frame
	learn.setup_menu(engine)
	learn.open()
	failed += _check(learn.rows.size() == 8, "参悟主职业页应 8 技能（实际 %d）" % learn.rows.size())
	failed += _check(
		String(learn.header_extra).find(content.class_display_name("leifa")) >= 0,
		"参悟页眉含职业名（%s）" % learn.header_extra
	)
	learn.page = 1
	learn.cursor = 0
	learn._rebuild()
	failed += _check(learn.rows.size() == 8, "参悟副职业页应 8 技能（实际 %d）" % learn.rows.size())

	# ---- 行囊菜单：三页计数与模型一致 ----
	var inv_menu = load("res://scripts/view/ui/menu_inventory.gd").new()
	root.add_child.call_deferred(inv_menu)
	await process_frame
	inv_menu.setup_menu(engine)
	state.player.inventory.add(content.build_item("lingzhi"))
	state.player.inventory.add(content.build_item("w_kunwu"))
	state.player.inventory.add(content.build_item("mat_demon_core"))
	inv_menu.open()
	failed += _check(inv_menu.rows.size() == 1, "行囊消耗品页 1 件（实际 %d）" % inv_menu.rows.size())
	inv_menu.page = 1
	inv_menu._rebuild()
	failed += _check(inv_menu.rows.size() == 1, "行囊装备页 1 件（实际 %d）" % inv_menu.rows.size())
	inv_menu.page = 2
	inv_menu._rebuild()
	failed += _check(inv_menu.rows.size() == 1, "行囊材料页 1 件（实际 %d）" % inv_menu.rows.size())

	# ---- 查看菜单：有可见敌时打开非空 ----
	var monster = content.build_monster("zhulong", 11, 10)
	map.actors.append(monster)
	map.compute_fov(10, 10)
	var examine = load("res://scripts/view/ui/menu_examine.gd").new()
	root.add_child.call_deferred(examine)
	await process_frame
	examine.setup_menu(engine)
	examine.open()
	failed += _check(examine.visible and examine.targets.size() == 1, "查看菜单应列出可见敌")

	# ---- 瞄准面板：显示目标不崩 ----
	var target_info = load("res://scripts/view/ui/target_info.gd").new()
	root.add_child.call_deferred(target_info)
	await process_frame
	target_info.setup(engine)
	var skill: Dictionary = content.skill_for_slot("leifa", 1)
	state.player.skill_levels[skill["id"]] = 1
	target_info.show_target(skill, monster)
	failed += _check(target_info.visible, "瞄准面板显示目标")

	# ---- 侧栏：刷新不崩（_draw 逻辑靠渲染帧，此处覆盖数据准备路径） ----
	var sidebar = load("res://scripts/view/ui/sidebar.gd").new()
	root.add_child.call_deferred(sidebar)
	await process_frame
	sidebar.setup(engine)
	engine.active_page = 1
	sidebar.refresh()
	failed += _check(true, "")  # 到此无运行时错误即通过

	# ---- 上下文提示条：情境切换 ----
	var hint_bar = load("res://scripts/view/ui/hint_bar.gd").new()
	root.add_child.call_deferred(hint_bar)
	await process_frame
	hint_bar.setup(engine)
	# 贴身可见敌（前段摆放的烛龙在 11,10）→ 近战提示
	var hint_melee: String = hint_bar.current_hint()
	failed += _check(hint_melee.find("攻击") >= 0, "贴身敌提示攻击（%s）" % hint_melee)
	map.actors.erase(monster)
	monster.x = 19
	monster.y = 19
	var hint_default: String = hint_bar.current_hint()
	failed += _check(hint_default.find("H") >= 0, "默认提示含 H 帮助（%s）" % hint_default)
	# 脚下物品 → 拾取提示
	var herb: Dictionary = content.build_item("lingzhi", 10, 10)
	map.items.append(herb)
	var hint_item: String = hint_bar.current_hint()
	failed += _check(hint_item.find("G") >= 0 and hint_item.find("灵芝") >= 0, "站上物品提示拾取（%s）" % hint_item)
	map.items.erase(herb)
	# 低气血 + 疗伤丹 → 服丹提示
	state.player.inventory.add(content.build_item("lingzhi"))
	state.player.fighter.hurt(state.player.fighter.hp() - 1)
	var hint_heal: String = hint_bar.current_hint()
	failed += _check(hint_heal.find("I") >= 0, "低血提示服丹（%s）" % hint_heal)
	# 帮助浮层：开关与行数
	var help = load("res://scripts/view/ui/help_overlay.gd").new()
	root.add_child.call_deferred(help)
	await process_frame
	help.setup_panel(engine)
	help.open()
	failed += _check(help.visible, "帮助浮层可打开")
	help.click_at(Vector2(50, 50))
	failed += _check(not help.visible, "帮助浮层点击关闭")

	# ---- 技能摘要：主副职业首技能均非空 ----
	var s1: String = Skills.summary(engine, state.player, content.skill_for_slot("leifa", 1))
	var s2: String = Skills.summary(engine, state.player, content.skill_for_slot("fushi", 1))
	failed += _check(s1 != "" and s2 != "", "双职业技能摘要非空（%s / %s）" % [s1, s2])

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS UI 逻辑冒烟（参悟/行囊/查看/瞄准/侧栏/摘要）")
		quit(0)


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
