class_name UiMenuClassSelect
extends UiListMenu
## 职业选择（开局第二步，氏族已定）：全职业自由择一（与氏族自由组合）；
## 行 = 职业名·职业被动，尾注 = 生效五维（已并入双被动常驻加成）；
## 下部展示游标职业渊源与双被动说明。M/F 或点右上角择性别。

var content: ContentDb
var clan_id := ""
var picked_primary := ""
var gender := "male"
var done := false


func setup_menu(p_content: ContentDb, p_clan_id := "") -> void:
	content = p_content
	clan_id = p_clan_id
	title = "择 · 职承"
	if not confirmed.is_connected(_on_confirm):
		confirmed.connect(_on_confirm)  # setup 可随氏族重选反复调用，防重复连接


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
		KEY_ESCAPE:
			# Esc 收起自身（主流程检测 visible=false 退回氏族页）
			cancelled.emit()
			close()
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
	_draw_desc_block()


## 游标职业的渊源 + 双被动说明（面板下部）。
func _draw_desc_block() -> void:
	if rows.is_empty() or cursor >= rows.size():
		return
	var cid := String(rows[cursor]["meta"])
	var cdef: Dictionary = content.classes[cid]
	var x := panel_rect.position.x + 24
	var width := panel_rect.size.x - 48
	var next_y := draw_wrapped(Vector2(x, panel_rect.end.y - 136),
		content.localize(cdef["desc"]), InkPalette.INK_SOFT, 13, width)
	var class_passive: Dictionary = cdef["passive"]
	next_y = draw_wrapped(Vector2(x, next_y + 6),
		"职承·%s——%s" % [content.localize(class_passive["name"]), content.localize(class_passive["desc"])],
		InkPalette.INK, 13, width)
	var clan_passive: Dictionary = content.clans.get(clan_id, {}).get("passive", {})
	if not clan_passive.is_empty():
		draw_wrapped(Vector2(x, next_y + 4),
			"血脉·%s——%s" % [content.localize(clan_passive["name"]), content.localize(clan_passive["desc"])],
			InkPalette.INK_SOFT, 13, width)


func _rebuild() -> void:
	rows.clear()
	for cid in content.classes:
		var cdef: Dictionary = content.classes[cid]
		var passive_name := content.localize(cdef["passive"]["name"])
		var stats := _effective_stats(cdef)
		rows.append({
			"text": "%s · %s" % [content.localize(cdef["name"]), passive_name],
			"tail": content.text("class_select_stats").format({
				"hp": stats["hp"], "pow": stats["power"],
				"def": stats["defense"], "mp": stats["mp"], "sp": stats["sp"],
			}),
			"meta": String(cid),
		})
	if clan_id != "":
		header_extra = "血脉已承 · %s —— 任意择一职承，属性取全量（已含双被动）" % content.clan_display_name(clan_id)
	else:
		header_extra = "择一道而行，属性取该职业全量"


## 生效开局五维：职业基础值 + 职业被动/所选氏族被动的常驻（stat_aura）加成。
func _effective_stats(cdef: Dictionary) -> Dictionary:
	var stats := {
		"hp": int(cdef["hp"]), "power": int(cdef["power"]), "defense": int(cdef["defense"]),
		"mp": int(cdef["mp"]), "sp": int(cdef.get("sp", 0)),
	}
	var clan_passive: Dictionary = content.clans.get(clan_id, {}).get("passive", {})
	for passive in [cdef.get("passive", {}), clan_passive]:
		var eff: Dictionary = passive.get("effect", {})
		if String(eff.get("type", "")) != "stat_aura":
			continue
		var aura: Dictionary = eff.get("stats", {})
		stats["hp"] += int(aura.get("max_hp", 0))
		stats["power"] += int(aura.get("power", 0))
		stats["defense"] += int(aura.get("defense", 0))
		stats["mp"] += int(aura.get("max_mp", 0))
		stats["sp"] += int(aura.get("max_sp", 0))
	return stats


func _on_confirm(cid) -> void:
	picked_primary = String(cid)
	done = true
