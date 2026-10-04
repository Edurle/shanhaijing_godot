class_name UiMenuAssign
extends UiPanel
## 技能编排（B）：左侧已学技能图标网格（悬浮提示由全局 tooltip 层负责），
## 右侧 4×4 槽位格。选技能（点击/拖拽释放）→ 按键或点槽/拖放绑定；X 清除。

const TILE := 52.0
const TILE_GAP := 10.0
const GRID_COLS := 5
const SLOT_TILE := 52.0
const SLOT_GAP := 10.0

var engine
var learned_skills: Array = []  # 技能 id 清单（双职业合并）
var selected_id := ""
var icon_rects := {}  # skill_id -> Rect2（点击/拖拽/悬停命中）
var slot_rects := {}  # 槽位号 -> Rect2（点击/释放命中）
var _icons_origin := Vector2.ZERO
var _slots_origin := Vector2.ZERO


func setup_menu(p_engine) -> void:
	engine = p_engine


func open() -> void:
	visible = true
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
	if selected_id != "" and not learned_skills.has(selected_id):
		selected_id = ""
	if selected_id == "" and not learned_skills.is_empty():
		selected_id = String(learned_skills[0])


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - minf(720.0, view_size.x - 60.0)) / 2.0,
		(view_size.y - minf(430.0, view_size.y - 60.0)) / 2.0,
		minf(720.0, view_size.x - 60.0), minf(430.0, view_size.y - 60.0)),
		engine.content.text("assign_title"))
	_icons_origin = panel_rect.position + Vector2(36, 86)
	_slots_origin = panel_rect.position + Vector2(430, 86)
	_rebuild_rects()
	queue_redraw()


func _rebuild_rects() -> void:
	icon_rects.clear()
	slot_rects.clear()
	for i in range(learned_skills.size()):
		var col := i % GRID_COLS
		var row := i / GRID_COLS
		icon_rects[String(learned_skills[i])] = Rect2(
			_icons_origin + Vector2(col * (TILE + TILE_GAP), row * (TILE + TILE_GAP)),
			Vector2(TILE, TILE))
	for slot in range(1, 17):
		var col := (slot - 1) % 4
		var row := (slot - 1) / 4
		slot_rects[slot] = Rect2(
			_slots_origin + Vector2(col * (SLOT_TILE + SLOT_GAP), row * (SLOT_TILE + SLOT_GAP)),
			Vector2(SLOT_TILE, SLOT_TILE))


# ---- 命中查询（主场景拖拽/悬停/点击路由） ----

## 图标命中 → 技能 id（空串 = 未命中）。
func icon_at(pos: Vector2) -> String:
	for sid in icon_rects:
		if icon_rects[sid].grow(2.0).has_point(pos):
			return String(sid)
	return ""


## 槽位格命中 → 槽位号（0 = 未命中）。
func slot_at(pos: Vector2) -> int:
	for slot in slot_rects:
		if slot_rects[slot].grow(2.0).has_point(pos):
			return int(slot)
	return 0


func select(skill_id: String) -> void:
	selected_id = skill_id
	queue_redraw()


func bind_to_slot(slot: int) -> void:
	if slot < 1 or slot > 16 or selected_id == "":
		return
	engine.player().skill_bar[slot - 1] = selected_id
	queue_redraw()


func clear_selected() -> void:
	if selected_id == "":
		return
	for i in range(16):
		if String(engine.player().skill_bar[i]) == selected_id:
			engine.player().skill_bar[i] = ""
	queue_redraw()


# ---- 键盘流（保留：方向键选技能 + 数字绑定 + X 清除） ----

func handle_key(keycode: int, shift := false) -> bool:
	if learned_skills.is_empty():
		if keycode == KEY_ESCAPE:
			close()
			return true
		return false
	var index := maxi(0, learned_skills.find(selected_id))
	match keycode:
		KEY_UP, KEY_W:
			index = (index - GRID_COLS + learned_skills.size()) % learned_skills.size()
		KEY_DOWN, KEY_S:
			index = (index + GRID_COLS) % learned_skills.size()
		KEY_LEFT, KEY_A:
			index = (index - 1 + learned_skills.size()) % learned_skills.size()
		KEY_RIGHT, KEY_D:
			index = (index + 1) % learned_skills.size()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			bind_to_slot(keycode - KEY_0 + (8 if shift else 0))
			return true
		KEY_X:
			clear_selected()
			return true
		KEY_ESCAPE:
			close()
			return true
		_:
			return false
	selected_id = String(learned_skills[index])
	queue_redraw()
	return true


func click_at(pos: Vector2) -> bool:
	if not visible or not panel_rect.has_point(pos):
		return false
	var sid := icon_at(pos)
	if sid != "":
		select(sid)
		return true
	var slot := slot_at(pos)
	if slot > 0:
		bind_to_slot(slot)  # 点击槽位 = 绑定当前所选
		return true
	return true  # 面板内未命中：吞掉


func _draw() -> void:
	if engine == null:
		return
	draw_paper()
	var player = engine.player()
	var font := get_theme_default_font()

	# 左：技能图标网格
	draw_text_line(Vector2(panel_rect.position.x + 36, panel_rect.position.y + 52),
		engine.content.text("assign_learned"), INK_SOFT, 13)
	for sid in learned_skills:
		var skill: Dictionary = engine.content.skill_by_id(String(sid))
		var rect: Rect2 = icon_rects[String(sid)]
		var selected := String(sid) == selected_id
		draw_rect(rect, Color(PAPER, 0.92) if selected else Color(PAPER, 0.7))
		draw_rect(rect, INK if selected else INK_SOFT, false, 2.0 if selected else 1.2)
		var icon_color: Color = INK
		var element := Skills.skill_element(skill)
		if element != "":
			icon_color = _element_color(element)
		draw_string(font, rect.position + Vector2(TILE / 2.0 - 11.0, 32),
			UiSkillBar.icon_char(engine, skill), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, icon_color)
		# 角标：已绑键位
		var bound := _bound_label(String(sid))
		if bound != "":
			draw_string(font, rect.position + Vector2(TILE - 22, 12), bound,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GOLD)
	if learned_skills.is_empty():
		draw_text_line(Vector2(panel_rect.position.x + 36, _icons_origin.y + 20),
			"（尚未参悟任何技能 · K 参悟）", INK_SOFT, 13)

	# 右：4×4 槽位格
	draw_text_line(Vector2(_slots_origin.x, panel_rect.position.y + 52),
		engine.content.text("assign_slots"), INK_SOFT, 13)
	for slot in range(1, 17):
		var rect: Rect2 = slot_rects[slot]
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
				draw_string(font, rect.position + Vector2(SLOT_TILE / 2.0 - 10.0, 34),
					UiSkillBar.icon_char(engine, skill), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, icon_color)

	draw_text_line(Vector2(panel_rect.position.x + 36, panel_rect.end.y - 20),
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
