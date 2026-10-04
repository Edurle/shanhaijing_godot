extends Control
## 数据编辑器主场景：页签 + 左侧实体列表/搜索 + 右侧表单或批量表格 + 底部校验面板。
## 编辑 data/content 下 JSON，保存前经 ContentDb 全量校验，只重写实际变更的文件。
## 启动：Godot 中运行本场景（F6）；导出预设里按 scripts/editor/* 排除，不进游戏产物。

const JsonStore := preload("res://scripts/editor/json_store.gd")
const Spec := preload("res://scripts/editor/entity_spec.gd")
const FormBuilder := preload("res://scripts/editor/form_builder.gd")
const GridView := preload("res://scripts/editor/grid_view.gd")
const SpawnCraftEditor := preload("res://scripts/editor/spawn_craft_editor.gd")

const CONTENT_DIR := "res://data/content"
const TAB_MONSTER := 0
const TAB_ITEM := 1
const TAB_SKILL := 2
const TAB_CLASS := 3
const TAB_SPAWN := 4
const TAB_CRAFT := 5

const PAPER := Color("EFE8D6")
const PAPER_DIM := Color("E4DBC6")
const INK := Color("2B2620")
const INK_SOFT := Color("6E675C")
const VERMILION := Color("C3272B")

var store
var current_tab := TAB_MONSTER
var current_id := ""
var grid_mode := false

var tab_bar: TabBar
var search_input: LineEdit
var entity_list: ItemList
var detail_title: Label
var form_scroll: ScrollContainer
var form_box: VBoxContainer
var grid_tree: Tree
var view_toggle: Button
var action_new: Button
var action_dup: Button
var action_del: Button
var error_list: ItemList
var status_label: Label
var save_button: Button
var form := FormBuilder.new()
var grid := GridView.new()
var spawn_craft := SpawnCraftEditor.new()


func _ready() -> void:
	var window := get_window()
	if window != null and not is_instance_valid(window):
		window = null
	if window != null:
		window.title = "数据编辑器 — tui_game_godot"
		window.size = Vector2i(1560, 960)
	theme = _make_theme()
	store = JsonStore.new()
	var errors: PackedStringArray = store.load_all(CONTENT_DIR)
	_build_layout()
	_show_errors(errors)
	_refresh_status()
	if not errors.is_empty():
		save_button.disabled = true
		status_label.text = "数据加载失败，保存已禁用"
	_select_tab(TAB_MONSTER)


