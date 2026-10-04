class_name Board
extends Node2D
## 棋盘渲染（视图层）：阶段 1 用程序化水墨色块占位，AI 素材到位后切换为贴图绘制。
## 重绘时机由 main 驱动（地图/视野/单位变动 → queue_redraw），无逐帧开销。

const CELL := 32

# ---- 水墨山海色板（宣纸/三阶墨/五行矿物色） ----
const PAPER := Color("E9E1CD")        # 宣纸底
const PAPER_DIM := Color("CFC6AE")    # 探索未视（记忆态）
const INK_LIGHT := Color("B9B2A2")    # 淡墨
const INK_MID := Color("6E675C")      # 中墨
const INK_DEEP := Color("2B2620")     # 浓墨（山体）
const WATER := Color("9FB6C4")        # 石青淡（水域）
const PLAYER_INK := Color("3A5A6E")   # 青墨（行者）
const ELEMENT_COLORS := {
	"metal": Color("C9A662"),  # 鎏金
	"wood": Color("4A7C59"),   # 石绿
	"water": Color("2E5977"),  # 石青
	"fire": Color("C3272B"),   # 朱砂
	"earth": Color("8C5A3C"),  # 赭石
}

var map: GameMap
var actors: Array = []  # [{x, y, element, is_player, label}]
var _jitter := {}  # (x,y) -> 0..2 纸面颗粒抖动，避免大色块呆板


func setup(p_map: GameMap) -> void:
	map = p_map
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
			var color := _terrain_color(map.tile_at(x, y), x, y, seen)
			var rect := Rect2(x * CELL + 1, y * CELL + 1, CELL - 2, CELL - 2)
			draw_rect(rect, color)
			if seen and map.tile_at(x, y) == GameMap.T_MOUNTAIN:
				_draw_mountain_stroke(x, y)
	for actor in actors:
		_draw_actor(actor)


func _terrain_color(kind: int, x: int, y: int, seen: bool) -> Color:
	var base: Color
	match kind:
		GameMap.T_MOUNTAIN:
			base = INK_DEEP
		GameMap.T_FOREST:
			base = INK_MID if seen else INK_LIGHT
		GameMap.T_WATER:
			base = WATER
		_:
			# 宣纸底 + 三档颗粒抖动，模拟纸面吸墨不匀
			base = PAPER.lightened(0.0 if _jitter.get(Vector2i(x, y), 0) == 0 else -0.02)
	if not seen:
		base = base.lerp(INK_LIGHT, 0.45)  # 记忆态罩一层灰墨
	return base


## 山体飞白：顶部两笔浅色横皴，让浓墨块有笔触感（占位手法，素材期替换）。
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


func _draw_actor(actor: Dictionary) -> void:
	if not map.is_visible(actor["x"], actor["y"]) and not actor.get("is_player", false):
		return
	var center := Vector2(actor["x"] * CELL + CELL / 2.0, actor["y"] * CELL + CELL / 2.0)
	if actor.get("is_player", false):
		draw_circle(center, 9.0, PLAYER_INK)
		draw_arc(center, 11.0, 0, TAU, 24, PAPER, 1.5)
		# 行者朝向剑锋（占位：一短笔）
		draw_line(center + Vector2(4, -4), center + Vector2(11, -11), INK_DEEP, 2.0)
	else:
		draw_circle(center, 8.0, INK_DEEP)
		var ring: Color = ELEMENT_COLORS.get(String(actor.get("element", "")), INK_MID)
		draw_arc(center, 11.0, 0, TAU, 24, ring, 2.0)
		# 点睛：异兽唯一的亮色
		draw_circle(center + Vector2(-2, -2), 1.6, Color("C3272B"))
