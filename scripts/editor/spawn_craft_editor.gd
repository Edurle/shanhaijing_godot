extends RefCounted
## 投放表 + 炼制编辑面板：spawn（难度/权重条目、per_room、未投放提示）与
## craft（配方列表编辑、材料掉落表、资源点只读）。配方表单复用 FormBuilder。

const JsonStore := preload("res://scripts/editor/json_store.gd")
const Spec := preload("res://scripts/editor/entity_spec.gd")
const FormBuilder := preload("res://scripts/editor/form_builder.gd")

var store
var on_edit: Callable = Callable()
var form := FormBuilder.new()
var recipe_list: ItemList
var recipe_form_box: VBoxContainer


# ---- 投放 ----

func build_spawn(p_store, box: VBoxContainer, p_on_edit: Callable) -> void:
	store = p_store
	on_edit = p_on_edit
	_rebuild_enum_context()
	_clear_box(box)
	var spawn: Dictionary = store.file_data("spawn_tables")
	box.add_child(_section("怪物投放", "难度过滤 + 权重抽取；max 为 ∞ 时填 -1"))
	_build_entry_rows(box, spawn, "monsters", _monster_options())
	box.add_child(_section("物品投放", ""))
	_build_entry_rows(box, spawn, "items", _item_options())
	box.add_child(_section("每房间投放", "chance=概率；min/max=数量范围"))
	_build_per_room(box, spawn)
	box.add_child(_section("未投放实体", "以下实体不在任何难度段出现（新加内容易漏挂）"))
	_build_unspawned(box, spawn)


func _build_entry_rows(box: VBoxContainer, spawn: Dictionary, list_key: String, id_options: Array) -> void:
	var entries: Array = spawn.get(list_key, [])
	var holder := VBoxContainer.new()
	box.add_child(holder)
	var rebuild: Callable
	rebuild = func() -> void:
		_clear_box(holder)
		for entry in entries:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var id_button := OptionButton.new()
			id_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for option in id_options:
				id_button.add_item("%s · %s" % [option[0], option[1]] if option[1] != "" else String(option[0]))
				id_button.set_item_metadata(id_button.item_count - 1, String(option[0]))
				if String(option[0]) == String(entry.get("id", "")):
					id_button.select(id_button.item_count - 1)
			id_button.item_selected.connect(func(index: int) -> void:
				entry["id"] = String(id_button.get_item_metadata(index))
				_notify()
			)
			row.add_child(id_button)
			row.add_child(_mini_spin("权重", entry, "weight", 1, 999))
			row.add_child(_mini_spin("min难度", entry, "min_difficulty", 0, 99))
			var max_box := _mini_spin("max难度", entry, "max_difficulty", -1, 99)
			max_box.tooltip_text = "-1 = 无上限（存为 null）"
			row.add_child(max_box)
			var remove_button := Button.new()
			remove_button.text = "删"
			remove_button.pressed.connect(func() -> void:
				entries.erase(entry)
				_notify()
				rebuild.call()
			)
			row.add_child(remove_button)
			holder.add_child(row)
		var add_button := Button.new()
		add_button.text = "＋ 添加条目"
		add_button.pressed.connect(func() -> void:
			var fresh := {"id": String(id_options[0][0]), "weight": 6, "min_difficulty": 1, "max_difficulty": null}
			entries.append(fresh)
			_notify()
			rebuild.call()
		)
		holder.add_child(add_button)
	rebuild.call()