# ---- 布局 ----

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = PAPER_DIM
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 顶栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var title := Label.new()
	title.text = "数据编辑器"
	title.custom_minimum_size.x = 110
	top.add_child(title)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color", INK_SOFT)
	top.add_child(status_label)
	save_button = Button.new()
	save_button.text = "保存 (Ctrl+S)"
	var shortcut := Shortcut.new()
	var key := InputEventKey.new()
	key.ctrl_pressed = true
	key.keycode = KEY_S
	shortcut.events.append(key)
	save_button.shortcut = shortcut
	save_button.pressed.connect(_on_save)
	top.add_child(save_button)
	var validate_button := Button.new()
	validate_button.text = "校验"
	validate_button.pressed.connect(func() -> void: _show_errors(store.validate()))
	top.add_child(validate_button)
	var reload_button := Button.new()
	reload_button.text = "重新加载"
	reload_button.pressed.connect(_on_reload)
	top.add_child(reload_button)

	# 页签
	tab_bar = TabBar.new()
	tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER
	for tab_name in ["怪物", "物品", "技能", "职业·玩家", "投放", "炼制"]:
		tab_bar.add_tab(tab_name)
	tab_bar.tab_changed.connect(_select_tab)
	root.add_child(tab_bar)

	# 主区
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 330
	root.add_child(split)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)
	search_input = LineEdit.new()
	search_input.placeholder_text = "搜索 id / 名称 / 标签…"
	search_input.text_changed.connect(func(_text: String) -> void: _rebuild_entity_list())
	left.add_child(search_input)
	entity_list = ItemList.new()
	entity_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entity_list.custom_minimum_size.x = 300
	entity_list.select_mode = ItemList.SELECT_SINGLE
	entity_list.item_selected.connect(_on_entity_selected)
	left.add_child(entity_list)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	right.add_child(toolbar)
	action_new = Button.new()
	action_new.text = "新建"
	action_new.pressed.connect(_on_new_entity)
	toolbar.add_child(action_new)
	action_dup = Button.new()
	action_dup.text = "复制"
	action_dup.pressed.connect(_on_duplicate_entity)
	toolbar.add_child(action_dup)
	action_del = Button.new()
	action_del.text = "删除"
	action_del.pressed.connect(_on_delete_entity)
	toolbar.add_child(action_del)
	view_toggle = Button.new()
	view_toggle.text = "表格视图"
	view_toggle.toggle_mode = true
	view_toggle.pressed.connect(_on_toggle_grid)
	toolbar.add_child(view_toggle)
	detail_title = Label.new()
	detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_title.add_theme_color_override("font_color", INK_SOFT)
	detail_title.clip_text = true
	toolbar.add_child(detail_title)

	form_scroll = ScrollContainer.new()
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(form_scroll)
	form_box = VBoxContainer.new()
	form_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.add_child(form_box)
	grid_tree = Tree.new()
	grid_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_tree.hide_root = true
	grid_tree.visible = false
	grid_tree.columns = 20
	grid_tree.item_edited.connect(_on_grid_edited)
	right.add_child(grid_tree)

	# 底部校验面板
	var bottom := VBoxContainer.new()
	bottom.custom_minimum_size.y = 130
	root.add_child(bottom)
	var error_caption := Label.new()
	error_caption.text = "校验（点击条目定位实体）"
	error_caption.add_theme_color_override("font_color", INK_SOFT)
	bottom.add_child(error_caption)
	error_list = ItemList.new()
	error_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	error_list.item_activated.connect(func(index: int) -> void: _locate_error(error_list.get_item_text(index)))
	bottom.add_child(error_list)

	form.on_change = _on_form_change
	grid.setup(grid_tree, self)
	grid.on_edit = func(_field: Dictionary) -> void: _refresh_status()


# ---- 页签与实体列表 ----

func _select_tab(index: int) -> void:
	current_tab = index
	current_id = ""
	grid_mode = false
	view_toggle.button_pressed = false
	view_toggle.visible = index in [TAB_MONSTER, TAB_ITEM, TAB_SKILL]
	action_new.visible = index in [TAB_MONSTER, TAB_ITEM, TAB_SKILL, TAB_CLASS]
	action_dup.visible = index in [TAB_MONSTER, TAB_ITEM, TAB_SKILL, TAB_CLASS]
	action_del.visible = index in [TAB_MONSTER, TAB_ITEM, TAB_SKILL, TAB_CLASS]
	_rebuild_enum_context()
	_rebuild_entity_list()
	if index == TAB_SPAWN:
		spawn_craft.build_spawn(store, form_box, _on_side_edit)
		form_scroll.visible = true
		grid_tree.visible = false
	elif index == TAB_CRAFT:
		spawn_craft.build_craft(store, form_box, _on_side_edit)
		form_scroll.visible = true
		grid_tree.visible = false
	elif not grid_mode:
		_show_current_form()
	detail_title.text = ""


func _tab_file() -> String:
	match current_tab:
		TAB_MONSTER: return "monsters"
		TAB_ITEM: return "items"
		TAB_SKILL: return "skills"
		TAB_CLASS: return "classes"
	return ""


