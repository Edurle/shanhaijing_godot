extends SceneTree
## Headless 测试：godot --headless -s tests/test_editor.gd --path <工程>
## 覆盖编辑器数据层（json_store）与字段注册表（entity_spec）的核心不变式。
## 全程在 user:// 沙箱副本上进行，不触碰仓库真实数据。

const JsonStore := preload("res://scripts/editor/json_store.gd")
const EntitySpec := preload("res://scripts/editor/entity_spec.gd")

const SANDBOX := "user://editor_test_content"
const SOURCE := "res://data/content"

var failed := 0


func _init() -> void:
	_make_sandbox()
	var store := JsonStore.new()
	var errors: PackedStringArray = store.load_all(SANDBOX)
	failed += _check(errors.is_empty(), "沙箱加载应无错误: %s" % str(errors))

	_test_round_trip(store)
	_test_untouched_save(store)
	_test_change_detection(store)
	_test_validation_intercept(store)
	_test_save_success(store)
	_test_spec_registry(store)
	_test_editor_scene(store)
	_test_ui_save_flow(store)

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 编辑器数据层全部测试")
		quit(0)


func _make_sandbox() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SANDBOX))
	for file_name in DirAccess.get_files_at(SOURCE):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SOURCE.path_join(file_name)),
			ProjectSettings.globalize_path(SANDBOX.path_join(file_name))
		)
	var strings_to := ProjectSettings.globalize_path(SANDBOX.path_join("strings"))
	DirAccess.make_dir_recursive_absolute(strings_to)
	for file_name in DirAccess.get_files_at(SOURCE.path_join("strings")):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SOURCE.path_join("strings").path_join(file_name)),
			strings_to.path_join(file_name)
		)


## 序列化不弄脏 diff：未改动时输出应与原文件字节一致（crafting 源含 1.0 写法，允许文本差异但语义等价）。
func _test_round_trip(store) -> void:
	var byte_perfect := 0
	for file_key in ["monsters", "items", "classes", "skills", "player", "spawn_tables"]:
		var original := FileAccess.get_file_as_string(SANDBOX.path_join("%s.json" % file_key))
		if store.serialize(file_key) == original:
			byte_perfect += 1
		else:
			print("FAIL round-trip 不一致: %s" % file_key)
	failed += _check(byte_perfect == 6, "6 个数据文件 round-trip 字节一致（实际 %d）" % byte_perfect)
	failed += _check(not store.is_file_changed("crafting"), "crafting 未改动时语义等价")
	failed += _check(not store.is_dirty(), "刚加载完不应有未保存修改")


## 未改动时保存：校验通过、零文件写盘。
func _test_untouched_save(store) -> void:
	var result: Array = store.save_all()
	failed += _check((result[0] as PackedStringArray).is_empty(), "原样保存校验应通过: %s" % str(result[0]))
	failed += _check(int(result[1]) == 0, "原样保存不应写任何文件（实际 %d）" % int(result[1]))


## 语义级变更检测：改了才算，改回即净。
func _test_change_detection(store) -> void:
	var monsters: Dictionary = store.file_data("monsters")
	var first_id := JsonStore.entity_ids(monsters)[0]
	var old_hp = monsters[first_id]["components"]["fighter"]["hp"]
	monsters[first_id]["components"]["fighter"]["hp"] = int(old_hp) + 5
	failed += _check(store.is_file_changed("monsters"), "改 hp 后应判定变更")
	monsters[first_id]["components"]["fighter"]["hp"] = old_hp
	failed += _check(not store.is_file_changed("monsters"), "改回原值应判定未变更")
	# 类型变化但数值等值（int/float）不算变更
	monsters[first_id]["components"]["fighter"]["hp"] = float(old_hp)
	failed += _check(not store.is_file_changed("monsters"), "int/float 等值不算变更")


