class_name UiMenuLearn
extends UiPanel
## 参悟面板（技能树）：双职业页（Tab），技能按前置深度分列，左根右叶。
## 图标格暂以技能名首字汉字代替（素材期换贴图），格下注技能名，父子连线随习得状态着色。
## 交互：方向键移动游标，Enter/原地点击参悟，拖格入技能栏或数字键绑定，悬浮看详情。

signal confirmed(meta)
signal cancelled

const NODE := 50.0        # 图标格边长
const COL_GAP := 36.0     # 列间距（连线区）
const ROW_GAP := 20.0     # 同列格距
const TREE_TOP := 70.0    # 树区顶部（标题 + 页眉下方）
const FOOT := 34.0        # 底栏高
const NAME_ROW := 16.0    # 格下技能名行高

var engine
var nodes: Array = []     # [{sid, skill, level, col, row, rect}]
var links: Array = []     # [{from, to}]（节点索引；子状态决定连线颜色）
var columns: Array = []   # columns[col] = [节点索引…]（列内按技能号序）
var cursor := 0
var page := 0
var page_count := 2
var header_extra := ""


func setup_menu(p_engine) -> void:
	engine = p_engine
	title = "参悟"
	confirmed.connect(_on_confirm)
	cancelled.connect(func(): close())


func open(center := true) -> void:
	visible = true
	cursor = 0
	_rebuild()
	if center:
		relayout(_viewport_size())
	queue_redraw()


func close() -> void:
	visible = false


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - minf(600.0, view_size.x - 60)) / 2.0,
		(view_size.y - minf(470.0, view_size.y - 60)) / 2.0,
		minf(600.0, view_size.x - 60), minf(470.0, view_size.y - 60)), title)
	_layout_nodes()


## 重建树：深度分层 → 列内排序 → 父子连线。
func _rebuild() -> void:
	var player = engine.player()
	var class_id := String(player.class_ids[page])
	var essence: int = player.inventory.count_material("mat_elite_essence")
	var core: int = player.inventory.count_material("mat_demon_core")
	header_extra = "%s · 技能点 %d · 精魄×%d 魔核×%d" % [
		engine.content.class_display_name(class_id), player.skill_points, essence, core,
	]
	nodes.clear()
	links.clear()
	var skills: Array = engine.content.skills_for_class(class_id)
	var depth_of := {}
	for skill in skills:
		var sid := String(skill["id"])
		depth_of[sid] = _skill_depth(sid, depth_of)
	var col_count := 0
	for skill in skills:
		col_count = maxi(col_count, int(depth_of[String(skill["id"])]) + 1)
	columns.resize(col_count)
	for col in range(col_count):
		columns[col] = []
	var index_of := {}
	for skill in skills:
		var col: int = int(depth_of[String(skill["id"])])
		columns[col].append(nodes.size())
		index_of[String(skill["id"])] = nodes.size()
		nodes.append({
			"sid": String(skill["id"]), "skill": skill,
			"level": player.skill_levels.get(String(skill["id"]), 0),
			"col": col, "row": columns[col].size() - 1, "rect": Rect2(),
		})
	for skill in skills:
		for req in skill.get("requires", []):
			links.append({"from": index_of[String(req)], "to": index_of[String(skill["id"])]})
	cursor = clampi(cursor, 0, maxi(0, nodes.size() - 1))
	_layout_nodes()
	queue_redraw()


## 前置链深度（同职业内递归；requires 均为同职业技能，取原始定义仅读 requires）。
func _skill_depth(sid: String, memo: Dictionary) -> int:
	if memo.has(sid):
		return int(memo[sid])
	var depth := 0
	for req in engine.content.skills[sid].get("requires", []):
		depth = maxi(depth, _skill_depth(String(req), memo) + 1)
	memo[sid] = depth
	return depth


## 依 panel_rect 摆格：列水平居中铺开，列内垂直居中成块。
func _layout_nodes() -> void:
	if nodes.is_empty() or panel_rect.size == Vector2.ZERO:
		return
	var col_count := columns.size()
	var tree_width: float = col_count * NODE + (col_count - 1) * COL_GAP
	var tree_left := panel_rect.position.x + (panel_rect.size.x - tree_width) / 2.0
	var tree_cy := panel_rect.position.y + TREE_TOP + (panel_rect.size.y - TREE_TOP - FOOT) / 2.0
	for col in range(col_count):
		var count: int = columns[col].size()
		var block_h: float = count * NODE + (count - 1) * ROW_GAP
		for row in range(count):
			var n: Dictionary = nodes[columns[col][row]]
			n["rect"] = Rect2(
				tree_left + col * (NODE + COL_GAP),
				tree_cy - block_h / 2.0 + row * (NODE + ROW_GAP),
				NODE, NODE)


## 节点习得状态：learned 已学 / ready 可学（前置齐）/ locked 前置缺失。
func _node_state(n: Dictionary) -> String:
	if int(n["level"]) > 0:
		return "learned"
	for req in n["skill"].get("requires", []):
		if not engine.player().skill_levels.has(req):
			return "locked"
	return "ready"


