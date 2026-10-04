class_name UiMenuAssign
extends UiPanel
## 技能编排（B）：左侧已学技能清单（双职业合并），右侧 4×4 槽位格。
## ↑↓/点击选技能 → 按 1-8/Shift+1-8 或点击槽位绑定；X 清除所选技能的绑定。

const LIST_ROW_STEP := 26.0
const GRID_TILE := 50.0
const GRID_GAP := 8.0

var engine
var learned_skills: Array = []  # 技能 id 清单（双职业合并）
var cursor := 0
var slot_rects := {}  # 槽位号 -> Rect2（点击命中）
var list_first_y := 0.0


func setup_menu(p_engine) -> void:
	engine = p_engine


func open() -> void:
	visible = true
	cursor = 0
	_rebuild()
	relayout(_viewport_size())


func close() -> void:
	visible = false


func _rebuild() -> void:
	learned_skills.clear()
	var player = engine.player()
	for class_id in player.class_ids:
		for skill in engine.content.skills_for_class(String(class_id)):
			if player.skill_levels.has(skill["id"]):
				learned_skills.append(String(skill["id"]))


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - minf(700.0, view_size.x - 80.0)) / 2.0,
		(view_size.y - minf(470.0, view_size.y - 60.0)) / 2.0,
		minf(700.0, view_size.x - 80.0), minf(470.0, view_size.y - 60.0)),
		engine.content.text("assign_title"))
	queue_redraw()


func handle_key(keycode: int, shift := false) -> bool:
	match keycode:
		KEY_UP, KEY_W:
			cursor = (cursor - 1 + maxi(1, learned_skills.size())) % maxi(1, learned_skills.size())
			queue_redraw()
			return true
		KEY_DOWN, KEY_S:
			cursor = (cursor + 1) % maxi(1, learned_skills.size())
			queue_redraw()
			return true
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			_bind_by_slot(keycode - KEY_0 + (8 if shift else 0))
			return true
		KEY_X:
			_clear_selected()
			return true
		KEY_ESCAPE:
			close()
			return true
	return false


func _bind_by_slot(slot: int) -> void:
	if slot < 1 or slot > 16 or learned_skills.is_empty():
		return
	engine.player().skill_bar[slot - 1] = learned_skills[cursor]
	queue_redraw()


func _clear_selected() -> void:
	if learned_skills.is_empty():
		return
	var sid := String(learned_skills[cursor])
	for i in range(16):
		if String(engine.player().skill_bar[i]) == sid:
			engine.player().skill_bar[i] = ""
	queue_redraw()


## 点击路由：先槽位格（绑定当前所选技能），再清单行（换选）。
func click_at(pos: Vector2) -> bool:
	if not visible or not panel_rect.has_point(pos):
		return false
	for slot in slot_rects:
		if slot_rects[slot].has_point(pos):
			_bind_by_slot(int(slot))
			return true
	var y := list_first_y
	for i in range(learned_skills.size()):
		if Rect2(panel_rect.position.x + 30, y - 18, 320, LIST_ROW_STEP).has_point(pos):
			cursor = i
			queue_redraw()
			return true
		y += LIST_ROW_STEP
	return true  # 面板内未命中：吞掉


func _draw() -> void:
	draw_paper()
	var player = engine.player()
	var font := get_theme_default_font()

	# ---- 左列：已学技能清单 ----
	draw_text_line(Vector2(panel_rect.position.x + 30, panel_rect.position.y + 46),
		engine.content.text("assign_learned"), INK_SOFT, 14)
	list_first_y = panel_rect.position.y + 76
	var y := list_first_y
	for i in range(learned_skills.size()):
		var sid := String(learned_skills[i])
		var skill: Dictionary = engine.content.skill_by_id(sid)
		var selected := i == cursor
		if selected:
			draw_rect(Rect2(panel_rect.position.x + 20, y - 18, 330, LIST_ROW_STEP), Color(PAPER_SHADOW, 0.8))
			draw_text_line(Vector2(panel_rect.position.x + 22, y), "►", VERMILION, 14)
		var icon_color: Color = INK
		var element := Skills.skill_element(skill)
		if element != "":
			icon_color = _element_color(element)
		draw_string(font, Vector2(panel_rect.position.x + 46, y), UiSkillBar.icon_char(engine, skill),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, icon_color)
		var bound := _bound_label(sid)
		var label: String = engine.content.localize(skill["name"])
		if bound != "":
			label += "  → %s" % bound
		draw_text_line(Vector2(panel_rect.position.x + 70, y), label, INK, 14)
		y += LIST_ROW_STEP
	if learned_skills.is_empty():
		draw_text_line(Vector2(panel_rect.position.x + 46, y), "（尚未参悟任何技能 · K 参悟）", INK_SOFT, 13)

	# ---- 右列：4×4 槽位格 ----
	var grid_x := panel_rect.position.x + 390
	var grid_y := panel_rect.position.y + 76
	draw_text_line(Vector2(grid_x, panel_rect.position.y + 46), engine.content.text("assign_slots"), INK_SOFT, 14)
	slot_rects.clear()
	for slot in range(1, 17):
		var col := (slot - 1) % 4
		var row := (slot - 1) / 4
		var rect := Rect2(
			grid_x + col * (GRID_TILE + GRID_GAP),
			grid_y + row * (GRID_TILE + GRID_GAP),
			GRID_TILE, GRID_TILE)
		slot_rects[slot] = rect
		var sid := String(player.skill_bar[slot - 1])
		draw_rect(rect, Color(PAPER, 0.9) if sid != "" else Color(PAPER_SHADOW, 0.5))
		draw_rect(rect, INK if sid != "" else INK_SOFT, false, 1.4)
		draw_string(font, rect.position + Vector2(3, 11), UiSkillBar.key_label(slot),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK_SOFT)
		if sid != "":
			var skill: Dictionary = engine.content.skill_by_id(sid)
			if not skill.is_empty():
				var icon_color: Color = INK
				var element := Skills.skill_element(skill)
				if element != "":
					icon_color = _element_color(element)
				draw_string(font, rect.position + Vector2(GRID_TILE / 2.0 - 10.0, 33),
					UiSkillBar.icon_char(engine, skill), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, icon_color)

	draw_text_line(Vector2(panel_rect.position.x + 30, panel_rect.end.y - 20),
		engine.content.text("assign_hint"), INK_SOFT, 12)


func _bound_label(sid: String) -> String:
	for i in range(16):
		if String(engine.player().skill_bar[i]) == sid:
			return UiSkillBar.key_label(i + 1)
	return ""


func _element_color(element: String) -> Color:
	var colors := {
		"metal": Color("C9A662"), "wood": Color("4A7C59"), "water": Color("2E5977"),
		"fire": Color("C3272B"), "earth": Color("8C5A3C"),
	}
	return colors.get(element, INK)