## 非法数据必须被拦下：校验失败时不写盘、原文件完好。
func _test_validation_intercept(store) -> void:
	var monsters: Dictionary = store.file_data("monsters")
	var first_id := JsonStore.entity_ids(monsters)[0]
	monsters[first_id]["resistances"] = {"fire": 100}
	var before := FileAccess.get_file_as_string(SANDBOX.path_join("monsters.json"))
	var result: Array = store.save_all()
	var errors: PackedStringArray = result[0]
	var intercepted := false
	for e in errors:
		if e.contains("超出"):
			intercepted = true
	failed += _check(intercepted, "抗性 100 应被校验拦截: %s" % str(errors))
	failed += _check(FileAccess.get_file_as_string(SANDBOX.path_join("monsters.json")) == before, "拦截时磁盘文件不得被写")
	# 复原
	monsters[first_id].erase("resistances")


## 合法修改落盘：写后干净、内容正确、脏标记清除。
func _test_save_success(store) -> void:
	var monsters: Dictionary = store.file_data("monsters")
	var first_id := JsonStore.entity_ids(monsters)[0]
	var old_power: int = monsters[first_id]["components"]["fighter"]["power"]
	monsters[first_id]["components"]["fighter"]["power"] = old_power + 1
	var result: Array = store.save_all()
	failed += _check((result[0] as PackedStringArray).is_empty(), "合法保存应通过校验: %s" % str(result[0]))
	failed += _check(int(result[1]) == 1, "应恰好写 1 个文件（实际 %d）" % int(result[1]))
	var on_disk := FileAccess.get_file_as_string(SANDBOX.path_join("monsters.json"))
	failed += _check(on_disk == store.serialize("monsters"), "落盘内容应与序列化一致")
	failed += _check(on_disk.contains("\"power\": %d" % (old_power + 1)), "落盘应含新数值")
	failed += _check(not on_disk.contains(".0,"), "落盘不应出现规整遗漏的 .0")
	failed += _check(not store.is_dirty(), "保存后不应再有脏标记")
	# 写回后再次原样保存应零写盘（_raw 基线已更新）
	var again: Array = store.save_all()
	failed += _check(int(again[1]) == 0, "保存后的原样保存应零写盘")


## 字段注册表：路径可解析、类型合法、枚举与 ContentDb 常量一致、引用扫描正确。
func _test_spec_registry(store) -> void:
	# 1. 每种实体的每个字段路径至少被一个现有实体命中（防止 spec 漂移）
	for entity_type in EntitySpec.TYPES:
		var fields: Array = EntitySpec.fields_for(entity_type)
		var sample: Array = _sample_entities(store, entity_type)
		failed += _check(not sample.is_empty(), "%s 应有样本实体" % entity_type)
		for field in fields:
			if field.get("optional", false):
				continue
			var hit := false
			for entity in sample:
				if EntitySpec.read_path(entity, String(field["key"])) != null:
					hit = true
					break
			if not hit:
				print("FAIL 字段无样本命中: %s.%s" % [entity_type, field["key"]])
			failed += _check(hit, "%s 的字段 %s 应至少被一个实体使用" % [entity_type, field["key"]])

	# 2. 技能/消耗品效果参数表覆盖全部已注册类型
	var effect_types: PackedStringArray = preload("res://scripts/core/content_db.gd").SKILL_EFFECT_TYPES
	for eff_type in effect_types:
		failed += _check(
			EntitySpec.EFFECT_PARAMS.has(eff_type),
			"技能效果 %s 应有参数表" % eff_type
		)
	var consumable_types := [
		"heal", "heal_mp", "cleanse", "buff_item", "lightning",
		"knockback", "stun_area", "smoke", "tianshu",
	]
	for ctype in consumable_types:
		failed += _check(
			EntitySpec.CONSUMABLE_PARAMS.has(ctype),
			"消耗品效果 %s 应有参数表" % ctype
		)

	# 3. 引用扫描：已知被引用的 id 必须报出处，无引用的 id 必须放行
	var spawn_monster_id := String(store.file_data("spawn_tables")["monsters"][0]["id"])
	var refs: PackedStringArray = EntitySpec.find_references(store.data, spawn_monster_id)
	failed += _check(
		_refs_has_spawn(refs),
		"投放表中的怪 %s 应被扫描到" % spawn_monster_id
	)
	var refs_none := EntitySpec.find_references(store.data, "id_that_never_exists_42")
	failed += _check(refs_none.is_empty(), "不存在的 id 引用扫描应为空")


	# 4. 新建模板合法：交给 ContentDb 校验应能通过基本结构（字段路径齐全）
	var template_monster: Dictionary = EntitySpec.new_entity_template("monster")
	failed += _check(
		EntitySpec.read_path(template_monster, "components.fighter.hp") != null,
		"怪物新建模板应含 fighter.hp"
	)


