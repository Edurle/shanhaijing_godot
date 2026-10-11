extends Node2D
## 主场景：内容库 → 世界状态机 → 回合引擎 → 棋盘 + 水墨 UI。
## 模式状态机：职业选择 / 游历 / 行囊 / 参悟 / 查看 / 瞄准 / 择向。
## 操作双轨：古典（键盘回合制）+ 现代（鼠标点击旅行/攻击/施法、滚轮缩放、按键长按连走）。

const CoreContentDb := preload("res://scripts/core/content_db.gd")
const CoreWorldState := preload("res://scripts/core/world_state.gd")
const CoreTurnEngine := preload("res://scripts/core/turn_engine.gd")
const ViewBoard := preload("res://scripts/view/board.gd")
const ViewVfxLayer := preload("res://scripts/view/vfx_layer.gd")
const UiLogScript := preload("res://scripts/view/ui/log_panel.gd")
const UiTargetInfoScript := preload("res://scripts/view/ui/target_info.gd")
const MenuClanSelect := preload("res://scripts/view/ui/menu_clan_select.gd")
const MenuClassSelect := preload("res://scripts/view/ui/menu_class_select.gd")
const MenuCharacter := preload("res://scripts/view/ui/menu_character.gd")
const MenuLearn := preload("res://scripts/view/ui/menu_learn.gd")
const MenuExamine := preload("res://scripts/view/ui/menu_examine.gd")
const UiHintBarScript := preload("res://scripts/view/ui/hint_bar.gd")
const UiHelpOverlayScript := preload("res://scripts/view/ui/help_overlay.gd")
const UiHudVitalsScript := preload("res://scripts/view/ui/hud_vitals.gd")
const UiSkillBarScript := preload("res://scripts/view/ui/skill_bar.gd")
const UiTooltipScript := preload("res://scripts/view/ui/ui_tooltip.gd")
const UiDragGhostScript := preload("res://scripts/view/ui/drag_ghost.gd")
const TitleScreen := preload("res://scripts/view/ui/title_screen.gd")

enum Mode { TITLE, CLAN_SELECT, CLASS_SELECT, PLAY, INVENTORY, LEARN, EXAMINE, TARGETING, DIRECTION, HELP }

const MOVE_REPEAT_MSEC := 130  # 长按连走节流
const TRAVEL_STEP_INTERVAL := 0.075  # 点击旅行的步进节奏（秒/格）

var content: CoreContentDb
var state: CoreWorldState
var engine: CoreTurnEngine
var board: ViewBoard
var vfx: ViewVfxLayer
var camera: Camera2D
var ui: CanvasLayer
var log_panel
var target_info
var menu_clan: UiMenuClanSelect
var menu_class: UiMenuClassSelect
var menu_character: MenuCharacter
var menu_learn: MenuLearn
var menu_examine: MenuExamine
var hint_bar
var help_overlay
var hud_vitals
var skill_bar
var tooltip
var drag_ghost
var title_screen: UiTitleScreen
var mode := Mode.TITLE

# 瞄准/择向的进行中技能
var pending_skill: Dictionary = {}
var target_candidates: Array = []
var target_index := 0
var dir_delta := Vector2i.ZERO