## 当前页签下的实体条目：[{id, label, type}]。
func _tab_entries() -> Array:
	var entries: Array = []
	var filter_text := search_input.text.strip_edges().to_lower()
	match current_tab:
		TAB_MONSTER, TAB_ITEM, TAB_SKILL, TAB_CLASS:
			pass
		_:
			return entries
	if current_tab == TAB_CLASS:
		for cid in JsonStore.entity_ids(store.file_data("classes")):
			var cdef: Dictionary = store.file_data("classes")[cid]
			entries.append({"id": String(cid), "label": "%s · %s" % [cid, Spec.display_name(cdef)], "type": "class"})
		entries.append({"id": "player", "label": "（玩家初始）", "type": "player"})
	else:
		var file_key := _tab_file()
		var table: Dictionary = store.file_data(file_key)
		for eid in JsonStore.entity_ids(table):
			var edef: Dictionary = table[eid]
			var entity_type := Spec.item_kind(edef) if current_tab == TAB_ITEM else _tab_entity_type()
			var marker := ""
			match entity_type:
				"item_weapon": marker = "[武] "
				"item_gear": marker = "[防] "
				"item_consumable": marker = "[耗] "
				"item_material": marker = "[材] "
			var prefix := ""
			if current_tab == TAB_SKILL:
				prefix = "%s · " % Spec.display_name(store.file_data("classes").get(String(edef.get("class", "")), {}))
			var label := "%s%s · %s" % [prefix, eid, Spec.display_name(edef)]
			if filter_text != "" and not label.to_lower().contains(filter_text) and not _tags_text(edef).contains(filter_text):
				continue
			entries.append({"id": String(eid), "label": marker + label, "type": entity_type})
	return entries


func _tab_entity_type() -> String:
	match current_tab:
		TAB_MONSTER: return "monster"
		TAB_SKILL: return "skill"
	return ""


func _tags_text(entity: Dictionary) -> String:
	var parts := PackedStringArray()
	for tag in entity.get("tags", []):
		parts.append(String(tag))
	return ",".join(parts).to_lower()


func _rebuild_entity_list() -> void:
	entity_list.clear()
	var entries := _tab_entries()
	for entry in entries:
		entity_list.add_item(String(entry["label"]))
		entity_list.set_item_metadata(entity_list.item_count - 1, entry)
	if entity_list.item_count > 0 and current_tab != TAB_SPAWN and current_tab != TAB_CRAFT:
		entity_list.select(0)
		current_id = String(entries[0]["id"])
	if current_tab in [TAB_MONSTER, TAB_ITEM, TAB_SKILL, TAB_CLASS]:
		_show_current_form()


func _on_entity_selected(index: int) -> void:
	var entry: Dictionary = entity_list.get_item_metadata(index)
	current_id = String(entry["id"])
	grid_mode = false
	view_toggle.button_pressed = false
	_show_current_form()


# ---- 表单 ----

func _current_entity() -> Dictionary:
	if current_id == "":
		return {}
	match current_tab:
		TAB_MONSTER, TAB_ITEM, TAB_SKILL:
			return store.file_data(_tab_file()).get(current_id, {})
		TAB_CLASS:
			if current_id == "player":
				return store.file_data("player")
			return store.file_data("classes").get(current_id, {})
	return {}


func _current_entity_type() -> String:
	if current_tab == TAB_ITEM:
		return Spec.item_kind(_current_entity())
	return _tab_entity_type() if current_tab != TAB_CLASS else ("player" if current_id == "player" else "class")


func _fields_for_current(entity: Dictionary, entity_type: String) -> Array:
	var fields: Array = Spec.fields_for(entity_type)
	if entity_type == "skill" and entity.has("effect"):
		fields += Spec.effect_param_fields("effect", String(entity["effect"].get("type", "")))
	elif entity_type == "item_consumable" and entity.has("consumable"):
		fields += Spec.effect_param_fields("consumable", String(entity["consumable"].get("type", "")))
	return fields


