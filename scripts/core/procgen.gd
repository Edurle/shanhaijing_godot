class_name ProcGen
extends RefCounted
## 秘境地牢生成——Python 版 procgen.py 的移植：随机房间 + L 形走廊 + 上下山径。
## 阶段 2 范围：地形与楼梯（怪物/物品/资源点投放待阶段 3 实体模型接入）。

const MAX_ROOMS := 14  # 生成尝试数（相机视口下提升每层房间与遭遇密度）
const ROOM_MIN_SIZE := 6
const ROOM_MAX_SIZE := 8
const DUNGEON_WIDTH := 44
const DUNGEON_HEIGHT := 30


## 生成秘境一层。boss_floor = true 时为最深层（末房中央留给 BOSS，无下行山径）。
## 返回 {map: GameMap, player_start: Vector2i, boss_spot: Vector2i}。
static func generate_floor(
	floor_number: int, rng: RandomNumberGenerator,
	realm_id := "", realm_depth := 1, boss_floor := false
) -> Dictionary:
	var map := GameMap.new(DUNGEON_WIDTH, DUNGEON_HEIGHT, 12)
	map.map_type = "realm"
	map.floor_number = floor_number
	map.realm_id = realm_id
	map.realm_depth = realm_depth
	map.terrain.fill(GameMap.T_WALL)

	var rooms: Array = []
	var player_start := Vector2i(-1, -1)
	for _attempt in range(MAX_ROOMS):
		var room_w := rng.randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var room_h := rng.randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var x := rng.randi_range(1, map.width - room_w - 2)
		var y := rng.randi_range(1, map.height - room_h - 2)
		var room := Rect2i(x, y, room_w, room_h)
		if _intersects_any(room, rooms):
			continue
		for px in range(room.position.x + 1, room.end.x):
			for py in range(room.position.y + 1, room.end.y):
				map.set_tile(px, py, GameMap.T_FLOOR)
		if rooms.is_empty():
			player_start = _rect_center(room)
		else:
			for cell in _tunnel(_rect_center(rooms[rooms.size() - 1]), _rect_center(room), rng):
				map.set_tile(cell.x, cell.y, GameMap.T_FLOOR)
		rooms.append(room)

	map.upstairs_xy = player_start
	if boss_floor:
		map.downstairs_xy = Vector2i(-1, -1)
	else:
		map.downstairs_xy = _rect_center(rooms[rooms.size() - 1])
	return {
		"map": map,
		"player_start": player_start,
		"boss_spot": _rect_center(rooms[rooms.size() - 1]),
		"rooms": rooms,
	}


static func _rect_center(room: Rect2i) -> Vector2i:
	return Vector2i((room.position.x + room.end.x) / 2, (room.position.y + room.end.y) / 2)


static func _intersects_any(room: Rect2i, rooms: Array) -> bool:
	for other in rooms:
		if room.position.x <= other.end.x and room.end.x >= other.position.x \
		and room.position.y <= other.end.y and room.end.y >= other.position.y:
			return true
	return false


## L 形走廊，先横后竖或先竖后横随机。
static func _tunnel(start: Vector2i, end: Vector2i, rng: RandomNumberGenerator) -> Array:
	var corner := Vector2i(end.x, start.y) if rng.randf() < 0.5 else Vector2i(start.x, end.y)
	var cells: Array = []
	for cell in _walk_line(start, corner):
		cells.append(cell)
	for cell in _walk_line(corner, end):
		cells.append(cell)
	return cells


static func _walk_line(a: Vector2i, b: Vector2i) -> Array:
	var cells: Array = [a]
	var x := a.x
	var y := a.y
	while x != b.x:
		x += signi(b.x - x)
		cells.append(Vector2i(x, y))
	while y != b.y:
		y += signi(b.y - y)
		cells.append(Vector2i(x, y))
	return cells