# 现代操作：点击旅行 / 长按连走
var travel_target := Vector2i(-1, -1)
var _shake := 0.0            # Boss/处决的实体微震强度（衰减）
var _camera_base := Vector2.ZERO
var dragging_skill := ""  # 拖拽中的技能 id（编排面板 → 技能栏）
var press_learn_sid := ""  # 参悟格按下未起拖的技能 id（单击/拖拽待区分）
var press_learn_pos := Vector2.ZERO
const DRAG_THRESHOLD_PX := 6.0  # 位移超过该阈值才算拖拽，否则按单击参悟
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
	InkPalette.apply(content.theme)  # 调色板唯一色源：theme.json → 视图层
	var ink_font_path := "res://assets/fonts/LXGWWenKai-Regular.ttf"  # 霞鹜文楷（OFL），游戏文本 1319 字零缺字
	if ResourceLoader.exists(ink_font_path):
		ThemeDB.fallback_font = load(ink_font_path)

	board = ViewBoard.new()
	add_child(board)
	vfx = ViewVfxLayer.new()
	add_child(vfx)  # 演出层：Board 之上、UI CanvasLayer 之下
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

	ui = CanvasLayer.new()
	add_child(ui)
	log_panel = UiLogScript.new()
	target_info = UiTargetInfoScript.new()
	menu_clan = MenuClanSelect.new()
	menu_class = MenuClassSelect.new()
	menu_character = MenuCharacter.new()
	menu_learn = MenuLearn.new()
	menu_examine = MenuExamine.new()
	hint_bar = UiHintBarScript.new()
	help_overlay = UiHelpOverlayScript.new()
	hud_vitals = UiHudVitalsScript.new()
	skill_bar = UiSkillBarScript.new()
	tooltip = UiTooltipScript.new()
	drag_ghost = UiDragGhostScript.new()
	for panel in [log_panel, target_info, menu_clan, menu_class, menu_character, menu_learn, menu_examine, hint_bar, help_overlay, hud_vitals, skill_bar, tooltip, drag_ghost]:
		ui.add_child(panel)
	tooltip.visible = false
	drag_ghost.visible = false
	hint_bar.visible = false
	help_overlay.visible = false
	hud_vitals.visible = false
	skill_bar.visible = false
	target_info.hide_panel()
	for panel in [log_panel, menu_character, menu_learn, menu_examine]:
		panel.visible = false

	menu_clan.setup_menu(content)  # 氏族页待开卷确认后再打开
	title_screen = TitleScreen.new()
	ui.add_child(title_screen)  # 最后挂载：开卷期盖住其余 UI
	title_screen.setup(content)
	title_screen.open()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	set_process(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 参悟格按住后位移过阈值才起拖（此前按下即拖，单击加点会被误判）
		if dragging_skill == "" and press_learn_sid != "" \
				and event.position.distance_to(press_learn_pos) > DRAG_THRESHOLD_PX:
			dragging_skill = press_learn_sid
			press_learn_sid = ""
			drag_ghost.begin_drag(content.skill_by_id(dragging_skill))
			tooltip.hide_panel()
		drag_ghost.queue_redraw() if dragging_skill != "" else null
		_update_tooltip(event.position)
		return
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_end_drag(event.position)
			return
		if not event.pressed:
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(1.0 / 1.12)
			MOUSE_BUTTON_LEFT:
				_handle_click(event.position)
			MOUSE_BUTTON_RIGHT:
				_handle_right_click(event.position)
		return
	if event is InputEventKey and event.pressed:
		_dispatch(event.keycode, event.is_echo(), event.shift_pressed)


func _dispatch(keycode: int, is_echo: bool, shift := false) -> void:
	match mode:
		Mode.TITLE:
			if is_echo:
				return  # 快进后连按防误确认
			if keycode == KEY_F9 and OS.is_debug_build():
				# 调试捷径：直达数据编辑器。路径运行时拼接，避免导出依赖扫描把编辑器场景打进产物
				var editor_scene = load("res://scenes/data_" + "editor.tscn")
				if editor_scene != null:
					get_tree().change_scene_to_packed(editor_scene)
				return
			title_screen.handle_key(keycode)
			if title_screen.done:
				_title_action()
		Mode.CLAN_SELECT:
			if keycode == KEY_F9 and OS.is_debug_build():
				# 调试捷径：直达数据编辑器。路径运行时拼接，避免导出依赖扫描把编辑器场景打进产物
				var editor_scene = load("res://scenes/data_" + "editor.tscn")
				if editor_scene != null:
					get_tree().change_scene_to_packed(editor_scene)
				return
			menu_clan.handle_key(keycode)
			if menu_clan.done:
				_open_class_select()
		Mode.CLASS_SELECT:
			if keycode == KEY_F9 and OS.is_debug_build():
				return
			menu_class.handle_key(keycode)
			if menu_class.done:
				_start_game(menu_class.picked_primary, menu_clan.picked)
			elif not menu_class.visible:
				# Esc 退回氏族页（重开保留氏族游标）
				menu_clan.done = false
				menu_clan.open()
				_set_mode(Mode.CLAN_SELECT)
		Mode.PLAY:
			_handle_play(keycode, is_echo, shift)
		Mode.INVENTORY:
			menu_character.handle_key(keycode)
			if not menu_character.visible:
				_set_mode(Mode.PLAY)
			_refresh()
		Mode.LEARN:
			# 键盘编排：数字键把游标技能绑到对应槽（Shift=9-16）
			if keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]:
				var bind_sid: String = menu_learn.cursor_skill_id()
				if bind_sid != "":
					var bind_slot: int = keycode - KEY_0 + (8 if shift else 0)
					var bind_error: String = engine.bind_skill(bind_slot, bind_sid)
					if bind_error.is_empty():
						engine.log_message(content.text("assign_bound").format({
							"skill": content.localize(content.skills[bind_sid]["name"]),
							"slot": UiSkillBar.key_label(bind_slot),
						}), "info")
					else:
						engine.log_message(bind_error, "warn")
					_refresh()
					return
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