func _sample_entities(store, entity_type: String) -> Array:
	var out: Array = []
	match entity_type:
		"monster":
			for id in JsonStore.entity_ids(store.file_data("monsters")):
				out.append(store.file_data("monsters")[id])
		"class":
			for id in JsonStore.entity_ids(store.file_data("classes")):
				out.append(store.file_data("classes")[id])
		"player":
			out.append(store.file_data("player"))
		"skill":
			for id in JsonStore.entity_ids(store.file_data("skills")):
				out.append(store.file_data("skills")[id])
		"item_weapon":
			for id in JsonStore.entity_ids(store.file_data("items")):
				var idef: Dictionary = store.file_data("items")[id]
				if idef.get("equipment", {}).get("slot", "") == "weapon":
					out.append(idef)
		"item_gear":
			for id in JsonStore.entity_ids(store.file_data("items")):
				var idef: Dictionary = store.file_data("items")[id]
				var slot: String = idef.get("equipment", {}).get("slot", "")
				if idef.has("equipment") and slot != "weapon":
					out.append(idef)
		"item_consumable":
			for id in JsonStore.entity_ids(store.file_data("items")):
				var idef: Dictionary = store.file_data("items")[id]
				if idef.has("consumable"):
					out.append(idef)
		"item_material":
			for id in JsonStore.entity_ids(store.file_data("items")):
				var idef: Dictionary = store.file_data("items")[id]
				if (idef.get("tags", []) as Array).has("material"):
					out.append(idef)
	return out


func _refs_has_spawn(refs: PackedStringArray) -> bool:
	for r in refs:
		if r.contains("投放"):
			return true
	return false


## 编辑器场景实例化冒烟：六个页签全部构建、表单/表格/面板非空、经 UI 修改数据后脏标记生效。
func _test_editor_scene(_store) -> void:
	var packed: PackedScene = load("res://scenes/data_editor.tscn")
	if packed == null:
		print("FAIL 无法加载 data_editor.tscn")
		quit(1)
		return
	var editor = packed.instantiate()
	root.add_child(editor)
	if editor.form_box == null:
		# headless -s 模式下 add_child 不触发 NOTIFICATION_READY，手动初始化
		editor._ready()
	# 页签逐一构建（怪物页签在 _ready 里已建）
	var tab_expectations := {
		0: "怪物", 1: "物品", 2: "技能", 3: "职业·玩家", 4: "投放", 5: "炼制",
	}
	for tab_index in [1, 2, 3, 4, 5, 0]:
		editor._select_tab(tab_index)
		var kind_name: String = tab_expectations[tab_index]
		var has_content: bool = editor.form_box.get_child_count() > 0
		failed += _check(has_content, "%s 页签应生成内容控件" % kind_name)
	# 怪物表单应有分组与行控件
	editor._select_tab(0)
	var monster_form_rows := 0
	for child in editor.form_box.get_children():
		if child is HBoxContainer:
			monster_form_rows += 1
	failed += _check(monster_form_rows >= 10, "怪物表单应 ≥10 行（实际 %d）" % monster_form_rows)
	# 选中第一只怪，经 UI 数据路径改数值 → 脏标记出现
	var first_entry: Dictionary = editor.entity_list.get_item_metadata(0)
	editor.current_id = String(first_entry["id"])
	editor._show_current_form()
	var entity: Dictionary = editor._current_entity()
	var hp_path: Dictionary = entity["components"]["fighter"]
	var old_hp = hp_path["hp"]
	hp_path["hp"] = int(old_hp) + 1
	failed += _check(editor.store.is_dirty(), "经编辑器改 hp 后应出现脏标记")
	hp_path["hp"] = old_hp
	failed += _check(not editor.store.is_dirty(), "改回后脏标记应消失")
	# 表格视图：怪物/装备/技能三种列配置填充行
	for tab_index in [0, 1, 2]:
		editor._select_tab(tab_index)
		editor.view_toggle.button_pressed = true
		editor._on_toggle_grid()
		var row: TreeItem = editor.grid_tree.get_root().get_first_child() if editor.grid_tree.get_root() != null else null
		failed += _check(row != null, "页签 %d 表格应有数据行" % tab_index)
		editor.view_toggle.button_pressed = false
		editor._on_toggle_grid()
	# 炼制页选中第一个配方 → 配方表单生成（含 struct_list 行与引用下拉）
	editor._select_tab(5)
	if editor.spawn_craft.recipe_list.item_count > 0:
		editor.spawn_craft.recipe_list.select(0)
		editor.spawn_craft.recipe_list.item_selected.emit(0)
		var recipe_rows: int = editor.spawn_craft.recipe_form_box.get_child_count()
		failed += _check(recipe_rows >= 4, "配方表单应生成多行（实际 %d）" % recipe_rows)
	# 引用扫描阻断：删除投放表中的怪应创建「无法删除」对话框
	# （headless 下 popup_centered 因未入树而失败，故只断言对话框已创建）
	editor._select_tab(0)
	editor.current_id = String(editor.store.file_data("spawn_tables")["monsters"][0]["id"])
	editor._on_delete_entity()
	var blocking_dialogs := 0
	for child in editor.get_children():
		if child is AcceptDialog:
			blocking_dialogs += 1
	failed += _check(blocking_dialogs == 1, "删除被引用怪应弹阻止对话框（实际 %d）" % blocking_dialogs)
	for child in editor.get_children():
		if child is AcceptDialog:
			child.queue_free()
	editor.queue_free()


