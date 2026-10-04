class_name UiMenuClassSelect
extends UiListMenu
## 职业选择：先主后副（不可同职），两次确认后开局。

var content: ContentDb
var picking_secondary := false
var picked_primary := ""
var picked_secondary := ""
var done := false


func setup_menu(p_content: ContentDb) -> void:
	content = p_content
	title = "择 · 主修之道"
	confirmed.connect(_on_confirm)
	cancelled.connect(func():
		if picking_secondary:
			picking_secondary = false
			title = "择 · 主修之道"
			_rebuild()
			queue_redraw()
	)


func _rebuild() -> void:
	rows.clear()
	for cid in content.classes:
		if picking_secondary and String(cid) == picked_primary:
			continue
		var cdef: Dictionary = content.classes[cid]
		rows.append({
			"text": content.localize(cdef["name"]),
			"tail": content.text("class_select_stats").format({
				"hp": int(cdef["hp"]), "pow": int(cdef["power"]),
				"def": int(cdef["defense"]), "mp": int(cdef["mp"]), "sp": int(cdef.get("sp", 0)),
			}),
			"meta": String(cid),
		})
	header_extra = "第二步：择辅修之道（真气/灵力/气血取半）" if picking_secondary else "第一步：择主修之道（属性全量）"


func _on_confirm(cid) -> void:
	if not picking_secondary:
		picked_primary = String(cid)
		picking_secondary = true
		title = "择 · 辅修之道"
		cursor = 0
		_rebuild()
		queue_redraw()
		return
	picked_secondary = String(cid)
	done = true