## 开卷已定：新游历 → 氏族选择；离开 → 退出。
func _title_action() -> void:
	title_screen.visible = false
	if title_screen.action == "quit":
		get_tree().quit()
		return
	menu_clan.done = false
	menu_clan.open()
	_set_mode(Mode.CLAN_SELECT)


## 氏族已定：打开该氏族的职业选择页（可反复进出，须重置完成态）。
func _open_class_select() -> void:
	menu_class.done = false
	menu_class.picked_primary = ""
	menu_class.setup_menu(content, menu_clan.picked)
	menu_class.open()
	_set_mode(Mode.CLASS_SELECT)


func _start_game(class_id: String, clan_id := "") -> void:
	state = CoreWorldState.new()
	state.content = content
	var gen_error := state.generate_new_world(class_id, clan_id)
	if not gen_error.is_empty():
		push_error("世界生成失败：%s" % gen_error)
		get_tree().quit(1)
		return
	engine = CoreTurnEngine.new(state, content)
	state.player.gender = menu_class.gender  # 形象（棋盘 icon/立绘按此取图）
	log_panel.setup(engine)
	log_panel.visible = true
	target_info.setup(engine)
	menu_character.setup_menu(engine)
	tooltip.setup(engine)
	drag_ghost.setup(engine)
	menu_learn.setup_menu(engine)
	menu_examine.setup_menu(engine)
	hint_bar.setup(engine)
	hint_bar.visible = true
	hud_vitals.setup(engine)
	hud_vitals.visible = true
	skill_bar.setup(engine)
	skill_bar.visible = true
	help_overlay.setup_panel(engine)
	menu_clan.visible = false
	menu_class.visible = false
	board.setup(state.current, state.player)
	_apply_realm_tone()
	_set_mode(Mode.PLAY)
	_on_viewport_resized()  # 窗口启动即最大化时 size_changed 不会触发，主动按真实视口排布
	_refresh()


# ---- 游历模式（键盘） ----

func _handle_play(keycode: int, is_echo: bool, shift := false) -> void:
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
		KEY_PERIOD, KEY_SPACE, KEY_KP_5:
			_stop_travel()
			_act(engine.player_wait())
		KEY_G:
			_act(engine.player_pickup())
		KEY_E:
			_interact_down()
		KEY_Q:
			_interact_up()
		KEY_I:
			_stop_travel()
			menu_character.open()
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
			_cast_binding(keycode - KEY_0 + (8 if shift else 0))
		KEY_H:
			help_overlay.open()
			_set_mode(Mode.HELP)


func _act(_acted: bool) -> void:
	_refresh()


# ---- 鼠标（现代操作） ----

## 悬浮提示：行囊面板物品 > 技能栏（任意模式）> 编排面板图标/槽位 → 说明卡。
func _update_tooltip(pos: Vector2) -> void:
	if state == null or dragging_skill != "" or press_learn_sid != "":
		tooltip.hide_panel()
		return
	if menu_character.visible:
		var hovered: Dictionary = menu_character.hover(pos)
		if not hovered.is_empty():
			tooltip.show_item(hovered, state.player, pos)
			return
		if menu_character.panel_rect.has_point(pos):
			tooltip.hide_panel()  # 面板空白处不透传给下层技能栏
			return
	var bottom_slot: int = skill_bar.skill_slot_at(pos)
	if bottom_slot > 0:
		var sid := String(state.player.skill_bar[bottom_slot - 1])
		if sid != "":
			tooltip.show_skill(content.skill_by_id(sid), state.player, pos, UiSkillBar.key_label(bottom_slot))
			return
	if mode == Mode.LEARN and menu_learn.visible:
		var learn_sid := menu_learn.node_skill_at(pos)
		if learn_sid != "":
			var bound := ""
			for i in range(16):
				if String(state.player.skill_bar[i]) == learn_sid:
					bound = UiSkillBar.key_label(i + 1)
					break
			tooltip.show_skill(content.skill_by_id(learn_sid), state.player, pos, bound)
			return
	tooltip.hide_panel()


