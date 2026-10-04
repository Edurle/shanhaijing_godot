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

	# ---- 角色面板（装备+行囊 2合1）：清单混排、装备格命中 ----
	var char_menu = load("res://scripts/view/ui/menu_character.gd").new()
	root.add_child.call_deferred(char_menu)
	await process_frame
	char_menu.setup_menu(engine)
	state.player.inventory.add(content.build_item("lingzhi"))
	state.player.inventory.add(content.build_item("w_kunwu"))
	state.player.inventory.add(content.build_item("mat_demon_core"))
	char_menu.open()
	failed += _check(char_menu.bag_items.size() == 3, "行囊混排 3 件（实际 %d）" % char_menu.bag_items.size())
	# 装备武器后行囊少一件、装备格非空
	state.player.inventory.add(content.build_item("w_taomu"))
	char_menu._rebuild()
	char_menu._use_bag_item(char_menu.bag_items.size() - 1)
	failed += _check(char_menu.bag_items.size() == 3, "装备后行囊归位 3 件（实际 %d）" % char_menu.bag_items.size())
	failed += _check(state.player.equipment.weapon_damage() == [3, "wood"], "桃木剑武器面 物3木")
	# 点击装备格卸下
	char_menu.equip_rects.clear()
	char_menu._rebuild()
	char_menu.queue_redraw()
	await process_frame  # 触发 _draw 填充 equip_rects
	failed += _check(char_menu.equip_rects.has("weapon"), "装备格命中区已生成")
	if char_menu.equip_rects.has("weapon"):
		char_menu.click_at(char_menu.equip_rects["weapon"].get_center())
		failed += _check(state.player.equipment.weapon_damage() == [0, ""], "点击装备格卸下武器")

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

	# ---- 底部技能栏：槽位/命中/图标占位 ----
	var skill_bar = load("res://scripts/view/ui/skill_bar.gd").new()
	root.add_child.call_deferred(skill_bar)
	await process_frame
	skill_bar.setup(engine)
	var hit_slot: int = skill_bar.skill_slot_at(skill_bar.slot_rect(3).get_center())
	failed += _check(hit_slot == 3, "技能槽命中检测（点第3槽得%d）" % hit_slot)
	failed += _check(skill_bar.skill_slot_at(Vector2(5, 5)) == 0, "槽外点击不命中")
	# 16 格平铺 + 正方形 + 主辅页映射
	var rect12: Rect2 = skill_bar.slot_rect(12)
	failed += _check(skill_bar.skill_slot_at(rect12.get_center()) == 12, "第12槽命中（辅修4）")
	failed += _check(rect12.size.x == rect12.size.y, "技能格为正方形（%s）" % rect12.size)
	failed += _check(String(state.player.skill_bar[11]) == "s_fushi_4", "默认编排：槽12=辅修4")
	# 自由重排：绑定火符到槽 3，原槽清空逻辑由编排面板负责
	state.player.skill_bar[2] = "s_fushi_1"
	failed += _check(String(state.player.skill_bar[2]) == "s_fushi_1", "自由重排槽3=火符")
	failed += _check(UiSkillBar.key_label(3) == "3" and UiSkillBar.key_label(12) == "S4", "键位标签 3/S4")

	# ---- 技能编排面板：图标命中/绑定/清除/悬浮行 ----
	var assign = load("res://scripts/view/ui/menu_assign.gd").new()
	root.add_child.call_deferred(assign)
	await process_frame
	assign.setup_menu(engine)
	assign.open()
	failed += _check(assign.learned_skills.size() >= 1, "编排清单含已学技能（%d）" % assign.learned_skills.size())
	var first_id := String(assign.learned_skills[0])
	var icon_rect: Rect2 = assign.icon_rects[first_id]
	failed += _check(assign.icon_at(icon_rect.get_center()) == first_id, "图标命中检测")
	failed += _check(assign.slot_at(assign.slot_rects[15].get_center()) == 15, "槽位格命中检测")
	assign.select(first_id)
	assign.bind_to_slot(15)
	failed += _check(String(state.player.skill_bar[14]) == first_id, "绑定到槽15")
	assign.clear_selected()
	failed += _check(String(state.player.skill_bar[14]) == "", "X 清除该技能绑定")
	# 悬浮说明行：标题/摘要/描述折行
	var tip = load("res://scripts/view/ui/ui_tooltip.gd").new()
	root.add_child.call_deferred(tip)
	await process_frame
	tip.setup(engine)
	var lines: Array = tip.build_lines(content.skill_by_id("s_leifa_1"), state.player, "S4")
	failed += _check(String(lines[0]["text"]).find("掌心雷") >= 0, "说明标题含技能名")
	failed += _check(lines.size() >= 4, "说明含摘要/五行/描述多行（%d 行）" % lines.size())
	var icon: String = skill_bar.icon_char(engine, content.skill_for_slot("leifa", 1))
	failed += _check(icon.length() == 1, "技能图标占位为单字（%s）" % icon)

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
