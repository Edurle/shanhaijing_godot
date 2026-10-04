class_name Board
extends Node2D
## 棋盘渲染（视图层）：阶段 1-2 用程序化水墨色块占位，AI 素材到位后切换为贴图绘制。
## 重绘时机由 main 驱动（地图/视野/单位变动 → queue_redraw），无逐帧开销。

const CELL := 32

# ---- 水墨山海色板（宣纸/三阶墨/五行矿物色） ----
const PAPER := Color("E9E1CD")        # 宣纸底
const INK_LIGHT := Color("B9B2A2")    # 淡墨
const INK_MID := Color("6E675C")      # 中墨
const INK_DEEP := Color("2B2620")     # 浓墨（山体/石壁）
const PLAYER_INK := Color("3A5A6E")   # 青墨（行者）
const VERMILION := Color("C3272B")    # 朱砂（秘境门印/点睛）
const TERRAIN_COLORS := {
	GameMap.T_FLOOR: Color("D8CFBA"),   # 洞府地面（淡纸）
	GameMap.T_PLAIN: Color("E9E1CD"),   # 原野（宣纸+颗粒）
	GameMap.T_FOREST: Color("8A8674"),  # 森林（灰绿墨）
	GameMap.T_HILL: Color("C4B99F"),    # 丘陵（淡墨染）
	GameMap.T_MOUNTAIN: Color("2B2620"),
	GameMap.T_WATER: Color("9FB6C4"),   # 湖泊（石青淡）
	GameMap.T_RIVER: Color("B7C9D4"),   # 河流（更淡的石青）
	GameMap.T_BRIDGE: Color("A8815C"),  # 木桥（赭木）
	GameMap.T_ABYSS: Color("191414"),   # 深渊（玄黑）
	GameMap.T_SNOW: Color("F4EFE2"),    # 雪峰（留白）
	GameMap.T_SHORE: Color("D9C9A3"),   # 滩涂（沙黄）
}
const ELEMENT_COLORS := {
	"metal": Color("C9A662"),  # 鎏金
	"wood": Color("4A7C59"),   # 石绿
	"water": Color("2E5977"),  # 石青
	"fire": Color("C3272B"),   # 朱砂
	"earth": Color("8C5A3C"),  # 赭石
}

var map: GameMap
var player: Actor
var _jitter := {}  # Vector2i -> 0..2 纸面颗粒抖动，避免大色块呆板


func setup(p_map: GameMap, p_player: Actor = null) -> void:
	map = p_map
	player = p_player
	_jitter.clear()
	for x in range(map.width):
		for y in range(map.height):
			_jitter[Vector2i(x, y)] = (x * 7 + y * 13) % 3
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	draw_rect(Rect2(0, 0, map.width * CELL, map.height * CELL), PAPER)
	for x in range(map.width):
		for y in range(map.height):
			if not map.is_explored(x, y):
				continue
			var seen := map.is_visible(x, y)
			var kind := map.tile_at(x, y)
			var color := _terrain_color(kind, x, y, seen)
			draw_rect(Rect2(x * CELL + 1, y * CELL + 1, CELL - 2, CELL - 2), color)
			if seen and (kind == GameMap.T_MOUNTAIN or kind == GameMap.T_WALL):
				_draw_mountain_stroke(x, y)
	_draw_stairs()
	_draw_gates()
	_draw_items()
	for actor in map.actors:
		if actor.is_alive():
			_draw_actor(actor)


func _terrain_color(kind: int, x: int, y: int, seen: bool) -> Color:
	var base: Color = TERRAIN_COLORS.get(kind, PAPER)
	if kind == GameMap.T_PLAIN:
		# 宣纸底 + 三档颗粒抖动，模拟纸面吸墨不匀
		var j := int(_jitter.get(Vector2i(x, y), 0))
		base = PAPER.lightened(0.0 if j == 0 else -0.025)
	if not seen:
		base = base.lerp(INK_LIGHT, 0.45)  # 记忆态罩一层灰墨
	return base


