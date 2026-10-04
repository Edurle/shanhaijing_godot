class_name UiSidebar
extends UiPanel
## 右侧栏：行者名/资源条/修为/地名/技能栏（1-8 带耗与摘要）/装备五槽。
## 数据每次 refresh() 从引擎拉取后重绘。

const WIDTH := 300.0

var engine
var state


func setup(p_engine) -> void:
	engine = p_engine
	state = p_engine.state
	relayout(Vector2(1280, 768))


func relayout(view_size: Vector2) -> void:
	var height: float = view_size.y
	setup_ui(Rect2(view_size.x - WIDTH, 0, WIDTH, height))
	_panel_height = height
	queue_redraw()


var _panel_height := 768.0


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if engine == null:
		return
	draw_paper_dim()
	var x := panel_rect.position.x + 16
	var y := 34.0
	var player = state.player
	var fighter = player.fighter

	# 名字 + 修为
	draw_text_line(Vector2(x, y), player.label, INK, 22)
	draw_text_line(Vector2(x + 150, y), "修为 %d 重 · 技能点 %d" % [
		player.level.current_level, player.skill_points,
	], INK_SOFT, 15)
	y += 26
	# 气血条
	draw_text_line(Vector2(x, y), "气血 %d/%d" % [fighter.hp(), fighter.max_hp()], INK_SOFT, 14)
	draw_bar(Vector2(x, y + 6), WIDTH - 32, float(fighter.hp()) / maxf(1, fighter.max_hp()), VERMILION)
	y += 30
	# 真气/灵力
	draw_bar(Vector2(x, y), WIDTH - 32, float(fighter.mp()) / maxf(1, fighter.max_mp()), Color("2E5977"), 7)
	draw_text_line(Vector2(x, y - 3), "真气 %d/%d" % [fighter.mp(), fighter.max_mp()], INK_SOFT, 13)
	y += 18
	if fighter.max_sp() > 0:
		draw_bar(Vector2(x, y), WIDTH - 32, float(fighter.sp()) / maxf(1, fighter.max_sp()), Color("7B5EA7"), 7)
		draw_text_line(Vector2(x, y - 3), "灵力 %d/%d" % [fighter.sp(), fighter.max_sp()], INK_SOFT, 13)
		y += 18
	# 地名 + 状态标记
	var status := ""
	if fighter.has_dot():
		status += "·蚀"
	if fighter.stun_turns > 0:
		status += "·冰"
	if fighter.rooted_turns > 0:
		status += "·缠"
	if engine.smoke_turns > 0:
		status += "·烟"
	draw_text_line(Vector2(x, y), state.location_name() + ("  " + status if status != "" else ""), INK, 16)
	y += 28

	# 技能栏（主职业 8 槽）
	draw_text_line(Vector2(x, y), "— %s —" % engine.content.class_name(String(player.class_ids[0])), INK_SOFT, 14)
	y += 20
	for slot in range(1, 9):
		var skill: Dictionary = engine.content.skill_for_slot(String(player.class_ids[0]), slot)
		if skill.is_empty():
			continue
		var learned: bool = player.skill_levels.has(skill["id"])
		var level: int = player.skill_levels.get(skill["id"], 0)
		var affordable: bool = fighter.mp() >= Skills.mp_cost(player, skill) and fighter.sp() >= Skills.sp_cost(player, skill)
		var color := INK if (learned and affordable) else Color(150, 145, 135)
		var label := "%d %s" % [slot, engine.content.localize(skill["name"])]
		if level > 1:
			label += "·%d" % level
		var tail := ""
		if learned:
			var cost_text := ""
			var mp_need := Skills.mp_cost(player, skill)
			if mp_need > 0:
				cost_text += "%d气" % mp_need
			var sp_need := Skills.sp_cost(player, skill)
			if sp_need > 0:
				cost_text += "%d灵" % sp_need
			tail = cost_text
		draw_text_line(Vector2(x, y), label, color, 16)
		if tail != "":
			draw_text_line(Vector2(x + WIDTH - 16 - 14 - tail.length() * 8, y), tail, INK_SOFT, 13)
		y += 21

	# 装备五槽
	y += 10
	for slot in Equipment.SLOT_ORDER:
		var item: Dictionary = player.equipment.slots.get(slot)
		var slot_label: String = engine.content.text("slot_" + slot)
		var text := "%s %s" % [slot_label, item["label"] if item != null else "——"]
		if item != null and item.has("damage"):
			var d: Dictionary = item["damage"]
			var summary := "物%d" % int(d["physical"])
			if String(d.get("element", "")) != "":
				summary += "·" + engine.content.text("element_" + String(d["element"]))
			text += "  " + summary
		draw_text_line(Vector2(x, y), text, INK if item != null else Color(170, 165, 155), 15)
		y += 20

	# 底部操作提示
	draw_text_line(Vector2(x, _panel_height - 24),
		"移动 WASD · 技能 1-8 · 行囊 I · 参悟 K · 查看 X · 拾取 G · 踏入 E/Q", INK_SOFT, 13)


## 侧栏半透明（不遮蔽棋盘边缘太多）。
func draw_paper_dim() -> void:
	draw_rect(panel_rect, PAPER, false, 0.0)
	draw_rect(Rect2(panel_rect.position, panel_rect.size), Color(PAPER, 0.92))
	draw_rect(panel_rect, INK, false, 2.0)


## 技能行命中检测（主场景点击路由）：返回槽位 1-8，未命中 0。
func skill_row_at(pos: Vector2) -> int:
	var x := panel_rect.position.x + 16
	var y := panel_rect.position.y + 34 + 26 + 30 + 18 + 18 + 28  # 到技能标题行的累积高度
	y += 20  # 标题行
	for slot in range(1, 9):
		if Rect2(x - 8, y - 16, WIDTH - 16, 21).has_point(pos):
			return slot
		y += 21
	return 0
