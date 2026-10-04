class_name GameMap
extends RefCounted
## 地图模型：地形网格 + 探索/视野 + 秘境/世界字段（模型层，不接触节点树）。
## terrain id 与 Python 版完全一致（存档/数据契约），数组按 x*height+y 平铺。

# ---- 地形 id（0/1 为秘境地牢沿用，世界地形从 2 起） ----
const T_FLOOR := 0
const T_WALL := 1
const T_PLAIN := 2
const T_FOREST := 3
const T_HILL := 4
const T_MOUNTAIN := 5
const T_WATER := 6
const T_RIVER := 7
const T_BRIDGE := 8
const T_ABYSS := 9
const T_SNOW := 10
const T_SHORE := 11

## 地形语义查找表：walkable / transparent（forest 遮视野、mountain 阻通行）。
const WALKABLE_LUT: PackedByteArray = [1, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1]
const TRANSPARENT_LUT: PackedByteArray = [1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1]

var width: int
var height: int
var terrain: PackedByteArray
var explored: PackedByteArray
var visible: PackedByteArray
var fov_radius := 14

# ---- 上下文（世界 / 秘境层） ----
var map_type := "world"
var floor_number := 0  # 投放难度轴（世界=0；秘境层=层难度）
var realm_id := ""
var realm_depth := 1
var upstairs_xy := Vector2i(-1, -1)
var downstairs_xy := Vector2i(-1, -1)
var spawn_xy := Vector2i(-1, -1)
var region_ids: PackedByteArray  # 世界：每格所属区域索引（regions.json 顺序）
var landmarks: Array = []  # [{x, y, region_id, name}]
var gates: Array = []  # 秘境入口 [{realm_id, x, y, sealed}]
var actors: Array = []  # Actor 实例（含玩家，由 world_state 维护挂载）
var items: Array = []  # 地面物品 dict


func _init(map_width: int = 80, map_height: int = 45, p_fov_radius := 14) -> void:
	width = map_width
	height = map_height
	fov_radius = p_fov_radius
	terrain.resize(width * height)
	explored.resize(width * height)
	visible.resize(width * height)
	region_ids.resize(width * height)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func tile_at(x: int, y: int) -> int:
	return terrain[x * height + y]


func set_tile(x: int, y: int, kind: int) -> void:
	terrain[x * height + y] = kind


func region_at(x: int, y: int) -> int:
	return region_ids[x * height + y]


func is_walkable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return WALKABLE_LUT[tile_at(x, y)] == 1


func blocks_sight(x: int, y: int) -> bool:
	return TRANSPARENT_LUT[tile_at(x, y)] == 0


func is_explored(x: int, y: int) -> bool:
	return in_bounds(x, y) and explored[x * height + y] == 1


func is_visible(x: int, y: int) -> bool:
	return in_bounds(x, y) and visible[x * height + y] == 1


## 指定格上的存活 actor（玩家也在 actors 内）。
func actor_at(x: int, y: int) -> Actor:
	for actor in actors:
		if actor.is_alive() and actor.x == x and actor.y == y:
			return actor
	return null


## 指定格上的地面物品。
func item_at(x: int, y: int) -> Dictionary:
	for item in items:
		if item["x"] == x and item["y"] == y:
			return item
	return {}


func gate_at(x: int, y: int) -> Dictionary:
	for gate in gates:
		if gate["x"] == x and gate["y"] == y:
			return gate
	return {}


## 对称视线 FOV：目标可见 = 起点→目标或目标→起点至少一条 Bresenham 线全程透明。
## 对称性保证"你看得见怪 ⇔ 怪看得见你"，与 Python 版 tcod SYMMETRIC 语义对齐。
func compute_fov(origin_x: int, origin_y: int) -> void:
	visible.fill(0)
	var r := fov_radius
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var tx := origin_x + dx
			var ty := origin_y + dy
			if not in_bounds(tx, ty):
				continue
			if dx * dx + dy * dy > r * r:
				continue
			if _line_clear(origin_x, origin_y, tx, ty) or _line_clear(tx, ty, origin_x, origin_y):
				visible[tx * height + ty] = 1
				explored[tx * height + ty] = 1
	visible[origin_x * height + origin_y] = 1
	explored[origin_x * height + origin_y] = 1


func _line_clear(x0: int, y0: int, x1: int, y1: int) -> bool:
	## Bresenham 线：起点与终点视为透明，只检查中间格。
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	var cx := x0
	var cy := y0
	while cx != x1 or cy != y1:
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
		if cx == x1 and cy == y1:
			break
		if blocks_sight(cx, cy):
			return false
	return true
