class_name UiMenuInventory
extends UiListMenu
## 行囊：消耗品/装备/材料三页（Tab 切换）。
## Enter = 使用/装备；装备页 U = 卸下所选同槽位。

const PAGE_NAMES: PackedStringArray = ["丹药符箓", "装备", "材料"]

var engine


func setup_menu(p_engine) -> void:
	engine = p_engine
	title = "行囊"
	confirmed.connect(_on_confirm)
	cancelled.connect(func(): close())


func _rebuild() -> void:
	page_count = 3
	var items: Array = engine.player().inventory.items
	rows.clear()
	for item in items:
		var in_page := false
		var tail := ""
		if item.has("consumable"):
			in_page = page == 0
			tail = Consumables.summary(engine, item)
		elif item.has("slot"):
			in_page = page == 1
			if item.has("damage"):
				var d: Dictionary = item["damage"]
				tail = "物%d" % int(d["physical"])
				if String(d.get("element", "")) != "":
					tail += "·" + engine.content.text("element_" + String(d["element"]))
			else:
				var parts: Array = []
				for key in ["power", "defense", "max_hp", "max_mp", "max_sp"]:
					var value: int = int(item.get("bonuses", {}).get(key, 0))
					if value > 0:
						parts.append("%s+%d" % [key, value])
				tail = " ".join(parts)
		elif engine.player().inventory.is_material(item):
			in_page = page == 2
			tail = "×%d" % int(item.get("stack", 1))
		if in_page:
			rows.append({"text": String(item["label"]), "tail": tail, "meta": item})
	header_extra = "%s（%d 件）" % [PAGE_NAMES[page], rows.size()]


func handle_key(keycode: int) -> bool:
	if keycode == KEY_U and page == 1 and not rows.is_empty():
		var item: Dictionary = rows[cursor]["meta"]
		var error: String = engine.player_unequip(String(item["slot"]))
		if not error.is_empty():
			engine.log_message(error, "warn")
		_rebuild()
		queue_redraw()
		return true
	return super(keycode)


func _on_confirm(meta) -> void:
	var item: Dictionary = meta
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
