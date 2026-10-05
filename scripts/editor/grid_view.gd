extends RefCounted
## 批量数值表格：Tree 可编辑单元格，多实体横向对比调数值（怪物/装备/技能三套列配置）。
## 单元格提交走 entity_spec 的点路径写回；枚举格按原值或中文标签匹配，非法输入回弹并整表刷新。
## 结构性字段（如非武器上的 physical）只在路径已存在时可编辑，避免写出校验必拦的数据。

const Spec := preload("res://scripts/editor/entity_spec.gd")
const JsonStore := preload("res://scripts/editor/json_store.gd")

var on_edit: Callable = Callable()
var tree: Tree
var columns: Array = []
var kind := ""


func setup(p_tree: Tree, _host) -> void:
	tree = p_tree


func populate(p_kind: String, table: Dictionary) -> void:
	kind = p_kind
	columns = _columns_for(p_kind)
	tree.clear()
	tree.columns = columns.size()
	for i in range(columns.size()):
		tree.set_column_title(i, String(columns[i]["title"]))
		tree.set_column_custom_minimum_width(i, int(columns[i].get("width", 72)))
	var root := tree.create_item()
	for eid in JsonStore.entity_ids(table):
		var entity: Dictionary = table[eid]
		if kind == "item" and not entity.has("equipment"):
			continue
		var row := tree.create_item(root)
		row.set_meta("entity", entity)
		row.set_meta("entity_id", String(eid))
		for i in range(columns.size()):
			_fill_cell(row, i, columns[i], entity)


func _fill_cell(row: TreeItem, col_index: int, col: Dictionary, entity: Dictionary) -> void:
	var text := ""
	if String(col.get("path", "")) == "__id__":
		text = String(row.get_meta("entity_id"))
	elif String(col.get("kind", "")) == "name":
		text = Spec.display_name(entity)
	else:
		var value = Spec.read_path(entity, String(col["path"]))
		if value != null:
			if String(col.get("kind", "")) == "int":
				text = str(int(value))
			elif String(col.get("kind", "")) == "float":
				text = str(snappedf(float(value), 0.01))
			else:
				text = String(value)
	row.set_text(col_index, text)
	var editable: bool = not col.get("readonly", false)
	if editable and String(col.get("kind", "")) != "name":
		# 只在路径已存在或列声明可创建时开放编辑
		if not col.get("create", false) and not Spec.has_path(entity, String(col.get("path", ""))):
			editable = false
	row.set_editable(col_index, editable)


## 单元格编辑提交（Tree.item_edited 触发）。
func commit_edit() -> void:
	var item := tree.get_edited()
	if item == null:
		return
	var col_index := tree.get_edited_column()
	var col: Dictionary = columns[col_index]
	var entity: Dictionary = item.get_meta("entity")
	var path: String = col.get("path", "")
	var text := item.get_text(col_index).strip_edges()
	var value = null
	match String(col.get("kind", "")):
		"int":
			if not text.is_valid_int():
				_repopulate_guard(item)
				return
			value = int(text)
			if col.has("min") and value < col["min"]:
				value = col["min"]
			if col.has("max") and value > col["max"]:
				value = col["max"]
		"float":
			if not text.is_valid_float():
				_repopulate_guard(item)
				return
			value = snappedf(float(text), 0.01)
		"enum":
			value = _match_enum(text, col)
			if value == null:
				_repopulate_guard(item)
				return
		_:
			value = text
	if col.get("omit_zero", false) and value is float and float(value) == 0.0:
		Spec.erase_path(entity, path)
	elif String(col.get("kind", "")) == "enum" and String(value) == "":
		Spec.erase_path(entity, path)
	elif col.has("omit_equals") and String(value) == String(col["omit_equals"]):
		Spec.erase_path(entity, path)
	else:
		Spec.write_path(entity, path, value)
	item.set_text(col_index, text)
	if on_edit.is_valid():
		on_edit.call(col)


func _repopulate_guard(_item: TreeItem) -> void:
	# 非法输入：从数据整表刷新（回弹原值）
	push_warning("表格输入非法，已回弹")
	_refill_texts()


func _refill_texts() -> void:
	var root := tree.get_root()
	if root == null:
		return
	var row := root.get_first_child()
	while row != null:
		var entity: Dictionary = row.get_meta("entity")
		for i in range(columns.size()):
			_fill_cell(row, i, columns[i], entity)
		row = row.get_next()


func _match_enum(text: String, col: Dictionary):
	var values: Array = col.get("enum_values", [])
	for v in values:
		var raw := String(v)
		if raw == text or Spec.enum_label(raw) == text:
			return raw
	if text == "" or text == "无":
		return ""
	return null


# ---- 列配置 ----