func _show_current_form() -> void:
	if current_tab in [TAB_SPAWN, TAB_CRAFT]:
		return
	var entity := _current_entity()
	var entity_type := _current_entity_type()
	form_scroll.visible = true
	grid_tree.visible = false
	if entity.is_empty():
		form.build(form_box, {}, [])
		detail_title.text = "（无选中）"
		return
	detail_title.text = "%s ｜ %s" % [current_id, Spec.display_name(entity)]
	form.build(form_box, entity, _fields_for_current(entity, entity_type))
	_refresh_status()


func _on_form_change(field: Dictionary) -> void:
	if field.get("shape", false):
		var entity := _current_entity()
		if String(field["key"]) == "effect.type" or String(field["key"]) == "consumable.type":
			Spec.normalize_effect_params(entity, String(field["key"]).split(".")[0])
		elif String(field["key"]) == "equipment.slot":
			Spec.normalize_item_equipment(entity)
		_show_current_form()
		if current_tab == TAB_SKILL:
			_rebuild_entity_list()
	_refresh_status()


## 投放/炼制页里控件编辑后的统一回调。
func _on_side_edit() -> void:
	_refresh_status()


# ---- 表格视图 ----

func _on_toggle_grid() -> void:
	grid_mode = view_toggle.button_pressed
	view_toggle.text = "表格视图" if not grid_mode else "表单视图"
	if current_tab in [TAB_SPAWN, TAB_CRAFT]:
		grid_mode = false
		view_toggle.button_pressed = false
		return
	if grid_mode:
		form_scroll.visible = false
		grid_tree.visible = true
		match current_tab:
			TAB_MONSTER: grid.populate("monster", store.file_data("monsters"))
			TAB_ITEM: grid.populate("item", store.file_data("items"))
			TAB_SKILL: grid.populate("skill", store.file_data("skills"))
	else:
		_show_current_form()


func _on_grid_edited() -> void:
	grid.commit_edit()


# ---- 新建 / 复制 / 删除 ----

func _on_new_entity() -> void:
	match current_tab:
		TAB_MONSTER:
			_prompt_new("新建怪物", "monster", {})
		TAB_ITEM:
			_prompt_new_item()
		TAB_SKILL:
			_prompt_new_skill({})
		TAB_CLASS:
			_prompt_new("新建职业", "class", {})


func _on_duplicate_entity() -> void:
	var entity := _current_entity()
	if entity.is_empty() or current_id == "player":
		return
	match current_tab:
		TAB_MONSTER:
			_prompt_new("复制怪物（源自 %s）" % current_id, "monster", {"template": entity.duplicate(true)})
		TAB_ITEM:
			var kind := Spec.item_kind(entity)
			_prompt_new_item_with(kind, entity.duplicate(true))
		TAB_SKILL:
			_prompt_new_skill({"template": entity.duplicate(true)})
		TAB_CLASS:
			_prompt_new("复制职业（源自 %s）" % current_id, "class", {"template": entity.duplicate(true)})


func _on_delete_entity() -> void:
	if current_id == "" or current_id == "player":
		return
	var refs := Spec.find_references(store.data, current_id)
	if not refs.is_empty():
		var dialog := AcceptDialog.new()
		dialog.title = "无法删除"
		var vbox: Node = dialog  # Godot 4.6 AcceptDialog 无 get_vbox，直接挂子节点
		var message := Label.new()
		message.text = "%s 仍被以下位置引用，请先解除：" % current_id
		vbox.add_child(message)
		var list := Label.new()
		list.text = "\n".join(refs)
		vbox.add_child(list)
		add_child(dialog)
		dialog.popup_centered()
		dialog.visibility_changed.connect(func() -> void:
			if not dialog.visible:
				dialog.queue_free()
		)
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = "删除确认"
	confirm.dialog_text = "确定删除 %s？（未保存前可「重新加载」找回）" % current_id
	add_child(confirm)
	confirm.confirmed.connect(func() -> void:
		var table: Dictionary = store.file_data(_tab_file())
		table.erase(current_id)
		current_id = ""
		_rebuild_entity_list()
		_refresh_status()
		confirm.queue_free()
	)
	confirm.close_requested.connect(func() -> void: confirm.queue_free())
	confirm.popup_centered()