func _build_per_room(box: VBoxContainer, spawn: Dictionary) -> void:
	var per_room: Dictionary = spawn.get("per_room", {"monsters": {"chance": 0.6, "min": 1, "max": 2}, "items": {"chance": 0.45, "min": 1, "max": 1}})
	if not spawn.has("per_room"):
		spawn["per_room"] = per_room
	for list_key in ["monsters", "items"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var caption := Label.new()
		caption.text = "　%s：" % ("怪物" if list_key == "monsters" else "物品")
		caption.custom_minimum_size.x = 80
		row.add_child(caption)
		row.add_child(_mini_spin("概率%", per_room[list_key], "chance", 0, 100))
		row.add_child(_mini_spin("min", per_room[list_key], "min", 0, 9))
		row.add_child(_mini_spin("max", per_room[list_key], "max", 0, 9))
		box.add_child(row)


func _build_unspawned(box: VBoxContainer, spawn: Dictionary) -> void:
	var spawned := {}
	for entry in spawn.get("monsters", []):
		spawned[String(entry.get("id", ""))] = true
	for entry in spawn.get("items", []):
		spawned[String(entry.get("id", ""))] = true
	var missing := PackedStringArray()
	var monsters: Dictionary = store.file_data("monsters")
	for mid in JsonStore.entity_ids(monsters):
		if not spawned.has(String(mid)):
			missing.append("怪物 %s" % mid)
	var items: Dictionary = store.file_data("items")
	for iid in JsonStore.entity_ids(items):
		if not spawned.has(String(iid)):
			missing.append("物品 %s" % iid)
	var label := Label.new()
	label.text = "、".join(missing) if not missing.is_empty() else "（全部实体均已投放）"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 800
	box.add_child(label)


# ---- 炼制 ----

func build_craft(p_store, box: VBoxContainer, p_on_edit: Callable) -> void:
	store = p_store
	on_edit = p_on_edit
	_rebuild_enum_context()
	_clear_box(box)
	var crafting: Dictionary = store.file_data("crafting")
	box.add_child(_section("配方", "原料 → 产物；inputs/output 的物品 id 下拉来自 items.json"))
	_build_recipes(box, crafting)
	box.add_child(_section("材料掉落", "按怪物 tag 匹配（首个命中生效）"))
	_build_drops(box, crafting)
	box.add_child(_section("资源点（只读）", "crafting.nodes 由世界生成消费，暂不开放编辑"))
	_build_nodes_readonly(box, crafting)


func _build_recipes(box: VBoxContainer, crafting: Dictionary) -> void:
	var recipes: Array = crafting.get("recipes", [])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	recipe_list = ItemList.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.custom_minimum_size.x = 320
	recipe_list.item_selected.connect(func(index: int) -> void:
		_show_recipe_form(recipe_form_box, recipes[index])
	)
	row.add_child(recipe_list)
	var buttons := VBoxContainer.new()
	var add_button := Button.new()
	add_button.text = "＋ 新配方"
	add_button.pressed.connect(func() -> void:
		var first_item: Array = _item_options()[0]
		recipes.append({
			"id": "new_recipe_%d" % (recipes.size() + 1),
			"kind": "alchemy",
			"name": {"zh_CN": "新配方", "en_US": ""},
			"inputs": [{"id": String(first_item[0]), "count": 1}],
			"output": {"id": String(first_item[0]), "count": 1},
		})
		_refresh_recipe_list(recipes)
		_notify()
	)
	buttons.add_child(add_button)
	var remove_button := Button.new()
	remove_button.text = "删所选"
	remove_button.pressed.connect(func() -> void:
		var selected := recipe_list.get_selected_items()
		if not selected.is_empty():
			recipes.remove_at(selected[0])
			_clear_box(recipe_form_box)
			_refresh_recipe_list(recipes)
			_notify()
	)
	buttons.add_child(remove_button)
	row.add_child(buttons)
	recipe_form_box = VBoxContainer.new()
	recipe_form_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(recipe_form_box)
	box.add_child(row)
	_refresh_recipe_list(recipes)


func _refresh_recipe_list(recipes: Array) -> void:
	recipe_list.clear()
	for recipe in recipes:
		recipe_list.add_item("%s · %s" % [recipe.get("id", "?"), Spec.display_name(recipe)])


func _show_recipe_form(box: VBoxContainer, recipe: Dictionary) -> void:
	_clear_box(box)
	form.on_change = func(_field: Dictionary) -> void: _notify()
	var fields: Array = [
		Spec.f("id", "配方 id", "string", "配方"),
		Spec.f("kind", "类别", "enum", "配方", {"enum_values": ["alchemy", "forge", "talisman"]}),
		Spec.f("name", "名称", "localized", "配方"),
		Spec.f("inputs", "原料", "struct_list", "配方", {"item_fields": [
			{"key": "id", "label": "物品", "kind": "ref", "ref": "items"},
			{"key": "count", "label": "数量", "kind": "int", "min": 1, "max": 99},
		]}),
		Spec.f("output.id", "产物", "ref", "产物", {"ref": "items"}),
		Spec.f("output.count", "产物数量", "int", "产物", {"min": 1, "max": 99}),
	]
	form.build(box, recipe, fields)


func _build_drops(box: VBoxContainer, crafting: Dictionary) -> void:
	var drops: Dictionary = crafting.get("drops", {})
	var tag_options := _tag_options()
	var item_options := _material_options()
	var holder := VBoxContainer.new()
	box.add_child(holder)
	var rebuild: Callable
	rebuild = func() -> void:
		_clear_box(holder)
		for tag in drops:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var tag_button := OptionButton.new()
			tag_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for option in tag_options:
				tag_button.add_item("%s · %s" % [option[0], option[1]] if option[1] != "" else String(option[0]))
				tag_button.set_item_metadata(tag_button.item_count - 1, String(option[0]))
				if String(option[0]) == String(tag):
					tag_button.select(tag_button.item_count - 1)
			tag_button.item_selected.connect(func(index: int) -> void:
				var new_tag := String(tag_button.get_item_metadata(index))
				if String(new_tag) != String(tag) and not drops.has(new_tag):
					var entry: Dictionary = drops[tag]
					drops.erase(tag)
					drops[new_tag] = entry
					_notify()
					rebuild.call()
			)
			row.add_child(tag_button)
			var id_button := OptionButton.new()
			id_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for option in item_options:
				id_button.add_item("%s · %s" % [option[0], option[1]] if option[1] != "" else String(option[0]))
				id_button.set_item_metadata(id_button.item_count - 1, String(option[0]))
				if String(option[0]) == String(drops[tag].get("id", "")):
					id_button.select(id_button.item_count - 1)
			id_button.item_selected.connect(func(index: int) -> void:
				drops[tag]["id"] = String(id_button.get_item_metadata(index))
				_notify()
			)
			row.add_child(id_button)
			row.add_child(_mini_spin("概率%", drops[tag], "chance", 0, 100))
			var remove_button := Button.new()
			remove_button.text = "删"
			remove_button.pressed.connect(func() -> void:
				drops.erase(tag)
				_notify()
				rebuild.call()
			)
			row.add_child(remove_button)
			holder.add_child(row)
		var add_button := Button.new()
		add_button.text = "＋ 添加掉落"
		add_button.pressed.connect(func() -> void:
			var fresh_tag := ""
			for option in tag_options:
				if not drops.has(String(option[0])):
					fresh_tag = String(option[0])
					break
			if fresh_tag == "":
				return
			drops[fresh_tag] = {"id": String(item_options[0][0]), "chance": 0.5}
			_notify()
			rebuild.call()
		)
		holder.add_child(add_button)
	rebuild.call()


func _build_nodes_readonly(box: VBoxContainer, crafting: Dictionary) -> void:
	var text := PackedStringArray()
	for node_key in crafting.get("nodes", {}):
		var node_def: Dictionary = crafting["nodes"][node_key]
		var yields: Dictionary = node_def.get("yields", {})
		text.append("%s：%s ×%s-%s（世界 %s / 秘境每层 %s）" % [
			Spec.display_name(node_def), yields.get("id", "?"),
			yields.get("min", "?"), yields.get("max", "?"),
			node_def.get("world_target", "?"), node_def.get("realm_per_floor", "?"),
		])
	var label := Label.new()
	label.text = "\n".join(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 800
	box.add_child(label)


# ---- 通用小件 ----

## 行内数字输入（带标签）。概率% 读写 0-100，落盘换算 0-1；max难度 -1 落盘 null。
func _mini_spin(caption: String, entry: Dictionary, key: String, min_value: float, max_value: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 62
	box.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1.0 if key != "chance" else 5.0
	spin.custom_minimum_size.x = 70
	var stored = entry.get(key, min_value)
	if key == "chance":
		spin.value = float(stored) * 100.0
	elif key == "max_difficulty" and stored == null:
		spin.value = -1.0
	else:
		spin.value = float(int(stored)) if stored != null else min_value
	spin.value_changed.connect(func(value: float) -> void:
		if key == "chance":
			entry[key] = snappedf(value / 100.0, 0.01)
		elif key == "max_difficulty" and int(value) < 0:
			entry[key] = null
		else:
			entry[key] = int(value)
		_notify()
	)
	box.add_child(spin)
	return box


func _section(title: String, hint: String) -> Control:
	var box := VBoxContainer.new()
	var header := Label.new()
	header.text = "— %s —%s" % [title, ("　%s" % hint) if hint != "" else ""]
	header.add_theme_color_override("font_color", Color("6E675C"))
	header.custom_minimum_size.y = 30
	header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	box.add_child(header)
	return box


func _clear_box(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _notify() -> void:
	if on_edit.is_valid():
		on_edit.call()


# ---- 选项上下文 ----

func _monster_options() -> Array:
	return _options_from("monsters")


func _item_options() -> Array:
	return _options_from("items")


func _material_options() -> Array:
	var out: Array = []
	var items: Dictionary = store.file_data("items")
	for iid in JsonStore.entity_ids(items):
		if (items[iid].get("tags", []) as Array).has("material"):
			out.append([String(iid), Spec.display_name(items[iid])])
	return out


func _tag_options() -> Array:
	var tag_set := {}
	var monsters: Dictionary = store.file_data("monsters")
	for mid in JsonStore.entity_ids(monsters):
		for tag in monsters[mid].get("tags", []):
			tag_set[String(tag)] = true
	for tag in store.file_data("crafting").get("drops", {}):
		tag_set[String(tag)] = true
	var out: Array = []
	for tag in tag_set:
		out.append([String(tag), ""])
	out.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	return out


func _options_from(file_key: String) -> Array:
	var out: Array = []
	var table: Dictionary = store.file_data(file_key)
	for eid in JsonStore.entity_ids(table):
		out.append([String(eid), Spec.display_name(table[eid])])
	return out


func _rebuild_enum_context() -> void:
	form.enum_context = {"items": _item_options()}
