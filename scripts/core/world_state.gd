class_name WorldState
extends RefCounted
## 世界/秘境切换状态机——Python 版 engine.py 地图管理部分的移植（模型层）。
## 持有：大世界常驻 + 秘境按 (realm_id, depth) 缓存 + 行者 Actor + 归途坐标。

const WORLD_FOV := 14

var content: ContentDb
var rng := RandomNumberGenerator.new()
var world: GameMap
var realms := {}  # realm_id -> {depth: GameMap}
var current_realm := ""
var current: GameMap
var world_return_xy := Vector2i.ZERO
var known_gates := {}  # Vector2i -> true（踏入过的秘境门，山海图卷用）
var player: Actor
var on_floor_generated: Callable  # 引擎注入（秘境层生成后投放怪物的钩子）


## 生成大世界（不变量失败自动换种子，至多 3 次）；返回错误串（空 = 成功）。
func generate_new_world() -> String:
	var class_pair: Array = ["leifa", "fushi"]
	for _attempt in range(3):
		rng.randomize()
		var result: Variant = WorldGen.generate_world(content, rng)
		if result is GameMap:
			world = result
			player = content.build_player(class_pair, world.spawn_xy.x, world.spawn_xy.y)
			Populate.populate_world(world, content, rng, player)
			switch_to(world, world.spawn_xy)
			current_realm = ""
			return ""
		push_warning("世界生成失败，换种子重试：%s" % result)
	return "世界生成 3 次均失败"


func player_xy() -> Vector2i:
	return Vector2i(player.x, player.y)


## 地图切换：行者从旧图摘除、挂入新图并落位（供 AI 感知与占位判定）。
func switch_to(map: GameMap, xy: Vector2i) -> void:
	if current != null and current.actors.has(player):
		current.actors.erase(player)
	current = map
	player.x = xy.x
	player.y = xy.y
	if not map.actors.has(player):
		map.actors.append(player)


## 秘境层难度 = 所属区域基础难度 + (层深-1)*2。
func realm_difficulty(realm_id: String, depth: int) -> int:
	var region_id := String(content.realms[realm_id]["region"])
	for region in content.regions:
		if String(region["id"]) == region_id:
			return int(region["base_difficulty"]) + (depth - 1) * 2
	return 1


## 踏入秘境第 1 层；缓存存在则复用（保留探索过的层）。
func enter_realm(realm_id: String, return_xy: Vector2i) -> void:
	world_return_xy = return_xy
	var floors: Dictionary = realms.get_or_add(realm_id, {})
	if floors.has(1):
		switch_to(floors[1], floors[1].upstairs_xy)
	else:
		current = _generate_realm_floor(realm_id, 1)
	current_realm = realm_id
	current.compute_fov(player.x, player.y)


## 从秘境回世界，落在入口坐标。
func exit_realm() -> void:
	if current_realm == "":
		return
	realms.get_or_add(current_realm, {})[current.realm_depth] = current
	current_realm = ""
	switch_to(world, world_return_xy)
	current.compute_fov(player.x, player.y)


## 秘境内沿山径下行一层（难度递增；真气全复的钩子在引擎侧）。
func next_floor() -> void:
	var realm_id := current.realm_id
	var depth := current.realm_depth
	if realm_id == "" or depth >= int(content.realms[realm_id]["depth"]):
		return
	realms.get_or_add(realm_id, {})[depth] = current
	var floors: Dictionary = realms[realm_id]
	if floors.has(depth + 1):
		switch_to(floors[depth + 1], floors[depth + 1].upstairs_xy)
	else:
		current = _generate_realm_floor(realm_id, depth + 1)
	current.compute_fov(player.x, player.y)


## 秘境内回上层；已在第 1 层则回世界。
func previous_floor() -> void:
	if current.realm_depth <= 1:
		exit_realm()
		return
	var realm_id := current.realm_id
	realms.get_or_add(realm_id, {})[current.realm_depth] = current
	var above: GameMap = realms[realm_id][current.realm_depth - 1]
	switch_to(above, above.downstairs_xy)
	current.compute_fov(player.x, player.y)


func _generate_realm_floor(realm_id: String, depth: int) -> GameMap:
	var realm_def: Dictionary = content.realms[realm_id]
	var is_boss := depth >= int(realm_def["depth"])
	var result: Dictionary = ProcGen.generate_floor(
		realm_difficulty(realm_id, depth), rng, realm_id, depth, is_boss
	)
	var map: GameMap = result["map"]
	Populate.populate_floor(map, content, rng, realm_difficulty(realm_id, depth), result["rooms"], is_boss, String(realm_def["boss"]))
	switch_to(map, result["player_start"])
	return map


## HUD 地名：世界显示区域名，秘境显示秘境名与层深。
func location_name() -> String:
	if current.map_type == "realm" and content.realms.has(current.realm_id):
		var realm_def: Dictionary = content.realms[current.realm_id]
		return "%s · 第 %d 层" % [content.localize(realm_def["name"]), current.realm_depth]
	var idx := current.region_at(player.x, player.y)
	if idx >= 0 and idx < content.regions.size():
		return content.localize(content.regions[idx]["name"])
	return "山海大陆"
