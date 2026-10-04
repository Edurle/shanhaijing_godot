extends Node2D
## 主场景：内容库 → 世界状态机 → 回合引擎 → 棋盘 + 水墨 UI。
## 模式状态机：职业选择 / 游历 / 行囊 / 参悟 / 查看 / 瞄准 / 择向。
## 操作双轨：古典（键盘回合制）+ 现代（鼠标点击旅行/攻击/施法、滚轮缩放、按键长按连走）。

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
const UiHintBarScript := preload("res://scripts/view/ui/hint_bar.gd")
const UiHelpOverlayScript := preload("res://scripts/view/ui/help_overlay.gd")

enum Mode { CLASS_SELECT, PLAY, INVENTORY, LEARN, EXAMINE, TARGETING, DIRECTION, HELP }

const MOVE_REPEAT_MSEC := 130  # 长按连走节流
const TRAVEL_STEP_INTERVAL := 0.075  # 点击旅行的步进节奏（秒/格）

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
var hint_bar
var help_overlay
var mode := Mode.CLASS_SELECT

# 瞄准/择向的进行中技能
var pending_skill: Dictionary = {}
var target_candidates: Array = []
var target_index := 0
var dir_delta := Vector2i.ZERO

# 现代操作：点击旅行 / 长按连走
var travel_target := Vector2i(-1, -1)
var travel_attack := false
var _travel_clock := 0.0
var _last_move_msec := -100000


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
	hint_bar = UiHintBarScript.new()
	help_overlay = UiHelpOverlayScript.new()
	for panel in [sidebar, log_panel, target_info, menu_class, menu_inventory, menu_learn, menu_examine, hint_bar, help_overlay]:
		ui.add_child(panel)
	hint_bar.visible = false
	help_overlay.visible = false
	target_info.hide_panel()
	for panel in [sidebar, log_panel, menu_inventory, menu_learn, menu_examine]:
		panel.visible = false

	menu_class.setup_menu(content)
	menu_class.open()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	set_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(1.0 / 1.12)
			MOUSE_BUTTON_LEFT:
				_handle_click(event.position)
			MOUSE_BUTTON_RIGHT:
				_handle_right_click()
		return
	if event is InputEventKey and event.pressed:
		_dispatch(event.keycode, event.is_echo())


func _dispatch(keycode: int, is_echo: bool) -> void:
	match mode:
		Mode.CLASS_SELECT:
			menu_class.handle_key(keycode)
			if menu_class.done:
				_start_game([menu_class.picked_primary, menu_class.picked_secondary])
		Mode.PLAY:
			_handle_play(keycode, is_echo)
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
		Mode.HELP:
			if keycode in [KEY_H, KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
				help_overlay.close()
				_set_mode(Mode.PLAY)
				_refresh()


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
	hint_bar.setup(engine)
	hint_bar.visible = true
	help_overlay.setup_panel(engine)
	menu_class.visible = false
	board.setup(state.current, state.player)
	_set_mode(Mode.PLAY)
	_on_viewport_resized()  # 窗口启动即最大化时 size_changed 不会触发，主动按真实视口排布
	_refresh()


# ---- 游历模式（键盘） ----

func _handle_play(keycode: int, is_echo: bool) -> void:
	if engine.game_over:
		return
	var delta := Vector2i.ZERO
	match keycode:
		KEY_UP, KEY_W:
			delta = Vector2i(0, -1)
		KEY_DOWN, KEY_S:
			delta = Vector2i(0, 1)
		KEY_LEFT, KEY_A:
			delta = Vector2i(-1, 0)
		KEY_RIGHT, KEY_D:
			delta = Vector2i(1, 0)
	if delta != Vector2i.ZERO:
		if is_echo and Time.get_ticks_msec() - _last_move_msec < MOVE_REPEAT_MSEC:
			return
		_last_move_msec = Time.get_ticks_msec()
		_stop_travel()
		_act(engine.player_step(delta))
		return
	if is_echo:
		return
	match keycode:
		KEY_G:
			_act(engine.player_pickup())
		KEY_E:
			_interact_down()
		KEY_Q:
			_interact_up()
		KEY_I:
			_stop_travel()
			menu_inventory.open()
			_set_mode(Mode.INVENTORY)
		KEY_K:
			_stop_travel()
			menu_learn.open()
			_set_mode(Mode.LEARN)
		KEY_X:
			_stop_travel()
			menu_examine.open()
			if menu_examine.visible:
				_set_mode(Mode.EXAMINE)
				_sync_examine_marker()
			board.queue_redraw()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			_begin_cast(keycode - KEY_0)
		KEY_TAB:
			engine.active_page = 1 - engine.active_page
			_refresh()
		KEY_H:
			help_overlay.open()
			_set_mode(Mode.HELP)


func _act(_acted: bool) -> void:
	_refresh()


# ---- 鼠标（现代操作） ----

func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, 0.55, 1.6)
	camera.zoom = Vector2(z, z)


