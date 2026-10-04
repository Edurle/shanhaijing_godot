extends Node2D
## 主场景：内容库 → 世界状态机 → 回合引擎 → 视图。
## 阶段 3：碰撞攻击/怪物回合/DOT 与状态结算/技能施放（1-8 调试键自动瞄准）。
## E=踏入/深入，Q=回返；阶段 4 换正式 UI（瞄准/行囊/参悟/侧栏）。

const CoreContentDb := preload("res://scripts/core/content_db.gd")
const CoreWorldState := preload("res://scripts/core/world_state.gd")
const CoreTurnEngine := preload("res://scripts/core/turn_engine.gd")
const ViewBoard := preload("res://scripts/view/board.gd")

const DEV_AUTO_LEARN := true  # 阶段 3 调试：主职业技能全解锁，阶段 4 换参悟菜单

var content: CoreContentDb
var state: CoreWorldState
var engine: CoreTurnEngine
var board: ViewBoard
var camera: Camera2D
var hud: Label
var log_label: Label


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
	engine = CoreTurnEngine.new(state, content)
	if DEV_AUTO_LEARN:
		for skill in content.skills_for_class(state.player.class_ids[0]):
			state.player.skill_levels[skill["id"]] = 1

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
	log_label = Label.new()
	log_label.position = Vector2(12, 36)
	log_label.add_theme_font_size_override("font_size", 15)
	log_label.custom_minimum_size = Vector2(600, 90)
	add_child(log_label)

	_center_camera()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_UP, KEY_W:
				_act(engine.player_step(Vector2i(0, -1)))
			KEY_DOWN, KEY_S:
				_act(engine.player_step(Vector2i(0, 1)))
			KEY_LEFT, KEY_A:
				_act(engine.player_step(Vector2i(-1, 0)))
			KEY_RIGHT, KEY_D:
				_act(engine.player_step(Vector2i(1, 0)))
			KEY_E:
				_interact_down()
			KEY_Q:
				_interact_up()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				var slot: int = event.keycode - KEY_0
				_act(_cast_slot(slot))


func _cast_slot(slot: int) -> bool:
	var error := engine.execute_skill(slot)
	if not error.is_empty() and error != "need_target":
		engine.log_message(error, "warn")
		_refresh()
		return false
	return error.is_empty()


func _act(acted: bool) -> void:
	if acted:
		_refresh()


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
	if xy == state.current.downstairs_xy:
		state.next_floor()
		engine.update_fov()
		_after_map_switch()


## Q：秘境第 1 层上行山径 → 回世界；更深层 → 回上层。
func _interact_up() -> void:
	if state.current.map_type != "realm":
		return
	if state.player_xy() == state.current.upstairs_xy:
		state.previous_floor()
		engine.update_fov()
		_after_map_switch()


func _after_map_switch() -> void:
	_bind_map()
	_center_camera()
	_refresh()


func _bind_map() -> void:
	board.setup(state.current, state.player)
	board.queue_redraw()


func _center_camera() -> void:
	camera.position = Vector2(
		(state.player.x + 0.5) * ViewBoard.CELL,
		(state.player.y + 0.5) * ViewBoard.CELL
	)


func _refresh() -> void:
	_center_camera()
	var fighter := state.player.fighter
	var hp_bar := _bar(fighter.hp(), fighter.max_hp(), 12)
	var mp_text := "真气 %d/%d" % [fighter.mp(), fighter.max_mp()]
	if fighter.max_sp() > 0:
		mp_text += "  灵力 %d/%d" % [fighter.sp(), fighter.max_sp()]
	hud.text = "%s ｜ %s%s ｜ %s ｜ %s ｜ 修为 %d" % [
		state.player.label, hp_bar, mp_text,
		state.location_name(), "第 %d 回合" % engine.turn_count,
		state.player.level.current_level if state.player.level != null else 1,
	]
	if engine.game_over:
		hud.text += "  ｜ ★ 行者陨落 ★"
	var recent: Array = engine.messages.slice(maxi(0, engine.messages.size() - 4), engine.messages.size())
	var lines: Array = []
	for msg in recent:
		lines.append(String(msg["text"]))
	log_label.text = "\n".join(lines)
	engine.events.clear()
	board.queue_redraw()


func _bar(value: int, limit: int, width: int) -> String:
	var filled := roundi(width * value / maxf(1.0, limit))
	return "气血 [" + "■".repeat(filled) + "·".repeat(width - filled) + "] %d/%d  " % [value, limit]
