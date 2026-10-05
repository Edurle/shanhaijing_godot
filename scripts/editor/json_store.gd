extends RefCounted
## 编辑器 JSON 存取层：保序加载、最小 diff 保存（临时目录 + ContentDb 校验 + 只重写实际变更的文件）。
## 仅数据编辑器场景使用——游戏侧零引用，导出预设里按 scripts/editor/* 排除。

const ContentDbScript := preload("res://scripts/core/content_db.gd")

## 编辑器可编辑的 content 文件；其余文件校验时按原样拷贝。
const EDITABLE_FILES: PackedStringArray = [
	"monsters", "items", "sets", "classes", "skills", "player", "spawn_tables", "crafting",
]
const COPY_FILES: PackedStringArray = ["theme", "regions", "realms"]

const CHECK_DIR := "user://editor_check"

var base_dir := ""
var _raw: Dictionary = {}    # file -> 原始文本（保存时对齐行尾/结尾换行的基线）
var _use_crlf: Dictionary = {}  # file -> 是否以 CRLF 为主（按多数派行尾判定，容忍个别混杂）
var _orig: Dictionary = {}   # file -> 解析出的原始数据（语义比对基线，判"是否真的改了"）
var data: Dictionary = {}    # file -> 当前编辑数据（_schema 说明键原样保留）


## 加载目录下全部相关 JSON；返回错误清单（空 = 通过）。
func load_all(p_base_dir: String) -> PackedStringArray:
	base_dir = p_base_dir
	_raw.clear()
	_use_crlf.clear()
	_orig.clear()
	data.clear()
	var errors := PackedStringArray()
	for file_key in EDITABLE_FILES:
		var path := base_dir.path_join("%s.json" % file_key)
		var errors_of_file := _load_one(path, file_key)
		errors.append_array(errors_of_file)
	return errors


func _load_one(path: String, file_key: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(path):
		errors.append("缺少文件: %s" % path)
		return errors
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		errors.append("JSON 解析失败: %s" % path)
		return errors
	_raw[file_key] = text
	_orig[file_key] = parsed
	data[file_key] = parsed.duplicate(true)
	# 行尾按多数派判定：Godot IDE 等工具偶尔会把整文件另存为另一行尾，
	# 与 autocrlf 叠加后 git 无感知，逐字节对齐原文件即可保持 diff 干净
	var total_lf := text.count("\n")
	_use_crlf[file_key] = total_lf > 0 and text.count("\r\n") * 2 >= total_lf
	return errors


func file_data(file_key: String) -> Dictionary:
	return data.get(file_key, {})


## 语义级变更判定：与原始解析比对（int/float 等值视为相同），避免格式规整弄脏 diff。
func is_file_changed(file_key: String) -> bool:
	if not _orig.has(file_key):
		return false
	return not (data[file_key] == _orig[file_key])


func is_dirty() -> bool:
	for file_key in EDITABLE_FILES:
		if is_file_changed(file_key):
			return true
	return false


func changed_file_count() -> int:
	var count := 0
	for file_key in EDITABLE_FILES:
		if is_file_changed(file_key):
			count += 1
	return count


## 丢弃全部未保存修改。
func reload_all() -> void:
	for file_key in _orig:
		data[file_key] = (_orig[file_key] as Dictionary).duplicate(true)


## 序列化当前数据：2 空格缩进、整数值 float 规整为 int、行尾按多数派、结尾换行对齐原文件。
func serialize(file_key: String) -> String:
	var out := JSON.stringify(_normalize_numbers(data[file_key]), "  ", false, false)
	if _raw[file_key].ends_with("\n"):
		out += "\n"
	if _use_crlf.get(file_key, false):
		out = out.replace("\n", "\r\n")
	return out


func _normalize_numbers(value):
	if value is float:
		if value == floor(value) and abs(value) < 1e15:
			return int(value)
		return value
	if value is Array:
		var out_arr := []
		for element in value:
			out_arr.append(_normalize_numbers(element))
		return out_arr
	if value is Dictionary:
		var out_dict := {}
		for key in value:
			out_dict[key] = _normalize_numbers(value[key])
		return out_dict
	return value


## 校验当前数据（不写盘）：全部文件落到临时目录，跑 ContentDb.load_all 的完整校验。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHECK_DIR))
	for file_key in COPY_FILES:
		var from := ProjectSettings.globalize_path(base_dir.path_join("%s.json" % file_key))
		var to := ProjectSettings.globalize_path(CHECK_DIR.path_join("%s.json" % file_key))
		if DirAccess.copy_absolute(from, to) != OK:
			errors.append("无法拷贝校验文件: %s" % from)
	var strings_from := ProjectSettings.globalize_path(base_dir.path_join("strings"))
	var strings_to := ProjectSettings.globalize_path(CHECK_DIR.path_join("strings"))
	DirAccess.make_dir_recursive_absolute(strings_to)
	for file_name in DirAccess.get_files_at(strings_from):
		DirAccess.copy_absolute(strings_from.path_join(file_name), strings_to.path_join(file_name))
	if not errors.is_empty():
		return errors
	for file_key in EDITABLE_FILES:
		var writer := FileAccess.open(CHECK_DIR.path_join("%s.json" % file_key), FileAccess.WRITE)
		if writer == null:
			errors.append("无法写入临时校验文件: %s" % file_key)
			return errors
		writer.store_string(serialize(file_key))
	if not errors.is_empty():
		return errors
	var probe := ContentDbScript.new()
	errors.append_array(probe.load_all(CHECK_DIR))
	return errors


## 保存：先校验，通过后只重写"数据实际变更"的文件；返回错误清单（空 = 已保存）。
## 返回值第二项为实际写盘的文件数（通过 Array 单元素传出，便于调用方展示）。
func save_all() -> Array:
	var errors := validate()
	if not errors.is_empty():
		return [errors, 0]
	var written := 0
	for file_key in EDITABLE_FILES:
		if not is_file_changed(file_key):
			continue
		var path := base_dir.path_join("%s.json" % file_key)
		var text := serialize(file_key)
		if text == _raw[file_key]:
			continue
		var global_path := ProjectSettings.globalize_path(path)
		var tmp_path := global_path + ".tmp"
		var writer := FileAccess.open(tmp_path, FileAccess.WRITE)
		if writer == null:
			errors.append("无法写入临时文件: %s" % tmp_path)
			continue
		writer.store_string(text)
		writer.flush()
		var copy_err := DirAccess.copy_absolute(tmp_path, global_path, true)
		DirAccess.remove_absolute(tmp_path)
		if copy_err != OK:
			errors.append("覆盖失败: %s" % path)
			continue
		_raw[file_key] = text
		_orig[file_key] = (data[file_key] as Dictionary).duplicate(true)
		written += 1
	return [errors, written]


## 文件级实体 id 清单（跳过 _ 前缀说明键）。
static func entity_ids(file_data: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	for key in file_data:
		if not String(key).begins_with("_"):
			ids.append(String(key))
	return ids
