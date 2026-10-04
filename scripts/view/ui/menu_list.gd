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
		setup_ui(Rect2((1280 - 520) / 2.0, (768 - 540) / 2.0, 520, 540), title)
	queue_redraw()


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
		draw_text_line(Vector2(x, y), header_extra, INK_SOFT, 14)
		y += 24
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var selected := i == cursor
		if selected:
			draw_rect(Rect2(x - 12, y - 16, panel_rect.size.x - 36, 24), Color(PAPER_SHADOW, 0.8))
			draw_text_line(Vector2(x - 10, y), "►", VERMILION, 16)
		var color: Color = row.get("color", INK)
		draw_text_line(Vector2(x + 16, y), String(row.get("text", "")), color, 16)
		var tail := String(row.get("tail", ""))
		if tail != "":
			draw_text_line(Vector2(panel_rect.end.x - 24 - tail.length() * 9, y), tail, INK_SOFT, 13)
		y += 24
	if rows.is_empty():
		draw_text_line(Vector2(x + 16, y), "（空）", INK_SOFT, 15)
	draw_text_line(Vector2(x, panel_rect.end.y - 18), "↑↓ 选择 · Tab 翻页 · Enter 确认 · Esc 关闭", INK_SOFT, 13)