func _draw() -> void:
	draw_paper()
	var font := get_theme_default_font()
	if header_extra != "":
		draw_text_line(panel_rect.position + Vector2(24, 34), header_extra, INK_SOFT, 14)
	# 父子连线：父右缘中点 → 中垂折线 → 子左缘中点，颜色随子状态
	for link in links:
		var child: Dictionary = nodes[link["to"]]
		var st := _node_state(child)
		var line_color := INK if st == "learned" else (INK_SOFT if st == "ready" else INK_SOFT.lerp(PAPER, 0.55))
		var p_from: Vector2 = (nodes[link["from"]]["rect"] as Rect2).get_center() + Vector2(NODE / 2.0, 0)
		var p_to: Vector2 = (child["rect"] as Rect2).get_center() - Vector2(NODE / 2.0, 0)
		var mid_x := (p_from.x + p_to.x) / 2.0
		draw_polyline(PackedVector2Array([
			p_from, Vector2(mid_x, p_from.y), Vector2(mid_x, p_to.y), p_to,
		]), line_color, 1.4)
	# 图标格：汉字图标（元素色）/ 右上重数 / 格下技能名
	for i in range(nodes.size()):
		var n: Dictionary = nodes[i]
		var rect: Rect2 = n["rect"]
		var skill: Dictionary = n["skill"]
		var st := _node_state(n)
		var label: String = engine.content.localize(skill["name"])
		draw_rect(rect, Color(PAPER, 0.92 if st == "learned" else 0.55))
		var frame_color := INK if st == "learned" else (INK_SOFT if st == "ready" else INK_SOFT.lerp(PAPER, 0.55))
		draw_rect(rect, frame_color, false, 1.6 if st == "learned" else 1.0)
		var icon_color: Color = ELEMENT_COLORS.get(Skills.skill_element(skill), INK)
		if st != "learned":
			icon_color = icon_color.lerp(PAPER, 0.45 if st == "ready" else 0.68)
		draw_string(font, rect.position + Vector2(NODE / 2.0 - 11.0, 33), label.substr(0, 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, icon_color)
		if int(n["level"]) > 1:
			draw_string(font, rect.position + Vector2(NODE - 14, 12), str(int(n["level"])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GOLD)
		if i == cursor:
			draw_rect(rect.grow(4), VERMILION, false, 2.0)
		draw_string(font, Vector2(rect.get_center().x - label.length() * 5.5, rect.end.y + NAME_ROW - 3), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK if st == "learned" else INK_SOFT)
	draw_text_line(Vector2(panel_rect.position.x + 24, panel_rect.end.y - 16),
		"←→↑↓ 移动 · Tab 换页 · Enter 参悟 · 拖入技能栏/数字键 绑定 · Esc 关闭", INK_SOFT, 13)


## 网格游标：左右取相邻列最近行，上下在同列环绕。
func _move_cursor(dx: int, dy: int) -> void:
	if nodes.is_empty():
		return
	var cur: Dictionary = nodes[cursor]
	if dx != 0:
		var target_col: int = int(cur["col"]) + dx
		var best := -1
		var best_dist := 1 << 30
		for i in range(nodes.size()):
			if int(nodes[i]["col"]) == target_col:
				var dist: int = abs(int(nodes[i]["row"]) - int(cur["row"]))
				if dist < best_dist:
					best_dist = dist
					best = i
		if best >= 0:
			cursor = best
	else:
		var col_nodes: Array = []
		for i in range(nodes.size()):
			if int(nodes[i]["col"]) == int(cur["col"]):
				col_nodes.append(i)
		col_nodes.sort_custom(func(a, b): return int(nodes[a]["row"]) < int(nodes[b]["row"]))
		var idx := col_nodes.find(cursor)
		cursor = col_nodes[(idx + dy + col_nodes.size()) % col_nodes.size()]
	queue_redraw()


func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_LEFT, KEY_A:
			_move_cursor(-1, 0)
			return true
		KEY_RIGHT, KEY_D:
			_move_cursor(1, 0)
			return true
		KEY_UP, KEY_W:
			_move_cursor(0, -1)
			return true
		KEY_DOWN, KEY_S:
			_move_cursor(0, 1)
			return true
		KEY_TAB:
			if page_count > 1:
				page = (page + 1) % page_count
				cursor = 0
				_rebuild()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if not nodes.is_empty():
				confirmed.emit(nodes[cursor]["sid"])
			return true
		KEY_ESCAPE:
			cancelled.emit()
			return true
	return false


## 面板内点击：命中格 → 游标 + 参悟；未命中格吞掉点击。
func click_at(pos: Vector2) -> bool:
	if not visible or not panel_rect.has_point(pos):
		return false
	var index := node_index_at(pos)
	if index >= 0:
		cursor = index
		queue_redraw()
		confirmed.emit(nodes[index]["sid"])
	return true


func _on_confirm(meta) -> void:
	var error: String = engine.learn_skill(String(meta))
	if not error.is_empty():
		engine.log_message(error, "warn")
	_rebuild()
	queue_redraw()


## 格命中（含格下名字行；拖拽起拖/悬浮路由用）：返回节点索引，未命中 -1。
func node_index_at(pos: Vector2) -> int:
	if not visible:
		return -1
	for i in range(nodes.size()):
		var rect: Rect2 = nodes[i]["rect"]
		if Rect2(rect.position + Vector2(-4, -4), Vector2(NODE + 8, NODE + NAME_ROW + 8)).has_point(pos):
			return i
	return -1


## 格 → 技能 id（空串 = 未命中）。
func node_skill_at(pos: Vector2) -> String:
	var index := node_index_at(pos)
	return String(nodes[index]["sid"]) if index >= 0 else ""


## 游标所指技能 id（数字键绑定用；空串 = 无节点）。
func cursor_skill_id() -> String:
	if nodes.is_empty():
		return ""
	return String(nodes[cursor]["sid"])
