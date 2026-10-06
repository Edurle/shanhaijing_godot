class_name VfxLayer
extends Node2D
## 墨迹演出层（表现层批次 3）：消费 TurnEngine.events 的即时绘制动画。
## 挂在 Board 之上、UI CanvasLayer 之下，世界坐标随相机。
## 克制快速节奏：hit≤0.15s / kill≤0.35s / 数字≤0.5s；无活动效果即停 _process（事件驱动纪律）。
## 色、语汇见 [[水墨美术风格调研]]：溅=墨点顺攻击向飞洒，克制命中=朱砂点睛，
## 击杀=墨渍晕开消散，数字=楷体墨迹上浮晕淡（非西式弹跳）。

const DUR_SPLASH := 0.15   # 墨点飞溅
const DUR_FLASH := 0.12    # 受击处墨色加深（闪 = 更浓的墨，不闪白）
const DUR_BLOT := 0.35     # 击杀墨渍晕开
const DUR_NUMBER := 0.5    # 伤害数字上浮
const DUR_RIPPLE := 0.45   # 落子惊水涟漪
const NUMBER_RISE := 16.0  # 数字上浮行程（世界像素）

var map  # 当前 GameMap（落子惊水的水陆判定；main._refresh 注入）

var speed_scale := 1.0  # 快速演出倍率（阶段 6 设置项预留；>1 更快）

var _effects: Array = []
var _rng := RandomNumberGenerator.new()
var _number_slots := {}  # Vector2i -> 本回合同格数字序号（错位防叠字）


func _ready() -> void:
	_rng.randomize()
	set_process(false)


## 消费一个回合累计的演出事件（main._refresh 驱动，随后 main 清空 engine.events）。
func play(events: Array) -> void:
	_number_slots.clear()
	for event in events:
		_spawn(event)
	if _effects.is_empty():
		return
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var step := delta * speed_scale
	for effect in _effects:
		effect["age"] = float(effect["age"]) + step
	_effects = _effects.filter(func(e): return float(e["age"]) < _lifetime(String(e["kind"])))
	if _effects.is_empty():
		set_process(false)
	queue_redraw()


# ---- 生成 ----

func _spawn(event: Dictionary) -> void:
	var cell := Vector2i(int(event.get("x", -1)), int(event.get("y", -1)))
	if cell.x < 0:
		return
	var data: Dictionary = event.get("data", {})
	match String(event.get("type", "")):
		"hit":
			_spawn_hit(cell, data)
			_spawn_ripple_near(cell)  # 落点贴水 → 水回应
		"kill":
			_effects.append({"kind": "blot", "cell": cell, "age": 0.0})
		"heal":
			_spawn_number(cell, "+%d" % int(data.get("amount", 0)), InkPalette.SAFE)
		"dot_tick":
			_spawn_number(cell, "-%d" % int(data.get("amount", 0)),
				InkPalette.ELEMENT_COLORS.get(String(data.get("kind", "")), InkPalette.WARN))
		"step":
			_spawn_ripple_near(cell)
		"pickup", "levelup", "stun", "root", "smoke", "summon", "trail":
			pass  # 后续批次：金粉/朱印/飞白拖影等


## 落子惊水：上桥（脚下即水）或落点贴水 → 在水格上荡开涟漪（仅可见区）。
func _spawn_ripple_near(cell: Vector2i) -> void:
	if map == null or not map.is_visible(cell.x, cell.y):
		return
	if map.tile_at(cell.x, cell.y) == GameMap.T_BRIDGE:
		_effects.append({"kind": "ripple", "cell": cell, "age": 0.0})
		return
	var spawned := 0
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = cell.x + dir.x
		var ny: int = cell.y + dir.y
		if map.in_bounds(nx, ny) and map.is_visible(nx, ny) and spawned < 2:
			var kind: int = map.tile_at(nx, ny)
			if kind == GameMap.T_WATER or kind == GameMap.T_RIVER:
				_effects.append({"kind": "ripple", "cell": Vector2i(nx, ny), "age": 0.0})
				spawned += 1


func _spawn_hit(cell: Vector2i, data: Dictionary) -> void:
	_effects.append({"kind": "flash", "cell": cell, "age": 0.0})
	var color := _hit_color(data)
	var from := Vector2i(int(data.get("from_x", cell.x)), int(data.get("from_y", cell.y)))
	var dir := Vector2(cell - from)
	dir = dir.normalized() if dir.length() > 0.0 else Vector2.RIGHT
	var droplets: Array = []
	for _i in range(5):
		var angle := dir.angle() + _rng.randf_range(-0.55, 0.55)
		droplets.append({
			"vel": Vector2(cos(angle), sin(angle)) * _rng.randf_range(46.0, 92.0),
			"size": _rng.randf_range(1.6, 3.2),
			"bias": dir * 4.0,  # 起笔偏攻击来向，溅势越过目标
		})
	_effects.append({
		"kind": "splash", "cell": cell, "age": 0.0, "color": color, "droplets": droplets,
	})
	_spawn_number(cell, "-%d" % int(data.get("amount", 0)), color, bool(data.get("countered", false)))


