class_name UiMenuCharacter
extends UiPanel
## 角色面板（RPG 式 2 合 1）：左侧装备纸娃娃（五槽）+ 右侧行囊清单。
## 点击/Enter 使用或装备行囊物；点击装备格或 1-5 卸下；材料显示 ×N。

const SLOT_TILE := 56.0
const SLOT_STEP := 66.0
const ROW_STEP := 26.0

var engine
var cursor := 0
var bag_items: Array = []
var equip_rects := {}  # slot -> Rect2（点击命中）
var bag_first_y := 0.0


func setup_menu(p_engine) -> void:
	engine = p_engine


func open() -> void:
	visible = true
	cursor = 0
	_rebuild()
	relayout(_viewport_size())


func close() -> void:
	visible = false


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - minf(760.0, view_size.x - 80.0)) / 2.0,
		(view_size.y - minf(540.0, view_size.y - 60.0)) / 2.0,
		minf(760.0, view_size.x - 80.0), minf(540.0, view_size.y - 60.0)),
		engine.content.text("char_title"))
	queue_redraw()


func _rebuild() -> void:
	bag_items = engine.player().inventory.items.duplicate()


func handle_key(keycode: int) -> bool:
	match keycode:
		KEY_UP, KEY_W:
			cursor = (cursor - 1 + maxi(1, bag_items.size())) % maxi(1, bag_items.size())
			queue_redraw()
			return true
		KEY_DOWN, KEY_S:
			cursor = (cursor + 1) % maxi(1, bag_items.size())
			queue_redraw()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if not bag_items.is_empty():
				_use_bag_item(cursor)
			return true
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_unequip_index(keycode - KEY_1)
			return true
		KEY_ESCAPE:
			close()
			return true
	return false


## 点击路由：先装备格（卸下），再行囊行（使用/装备）；面板内未命中也吞掉。
func click_at(pos: Vector2) -> bool:
	if not visible or not panel_rect.has_point(pos):
		return false
	for slot in equip_rects:
		if equip_rects[slot].has_point(pos):
			var error: String = engine.player_unequip(String(slot))
			if not error.is_empty():
				engine.log_message(error, "warn")
			_rebuild()
			queue_redraw()
			return true
	var row := _bag_row_at(pos)
	if row >= 0:
		cursor = row
		_use_bag_item(row)
	return true


func _use_bag_item(index: int) -> void:
	if index < 0 or index >= bag_items.size():
		return
	var item: Dictionary = bag_items[index]
	if item.has("consumable"):
		var error: String = engine.player_use_item(item)
		if not error.is_empty():
			engine.log_message(error, "warn")
	elif item.has("slot"):
		var error: String = engine.player_equip(item)
		if not error.is_empty():
			engine.log_message(error, "warn")
	_rebuild()
	queue_redraw()


func _unequip_index(index: int) -> void:
	if index < 0 or index >= Equipment.SLOT_ORDER.size():
		return
	var error: String = engine.player_unequip(String(Equipment.SLOT_ORDER[index]))
	if not error.is_empty():
		engine.log_message(error, "warn")
	_rebuild()
	queue_redraw()


func _bag_row_at(pos: Vector2) -> int:
	var y := bag_first_y
	for i in range(bag_items.size()):
		if Rect2(panel_rect.position.x + 300, y - 18, panel_rect.size.x - 330, ROW_STEP).has_point(pos):
			return i
		y += ROW_STEP
	return -1


