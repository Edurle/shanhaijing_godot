extends RefCounted
## 表单生成器：按 entity_spec 字段描述符在容器内生成控件并双向绑定。
## 控件变更直接按 omit 规则写回实体 dict，再经 on_change 通知宿主（标脏 / shape 字段触发表单重建）。

const Spec := preload("res://scripts/editor/entity_spec.gd")

const LABEL_WIDTH := 170.0

## 宿主回调：on_change(field: Dictionary)。
var on_change: Callable = Callable()
## 引用型字段（ref）的选项上下文：ref 名 -> Array of [id: String, label: String]。
var enum_context: Dictionary = {}


func build(container: VBoxContainer, entity: Dictionary, fields: Array) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var groups := {}
	var order: Array = []
	for field in fields:
		var group: String = field.get("group", "")
		if not groups.has(group):
			groups[group] = []
			order.append(group)
		groups[group].append(field)
	for group in order:
		if String(group) != "":
			var header := Label.new()
			header.text = "— %s —" % group
			header.custom_minimum_size.y = 30
			header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			container.add_child(header)
		for field in groups[group]:
			_add_field_row(container, entity, field)


func _add_field_row(container: VBoxContainer, entity: Dictionary, field: Dictionary) -> void:
	if String(field.get("kind", "")) == "struct_list":
		var block := _make_struct_list(entity, field)
		container.add_child(block)
		return
	if String(field.get("kind", "")) == "id_list":
		var id_block := _make_id_list(entity, field)
		container.add_child(id_block)
		return
	if String(field.get("kind", "")) == "subdict":
		var sub_block := _make_subdict(entity, field)
		container.add_child(sub_block)
		return
	var row := HBoxContainer.new()
	row.add_child(_make_label(String(field.get("label", field["key"]))))
	var control := _make_control(entity, field)
	if control != null:
		row.add_child(control)
	container.add_child(row)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_WIDTH
	label.clip_text = true
	return label


func _make_control(entity: Dictionary, field: Dictionary) -> Control:
	var kind: String = field.get("kind", "string")
	var path: String = field["key"]
	match kind:
		"int":
			return _make_int(entity, field, path)
		"float":
			return _make_float(entity, field, path)
		"string":
			return _make_string(entity, field, path, false)
		"localized":
			return _make_localized(entity, field, path)
		"enum":
			return _make_enum(entity, field, path, Array(field.get("enum_values", [])), "")
		"ref":
			var options: Array = enum_context.get(String(field.get("ref", "")), [])
			return _make_ref(entity, field, path, options)
		"tags", "elements":
			return _make_string(entity, field, path, true)
		"color":
			return _make_color(entity, field, path)
	return null


func _current(entity: Dictionary, field: Dictionary, fallback):
	var value = Spec.read_path(entity, String(field["key"]))
	return fallback if value == null else value


func _make_int(entity: Dictionary, field: Dictionary, path: String) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = float(field.get("min", 0))
	box.max_value = float(field.get("max", 99999))
	box.step = 1.0
	box.value = float(int(_current(entity, field, field.get("default", box.min_value))))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit := func(value: float) -> void:
		_commit_value(entity, field, int(value))
	box.value_changed.connect(commit)
	return box


