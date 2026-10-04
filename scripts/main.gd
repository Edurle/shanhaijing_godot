extends Node2D
## 主场景：内容库 → 世界状态机 → 回合引擎 → 棋盘 + 水墨 UI。
## 模式状态机：职业选择 / 游历 / 行囊 / 参悟 / 查看 / 瞄准 / 择向。
## E=踏入/深入，Q=回返；阶段 5 前保持程序化水墨占位视觉。

const CoreContentDb := preload("res://scripts/core/content_db.gd")
const CoreWorldState := preload("res://scripts/core/world_state.gd")
const CoreTurnEngine := preload("res://scripts/core/turn_engine.gd")
const ViewBoard := preload("res://scripts/view/board.gd")
const UiSidebarScript := preload("res://scripts/view/ui/sidebar.gd")
const UiLogScript := preload("res://scripts/view/ui/log_panel.gd")
const UiTargetInfoScript := preload("res://scripts/view/ui/target_info.gd")
const MenuClassSelect := preload("res://scripts/view/ui/menu_class_select.gd")
const MenuInventory := preload("res://scripts/view/ui/menu_inventory.gd")
const MenuLearn := preload("res://scripts/view/ui/menu_learn.gd")
const MenuExamine := preload("res://scripts/view/ui/menu_examine.gd")

enum Mode { CLASS_SELECT, PLAY, INVENTORY, LEARN, EXAMINE, TARGETING, DIRECTION }

var content: CoreContentDb
var state: CoreWorldState
var engine: CoreTurnEngine
var board: ViewBoard
var camera: Camera2D
var ui: CanvasLayer
var sidebar
var log_panel
var target_info
var menu_class: MenuClassSelect
var menu_inventory: MenuInventory
var menu_learn: MenuLearn
var menu_examine: MenuExamine
var mode := Mode.CLASS_SELECT

# 瞄准/择向的进行中技能
var pending_skill: Dictionary = {}
var target_candidates: Array = []
var target_index := 0
var dir_delta := Vector2i.ZERO


func _ready() -> void:
	content = CoreContentDb.new()
	var errors := content.load_all("res://data/content")
	if not errors.is_empty():
		push_error("内容校验失败 %d 项：\n%s" % [errors.size(), "\n".join(errors)])
		get_tree().quit(1)
		return

	board = ViewBoard.new()
	add_child(board)
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

	ui = CanvasLayer.new()
	add_child(ui)
	sidebar = UiSidebarScript.new()
	log_panel = UiLogScript.new()
	target_info = UiTargetInfoScript.new()
	menu_class = MenuClassSelect.new()
	menu_inventory = MenuInventory.new()
	menu_learn = MenuLearn.new()
	menu_examine = MenuExamine.new()
	for panel in [sidebar, log_panel, target_info, menu_class, menu_inventory, menu_learn, menu_examine]:
		ui.add_child(panel)
	target_info.hide_panel()
	for panel in [sidebar, log_panel, menu_inventory, menu_learn, menu_examine]:
		panel.visible = false

	menu_class.setup_menu(content)
	menu_class.open()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		_dispatch(event.keycode)


func _dispatch(keycode: int) -> void:
	match mode:
		Mode.CLASS_SELECT:
			menu_class.handle_key(keycode)
			if menu_class.done:
				_start_game([menu_class.picked_primary, menu_class.picked_secondary])
		Mode.PLAY:
			_handle_play(keycode)
		Mode.INVENTORY:
			menu_inventory.handle_key(keycode)
			if not menu_inventory.visible:
				_set_mode(Mode.PLAY)
			_refresh()
		Mode.LEARN:
			menu_learn.handle_key(keycode)
			if not menu_learn.visible:
				_set_mode(Mode.PLAY)
			_refresh()
		Mode.EXAMINE:
			menu_examine.handle_key(keycode)
			if not menu_examine.visible:
				board.target_cell = Vector2i(-1, -1)
				_set_mode(Mode.PLAY)
			else:
				_sync_examine_marker()
			board.queue_redraw()
		Mode.TARGETING:
			_handle_targeting(keycode)
		Mode.DIRECTION:
			_handle_direction(keycode)