## 鼠标释放收尾：拖拽中 → 技能栏槽位绑定（未参悟拒绝），其余位置视为取消；
## 未拖起（位移小于阈值）→ 释放点仍在原技能格 = 单击参悟。
func _end_drag(pos: Vector2) -> void:
	if dragging_skill == "":
		if press_learn_sid != "":
			var sid := press_learn_sid
			press_learn_sid = ""
			if mode == Mode.LEARN and menu_learn.visible \
					and menu_learn.node_skill_at(pos) == sid:
				menu_learn.confirmed.emit(sid)
				_refresh()
		return
	var sid := dragging_skill
	dragging_skill = ""
	drag_ghost.end_drag()
	var slot: int = skill_bar.skill_slot_at(pos)
	if slot > 0:
		var bind_error: String = engine.bind_skill(slot, sid)
		if bind_error.is_empty():
			engine.log_message(content.text("assign_bound").format({
				"skill": content.localize(content.skills[sid]["name"]),
				"slot": UiSkillBar.key_label(slot),
			}), "info")
		else:
			engine.log_message(bind_error, "warn")
	_refresh()


func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, 0.55, 1.6)
	camera.zoom = Vector2(z, z)


func _handle_right_click(pos := Vector2(-1, -1)) -> void:
	match mode:
		Mode.TARGETING, Mode.DIRECTION:
			_exit_cast()
			_refresh()
		Mode.INVENTORY, Mode.LEARN, Mode.EXAMINE:
			menu_character.close()
			menu_learn.close()
			menu_examine.close()
			board.target_cell = Vector2i(-1, -1)
			_set_mode(Mode.PLAY)
			board.queue_redraw()
		Mode.PLAY:
			# 右键技能栏槽位 = 解绑该槽
			var unbind_slot: int = skill_bar.skill_slot_at(pos) if pos.x >= 0 else 0
			if unbind_slot > 0 and String(state.player.skill_bar[unbind_slot - 1]) != "":
				state.player.skill_bar[unbind_slot - 1] = ""
				engine.log_message(content.text("slot_unbound").format({
					"slot": UiSkillBar.key_label(unbind_slot),
				}), "info")
				_refresh()
				return
			# 右键可见异兽 = 打开查看卡并定位该怪（左键仍是走过去攻击）
			if pos.x >= 0:
				var rcell := _screen_to_cell(pos)
				if state.current.is_visible(rcell.x, rcell.y):
					var victim = state.current.actor_at(rcell.x, rcell.y)
					if victim != null and victim.team != "player":
						_stop_travel()
						menu_examine.open()
						var victim_index: int = menu_examine.targets.find(victim)
						if victim_index >= 0:
							menu_examine.index = victim_index
						if menu_examine.visible:
							_set_mode(Mode.EXAMINE)
							_sync_examine_marker()
						board.queue_redraw()
						return
			_stop_travel()


func _handle_click(pos: Vector2) -> void:
	match mode:
		Mode.TITLE:
			title_screen.click_at(pos)
			if title_screen.done:
				_title_action()
		Mode.CLAN_SELECT:
			menu_clan.click_at(pos)
			if menu_clan.done:
				_open_class_select()
		Mode.CLASS_SELECT:
			menu_class.click_at(pos)
			if menu_class.done:
				_start_game(menu_class.picked_primary, menu_clan.picked)
			elif not menu_class.visible:
				menu_clan.done = false
				menu_clan.open()
				_set_mode(Mode.CLAN_SELECT)
		Mode.INVENTORY:
			menu_character.click_at(pos)
			if not menu_character.visible:
				_set_mode(Mode.PLAY)
			_refresh()
		Mode.LEARN:
			# 按下技能格仅记录：位移过阈值才起拖（→技能栏绑定），原地释放 = 单击参悟
			var press_sid: String = menu_learn.node_skill_at(pos)
			if press_sid != "":
				var node_index: int = menu_learn.node_index_at(pos)
				if node_index >= 0:
					menu_learn.cursor = node_index
					menu_learn.queue_redraw()
				press_learn_sid = press_sid
				press_learn_pos = pos
				tooltip.hide_panel()
				return
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
			# 候选未命中：点中可见敌但超距 → 距离提示（候选已按攻击距离过滤）
			var beyond = state.current.actor_at(cell.x, cell.y)
			if beyond != null and beyond.team != "player" and state.current.is_visible(cell.x, cell.y):
				engine.log_message(content.text("target_too_far"), "warn")
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
	# 底部技能栏：槽位点击施放（按绑定）
	if skill_bar.visible and skill_bar.skill_slot_at(pos) > 0:
		var slot: int = skill_bar.skill_slot_at(pos)
		_stop_travel()
		_cast_binding(slot)
		return
	var cell := _screen_to_cell(pos)
	if not state.current.in_bounds(cell.x, cell.y):
		return
	if not state.current.is_explored(cell.x, cell.y):
		return
	# 点击脚下 = 原地跳过一回合（被眩晕/缠绕缠住时的鼠标出路）
	if cell == state.player_xy():
		_stop_travel()
		_act(engine.player_wait())
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
	if engine != null and _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 10.0)
		camera.position = _camera_base + Vector2(randf() - 0.5, randf() - 0.5) * 6.0 * _shake
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