func _handle_right_click() -> void:
	match mode:
		Mode.TARGETING, Mode.DIRECTION:
			_exit_cast()
			_refresh()
		Mode.INVENTORY, Mode.LEARN, Mode.EXAMINE:
			menu_inventory.close()
			menu_learn.close()
			menu_examine.close()
			board.target_cell = Vector2i(-1, -1)
			_set_mode(Mode.PLAY)
			board.queue_redraw()
		Mode.PLAY:
			_stop_travel()


func _handle_click(pos: Vector2) -> void:
	match mode:
		Mode.CLASS_SELECT:
			menu_class.click_at(pos)
			if menu_class.done:
				_start_game([menu_class.picked_primary, menu_class.picked_secondary])
		Mode.INVENTORY:
			menu_inventory.click_at(pos)
			if not menu_inventory.visible:
				_set_mode(Mode.PLAY)
			_refresh()
		Mode.LEARN:
			menu_learn.click_at(pos)
			if not menu_learn.visible:
				_set_mode(Mode.PLAY)
			_refresh()
		Mode.EXAMINE:
			if not menu_examine.click_at(pos):
				var cell := _screen_to_cell(pos)
				for i in range(menu_examine.targets.size()):
					var t = menu_examine.targets[i]
					if Vector2i(t.x, t.y) == cell:
						menu_examine.index = i
						menu_examine.queue_redraw()
						_sync_examine_marker()
						break
		Mode.TARGETING:
			var cell := _screen_to_cell(pos)
			for i in range(target_candidates.size()):
				var t = target_candidates[i]
				if Vector2i(t.x, t.y) == cell:
					target_index = i
					_finish_cast(t)
					return
		Mode.DIRECTION:
			_exit_cast()
			_refresh()
		Mode.HELP:
			help_overlay.click_at(pos)
			if not help_overlay.visible:
				_set_mode(Mode.PLAY)
				_refresh()
		Mode.PLAY:
			_click_play(pos)


func _click_play(pos: Vector2) -> void:
	if engine.game_over:
		return
	# 侧栏区：技能行点击施放
	if sidebar.visible and pos.x >= sidebar.panel_rect.position.x:
		var slot: int = sidebar.skill_row_at(pos)
		if slot > 0:
			_stop_travel()
			_begin_cast(slot)
		return
	var cell := _screen_to_cell(pos)
	if not state.current.in_bounds(cell.x, cell.y):
		return
	if not state.current.is_explored(cell.x, cell.y):
		return
	# 点击可见敌 → 走过去并攻击一次；点击已探索可走格/门/山径/物品 → 旅行
	var victim = state.current.actor_at(cell.x, cell.y)
	if victim != null and victim.team != "player" and state.current.is_visible(cell.x, cell.y):
		travel_target = cell
		travel_attack = true
		board.travel_cell = cell
		board.queue_redraw()
		return
	if state.current.is_walkable(cell.x, cell.y):
		travel_target = cell
		travel_attack = false
		board.travel_cell = cell
		board.queue_redraw()


func _screen_to_cell(pos: Vector2) -> Vector2i:
	var view := get_viewport().get_visible_rect().size
	var world: Vector2 = (pos - view / 2.0) / camera.zoom.x + camera.position
	return Vector2i(floori(world.x / ViewBoard.CELL), floori(world.y / ViewBoard.CELL))


# ---- 点击旅行（现代操作） ----