func _start_game(class_pair: Array) -> void:
	state = CoreWorldState.new()
	state.content = content
	var gen_error := state.generate_new_world(class_pair)
	if not gen_error.is_empty():
		push_error("世界生成失败：%s" % gen_error)
		get_tree().quit(1)
		return
	engine = CoreTurnEngine.new(state, content)
	sidebar.setup(engine)
	sidebar.visible = true
	log_panel.setup(engine)
	log_panel.visible = true
	target_info.setup(engine)
	menu_inventory.setup_menu(engine)
	menu_learn.setup_menu(engine)
	menu_examine.setup_menu(engine)
	menu_class.visible = false
	board.setup(state.current, state.player)
	_set_mode(Mode.PLAY)
	_refresh()


# ---- 游历模式 ----

func _handle_play(keycode: int) -> void:
	if engine.game_over:
		return
	match keycode:
		KEY_UP, KEY_W:
			_act(engine.player_step(Vector2i(0, -1)))
		KEY_DOWN, KEY_S:
			_act(engine.player_step(Vector2i(0, 1)))
		KEY_LEFT, KEY_A:
			_act(engine.player_step(Vector2i(-1, 0)))
		KEY_RIGHT, KEY_D:
			_act(engine.player_step(Vector2i(1, 0)))
		KEY_G:
			_act(engine.player_pickup())
		KEY_E:
			_interact_down()
		KEY_Q:
			_interact_up()
		KEY_I:
			menu_inventory.open()
			_set_mode(Mode.INVENTORY)
		KEY_K:
			menu_learn.open()
			_set_mode(Mode.LEARN)
		KEY_X:
			menu_examine.open()
			if menu_examine.visible:
				_set_mode(Mode.EXAMINE)
				_sync_examine_marker()
			board.queue_redraw()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			_begin_cast(keycode - KEY_0)


func _act(_acted: bool) -> void:
	_refresh()


## 发起施放：按效果类型决定 直放 / 瞄准 / 择向。
func _begin_cast(slot: int) -> void:
	var skill: Dictionary = content.skill_for_slot(String(state.player.class_ids[0]), slot)
	if skill.is_empty():
		return
	if not state.player.skill_levels.has(skill["id"]):
		engine.log_message(content.text("not_learned"), "warn")
		_refresh()
		return
	var cost_error := _precheck_cost(skill)
	if not cost_error.is_empty():
		engine.log_message(cost_error, "warn")
		_refresh()
		return
	pending_skill = skill
	Skills._ensure_registry()
	var effect = Skills.EFFECTS[skill["effect"]["type"]]
	if effect.needs_target:
		target_candidates = engine.visible_enemies(state.player)
		if target_candidates.is_empty():
			engine.log_message(content.text("no_enemy_sight"), "warn")
			_refresh()
			return
		target_index = 0
		_set_mode(Mode.TARGETING)
		_sync_targeting()
	elif effect.needs_direction:
		dir_delta = Vector2i(0, -1)
		_set_mode(Mode.DIRECTION)
		board.landing_cell = _landing_preview()
		board.queue_redraw()
	else:
		_finish_cast(null)


func _precheck_cost(skill: Dictionary) -> String:
	if state.player.fighter.mp() < Skills.mp_cost(state.player, skill):
		return content.text("mp_low")
	if state.player.fighter.sp() < Skills.sp_cost(state.player, skill):
		return content.text("sp_low")
	return ""


func _finish_cast(target) -> void:
	var error: String = Skills.cast(engine, state.player, pending_skill, target)
	if not error.is_empty() and error != "need_target" and error != "need_direction":
		engine.log_message(error, "warn")
	_exit_cast()
	_refresh()


func _exit_cast() -> void:
	target_info.hide_panel()
	board.target_cell = Vector2i(-1, -1)
	board.landing_cell = Vector2i(-1, -1)
	board.queue_redraw()
	_set_mode(Mode.PLAY)


