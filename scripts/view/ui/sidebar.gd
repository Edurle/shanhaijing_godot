class_name UiSidebar
extends UiPanel
## 右侧栏（精简版）：地名与状态标记 + 当前职业页眉 + 装备五槽。
## 资源在左上 HUD，技能在底部技能栏。

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

	# 当前职业页眉（Tab 切页提示；技能本体在底部技能栏）
	var class_id := String(player.class_ids[engine.active_page])
	var page_text: String = engine.content.text("hud_main_page" if engine.active_page == 0 else "hud_second_page")
	draw_text_line(Vector2(x, y), "— %s —" % page_text.format({"name": engine.content.class_display_name(class_id)}), INK_SOFT, 14)
	y += 26

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
		y += 24


## 侧栏半透明（不遮蔽棋盘边缘太多）。
func draw_paper_dim() -> void:
	draw_rect(panel_rect, PAPER, false, 0.0)
	draw_rect(Rect2(panel_rect.position, panel_rect.size), Color(PAPER, 0.92))
	draw_rect(panel_rect, INK, false, 2.0)