func _stop_travel() -> void:
	travel_target = Vector2i(-1, -1)
	board.travel_cell = Vector2i(-1, -1)
	board.queue_redraw()


func _process(delta: float) -> void:
	if mode != Mode.PLAY or engine == null or engine.game_over or travel_target.x < 0:
		return
	_travel_clock += delta
	if _travel_clock < TRAVEL_STEP_INTERVAL:
		return
	_travel_clock = 0.0
	var here := state.player_xy()
	if here == travel_target:
		if travel_attack:
			var victim = state.current.actor_at(here.x, here.y)  # 与玩家同格不可能；攻击在相邻时触发
		_stop_travel()
		return
	# 非攻击旅行途中遇敌即停（现代手感的安全绳）
	if not travel_attack and not engine.visible_enemies(state.player).is_empty():
		_stop_travel()
		return
	var next := _next_step_bfs(here, travel_target)
	if next == Vector2i(-1, -1):
		_stop_travel()
		return
	if next == travel_target and travel_attack:
		var victim = state.current.actor_at(next.x, next.y)
		if victim != null and victim.team != "player":
			var dx := signi(next.x - here.x)
			var dy := signi(next.y - here.y)
			engine.player_step(Vector2i(dx, dy))
			_stop_travel()
			_refresh()
			return
	var dx := signi(next.x - here.x)
	var dy := signi(next.y - here.y)
	if not engine.player_step(Vector2i(dx, dy)):
		_stop_travel()
		return
	if state.player_xy() == travel_target and travel_attack:
		_stop_travel()
	_refresh()


## BFS 下一格（玩家旅行用）：同伴占位视为障碍，目标格除外；限 900 展开防爆扫。
func _next_step_bfs(from: Vector2i, to: Vector2i) -> Vector2i:
	var map = state.current
	if not map.in_bounds(to.x, to.y):
		return Vector2i(-1, -1)
	var came_from := {from: from}
	var queue: Array = [from]
	var expansions := 0
	while not queue.is_empty() and expansions < 900:
		expansions += 1
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			break
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nxt := Vector2i(cell.x + dx, cell.y + dy)
				if not map.in_bounds(nxt.x, nxt.y) or came_from.has(nxt):
					continue
				if not map.is_walkable(nxt.x, nxt.y):
					continue
				if nxt != to and map.actor_at(nxt.x, nxt.y) != null:
					continue
				came_from[nxt] = cell
				queue.append(nxt)
	if not came_from.has(to):
		return Vector2i(-1, -1)
	var cur := to
	while came_from[cur] != from:
		cur = came_from[cur]
		if cur == from:
			break
	return cur if cur != from else Vector2i(-1, -1)


# ---- 施放 ----

func _begin_cast(slot: int) -> void:
	var class_id := String(state.player.class_ids[engine.active_page])
	var skill: Dictionary = content.skill_for_slot(class_id, slot)
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
			_stop_travel()
			state.known_gates[xy] = true
			state.enter_realm(String(gate["realm_id"]), xy)
			_after_map_switch()
		return
	if xy == state.current.downstairs_xy:
		_stop_travel()
		state.next_floor()
		engine.update_fov()
		_after_map_switch()


func _interact_up() -> void:
	if state.current.map_type != "realm":
		return
	if state.player_xy() == state.current.upstairs_xy:
		_stop_travel()
		state.previous_floor()
		engine.update_fov()
		_after_map_switch()


func _after_map_switch() -> void:
	travel_target = Vector2i(-1, -1)
	board.setup(state.current, state.player)
	_refresh()


# ---- 视口自适应 ----

func _on_viewport_resized() -> void:
	var view := get_viewport().get_visible_rect().size
	sidebar.relayout(view)
	log_panel.relayout(view)
	hint_bar.relayout(view)
	if help_overlay.visible:
		help_overlay.relayout(view)
	if menu_class.visible:
		menu_class.relayout(view)
	if menu_inventory.visible:
		menu_inventory.relayout(view)
	if menu_learn.visible:
		menu_learn.relayout(view)
	if menu_examine.visible:
		menu_examine.relayout(view)


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
	hint_bar.visible = mode == Mode.PLAY or mode == Mode.HELP
	hint_bar.refresh()
	board.queue_redraw()
