class_name GameMap
extends RefCounted
## 地图模型：地形网格 + 探索/视野（模型层，不接触节点树）。
## 数组按 [x][y] 列主序存 PackedByteArray——x 一列整包，遍历行时同列连续。

const T_PLAIN := 0
const T_FOREST := 1
const T_MOUNTAIN := 2
const T_WATER := 3

var width: int
var height: int
var terrain: PackedByteArray  # x*height + y
var explored: PackedByteArray
var visible: PackedByteArray
var fov_radius := 14


func _init(map_width: int, map_height: int, p_fov_radius := 14) -> void:
	width = map_width
	height = map_height
	fov_radius = p_fov_radius
	terrain.resize(width * height)
	explored.resize(width * height)
	visible.resize(width * height)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func tile_at(x: int, y: int) -> int:
	return terrain[x * height + y]


func set_tile(x: int, int_y: int, kind: int) -> void:
	# 参数名 int_y 避免与局部习惯冲突；写入前不检查越界（生成器自证）
	terrain[x * height + int_y] = kind


func is_walkable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return tile_at(x, y) != T_MOUNTAIN and tile_at(x, y) != T_WATER


func blocks_sight(x: int, y: int) -> bool:
	return tile_at(x, y) == T_MOUNTAIN or tile_at(x, y) == T_FOREST


func is_explored(x: int, y: int) -> bool:
	return in_bounds(x, y) and explored[x * height + y] == 1


func is_visible(x: int, y: int) -> bool:
	return in_bounds(x, y) and visible[x * height + y] == 1


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
