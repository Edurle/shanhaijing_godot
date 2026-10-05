class_name UiListMenu
extends UiPanel
## 通用列表菜单基类：标题 + 行 + 游标 + 页眉，按键路由由子类扩展。
## 行结构 {text, tail, color, meta}；confirm/meta 由子类实现。

signal confirmed(meta)
signal cancelled

var rows: Array = []
var cursor := 0
var page := 0
var page_count := 1
var header_extra := ""


func open(center := true) -> void:
	visible = true
	cursor = 0
	_rebuild()
	if center:
		relayout(_viewport_size())
	queue_redraw()



func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - minf(520.0, view_size.x - 80)) / 2.0,
		(view_size.y - minf(540.0, view_size.y - 60)) / 2.0,
		minf(520.0, view_size.x - 80), minf(540.0, view_size.y - 60)), title)


## 行点击命中：设游标并触发确认；返回是否命中。
func click_at(pos: Vector2) -> bool:
	if not visible or not panel_rect.has_point(pos):
		return false
	var y := panel_rect.position.y + 34 + (24 if header_extra != "" else 0)
	for i in range(rows.size()):
		if Rect2(panel_rect.position.x + 12, y - 16, panel_rect.size.x - 24, 24).has_point(pos):
			cursor = i
			queue_redraw()
			confirmed.emit(rows[i].get("meta"))
			return true
		y += 24
	return true  # 面板内但未点中行：吞掉点击


func close() -> void:
	visible = false


## 子类重载：重建行数据。
func _rebuild() -> void:
	pass


## 按键处理；返回是否已消费。
func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_UP, KEY_W:
			cursor = (cursor - 1 + rows.size()) % maxi(1, rows.size())
			queue_redraw()
			return true
		KEY_DOWN, KEY_S:
			cursor = (cursor + 1) % maxi(1, rows.size())
			queue_redraw()
			return true
		KEY_TAB:
			if page_count > 1:
				page = (page + 1) % page_count
				cursor = 0
				_rebuild()
				queue_redraw()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if not rows.is_empty():
				confirmed.emit(rows[cursor].get("meta"))
			return true
		KEY_ESCAPE:
			cancelled.emit()
			return true
	return false


func _draw() -> void:
	draw_paper()
	var x := panel_rect.position.x + 24
	var y := panel_rect.position.y + 34
	if header_extra != "":
		draw_text_line(Vector2(x, y), header_extra, InkPalette.INK_SOFT, 14)
		y += 24
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var selected := i == cursor
		if selected:
			draw_rect(Rect2(x - 12, y - 16, panel_rect.size.x - 36, 24), Color(InkPalette.PAPER_SHADOW, 0.8))
			draw_text_line(Vector2(x - 10, y), "►", InkPalette.VERMILION, 16)
		var color: Color = row.get("color", InkPalette.INK)
		draw_text_line(Vector2(x + 16, y), String(row.get("text", "")), color, 16)
		var tail := String(row.get("tail", ""))
		if tail != "":
			draw_text_line(Vector2(panel_rect.end.x - 24 - tail.length() * 9, y), tail, InkPalette.INK_SOFT, 13)
		y += 24
	if rows.is_empty():
		draw_text_line(Vector2(x + 16, y), "（空）", InkPalette.INK_SOFT, 15)
	draw_text_line(Vector2(x, panel_rect.end.y - 18), "↑↓ 选择 · Tab 翻页 · Enter 确认 · Esc 关闭", InkPalette.INK_SOFT, 13)


## 行命中查询（悬浮提示等用）：返回行号，未命中 -1。几何与 _draw 保持一致。
func row_index_at(pos: Vector2) -> int:
	if not visible or not panel_rect.has_point(pos):
		return -1
	var y := panel_rect.position.y + 34 + (24 if header_extra != "" else 0)
	for i in range(rows.size()):
		if Rect2(panel_rect.position.x + 12, y - 16, panel_rect.size.x - 24, 24).has_point(pos):
			return i
		y += 24
	return -1
