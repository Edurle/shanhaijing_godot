class_name UiMenuClassSelect
extends UiListMenu
## 职业选择：单职业一步确认后开局；M/F 或点右上角择性别。

var content: ContentDb
var picked_primary := ""
var gender := "male"
var done := false


func setup_menu(p_content: ContentDb) -> void:
	content = p_content
	title = "择 · 修行之道"
	confirmed.connect(_on_confirm)


## 性别牌（右上角）：点击切换。
func _gender_rect() -> Rect2:
	return Rect2(panel_rect.end.x - 236, panel_rect.position.y + 8, 224, 26)


func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_M:
			gender = "male"
			queue_redraw()
			return true
		KEY_F:
			gender = "female"
			queue_redraw()
			return true
	return super.handle_key(keycode)


func click_at(pos: Vector2) -> bool:
	if _gender_rect().grow(4).has_point(pos):
		gender = "female" if gender == "male" else "male"
		queue_redraw()
		return true
	return super.click_at(pos)


func _draw() -> void:
	super._draw()
	var rect := _gender_rect()
	draw_rect(rect, Color(InkPalette.PAPER_UI, 0.92))
	draw_rect(rect, InkPalette.INK, false, 1.2)
	var shown := "男侠" if gender == "male" else "女侠"
	draw_text_line(Vector2(rect.position.x + 12, rect.position.y + 19),
		"性别 M男 F女 · 现：%s" % shown, InkPalette.VERMILION, 13)


func _rebuild() -> void:
	rows.clear()
	for cid in content.classes:
		var cdef: Dictionary = content.classes[cid]
		rows.append({
			"text": content.localize(cdef["name"]),
			"tail": content.text("class_select_stats").format({
				"hp": int(cdef["hp"]), "pow": int(cdef["power"]),
				"def": int(cdef["defense"]), "mp": int(cdef["mp"]), "sp": int(cdef.get("sp", 0)),
			}),
			"meta": String(cid),
		})
	header_extra = "择一道而行，属性取该职业全量"


func _on_confirm(cid) -> void:
	picked_primary = String(cid)
	done = true
