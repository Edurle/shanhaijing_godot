class_name UiSidebar
extends UiPanel
## 右侧栏（精简版）：地名与状态标记 + 技能栏（当前职业页）+ 装备五槽。
## 资源条/修为已移至左上角 HUD（UiHudVitals）。

const WIDTH := 300.0

const SKILL_FIRST_OFFSET := 82.0  # 顶到技能首行的纵向偏移（地名行+页眉）
const SKILL_ROW_STEP := 21.0

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

	# 地名 + 状态标记
	var status := ""
	if player.fighter.has_dot():
		status += "·蚀"
	if player.fighter.stun_turns > 0:
		status += "·冰"
	if player.fighter.rooted_turns > 0:
		status += "·缠"
	if engine.smoke_turns > 0:
		status += "·烟"
	draw_text_line(Vector2(x, y), state.location_name() + ("  " + status if status != "" else ""), INK, 16)
	y += 28

	# 技能栏（当前页 8 槽；Tab 切主/副职业）
	var class_id := String(player.class_ids[engine.active_page])
	var page_text: String = engine.content.text("hud_main_page" if engine.active_page == 0 else "hud_second_page")
	draw_text_line(Vector2(x, y), "— %s · Tab 切页 —" % page_text.format({"name": engine.content.class_display_name(class_id)}), INK_SOFT, 14)
	y += 20
	for slot in range(1, 9):
		var skill: Dictionary = engine.content.skill_for_slot(class_id, slot)
		if skill.is_empty():
			continue
		var learned: bool = player.skill_levels.has(skill["id"])
		var level: int = player.skill_levels.get(skill["id"], 0)
		var affordable: bool = player.fighter.mp() >= Skills.mp_cost(player, skill) and player.fighter.sp() >= Skills.sp_cost(player, skill)
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
			var effect_summary := Skills.summary(engine, player, skill)
			tail = effect_summary + " " + cost_text if effect_summary != "" else cost_text
		draw_text_line(Vector2(x, y), label, color, 16)
		if tail != "":
			draw_text_line(Vector2(x + WIDTH - 20 - tail.length() * 8, y), tail, INK_SOFT, 12)
		y += SKILL_ROW_STEP

	# 装备五槽
	y += 12
	for slot in Equipment.SLOT_ORDER:
		var slot_label: String = engine.content.text("slot_" + slot)
		var item: Dictionary = player.equipment.slots[slot] if player.equipment.slots.get(slot) != null else {}
		var text := "%s %s" % [slot_label, item["label"] if not item.is_empty() else "——"]
		if not item.is_empty() and item.has("damage"):
			var d: Dictionary = item["damage"]
			var summary := "物%d" % int(d["physical"])
			if String(d.get("element", "")) != "":
				summary += "·" + engine.content.text("element_" + String(d["element"]))
			text += "  " + summary
		draw_text_line(Vector2(x, y), text, INK if not item.is_empty() else Color(170, 165, 155), 15)
		y += 20


## 侧栏半透明（不遮蔽棋盘边缘太多）。
func draw_paper_dim() -> void:
	draw_rect(panel_rect, PAPER, false, 0.0)
	draw_rect(Rect2(panel_rect.position, panel_rect.size), Color(PAPER, 0.92))
	draw_rect(panel_rect, INK, false, 2.0)


## 技能行命中检测（主场景点击路由）：返回槽位 1-8，未命中 0。
func skill_row_at(pos: Vector2) -> int:
	var x := panel_rect.position.x + 16
	var y: float = panel_rect.position.y + SKILL_FIRST_OFFSET
	for slot in range(1, 9):
		if Rect2(x - 8, y - 16, WIDTH - 16, SKILL_ROW_STEP).has_point(pos):
			return slot
		y += SKILL_ROW_STEP
	return 0