func _make_float(entity: Dictionary, field: Dictionary, path: String) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = float(field.get("min", 0.0))
	box.max_value = float(field.get("max", 999.0))
	box.step = float(field.get("step", 0.1))
	box.value = float(_current(entity, field, field.get("default", 1.0)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit := func(value: float) -> void:
		_commit_value(entity, field, value)
	box.value_changed.connect(commit)
	return box


func _make_string(entity: Dictionary, field: Dictionary, path: String, as_tags: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if as_tags:
		var values: Array = _current(entity, field, [])
		var parts := PackedStringArray()
		for v in values:
			parts.append(String(v))
		input.text = ",".join(parts)
	else:
		input.text = String(_current(entity, field, ""))
		input.max_length = 4 if String(field["key"]) == "char" else 0
	row.add_child(input)
	var commit := func() -> void:
		if as_tags:
			var tags := PackedStringArray()
			for part in input.text.split(",", false):
				var trimmed := part.strip_edges()
				if not trimmed.is_empty():
					tags.append(trimmed)
			_commit_value(entity, field, Array(tags))
		else:
			_commit_value(entity, field, input.text)
	input.text_changed.connect(func(_t: String) -> void: commit.call())
	input.text_submitted.connect(func(_t: String) -> void: commit.call())
	return row


func _make_localized(entity: Dictionary, field: Dictionary, path: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value = _current(entity, field, {})
	var zh := ""
	var en := ""
	if value is Dictionary:
		zh = String(value.get("zh_CN", ""))
		en = String(value.get("en_US", ""))
	else:
		zh = String(value)
	var zh_label := Label.new()
	zh_label.text = "中"
	zh_label.custom_minimum_size.x = 24
	row.add_child(zh_label)
	var zh_input := LineEdit.new()
	zh_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zh_input.text = zh
	row.add_child(zh_input)
	var en_label := Label.new()
	en_label.text = "EN"
	en_label.custom_minimum_size.x = 28
	row.add_child(en_label)
	var en_input := LineEdit.new()
	en_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	en_input.text = en
	row.add_child(en_input)
	var commit := func() -> void:
		if en_input.text.is_empty():
			Spec.write_path(entity, path, zh_input.text)
		else:
			Spec.write_path(entity, path, {"zh_CN": zh_input.text, "en_US": en_input.text})
		_notify(field)
	zh_input.text_changed.connect(func(_t: String) -> void: commit.call())
	en_input.text_changed.connect(func(_t: String) -> void: commit.call())
	return row


func _make_enum(entity: Dictionary, field: Dictionary, path: String, values: Array, _unused: String) -> OptionButton:
	var button := OptionButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := String(_current(entity, field, ""))
	for v in values:
		var raw := String(v)
		button.add_item(_enum_display(raw))
		button.set_item_metadata(button.item_count - 1, raw)
	var selected := values.find(current)
	button.select(selected if selected >= 0 else 0)
	button.item_selected.connect(func(index: int) -> void:
		_commit_value(entity, field, String(button.get_item_metadata(index)))
	)
	return button


func _make_ref(entity: Dictionary, field: Dictionary, path: String, options: Array) -> OptionButton:
	var button := OptionButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := String(_current(entity, field, ""))
	for entry in options:
		var id := String(entry[0])
		var label := String(entry[1])
		button.add_item("%s · %s" % [id, label] if label != "" else id)
		button.set_item_metadata(button.item_count - 1, id)
	var selected := -1
	for i in range(button.item_count):
		if String(button.get_item_metadata(i)) == current:
			selected = i
			break
	button.select(selected if selected >= 0 else 0)
	button.item_selected.connect(func(index: int) -> void:
		_commit_value(entity, field, String(button.get_item_metadata(index)))
	)
	return button


func _make_color(entity: Dictionary, field: Dictionary, path: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current: Array = _current(entity, field, [255, 255, 255])
	var boxes: Array = []
	var preview := ColorRect.new()
	preview.custom_minimum_size = Vector2(36, 24)
	row.add_child(preview)
	var refresh_preview := func() -> void:
		preview.color = Color(
			(boxes[0] as SpinBox).value / 255.0,
			(boxes[1] as SpinBox).value / 255.0,
			(boxes[2] as SpinBox).value / 255.0
		)
	for i in range(3):
		var box := SpinBox.new()
		box.min_value = 0.0
		box.max_value = 255.0
		box.step = 1.0
		box.value = float(int(current[i])) if i < current.size() else 255.0
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boxes.append(box)
		row.add_child(box)
	var commit := func(_value: float) -> void:
		_commit_value(entity, field, [
			int((boxes[0] as SpinBox).value),
			int((boxes[1] as SpinBox).value),
			int((boxes[2] as SpinBox).value),
		])
		refresh_preview.call()
	for box in boxes:
		(box as SpinBox).value_changed.connect(commit)
	refresh_preview.call()
	return row


## struct_list：可增删的行列表（如装备词条 affixes）。
func _make_struct_list(entity: Dictionary, field: Dictionary) -> VBoxContainer:
	var block := VBoxContainer.new()
	var rebuild: Callable
	rebuild = func() -> void:
		for child in block.get_children():
			block.remove_child(child)
			child.queue_free()
		var path: String = field["key"]
		var entries: Array = Spec.read_path(entity, path) if Spec.has_path(entity, path) else []
		var had_origin := Spec.has_path(entity, path)
		for row_data in entries:
			var row := HBoxContainer.new()
			row.add_child(_make_list_spacer())
			for item_field in field.get("item_fields", []):
				var item_def: Dictionary = item_field
				var label := Label.new()
				label.text = String(item_def.get("label", ""))
				label.custom_minimum_size.x = 60
				row.add_child(label)
				row.add_child(_make_item_control(row_data, item_def))
			var remove_button := Button.new()
			remove_button.text = "删"
			remove_button.pressed.connect(func() -> void:
				entries.erase(row_data)
				if entries.is_empty() and not had_origin:
					Spec.erase_path(entity, path)
				else:
					Spec.write_path(entity, path, entries)
				_notify(field)
				rebuild.call()
			)
			row.add_child(remove_button)
			block.add_child(row)
		var add_button := Button.new()
		add_button.text = "＋ 添加%s" % String(field.get("label", "条目"))
		add_button.pressed.connect(func() -> void:
			var fresh := {}
			for item_field in field.get("item_fields", []):
				var item_def: Dictionary = item_field
				if item_def.get("kind", "") == "int":
					fresh[item_def["key"]] = int(item_def.get("min", 1))
				else:
					var enum_values: Array = item_def.get("enum_values", [])
					fresh[item_def["key"]] = String(enum_values[0]) if not enum_values.is_empty() else ""
			entries.append(fresh)
			Spec.write_path(entity, path, entries)
			_notify(field)
			rebuild.call()
		)
		block.add_child(add_button)
	rebuild.call()
	return block


func _make_item_control(row_data: Dictionary, item_def: Dictionary) -> Control:
	match String(item_def.get("kind", "")):
		"int":
			var box := SpinBox.new()
			box.min_value = float(item_def.get("min", 0))
			box.max_value = float(item_def.get("max", 9999))
			box.step = 1.0
			box.value = float(int(row_data.get(item_def["key"], item_def.get("min", 1))))
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.value_changed.connect(func(value: float) -> void:
				row_data[item_def["key"]] = int(value)
				_notify(item_def)
			)
			return box
		"enum":
			var button := OptionButton.new()
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var values: Array = item_def.get("enum_values", [])
			for v in values:
				var raw := String(v)
				button.add_item(_enum_display(raw))
				button.set_item_metadata(button.item_count - 1, raw)
			var selected := values.find(String(row_data.get(item_def["key"], "")))
			button.select(selected if selected >= 0 else 0)
			button.item_selected.connect(func(index: int) -> void:
				row_data[item_def["key"]] = String(button.get_item_metadata(index))
				_notify(item_def)
			)
			return button
		"ref":
			var ref_button := OptionButton.new()
			ref_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var options: Array = enum_context.get(String(item_def.get("ref", "")), [])
			for entry in options:
				var id := String(entry[0])
				var label := String(entry[1])
				ref_button.add_item("%s · %s" % [id, label] if label != "" else id)
				ref_button.set_item_metadata(ref_button.item_count - 1, id)
			var ref_selected := -1
			for i in range(ref_button.item_count):
				if String(ref_button.get_item_metadata(i)) == String(row_data.get(item_def["key"], "")):
					ref_selected = i
					break
			ref_button.select(ref_selected if ref_selected >= 0 else 0)
			ref_button.item_selected.connect(func(index: int) -> void:
				row_data[item_def["key"]] = String(ref_button.get_item_metadata(index))
				_notify(item_def)
			)
			return ref_button
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text = String(row_data.get(item_def["key"], ""))
	input.text_changed.connect(func(text: String) -> void:
		row_data[item_def["key"]] = text
		_notify(item_def)
	)
	return input


## id_list：纯字符串引用数组（如怪物 skills 绑定），行内下拉 + 升降序（顺序即优先级）。
func _make_id_list(entity: Dictionary, field: Dictionary) -> VBoxContainer:
	var block := VBoxContainer.new()
	var path: String = field["key"]
	var options: Array = enum_context.get(String(field.get("ref", "")), [])
	var had_origin := Spec.has_path(entity, path)
	var rebuild: Callable
	rebuild = func() -> void:
		_clear_children(block)
		var entries: Array = Spec.read_path(entity, path) if Spec.has_path(entity, path) else []
		for index in range(entries.size()):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row.add_child(_make_list_spacer())
			var id_button := OptionButton.new()
			id_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for option in options:
				id_button.add_item("%s · %s" % [option[0], option[1]] if String(option[1]) != "" else String(option[0]))
				id_button.set_item_metadata(id_button.item_count - 1, String(option[0]))
				if String(option[0]) == String(entries[index]):
					id_button.select(id_button.item_count - 1)
			id_button.item_selected.connect(func(item_index: int) -> void:
				entries[index] = String(id_button.get_item_metadata(item_index))
				_notify(field)
			)
			row.add_child(id_button)
			for pair in [["↑", -1], ["↓", 1]]:
				var shift_button := Button.new()
				shift_button.text = String(pair[0])
				shift_button.tooltip_text = "调整优先级"
				var delta: int = pair[1]
				shift_button.pressed.connect(func() -> void:
					var other := index + delta
					if other < 0 or other >= entries.size():
						return
					var swapped = entries[index]
					entries[index] = entries[other]
					entries[other] = swapped
					_notify(field)
					rebuild.call()
				)
				row.add_child(shift_button)
			var remove_button := Button.new()
			remove_button.text = "删"
			remove_button.pressed.connect(func() -> void:
				entries.remove_at(index)
				if entries.is_empty() and not had_origin:
					Spec.erase_path(entity, path)
				else:
					Spec.write_path(entity, path, entries)
				_notify(field)
				rebuild.call()
			)
			row.add_child(remove_button)
			block.add_child(row)
		var add_button := Button.new()
		add_button.text = "＋ 添加%s" % String(field.get("label", "条目"))
		add_button.disabled = options.is_empty()
		add_button.pressed.connect(func() -> void:
			entries.append(String(options[0][0]))
			Spec.write_path(entity, path, entries)
			_notify(field)
			rebuild.call()
		)
		block.add_child(add_button)
	rebuild.call()
	return block


func _clear_children(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## subdict：开关 + 子字段（如技能附带的 dot/sunder 控制块）。
func _make_subdict(entity: Dictionary, field: Dictionary) -> VBoxContainer:
	var block := VBoxContainer.new()
	var path: String = field["key"]
	var rebuild: Callable
	rebuild = func() -> void:
		for child in block.get_children():
			block.remove_child(child)
			child.queue_free()
		var toggle_row := HBoxContainer.new()
		var toggle := CheckButton.new()
		toggle.text = String(field.get("label", path))
		toggle.button_pressed = Spec.has_path(entity, path)
		toggle_row.add_child(_make_label(""))
		toggle_row.add_child(toggle)
		block.add_child(toggle_row)
		var child_box := VBoxContainer.new()
		block.add_child(child_box)
		var refresh_children := func() -> void:
			child_box.visible = Spec.has_path(entity, path)
		toggle.toggled.connect(func(on: bool) -> void:
			if on:
				Spec.write_path(entity, path, {})
				for child_field in field.get("children", []):
					var child_def: Dictionary = child_field
					var default_value = child_def.get("default", child_def.get("min", 1))
					Spec.write_path(entity, String(child_def["key"]), default_value)
			else:
				Spec.erase_path(entity, path)
			_notify(field)
			refresh_children.call()
			for child in child_box.get_children():
				child_box.remove_child(child)
				child.queue_free()
			if Spec.has_path(entity, path):
				for child_field in field.get("children", []):
					_add_field_row(child_box, entity, child_field)
		)
		if Spec.has_path(entity, path):
			for child_field in field.get("children", []):
				_add_field_row(child_box, entity, child_field)
		refresh_children.call()
	rebuild.call()
	return block


func _make_list_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.x = LABEL_WIDTH
	return spacer


func _enum_display(raw: String) -> String:
	if raw == "":
		return "（无）"
	var label := Spec.enum_label(raw)
	return raw if label == raw else "%s %s" % [label, raw]


## 统一提交口：按 omit 规则决定写值还是删键。
func _commit_value(entity: Dictionary, field: Dictionary, value) -> void:
	var path: String = field["key"]
	var numeric := value is float or value is int
	if field.get("omit_zero", false) and numeric and float(value) == 0.0:
		Spec.erase_path(entity, path)
	elif field.get("omit_empty", false) and String(value) == "":
		Spec.erase_path(entity, path)
	elif field.has("omit_equals") and value == field["omit_equals"]:
		Spec.erase_path(entity, path)
	else:
		Spec.write_path(entity, path, value)
	_notify(field)


func _notify(field: Dictionary) -> void:
	if on_change.is_valid():
		on_change.call(field)