# ---- 瞄准模式 ----

func _handle_targeting(keycode: int) -> void:
	match keycode:
		KEY_UP, KEY_W, KEY_TAB:
			target_index = (target_index - 1 + target_candidates.size()) % target_candidates.size()
			_sync_targeting()
		KEY_DOWN, KEY_S:
			target_index = (target_index + 1) % target_candidates.size()
			_sync_targeting()
		KEY_ENTER, KEY_KP_ENTER:
			_finish_cast(target_candidates[target_index])
		KEY_ESCAPE:
			_exit_cast()
			_refresh()


func _sync_targeting() -> void:
	var target = target_candidates[target_index]
	board.target_cell = Vector2i(target.x, target.y)
	board.queue_redraw()
	target_info.show_target(pending_skill, target)


# ---- 择向模式 ----

func _handle_direction(keycode: int) -> void:
	match keycode:
		KEY_UP, KEY_W:
			dir_delta = Vector2i(0, -1)
		KEY_DOWN, KEY_S:
			dir_delta = Vector2i(0, 1)
		KEY_LEFT, KEY_A:
			dir_delta = Vector2i(-1, 0)
		KEY_RIGHT, KEY_D:
			dir_delta = Vector2i(1, 0)
		KEY_ENTER, KEY_KP_ENTER:
			if dir_delta != Vector2i.ZERO:
				_finish_cast(dir_delta)
			return
		KEY_ESCAPE:
			_exit_cast()
			_refresh()
			return
		_:
			return
	board.landing_cell = _landing_preview()
	board.queue_redraw()


func _landing_preview() -> Vector2i:
	var eff: Dictionary = pending_skill.get("effect", {})
	var cast_range := int(eff.get("range", 3))
	var last := Vector2i(state.player.x, state.player.y)
	for step in range(1, cast_range + 1):
		var nx: int = state.player.x + dir_delta.x * step
		var ny: int = state.player.y + dir_delta.y * step
		if not state.current.in_bounds(nx, ny) or not state.current.is_walkable(nx, ny):
			break
		if state.current.actor_at(nx, ny) != null:
			break
		last = Vector2i(nx, ny)
	return last


# ---- 查看 ----

func _sync_examine_marker() -> void:
	var target = menu_examine.current_target()
	if target != null:
		board.target_cell = Vector2i(target.x, target.y)
		board.queue_redraw()


# ---- E/Q 交互（秘境门/山径） ----

func _interact_down() -> void:
	var xy := state.player_xy()
	if state.current.map_type == "world":
		var gate: Dictionary = state.current.gate_at(xy.x, xy.y)
		if not gate.is_empty():
			state.known_gates[xy] = true
			state.enter_realm(String(gate["realm_id"]), xy)
			_after_map_switch()
		return
	if xy == state.current.downstairs_xy:
		state.next_floor()
		engine.update_fov()
		_after_map_switch()


func _interact_up() -> void:
	if state.current.map_type != "realm":
		return
	if state.player_xy() == state.current.upstairs_xy:
		state.previous_floor()
		engine.update_fov()
		_after_map_switch()


func _after_map_switch() -> void:
	board.setup(state.current, state.player)
	_refresh()


# ---- 刷新 ----

func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	match new_mode:
		Mode.INVENTORY:
			menu_learn.close()
			menu_examine.close()
		Mode.LEARN:
			menu_inventory.close()
			menu_examine.close()
		Mode.EXAMINE:
			menu_inventory.close()
			menu_learn.close()
		_:
			menu_inventory.close()
			menu_learn.close()
			menu_examine.close()


func _refresh() -> void:
	if state == null:
		return
	camera.position = Vector2(
		(state.player.x + 0.5) * ViewBoard.CELL,
		(state.player.y + 0.5) * ViewBoard.CELL
	)
	sidebar.refresh()
	log_panel.refresh()
	board.queue_redraw()