## 山体/石壁飞白：两笔浅色横皴，让浓墨块有笔触感（占位手法，素材期替换）。
func _draw_mountain_stroke(x: int, y: int) -> void:
	var px := x * CELL
	var py := y * CELL
	var stroke := INK_DEEP.lightened(0.28)
	draw_line(
		Vector2(px + 6, py + 10), Vector2(px + CELL - 8, py + 8), stroke, 2.0
	)
	draw_line(
		Vector2(px + 10, py + CELL - 9), Vector2(px + CELL - 6, py + CELL - 12), stroke, 1.5
	)


## 山径：下行（墨三角向下）/上行（淡三角向上），踏入交互的视觉锚点。
func _draw_stairs() -> void:
	if map.map_type != "realm":
		return
	var down := map.downstairs_xy
	if down.x >= 0 and map.is_explored(down.x, down.y):
		var c := _cell_center(down)
		var pts := PackedVector2Array([
			c + Vector2(-7, -5), c + Vector2(7, -5), c + Vector2(0, 7),
		])
		draw_colored_polygon(pts, INK_MID if map.is_visible(down.x, down.y) else INK_LIGHT)
	var up := map.upstairs_xy
	if up.x >= 0 and map.is_explored(up.x, up.y):
		var c := _cell_center(up)
		var pts := PackedVector2Array([
			c + Vector2(-7, 6), c + Vector2(7, 6), c + Vector2(0, -7),
		])
		draw_colored_polygon(pts, VERMILION if map.is_visible(up.x, up.y) else INK_LIGHT)


## 秘境门：朱砂方印（外框 + 中心点），走上去踏入。
func _draw_gates() -> void:
	if map.map_type != "world":
		return
	for gate in map.gates:
		var x: int = gate["x"]
		var y: int = gate["y"]
		if not map.is_visible(x, y):
			continue
		var c := _cell_center(Vector2i(x, y))
		var seal: Color = INK_LIGHT if gate.get("sealed", false) else VERMILION
		draw_rect(Rect2(c - Vector2(10, 10), Vector2(20, 20)), seal, false, 2.5)
		draw_circle(c, 3.0, seal)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0)


## 地面物品：赭墨小方点（拾取交互阶段 4 接入）。
func _draw_items() -> void:
	for item in map.items:
		var x: int = item["x"]
		var y: int = item["y"]
		if not map.is_visible(x, y):
			continue
		var c := _cell_center(Vector2i(x, y))
		draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color("8C5A3C"))
		draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), INK_DEEP, false, 1.0)


func _draw_actor(actor: Actor) -> void:
	if not map.is_visible(actor.x, actor.y) and actor != player:
		return
	var center := _cell_center(Vector2i(actor.x, actor.y))
	if actor == player:
		draw_circle(center, 9.0, PLAYER_INK)
		draw_arc(center, 11.0, 0, TAU, 24, PAPER, 1.5)
		# 行者朝向剑锋（占位：一短笔）
		draw_line(center + Vector2(4, -4), center + Vector2(11, -11), INK_DEEP, 2.0)
		return
	var radius := 8.0 if not actor.elite else 10.0
	if actor.elite:
		draw_circle(center, radius, Color("D9A404").darkened(0.25))
	else:
		draw_circle(center, radius, INK_DEEP)
	var ring: Color = ELEMENT_COLORS.get(actor.element, INK_MID)
	draw_arc(center, radius + 3.0, 0, TAU, 24, ring, 2.0)
	# 点睛：异兽唯一的亮色
	draw_circle(center + Vector2(-2, -2), 1.6, VERMILION)
	# 血条细线（受伤才显示）
	var hp_ratio := float(actor.fighter.hp()) / maxf(1.0, actor.fighter.max_hp())
	if hp_ratio < 1.0:
		var bar_w := 22.0
		draw_rect(Rect2(center - Vector2(bar_w / 2, radius + 7), Vector2(bar_w, 3)), INK_LIGHT)
		draw_rect(Rect2(center - Vector2(bar_w / 2, radius + 7), Vector2(bar_w * hp_ratio, 3)), VERMILION)
