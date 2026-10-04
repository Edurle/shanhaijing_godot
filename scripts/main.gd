extends Node2D
## 主场景：组装内容库 → 地图模型 → 视图（阶段 1 骨架：移动/视野/相机/HUD）。
## 回合结算、战斗、异兽 AI 在阶段 3 接入；输入映射阶段 4 迁入 project.godot。

const CoreContentDb := preload("res://scripts/core/content_db.gd")
const CoreGameMap := preload("res://scripts/core/game_map.gd")
const CoreWorldGen := preload("res://scripts/core/worldgen.gd")
const ViewBoard := preload("res://scripts/view/board.gd")

var content: CoreContentDb
var map: CoreGameMap
var board: ViewBoard
var camera: Camera2D
var hud: Label
var player := {"x": 0, "y": 0, "is_player": true}
var actors: Array = []


func _ready() -> void:
	content = CoreContentDb.new()
	var errors := content.load_all("res://data/content")
	if not errors.is_empty():
		push_error("内容校验失败 %d 项：\n%s" % [errors.size(), "\n".join(errors)])
		get_tree().quit(1)
		return
	map = CoreWorldGen.make_test_map()
	player["x"] = map.width / 2
	player["y"] = map.height / 2
	_spawn_demo_beasts()

	board = ViewBoard.new()
	board.setup(map)
	add_child(board)
	_refresh_actors()

	camera = Camera2D.new()
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 16)
	add_child(hud)

	map.compute_fov(player["x"], player["y"])
	_center_camera()
	_update_hud()
	board.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var delta := Vector2i.ZERO
		match event.keycode:
			KEY_UP, KEY_W:
				delta = Vector2i(0, -1)
			KEY_DOWN, KEY_S:
				delta = Vector2i(0, 1)
			KEY_LEFT, KEY_A:
				delta = Vector2i(-1, 0)
			KEY_RIGHT, KEY_D:
				delta = Vector2i(1, 0)
			_:
				return
		_try_step(delta)


func _try_step(delta: Vector2i) -> void:
	var dest: Vector2i = Vector2i(player["x"], player["y"]) + delta
	if map.is_walkable(dest.x, dest.y):
		player["x"] = dest.x
		player["y"] = dest.y
		map.compute_fov(player["x"], player["y"])
		_center_camera()
		_update_hud()
		board.queue_redraw()


func _center_camera() -> void:
	camera.position = Vector2(
		(player["x"] + 0.5) * ViewBoard.CELL,
		(player["y"] + 0.5) * ViewBoard.CELL
	)


func _update_hud() -> void:
	var walked := 0
	for x in range(map.width):
		for y in range(map.height):
			if map.is_explored(x, y):
				walked += 1
	hud.text = "山海行 · 水墨 ｜ 行者 (%d, %d) ｜ 已览 %d/%d" % [
		player["x"], player["y"], walked, map.width * map.height
	]


## 阶段 1 演示：从内容库取两只异兽放置在出生点旁，验证 数据→模型→视图 管线。
func _spawn_demo_beasts() -> void:
	for pair in [["xingxing", 4, -2], ["bifang", -4, 3]]:
		var mid: String = pair[0]
		if not content.monsters.has(mid):
			continue
		var mdef: Dictionary = content.monsters[mid]
		actors.append({
			"x": player["x"] + pair[1],
			"y": player["y"] + pair[2],
			"element": mdef.get("element", ""),
			"label": content.localize(mdef["name"]),
		})


func _refresh_actors() -> void:
	board.actors = [player] + actors
