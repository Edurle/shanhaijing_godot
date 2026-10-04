extends Node2D
## 主场景：组装内容库 → 世界状态机 → 视图。
## 阶段 2：大世界/秘境进出、层间移动、门与山径交互（E=踏入/下行，Q=上行/回世界）。
## 回合结算与战斗在阶段 3 接入；输入映射阶段 4 迁入 project.godot。

const CoreContentDb := preload("res://scripts/core/content_db.gd")
const CoreWorldState := preload("res://scripts/core/world_state.gd")
const ViewBoard := preload("res://scripts/view/board.gd")

var content: CoreContentDb
var state: CoreWorldState
var board: ViewBoard
var camera: Camera2D
var hud: Label
var world_beasts: Array = []  # 大世界演示异兽（阶段 3 换正式实体模型）


func _ready() -> void:
	content = CoreContentDb.new()
	var errors := content.load_all("res://data/content")
	if not errors.is_empty():
		push_error("内容校验失败 %d 项：\n%s" % [errors.size(), "\n".join(errors)])
		get_tree().quit(1)
		return
	state = CoreWorldState.new()
	state.content = content
	var gen_error := state.generate_new_world()
	if not gen_error.is_empty():
		push_error("世界生成失败：%s" % gen_error)
		get_tree().quit(1)
		return
	_spawn_demo_beasts()

	board = ViewBoard.new()
	add_child(board)
	_bind_map()

	camera = Camera2D.new()
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 16)
	add_child(hud)

	_center_camera()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_UP, KEY_W:
				_try_step(Vector2i(0, -1))
			KEY_DOWN, KEY_S:
				_try_step(Vector2i(0, 1))
			KEY_LEFT, KEY_A:
				_try_step(Vector2i(-1, 0))
			KEY_RIGHT, KEY_D:
				_try_step(Vector2i(1, 0))
			KEY_E:
				_interact_down()
			KEY_Q:
				_interact_up()


func _try_step(delta: Vector2i) -> void:
	var dest: Vector2i = state.player_xy() + delta
	if state.current.is_walkable(dest.x, dest.y):
		state.player["x"] = dest.x
		state.player["y"] = dest.y
		state.current.compute_fov(dest.x, dest.y)
		_center_camera()
		_update_hud()
		board.queue_redraw()


## E：站在秘境门上 → 踏入；站在下行山径上 → 深入一层。
func _interact_down() -> void:
	var xy := state.player_xy()
	if state.current.map_type == "world":
		var gate := state.current.gate_at(xy.x, xy.y)
		if not gate.is_empty():
			state.known_gates[xy] = true
			state.enter_realm(String(gate["realm_id"]), xy)
			_after_map_switch()
			return
		return
	if xy == state.current.downstairs_xy:
		state.next_floor()
		_after_map_switch()


## Q：秘境第 1 层上行山径 → 回世界；更深层 → 回上层。
func _interact_up() -> void:
	if state.current.map_type != "realm":
		return
	if state.player_xy() == state.current.upstairs_xy:
		state.previous_floor()
		_after_map_switch()


func _after_map_switch() -> void:
	_bind_map()
	_center_camera()
	_update_hud()


## 地图切换后重挂视图：换地图引用并重建演员清单。
func _bind_map() -> void:
	board.setup(state.current)
	if state.current.map_type == "world":
		board.actors = [state.player] + world_beasts
	else:
		board.actors = [state.player]
	board.queue_redraw()


func _center_camera() -> void:
	camera.position = Vector2(
		(state.player["x"] + 0.5) * ViewBoard.CELL,
		(state.player["y"] + 0.5) * ViewBoard.CELL
	)


func _update_hud() -> void:
	var walked := 0
	for i in range(state.current.explored.size()):
		walked += state.current.explored[i]
	var hint := "E 踏入/深入 ｜ Q 回返" if state.current.map_type == "realm" or not state.current.gate_at(state.player["x"], state.player["y"]).is_empty() else "WASD/方向键 移动"
	hud.text = "山海行 · 水墨 ｜ %s ｜ 行者 (%d, %d) ｜ 已览 %d/%d ｜ %s" % [
		state.location_name(), state.player["x"], state.player["y"],
		walked, state.current.width * state.current.height, hint,
	]


## 阶段 2 演示：从内容库取两只异兽放置在出生点旁，验证 数据→模型→视图 管线。
func _spawn_demo_beasts() -> void:
	for pair in [["xingxing", 4, -2], ["bifang", -4, 3]]:
		var mid: String = pair[0]
		if not content.monsters.has(mid):
			continue
		var mdef: Dictionary = content.monsters[mid]
		world_beasts.append({
			"x": state.world.spawn_xy.x + pair[1],
			"y": state.world.spawn_xy.y + pair[2],
			"element": mdef.get("element", ""),
		})