## 端到端：真实控件操作（SpinBox 提交）→ 保存 → 校验 → 沙箱落盘；真实数据零接触。
func _test_ui_save_flow(_store) -> void:
	var packed: PackedScene = load("res://scenes/data_editor.tscn")
	var editor = packed.instantiate()
	root.add_child(editor)
	if editor.form_box == null:
		editor._ready()
	# 换成沙箱数据源，确保写盘不碰仓库
	var sandbox_store := JsonStore.new()
	var load_errors: PackedStringArray = sandbox_store.load_all(SANDBOX)
	failed += _check(load_errors.is_empty(), "沙箱数据源加载: %s" % str(load_errors))
	editor.store = sandbox_store
	editor._select_tab(0)
	editor._rebuild_enum_context()
	# 找到「气血」行的 SpinBox，模拟用户改值（触发 value_changed → 提交回数据）
	var hp_spin: SpinBox = null
	var first_id := ""
	for i in range(editor.entity_list.item_count):
		var entry: Dictionary = editor.entity_list.get_item_metadata(i)
		first_id = String(entry["id"])
		break
	editor.current_id = first_id
	editor._show_current_form()
	for row in editor.form_box.get_children():
		if row is HBoxContainer and row.get_child_count() >= 2 and row.get_child(0) is Label:
			if (row.get_child(0) as Label).text == "气血" and row.get_child(1) is SpinBox:
				hp_spin = row.get_child(1)
				break
	failed += _check(hp_spin != null, "表单应含「气血」SpinBox")
	if hp_spin != null:
		# 4.6 程序化赋值不发 value_changed，显式补发以模拟用户操作
		hp_spin.value = 4242.0
		hp_spin.value_changed.emit(4242.0)
		var entity: Dictionary = sandbox_store.file_data("monsters")[first_id]
		failed += _check(int(entity["components"]["fighter"]["hp"]) == 4242, "SpinBox 提交应写回数据")
		failed += _check(sandbox_store.is_dirty(), "改值后应有脏标记")
		editor._on_save()
		var on_disk := FileAccess.get_file_as_string(SANDBOX.path_join("monsters.json"))
		failed += _check(on_disk.contains("\"hp\": 4242"), "保存后沙箱文件应含新数值")
		failed += _check(not sandbox_store.is_dirty(), "保存后脏标记应清除")
	# 真实仓库数据必须零接触
	var real_text := FileAccess.get_file_as_string("res://data/content/monsters.json")
	failed += _check(not real_text.contains("\"hp\": 4242"), "真实数据文件不得被测试写入")
	editor.queue_free()


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