## 命中色优先级：生克点睛（朱砂）> 五行矿物色 > 浓墨。
func _hit_color(data: Dictionary) -> Color:
	if bool(data.get("countered", false)):
		return InkPalette.VERMILION
	var element := String(data.get("element", ""))
	if element != "":
		return InkPalette.ELEMENT_COLORS.get(element, InkPalette.INK_DEEP)
	return InkPalette.INK_DEEP


func _spawn_number(cell: Vector2i, text: String, color: Color, loud := false) -> void:
	var index := int(_number_slots.get(cell, 0))
	_number_slots[cell] = index + 1
	_effects.append({
		"kind": "number", "cell": cell, "age": 0.0, "text": text, "color": color,
		"loud": loud, "offset": Vector2((index % 2) * 14.0 - 7.0, -float(index) * 7.0),
	})


func _lifetime(kind: String) -> float:
	match kind:
		"splash":
			return DUR_SPLASH
		"flash":
			return DUR_FLASH
		"blot":
			return DUR_BLOT
		"ripple":
			return DUR_RIPPLE
	return DUR_NUMBER


# ---- 绘制 ----

func _draw() -> void:
	for effect in _effects:
		match String(effect["kind"]):
			"flash":
				_draw_flash(effect)
			"splash":
				_draw_splash(effect)
			"blot":
				_draw_blot(effect)
			"ripple":
				_draw_ripple(effect)
			"number":
				_draw_number(effect)


func _draw_flash(effect: Dictionary) -> void:
	var t := float(effect["age"]) / DUR_FLASH
	var cell: Vector2i = effect["cell"]
	draw_rect(
		Rect2(cell.x * Board.CELL + 2.0, cell.y * Board.CELL + 2.0, Board.CELL - 4.0, Board.CELL - 4.0),
		Color(InkPalette.INK_DEEP, 0.26 * (1.0 - t))
	)


func _draw_splash(effect: Dictionary) -> void:
	var t := float(effect["age"]) / DUR_SPLASH
	var center := _cell_center(effect["cell"])
	var fade := 1.0 - t * t
	var color: Color = effect["color"]
	var age := float(effect["age"])
	for droplet in effect["droplets"]:
		var offset: Vector2 = droplet["bias"] + droplet["vel"] * age
		draw_circle(center + offset, float(droplet["size"]) * (1.0 - 0.5 * t), Color(color, fade))


func _draw_blot(effect: Dictionary) -> void:
	var t := float(effect["age"]) / DUR_BLOT
	var center := _cell_center(effect["cell"])
	var radius := lerpf(5.0, 13.0, 1.0 - (1.0 - t) * (1.0 - t))  # ease-out 晕开
	draw_circle(center, radius, Color(InkPalette.INK_DEEP, 0.7 * (1.0 - t)))
	draw_circle(center + Vector2(10, -6), 2.4 * (1.0 - t), Color(InkPalette.INK_DEEP, 0.55 * (1.0 - t)))
	draw_circle(center + Vector2(-9, 7), 1.8 * (1.0 - t), Color(InkPalette.INK_DEEP, 0.5 * (1.0 - t)))


## 涟漪：双圈错相扩散的墨纹弧（落子惊水——静止的画只有被惊动时才活）。
func _draw_ripple(effect: Dictionary) -> void:
	var center := _cell_center(effect["cell"])
	for ring in range(2):
		var t := clampf(float(effect["age"]) / DUR_RIPPLE - ring * 0.14, 0.0, 1.0)
		if t <= 0.0:
			continue
		var radius := lerpf(4.0, 19.0, 1.0 - (1.0 - t) * (1.0 - t))
		draw_arc(center, radius, 0, TAU, 24, Color(InkPalette.INK_MID, 0.45 * (1.0 - t)), 1.2)


func _draw_number(effect: Dictionary) -> void:
	var t := float(effect["age"]) / DUR_NUMBER
	var rise := NUMBER_RISE * (1.0 - (1.0 - t) * (1.0 - t))  # ease-out 上浮
	var alpha := 1.0 if t < 0.55 else 1.0 - (t - 0.55) / 0.45
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var size := 17 if bool(effect["loud"]) else 14
	var text := String(effect["text"])
	var pos := _cell_center(effect["cell"]) + Vector2(effect["offset"]) + Vector2(0, -rise)
	pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(effect["color"], alpha))


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * Board.CELL + Board.CELL / 2.0,
		cell.y * Board.CELL + Board.CELL / 2.0,
	)