func _id_exists(candidate: String) -> bool:
	for file_key in ["monsters", "items", "skills", "classes"]:
		if store.file_data(file_key).has(candidate):
			return true
	return false


## 通用新建弹窗：id 输入 + 模板写入。
func _prompt_new(title: String, entity_type: String, ctx: Dictionary) -> void:
	var dialog := _make_id_dialog(title, func(id_text: String) -> void:
		var template: Dictionary = ctx.get("template", Spec.new_entity_template(entity_type, ctx))
		store.file_data(_tab_file())[id_text] = template
		current_id = id_text
		_rebuild_entity_list()
		_select_list_id(id_text)
		_refresh_status()
	)
	add_child(dialog)
	dialog.popup_centered()


func _prompt_new_item() -> void:
	var dialog := _make_item_dialog({}, func(id_text: String, kind: String) -> void:
		var template := Spec.new_entity_template(kind, {})
		store.file_data("items")[id_text] = template
		current_id = id_text
		_rebuild_entity_list()
		_select_list_id(id_text)
		_refresh_status()
	)
	add_child(dialog)
	dialog.popup_centered()


func _prompt_new_item_with(kind: String, template: Dictionary) -> void:
	var dialog := _make_item_dialog({"locked_kind": kind}, func(id_text: String, _kind: String) -> void:
		store.file_data("items")[id_text] = template
		current_id = id_text
		_rebuild_entity_list()
		_select_list_id(id_text)
		_refresh_status()
	)
	add_child(dialog)
	dialog.popup_centered()


## 技能新建：需选职业与空槽（每职业技能必须恰好占满 slot 1-8）。
func _prompt_new_skill(ctx: Dictionary) -> void:
	var class_ids := JsonStore.entity_ids(store.file_data("classes"))
	var free_slots := _free_skill_slots(String(class_ids[0]))
	if free_slots.is_empty():
		_inform("该职业技能槽已满（每职业恰好 8 技能），请先调整现有技能。")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "新建技能" if ctx.is_empty() else "复制技能（源自 %s）" % current_id
	var vbox: Node = dialog  # Godot 4.6 AcceptDialog 无 get_vbox，直接挂子节点
	var class_row := HBoxContainer.new()
	var class_caption := Label.new()
	class_caption.text = "职业"
	class_caption.custom_minimum_size.x = 100
	class_row.add_child(class_caption)
	var class_button := OptionButton.new()
	class_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for cid in class_ids:
		class_button.add_item("%s · %s" % [cid, Spec.display_name(store.file_data("classes")[cid])])
		class_button.set_item_metadata(class_button.item_count - 1, String(cid))
	class_row.add_child(class_button)
	vbox.add_child(class_row)
	var slot_row := HBoxContainer.new()
	var slot_caption := Label.new()
	slot_caption.text = "槽位"
	slot_caption.custom_minimum_size.x = 100
	slot_row.add_child(slot_caption)
	var slot_button := OptionButton.new()
	slot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_row.add_child(slot_button)
	vbox.add_child(slot_row)
	var id_input := LineEdit.new()
	id_input.placeholder_text = "技能 id（如 s_leifa_9）"
	vbox.add_child(id_input)
	var error_label := Label.new()
	error_label.add_theme_color_override("font_color", VERMILION)
	vbox.add_child(error_label)
	var refresh_slots := func() -> void:
		slot_button.clear()
		for slot in _free_skill_slots(String(class_button.get_item_metadata(class_button.selected))):
			slot_button.add_item("slot %d" % slot)
			slot_button.set_item_metadata(slot_button.item_count - 1, slot)
		slot_button.disabled = slot_button.item_count == 0
	refresh_slots.call()
	class_button.item_selected.connect(func(_i: int) -> void: refresh_slots.call())
	dialog.ok_button_text = "创建"
	dialog.confirmed.connect(func() -> void:
		var id_text := id_input.text.strip_edges()
		if not Spec.valid_id(id_text):
			error_label.text = "id 需为小写字母/数字/下划线，且以字母开头"
			dialog.popup_centered()
			return
		if _id_exists(id_text):
			error_label.text = "id 已存在: %s" % id_text
			dialog.popup_centered()
			return
		if slot_button.item_count == 0:
			error_label.text = "该职业技能槽已满"
			dialog.popup_centered()
			return
		var class_id := String(class_button.get_item_metadata(class_button.selected))
		var slot := int(slot_button.get_item_metadata(slot_button.selected))
		var template: Dictionary = ctx.get("template", {})
		if template.is_empty():
			template = Spec.new_entity_template("skill", {"class_id": class_id, "slot": slot})
		template["class"] = class_id
		template["slot"] = slot
		store.file_data("skills")[id_text] = template
		current_id = id_text
		_rebuild_entity_list()
		_select_list_id(id_text)
		_refresh_status()
		dialog.queue_free()
	)
	dialog.close_requested.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _free_skill_slots(class_id: String) -> Array:
	var used := {}
	for sid in JsonStore.entity_ids(store.file_data("skills")):
		var sdef: Dictionary = store.file_data("skills")[sid]
		if String(sdef.get("class", "")) == class_id:
			used[int(sdef.get("slot", 0))] = true
	var free: Array = []
	for slot in range(1, 9):
		if not used.has(slot):
			free.append(slot)
	return free