func _draw() -> void:
	if engine == null:
		return
	draw_paper()
	var player = engine.player()
	var x := panel_rect.position.x + 30
	var y := panel_rect.position.y + 46

	# ---- 左列：装备纸娃娃 ----
	draw_text_line(Vector2(x, y), engine.content.text("char_equipped"), INK_SOFT, 14)
	y += 26
	equip_rects.clear()
	var tile_x := x + 30.0
	for i in range(Equipment.SLOT_ORDER.size()):
		var slot := String(Equipment.SLOT_ORDER[i])
		var rect := Rect2(tile_x, y, SLOT_TILE, SLOT_TILE)
		equip_rects[slot] = rect
		var item: Dictionary = player.equipment.slots[slot] if player.equipment.slots.get(slot) != null else {}
		draw_rect(rect, Color(PAPER, 0.9) if not item.is_empty() else Color(PAPER_SHADOW, 0.5))
		draw_rect(rect, INK if not item.is_empty() else INK_SOFT, false, 1.6)
		if not item.is_empty():
			var icon_color := INK
			if UiPanel.has_rarity_color(item):
				icon_color = UiPanel.rarity_color(item)
			elif item.has("damage") and String(item["damage"].get("element", "")) != "":
				icon_color = _element_color(String(item["damage"]["element"]))
			_draw_tile_icon(rect, String(item["label"].substr(0, 1)), icon_color, str(i + 1))
		else:
			_draw_tile_icon(rect, "·", INK_SOFT, str(i + 1))
		y += SLOT_STEP
	# 卸下数字提示
	draw_text_line(Vector2(x, y + 6), "1-5 卸下", INK_SOFT, 12)

	# ---- 右列：行囊 ----
	var bag_x := panel_rect.position.x + 300
	var bag_y := panel_rect.position.y + 46
	draw_text_line(Vector2(bag_x, bag_y), engine.content.text("char_bag"), INK_SOFT, 14)
	bag_first_y = bag_y + 30
	var ry := bag_first_y
	for i in range(bag_items.size()):
		var item: Dictionary = bag_items[i]
		var selected := i == cursor
		if selected:
			draw_rect(Rect2(bag_x - 10, ry - 18, panel_rect.size.x - 330, ROW_STEP), Color(PAPER_SHADOW, 0.8))
			draw_text_line(Vector2(bag_x - 8, ry), "►", VERMILION, 15)
		var icon_color := INK
		if player.inventory.is_material(item):
			icon_color = Color("8C5A3C")
		elif UiPanel.has_rarity_color(item):
			icon_color = UiPanel.rarity_color(item)
		elif item.has("damage") and String(item["damage"].get("element", "")) != "":
			icon_color = _element_color(String(item["damage"]["element"]))
		elif item.has("slot"):
			icon_color = INK_SOFT
		draw_string(get_theme_default_font(), Vector2(bag_x + 16, ry), String(item["label"].substr(0, 1)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, icon_color)
		var tail := _item_tail(item)
		draw_text_line(Vector2(bag_x + 40, ry), String(item["label"]), UiPanel.rarity_color(item, INK), 15)
		if tail != "":
			draw_text_line(Vector2(panel_rect.end.x - 30 - tail.length() * 8, ry), tail, INK_SOFT, 12)
		ry += ROW_STEP
	if bag_items.is_empty():
		draw_text_line(Vector2(bag_x + 16, ry), "（空空如也）", INK_SOFT, 14)

	draw_text_line(Vector2(panel_rect.position.x + 30, panel_rect.end.y - 20),
		engine.content.text("char_hint"), INK_SOFT, 12)


func _draw_tile_icon(rect: Rect2, icon: String, color: Color, badge := "") -> void:
	var font := get_theme_default_font()
	draw_string(font, rect.position + Vector2(SLOT_TILE / 2.0 - 12.0, 36), icon,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)
	if badge != "":
		draw_string(font, rect.position + Vector2(4, 14), badge,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT)


func _item_tail(item: Dictionary) -> String:
	if engine.player().inventory.is_material(item):
		return "×%d" % int(item.get("stack", 1))
	var tail := ""
	if String(item.get("set_id", "")) != "":
		tail = "套%d/%d" % [_set_owned_count(item), engine.content.set_piece_total(String(item["set_id"]))]
	if item.has("damage"):
		var d: Dictionary = item["damage"]
		var summary := "物%d" % int(d["physical"])
		if String(d.get("element", "")) != "":
			summary += "·" + engine.content.text("element_" + String(d["element"]))
		return tail + " " + summary if tail != "" else summary
	if item.has("consumable"):
		return Consumables.summary(engine, item)
	var parts: Array = []
	for key in ["power", "defense", "max_hp", "max_mp", "max_sp"]:
		var value: int = int(item.get("bonuses", {}).get(key, 0))
		if value > 0:
			parts.append("%s+%d" % [key, value])
	var bonus_text := " ".join(parts)
	if tail != "":
		return tail + " " + bonus_text if bonus_text != "" else tail
	return bonus_text


## 同套件持有数（行囊 + 已穿戴）。
func _set_owned_count(item: Dictionary) -> int:
	var set_id := String(item.get("set_id", ""))
	var count := 0
	for held in engine.player().inventory.items:
		if String(held.get("set_id", "")) == set_id:
			count += 1
	for worn in engine.player().equipment.equipped_items():
		if String(worn.get("set_id", "")) == set_id:
			count += 1
	return count


func _element_color(element: String) -> Color:
	var colors := {
		"metal": Color("C9A662"), "wood": Color("4A7C59"), "water": Color("2E5977"),
		"fire": Color("C3272B"), "earth": Color("8C5A3C"),
	}
	return colors.get(element, INK)
