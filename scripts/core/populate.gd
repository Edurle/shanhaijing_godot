class_name Populate
extends RefCounted
## 投放——Python 版 worldgen._populate_world / procgen._populate_room 的移植。
## 世界按区域难度低密度游荡投放（出生点安全区）；秘境按房间概率投放。

const MONSTER_DENSITY := 1.0 / 240.0  # 每可走格游荡异兽密度（旅行可绕行）
const CENTER_MONSTER_DENSITY := 1.0 / 500.0  # 中山经腹地更安宁
const ITEM_DENSITY := 1.0 / 500.0
const WORLD_ELITE_CHANCE := 0.08
const REALM_ELITE_CHANCE := 0.1
const SPAWN_SAFE_RADIUS := 14  # 出生点曼哈顿距离内不投放任何异兽


## 大世界投放：游荡异兽 + 散落物品（按区域难度，中心区更稀）。
static func populate_world(map: GameMap, content: ContentDb, rng: RandomNumberGenerator, player: Actor) -> void:
	var walkable: Array = []
	for x in range(map.width):
		for y in range(map.height):
			if map.is_walkable(x, y):
				walkable.append(Vector2i(x, y))
	_shuffle(walkable, rng)
	var center_index := _center_index(content)
	var monsters_left := maxi(6, int(walkable.size() * MONSTER_DENSITY))
	var items_left := maxi(4, int(walkable.size() * ITEM_DENSITY))
	for cell in walkable:
		if monsters_left <= 0 and items_left <= 0:
			break
		var x: int = cell.x
		var y: int = cell.y
		if map.actor_at(x, y) != null or not map.item_at(x, y).is_empty():
			continue
		var near_spawn := absi(x - player.x) + absi(y - player.y) <= SPAWN_SAFE_RADIUS
		var in_center := map.region_at(x, y) == center_index
		var budget := CENTER_MONSTER_DENSITY if in_center else MONSTER_DENSITY
		if monsters_left > 0 and not near_spawn and rng.randf() < (budget / MONSTER_DENSITY) * 0.7:
			var difficulty := int(content.regions[map.region_at(x, y)]["base_difficulty"])
			var monster := content.build_monster(
				content.random_monster_id(difficulty, rng), x, y,
				rng.randf() < WORLD_ELITE_CHANCE
			)
			map.actors.append(monster)
			monsters_left -= 1
		elif items_left > 0 and not near_spawn:
			var difficulty := int(content.regions[map.region_at(x, y)]["base_difficulty"])
			map.items.append(content.build_item(content.random_item_id(difficulty, rng), x, y))
			items_left -= 1


## 秘境层投放：按房间概率（出生房间不放怪）；BOSS 层末房中央盘踞 BOSS。
static func populate_floor(
	map: GameMap, content: ContentDb, rng: RandomNumberGenerator,
	difficulty: int, rooms: Array, boss_floor := false, boss_id := ""
) -> void:
	var monster_cfg: Dictionary = content.per_room.get("monsters", {"chance": 0.6, "min": 1, "max": 2})
	var item_cfg: Dictionary = content.per_room.get("items", {"chance": 0.4, "min": 1, "max": 2})
	for i in range(rooms.size()):
		var room: Rect2i = rooms[i]
		var skip_first := i == 0
		if not skip_first and rng.randf() < float(monster_cfg["chance"]):
			for _n in range(rng.randi_range(int(monster_cfg["min"]), int(monster_cfg["max"]))):
				_place_in_room(map, content, rng, room, difficulty, true)
		if rng.randf() < float(item_cfg["chance"]):
			for _n in range(rng.randi_range(int(item_cfg["min"]), int(item_cfg["max"]))):
				_place_in_room(map, content, rng, room, difficulty, false)
	if boss_floor and boss_id != "":
		# BOSS 层：末房清场后中央盘踞
		var boss_room: Rect2i = rooms[rooms.size() - 1]
		var center := Vector2i((boss_room.position.x + boss_room.end.x) / 2, (boss_room.position.y + boss_room.end.y) / 2)
		for actor in map.actors.duplicate():
			if boss_room.has_point(Vector2(actor.x, actor.y)):
				map.actors.erase(actor)
		map.actors.append(content.build_monster(boss_id, center.x, center.y))


static func _place_in_room(
	map: GameMap, content: ContentDb, rng: RandomNumberGenerator,
	room: Rect2i, difficulty: int, is_monster: bool
) -> void:
	for _try in range(16):
		var x := rng.randi_range(room.position.x + 1, room.end.x - 1)
		var y := rng.randi_range(room.position.y + 1, room.end.y - 1)
		if map.is_walkable(x, y) and map.actor_at(x, y) == null and map.item_at(x, y).is_empty():
			if is_monster:
				map.actors.append(content.build_monster(
					content.random_monster_id(difficulty, rng), x, y,
					rng.randf() < REALM_ELITE_CHANCE
				))
			else:
				map.items.append(content.build_item(content.random_item_id(difficulty, rng), x, y))
			return


static func _center_index(content: ContentDb) -> int:
	for i in range(content.regions.size()):
		if String(content.regions[i]["zone"]) == "center":
			return i
	return 0


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