func _columns_for(p_kind: String) -> Array:
	match p_kind:
		"monster":
			return _monster_columns()
		"item":
			return _item_columns()
		"skill":
			return _skill_columns()
	return []


func _monster_columns() -> Array:
	var cols: Array = [
		{"title": "id", "path": "__id__", "kind": "string", "readonly": true, "width": 110},
		{"title": "名称", "kind": "name", "readonly": true, "width": 90},
		{"title": "气血", "path": "components.fighter.hp", "kind": "int", "min": 1, "max": 9999},
		{"title": "攻击", "path": "components.fighter.power", "kind": "int", "min": 0, "max": 999},
		{"title": "防御", "path": "components.fighter.defense", "kind": "int", "min": 0, "max": 99},
		{"title": "耗气", "path": "components.fighter.mp", "kind": "int", "min": 0, "max": 999, "create": true, "omit_zero": true, "width": 56},
		{"title": "经验", "path": "components.fighter.xp_reward", "kind": "int", "min": 0, "max": 9999, "create": true, "omit_zero": true},
	]
	var element_values: Array = Array(preload("res://scripts/core/content_db.gd").ELEMENTS).duplicate()
	element_values.append("")
	cols.append({"title": "五行", "path": "element", "kind": "enum", "enum_values": element_values, "create": true})
	var resist_labels := {"metal": "金抗", "wood": "木抗", "water": "水抗", "fire": "火抗", "earth": "土抗"}
	for resist_kind in preload("res://scripts/core/content_db.gd").RESIST_KINDS:
		var label: String = resist_labels.get(resist_kind, "%s抗" % Spec.enum_label(resist_kind))
		cols.append({
			"title": label, "path": "resistances.%s" % resist_kind, "kind": "int",
			"min": 0, "max": 80, "create": true, "omit_zero": true, "width": 56,
		})
	return cols


func _item_columns() -> Array:
	var slot_values: Array = Array(preload("res://scripts/core/content_db.gd").SLOT_ORDER).duplicate()
	var element_values: Array = Array(preload("res://scripts/core/content_db.gd").ELEMENTS).duplicate()
	element_values.append("")
	var rarity_values: Array = Array(preload("res://scripts/core/content_db.gd").RARITY_ORDER).duplicate()
	return [
		{"title": "id", "path": "__id__", "kind": "string", "readonly": true, "width": 110},
		{"title": "名称", "kind": "name", "readonly": true, "width": 100},
		{"title": "槽位", "path": "equipment.slot", "kind": "enum", "enum_values": slot_values, "width": 60},
		{"title": "品级", "path": "rarity", "kind": "enum", "enum_values": rarity_values, "create": true, "omit_equals": "common", "width": 88},
		{"title": "套装", "path": "set_id", "kind": "string", "create": true, "width": 70},
		{"title": "物伤", "path": "equipment.damage.physical", "kind": "int", "min": 1, "max": 99},
		{"title": "属性", "path": "equipment.damage.element", "kind": "enum", "enum_values": element_values},
		{"title": "加攻", "path": "equipment.bonuses.power", "kind": "int", "min": 0, "max": 99, "create": true, "omit_zero": true},
		{"title": "加防", "path": "equipment.bonuses.defense", "kind": "int", "min": 0, "max": 99, "create": true, "omit_zero": true},
		{"title": "加血", "path": "equipment.bonuses.max_hp", "kind": "int", "min": 0, "max": 99, "create": true, "omit_zero": true},
		{"title": "加气", "path": "equipment.bonuses.max_mp", "kind": "int", "min": 0, "max": 99, "create": true, "omit_zero": true},
		{"title": "加灵", "path": "equipment.bonuses.max_sp", "kind": "int", "min": 0, "max": 99, "create": true, "omit_zero": true},
		{"title": "品阶", "path": "tier", "kind": "int", "min": 1, "max": 9, "create": true},
	]


func _skill_columns() -> Array:
	return [
		{"title": "id", "path": "__id__", "kind": "string", "readonly": true, "width": 110},
		{"title": "名称", "kind": "name", "readonly": true, "width": 100},
		{"title": "职业", "path": "class", "kind": "string", "readonly": true, "width": 80},
		{"title": "槽位", "path": "slot", "kind": "int", "min": 1, "max": 8, "width": 50},
		{"title": "耗气", "path": "mp", "kind": "int", "min": 0, "max": 999, "width": 50},
		{"title": "行动点", "path": "cost", "kind": "int", "min": 1, "max": 2, "width": 50},
		{"title": "强度", "path": "effect.power", "kind": "int", "min": 1, "max": 99, "width": 50},
		{"title": "系数", "path": "effect.scale", "kind": "float", "width": 56},
	]