## 按绑定施放：空槽/未学/资源不足给出提示，需要目标/方向的技能进入对应模式。
func _cast_binding(slot: int) -> void:
	var skill_id := String(state.player.skill_bar[slot - 1]) if slot >= 1 and slot <= 16 else ""
	if skill_id == "":
		engine.log_message(content.text("slot_empty_skill"), "warn")
		_refresh()
		return
	var skill: Dictionary = content.skill_by_id(skill_id)
	if skill.is_empty():
		return
	if not state.player.skill_levels.has(skill_id):
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
		var seen := engine.visible_enemies(state.player)
		if seen.is_empty():
			engine.log_message(content.text("no_enemy_sight"), "warn")
			_refresh()
			return
		var reach := Skills.cast_reach(engine, pending_skill)
		target_candidates = []
		for enemy in seen:
			if state.player.distance_to(enemy) <= reach:
				target_candidates.append(enemy)
		if target_candidates.is_empty():
			engine.log_message(content.text("no_enemy_in_range"), "warn")
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
	if error.is_empty():
		# 施法成功即消耗回合（与移动/攻击一致；此前漏掉导致技能栏施法不推进怪物回合）
		engine.end_turn()
	elif error != "need_target" and error != "need_direction":
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
	_apply_realm_tone()
	_refresh()


## 秘境墨调：realms.json 的 theme 键 → theme.json realm_tones 整卷罩染（世界无罩染）。
func _apply_realm_tone() -> void:
	var key := ""
	if state.current.map_type == "realm":
		key = String(content.realms.get(state.current.realm_id, {}).get("theme", ""))
	board.set_realm_tone(key)


# ---- 视口自适应 ----

func _on_viewport_resized() -> void:
	var view := get_viewport().get_visible_rect().size
	log_panel.relayout(view)
	hint_bar.relayout(view)
	hud_vitals.relayout(view)
	skill_bar.relayout(view)
	if help_overlay.visible:
		help_overlay.relayout(view)
	tooltip.set_view_size(view)
	if title_screen != null and title_screen.visible:
		title_screen.relayout(view)
	if menu_clan.visible:
		menu_clan.relayout(view)
	if menu_class.visible:
		menu_class.relayout(view)
	if menu_character.visible:
		menu_character.relayout(view)
	if menu_learn.visible:
		menu_learn.relayout(view)
	if menu_examine.visible:
		menu_examine.relayout(view)


# ---- 刷新 ----

func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	if new_mode != Mode.INVENTORY:
		menu_character.close()
	if new_mode != Mode.LEARN:
		_cancel_skill_drag()
		menu_learn.close()
	if new_mode != Mode.EXAMINE:
		menu_examine.close()


## 清除参悟格的按压/拖拽状态（离开参悟面板：切模式、右键、Esc）。
func _cancel_skill_drag() -> void:
	press_learn_sid = ""
	if dragging_skill != "":
		dragging_skill = ""
		drag_ghost.end_drag()


func _refresh() -> void:
	if state == null:
		return
	board.sync_field()  # 地形/雾态数据纹理（shader 场在重绘前拿到最新状态）
	if not engine.events.is_empty():
		vfx.map = state.current  # 落子惊水的水陆判定
		for event in engine.events:
			var etype := String(event.get("type", ""))
			if etype == "kill":
				if bool(event.get("data", {}).get("boss", false)):
					board.ink_pulse(0.9)
					_shake = 1.0  # Boss/处决保留 2-3px 实体微震
				else:
					board.ink_pulse(0.5)
			elif etype == "hit" and bool(event.get("data", {}).get("countered", false)):
				board.ink_pulse(0.3)  # 生克点睛：墨震一记
		vfx.play(engine.events)  # 演出事件一次性消费（引擎约定：视图消费后清空）
		engine.events.clear()
	camera.position = Vector2(
		(state.player.x + 0.5) * ViewBoard.CELL,
		(state.player.y + 0.5) * ViewBoard.CELL
	)
	_camera_base = camera.position
	log_panel.refresh()
	hud_vitals.refresh()
	skill_bar.refresh()
	hint_bar.visible = mode == Mode.PLAY or mode == Mode.HELP
	hint_bar.refresh()
	board.queue_redraw()
