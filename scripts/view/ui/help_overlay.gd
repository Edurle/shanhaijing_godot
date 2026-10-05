class_name UiHelpOverlay
extends UiPanel
## 键位总览浮层（H 开关）：完整操作说明，现代+古典双轨都列出。

const ROW_KEYS: PackedStringArray = [
	"help_row_move", "help_row_combat", "help_row_skill", "help_row_target",
	"help_row_item", "help_row_grow", "help_row_interact", "help_row_view",
]

var engine


func setup_panel(p_engine) -> void:
	engine = p_engine


func open() -> void:
	relayout(_viewport_size())
	visible = true


func close() -> void:
	visible = false


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - minf(700.0, view_size.x - 100.0)) / 2.0,
		(view_size.y - 380.0) / 2.0,
		minf(700.0, view_size.x - 100.0), 380.0), engine.content.text("help_title"))
	queue_redraw()


func click_at(_pos: Vector2) -> bool:
	if visible:
		close()
	return visible


func _draw() -> void:
	if engine == null:
		return
	draw_paper()
	var x := panel_rect.position.x + 26
	var y := panel_rect.position.y + 42
	for row_key in ROW_KEYS:
		draw_text_line(Vector2(x, y), "· " + engine.content.text(row_key), InkPalette.INK, 15)
		y += 34
	draw_text_line(Vector2(x, panel_rect.end.y - 22), engine.content.text("help_close"), InkPalette.INK_SOFT, 13)