## id 输入弹窗（含合法性/查重校验，错误时保持打开）。
func _make_id_dialog(title: String, on_ok: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	var vbox: Node = dialog  # Godot 4.6 AcceptDialog 无 get_vbox，直接挂子节点
	var id_input := LineEdit.new()
	id_input.placeholder_text = "id（小写字母/数字/下划线）"
	vbox.add_child(id_input)
	var error_label := Label.new()
	error_label.add_theme_color_override("font_color", VERMILION)
	vbox.add_child(error_label)
	dialog.ok_button_text = "创建"
	dialog.confirmed.connect(func() -> void:
		var id_text := id_input.text.strip_edges()
		if not Spec.valid_id(id_text):
			error_label.text = "id 需为小写字母/数字/下划线，且以字母开头"
			dialog.popup_centered()
			return
		if _id_exists(id_text):
			error_label.text = "id 已存在: %s" % id_text
			dialog.popup_centered()
			return
		on_ok.call(id_text)
		dialog.queue_free()
	)
	dialog.close_requested.connect(func() -> void: dialog.queue_free())
	return dialog


## 物品新建弹窗：选子型 + id。
func _make_item_dialog(ctx: Dictionary, on_ok: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = "新建物品"
	var vbox: Node = dialog  # Godot 4.6 AcceptDialog 无 get_vbox，直接挂子节点
	var kind_row := HBoxContainer.new()
	var kind_caption := Label.new()
	kind_caption.text = "类型"
	kind_caption.custom_minimum_size.x = 100
	kind_row.add_child(kind_caption)
	var kind_button := OptionButton.new()
	kind_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in [["item_weapon", "装备·武器"], ["item_gear", "装备·防具"], ["item_consumable", "消耗品"], ["item_material", "材料"]]:
		kind_button.add_item(String(pair[1]))
		kind_button.set_item_metadata(kind_button.item_count - 1, String(pair[0]))
	kind_button.disabled = ctx.has("locked_kind")
	if ctx.has("locked_kind"):
		for i in range(kind_button.item_count):
			if String(kind_button.get_item_metadata(i)) == String(ctx["locked_kind"]):
				kind_button.select(i)
	kind_row.add_child(kind_button)
	vbox.add_child(kind_row)
	var id_input := LineEdit.new()
	id_input.placeholder_text = "物品 id（如 w_xinyu）"
	vbox.add_child(id_input)
	var error_label := Label.new()
	error_label.add_theme_color_override("font_color", VERMILION)
	vbox.add_child(error_label)
	dialog.ok_button_text = "创建"
	dialog.confirmed.connect(func() -> void:
		var id_text := id_input.text.strip_edges()
		if not Spec.valid_id(id_text):
			error_label.text = "id 需为小写字母/数字/下划线，且以字母开头"
			dialog.popup_centered()
			return
		if _id_exists(id_text):
			error_label.text = "id 已存在: %s" % id_text
			dialog.popup_centered()
			return
		on_ok.call(id_text, String(kind_button.get_item_metadata(kind_button.selected)))
		dialog.queue_free()
	)
	dialog.close_requested.connect(func() -> void: dialog.queue_free())
	return dialog


func _inform(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "提示"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)


func _select_list_id(id_text: String) -> void:
	for i in range(entity_list.item_count):
		var entry: Dictionary = entity_list.get_item_metadata(i)
		if String(entry["id"]) == id_text:
			entity_list.select(i)
			break
	_show_current_form()


# ---- 保存 / 校验 / 状态 ----

func _on_save() -> void:
	var result: Array = store.save_all()
	var errors: PackedStringArray = result[0]
	if not errors.is_empty():
		_show_errors(errors)
		_inform("校验未通过，未保存。请修正底部错误清单。")
		return
	_show_errors([])
	_inform("已保存（%d 个文件）" % int(result[1]) if int(result[1]) > 0 else "无变更，未写盘")
	_refresh_status()


func _on_reload() -> void:
	if not store.is_dirty():
		_inform("没有未保存的修改。")
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = "重新加载"
	confirm.dialog_text = "丢弃全部未保存修改并重新加载磁盘数据？"
	add_child(confirm)
	confirm.confirmed.connect(func() -> void:
		store.reload_all()
		_rebuild_enum_context()
		_rebuild_entity_list()
		_show_current_form()
		_refresh_status()
		confirm.queue_free()
	)
	confirm.close_requested.connect(func() -> void: confirm.queue_free())
	confirm.popup_centered()


func _show_errors(errors: PackedStringArray) -> void:
	error_list.clear()
	for e in errors:
		error_list.add_item(e)


func _refresh_status() -> void:
	if store.is_dirty():
		var count: int = store.changed_file_count()
		status_label.text = "● 未保存更改（%d 个文件）" % count
		status_label.add_theme_color_override("font_color", VERMILION)
	else:
		status_label.text = "○ 数据与磁盘一致"
		status_label.add_theme_color_override("font_color", INK_SOFT)


## 错误定位：在错误文本里匹配已知实体 id，跳转选中。
func _locate_error(message: String) -> void:
	var tokens := message.replace("：", " ").replace("，", " ").split(" ", false)
	var targets := [
		["monsters", TAB_MONSTER], ["items", TAB_ITEM], ["skills", TAB_SKILL],
		["classes", TAB_CLASS], ["player", TAB_CLASS],
	]
	for pair in targets:
		var file_key: String = pair[0]
		for token in tokens:
			var candidate := String(token).trim_suffix("的").trim_suffix("：")
			if store.file_data(file_key).has(candidate):
				var target_tab: int = pair[1]
				if file_key == "player" and candidate != "player":
					continue
				tab_bar.current_tab = target_tab
				_select_tab(target_tab)
				search_input.text = ""
				_rebuild_entity_list()
				_select_list_id(candidate)
				return


# ---- 枚举上下文（引用型字段的选项） ----

func _rebuild_enum_context() -> void:
	var context := {}
	for ref_name in ["classes", "skills", "monsters", "items"]:
		var file_key := String(ref_name)
		var options: Array = []
		var table: Dictionary = store.file_data(file_key)
		for eid in JsonStore.entity_ids(table):
			options.append([String(eid), Spec.display_name(table[eid])])
		context[ref_name] = options
	form.enum_context = context


# ---- 主题（纸墨风） ----

func _make_theme() -> Theme:
	var editor_theme := Theme.new()
	var ink_controls := ["LineEdit", "SpinBox", "OptionButton", "Button", "ItemList", "Tree", "TabContainer", "TabBar", "ConfirmationDialog", "AcceptDialog", "CheckButton", "Label"]
	for control in ink_controls:
		editor_theme.set_color("font_color", control, INK)
		editor_theme.set_color("font_hover_color", control, INK)
		editor_theme.set_color("font_pressed_color", control, INK)
		editor_theme.set_color("font_focus_color", control, INK)
	editor_theme.set_color("font_selected_color", "ItemList", PAPER)
	editor_theme.set_color("font_selected_color", "Tree", PAPER)
	editor_theme.set_stylebox("normal", "LineEdit", _flat(Color("F7F2E4"), INK_SOFT))
	editor_theme.set_stylebox("focus", "LineEdit", _flat(Color.TRANSPARENT, VERMILION, 2))
	editor_theme.set_stylebox("normal", "SpinBox", _flat(Color("F7F2E4"), INK_SOFT))
	editor_theme.set_stylebox("focus", "SpinBox", _flat(Color.TRANSPARENT, VERMILION, 2))
	editor_theme.set_stylebox("normal", "OptionButton", _flat(Color("F7F2E4"), INK_SOFT))
	editor_theme.set_stylebox("hover", "OptionButton", _flat(Color("F2EBDA"), INK))
	editor_theme.set_stylebox("pressed", "OptionButton", _flat(PAPER, INK))
	editor_theme.set_stylebox("normal", "Button", _flat(Color("F7F2E4"), INK_SOFT))
	editor_theme.set_stylebox("hover", "Button", _flat(Color("F2EBDA"), INK))
	editor_theme.set_stylebox("pressed", "Button", _flat(PAPER_DIM, INK))
	editor_theme.set_stylebox("hover_pressed", "Button", _flat(PAPER_DIM, INK))
	editor_theme.set_stylebox("focus", "Button", _flat(Color.TRANSPARENT, VERMILION, 2))
	editor_theme.set_stylebox("panel", "ItemList", _flat(Color("F7F2E4"), INK_SOFT))
	editor_theme.set_stylebox("panel", "Tree", _flat(Color("F7F2E4"), INK_SOFT))
	editor_theme.set_stylebox("selected", "ItemList", _flat(INK, INK))
	editor_theme.set_stylebox("selected_focus", "ItemList", _flat(INK, INK))
	editor_theme.set_stylebox("selected", "Tree", _flat(INK, INK))
	editor_theme.set_stylebox("selected_focus", "Tree", _flat(INK, INK))
	editor_theme.set_stylebox("tab_selected", "TabBar", _flat(PAPER, INK))
	editor_theme.set_stylebox("tab_unselected", "TabBar", _flat(PAPER_DIM, INK_SOFT))
	editor_theme.set_stylebox("tab_disabled", "TabBar", _flat(PAPER_DIM, INK_SOFT))
	editor_theme.set_stylebox("panel", "TabContainer", _flat(PAPER, INK_SOFT))
	editor_theme.set_stylebox("panel", "ConfirmationDialog", _flat(PAPER, INK))
	editor_theme.set_stylebox("panel", "AcceptDialog", _flat(PAPER, INK))
	editor_theme.set_stylebox("normal", "CheckButton", _flat(Color("F7F2E4"), INK_SOFT))
	editor_theme.set_constant("separation", "HBoxContainer", 8)
	editor_theme.set_constant("separation", "VBoxContainer", 4)
	return editor_theme


func _flat(bg: Color, border: Color, thickness := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(thickness)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style
