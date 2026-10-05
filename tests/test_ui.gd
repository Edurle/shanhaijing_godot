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

	# ---- 参悟菜单（技能树）：两页各 8 节点，页眉含职业名，深度分列 + 前置连线 ----
	var learn = load("res://scripts/view/ui/menu_learn.gd").new()
	root.add_child.call_deferred(learn)  # 挂树获得 viewport（headless 回退基准尺寸）
	await process_frame
	learn.setup_menu(engine)
	learn.open()
	failed += _check(learn.nodes.size() == 8, "参悟主职业树应 8 技能（实际 %d）" % learn.nodes.size())
	failed += _check(
		String(learn.header_extra).find(content.class_display_name("leifa")) >= 0,
		"参悟页眉含职业名（%s）" % learn.header_extra
	)
	# 雷法树形：深度 0-3 共 4 列；8 技能中 5 个有前置 → 5 条连线
	failed += _check(learn.columns.size() == 4, "雷法技能树分 4 列（实际 %d）" % learn.columns.size())
	failed += _check(learn.links.size() == 5, "雷法前置连线 5 条（实际 %d）" % learn.links.size())
	learn.page = 1
	learn.cursor = 0
	learn._rebuild()
	failed += _check(learn.nodes.size() == 8, "参悟副职业树应 8 技能（实际 %d）" % learn.nodes.size())
	# 格命中（拖拽起拖/悬浮路由用）：首格中心 → 索引 0 与技能 id
	var cell0: Rect2 = learn.nodes[0]["rect"]
	var node0: int = learn.node_index_at(cell0.get_center())
	failed += _check(node0 == 0, "参悟首格命中（%d）" % node0)
	failed += _check(String(learn.nodes[0]["sid"]) == learn.node_skill_at(cell0.get_center()), "格→技能id命中")
	failed += _check(learn.cursor_skill_id() != "", "游标技能可作数字键绑定源")
	failed += _check(learn.node_skill_at(cell0.get_center()) != "", "参悟格可作拖拽源")

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

	# ---- 装备品级着色：色表完备性与优先级（套装绿 > 品级 > 默认） ----
	failed += _check(InkPalette.RARITY_COLORS.size() == 4, "非白品级应 4 色（实际 %d）" % InkPalette.RARITY_COLORS.size())
	var ganjiang: Dictionary = content.build_item("w_ganjiang")
	failed += _check(UiPanel.rarity_color(ganjiang) == InkPalette.RARITY_COLORS["legendary"], "橙装取橙")
	failed += _check(UiPanel.has_rarity_color(ganjiang), "橙装有品级色")
	var taomu: Dictionary = content.build_item("w_taomu")
	failed += _check(not UiPanel.has_rarity_color(taomu), "白装无品级色")
	failed += _check(UiPanel.rarity_color(taomu, Color.RED) == Color.RED, "白装回落调用方默认色")
	var denglin: Dictionary = content.build_item("p_denglin")
	failed += _check(UiPanel.rarity_color(denglin) == InkPalette.SET_COLOR, "套装绿优先于品级色")

	# ---- 消息日志：分段着色绘制冒烟 ----
	var log_panel = load("res://scripts/view/ui/log_panel.gd").new()
	root.add_child.call_deferred(log_panel)
	await process_frame
	log_panel.setup(engine)
	engine.log_item_message("pickup", denglin, "loot")
	log_panel.refresh()
	await process_frame  # 触发 _draw 分段绘制路径
	var pickup_msg: Dictionary = engine.messages[engine.messages.size() - 1]
	failed += _check(pickup_msg.has("segments"), "拾取装备消息应含分段")
	var pickup_text: String = String(pickup_msg["text"])
	failed += _check(pickup_text.contains("邓林佩"), "分段消息全文仍含物品名（%s）" % pickup_text)

	# ---- 装备悬浮卡：行组装 + 悬停命中 ----
	var item_tip = load("res://scripts/view/ui/ui_tooltip.gd").new()
	item_tip.setup(engine)
	var kunwu_lines: Array = item_tip.build_item_lines(content.build_item("w_kunwu"), state.player)
	failed += _check(String(kunwu_lines[0]["text"]) == "昆吾刀", "悬浮卡标题为物品名（%s）" % String(kunwu_lines[0]["text"]))
	failed += _check(kunwu_lines[0]["color"] == InkPalette.RARITY_COLORS["magic"], "标题取品级色")
	var kunwu_text := ""
	for line in kunwu_lines:
		kunwu_text += String(line["text"])
	failed += _check(kunwu_text.contains("兵") and kunwu_text.contains("灵品"), "悬浮卡含槽位与品级（%s）" % kunwu_text)
	failed += _check(kunwu_text.contains("物5") and kunwu_text.contains("金"), "悬浮卡含武器伤害面（%s）" % kunwu_text)
	# 套装件：档位清单与激活态（先穿两件再悬浮）
	state.player.equipment.equip(content.build_item("b_zhurilv"))
	state.player.equipment.equip(content.build_item("p_denglin"))
	var denglin_lines: Array = item_tip.build_item_lines(content.build_item("p_denglin"), state.player)
	var tier_total := 0
	var tier_active := false
	for line in denglin_lines:
		var line_text := String(line["text"])
		if line_text.contains("件："):
			tier_total += 1
		if line_text.contains("✓ 2件"):
			tier_active = true
	failed += _check(tier_total == 2, "夸父套装应列 2 档（实际 %d）" % tier_total)
	failed += _check(tier_active, "两件在身时档2应标记激活")
	# 悬停命中：行囊行 / 已装备槽 / 空白处（行囊面板此前已打开并绘制）
	char_menu._rebuild()
	char_menu.queue_redraw()
	await process_frame
	var bag_x: float = char_menu.panel_rect.position.x + 300
	var hover_bag: Dictionary = char_menu.hover(Vector2(bag_x + 60, char_menu.bag_first_y))
	failed += _check(not hover_bag.is_empty(), "悬停行囊行应命中物品")
	var hover_blank: Dictionary = char_menu.hover(char_menu.panel_rect.position + Vector2(150, 20))
	failed += _check(hover_blank.is_empty(), "悬停面板空白处应无命中")
	if char_menu.equip_rects.has("amulet"):
		var hover_gear: Dictionary = char_menu.hover((char_menu.equip_rects["amulet"] as Rect2).get_center())
		failed += _check(String(hover_gear.get("id", "")) == "p_denglin", "悬停佩槽应命中邓林佩（%s）" % String(hover_gear.get("id", "")))
		failed += _check(char_menu.hover_slot == "amulet", "悬停槽高亮状态应记录")

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
	# 16 格平铺 + 正方形 + 初始全空（学习后拖入才绑定）
	var rect12: Rect2 = skill_bar.slot_rect(12)
	failed += _check(skill_bar.skill_slot_at(rect12.get_center()) == 12, "第12槽命中（Shift组）")
	failed += _check(rect12.size.x == rect12.size.y, "技能格为正方形（%s）" % rect12.size)
	failed += _check(String(state.player.skill_bar[11]) == "", "初始技能栏全空（槽12未绑定，无悬浮）")
	# 自由重排：绑定火符到槽 3，原槽清空逻辑由编排面板负责
	state.player.skill_bar[2] = "s_fushi_1"
	failed += _check(String(state.player.skill_bar[2]) == "s_fushi_1", "自由重排槽3=火符")
	failed += _check(UiSkillBar.key_label(3) == "3" and UiSkillBar.key_label(12) == "S4", "键位标签 3/S4")

	# 悬浮说明行：标题/摘要/描述折行
	var tip = load("res://scripts/view/ui/ui_tooltip.gd").new()
	root.add_child.call_deferred(tip)
	await process_frame
	tip.setup(engine)
	var lines: Array = tip.build_lines(content.skill_by_id("s_leifa_1"), state.player, "S4")
	failed += _check(String(lines[0]["text"]).find("掌心雷") >= 0, "说明标题含技能名")
	failed += _check(lines.size() >= 4, "说明含摘要/五行/描述多行（%d 行）" % lines.size())
	# 未学技能：前置行（雷池需掌心雷）
	state.player.skill_levels.erase("s_leifa_1")
	state.player.skill_levels.erase("s_leifa_3")
	var locked_lines: Array = tip.build_lines(content.skill_by_id("s_leifa_3"), state.player, "")
	var has_prereq := false
	for line in locked_lines:
		if String(line["text"]).find("前置") >= 0 and String(line["text"]).find("掌心雷") >= 0:
			has_prereq = true
	failed += _check(has_prereq, "未学技能说明含前置行")
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
