class_name UiMenuClanSelect
extends UiListMenu
## 氏族选择（开局第一步）：行 = 氏族名，尾注 = 氏族血脉被动名；
## 面板下部展示游标氏族的渊源与被动说明。氏族与职业自由组合，确认后进入全职业选择。

var content: ContentDb
var picked := ""
var done := false


func setup_menu(p_content: ContentDb) -> void:
	content = p_content
	title = "择 · 氏族"
	if not confirmed.is_connected(_on_confirm):
		confirmed.connect(_on_confirm)


func _rebuild() -> void:
	rows.clear()
	for clid in content.clans:
		var cdef: Dictionary = content.clans[clid]
		rows.append({
			"text": content.localize(cdef["name"]),
			"tail": content.localize(cdef["passive"]["name"]),
			"meta": String(clid),
		})
	header_extra = "先承一支血脉（氏族被动），再择任意职承（职业被动）——自由组合"


func _on_confirm(meta) -> void:
	picked = String(meta)
	done = true


func _draw() -> void:
	super._draw()
	if rows.is_empty() or cursor >= rows.size():
		return
	var clid := String(rows[cursor]["meta"])
	var cdef: Dictionary = content.clans[clid]
	var passive: Dictionary = cdef["passive"]
	var x := panel_rect.position.x + 24
	var width := panel_rect.size.x - 48
	var next_y := draw_wrapped(Vector2(x, panel_rect.end.y - 116),
		content.localize(cdef["desc"]), InkPalette.INK_SOFT, 13, width)
	draw_wrapped(Vector2(x, next_y + 6),
		"血脉·%s——%s" % [content.localize(passive["name"]), content.localize(passive["desc"])],
		InkPalette.INK, 13, width)
