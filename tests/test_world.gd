extends SceneTree
## Headless 世界/秘境生成测试：godot --headless -s tests/test_world.gd --path <工程>
## 锁定 Python 版 worldgen/procgen/world_state 的核心不变式。


func _init() -> void:
	var failed := 0
	var content = load("res://scripts/core/content_db.gd").new()
	var errors: PackedStringArray = content.load_all("res://data/content")
	if not errors.is_empty():
		print("FAIL 内容校验失败: " + "\n".join(errors))
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	var state = load("res://scripts/core/world_state.gd").new()
	state.content = content
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	state.rng = rng
	var gen_error: String = state.generate_new_world()
	failed += _check(gen_error.is_empty(), "世界生成应成功（错误: %s）" % gen_error)
	var elapsed := Time.get_ticks_msec() - t0
	print("世界生成耗时 %d ms（240x150）" % elapsed)
	failed += _check(elapsed < 10000, "世界生成应在 10s 内完成（实测 %d ms）" % elapsed)

	var world = state.world
	var map_script = load("res://scripts/core/game_map.gd")

	# 1. 区域覆盖：6 区域都出现
	var zones := {}
	for i in range(world.region_ids.size()):
		zones[world.region_ids[i]] = true
	failed += _check(zones.size() == 6, "世界应含全部 6 区域，实际 %d" % zones.size())

	# 2. 秘境门：与 realms.json 一一对应，且全部可达
	failed += _check(
		world.gates.size() == content.realms.size(),
		"秘境门应 %d 座，实际 %d" % [content.realms.size(), world.gates.size()]
	)
	var reached = load("res://scripts/core/worldgen.gd")._flood_reachable(world, world.spawn_xy)
	var gates_reachable := true
	for gate in world.gates:
		if reached[gate["x"] * world.height + gate["y"]] == 0:
			gates_reachable = false
	failed += _check(gates_reachable, "所有秘境门应从出生点可达")

	# 3. 出生点：可走且在中山经
	failed += _check(world.is_walkable(world.spawn_xy.x, world.spawn_xy.y), "出生点应可走")
	var spawn_zone: int = world.region_at(world.spawn_xy.x, world.spawn_xy.y)
	failed += _check(
		String(content.regions[spawn_zone]["zone"]) == "center",
		"出生点应在中山经"
	)

	# 4. 边界围栏：外圈 2 格全山
	var fence_ok := true
	for x in range(world.width):
		for y in range(2):
			if world.tile_at(x, y) != map_script.T_MOUNTAIN or world.tile_at(x, world.height - 1 - y) != map_script.T_MOUNTAIN:
				fence_ok = false
	for y in range(world.height):
		for x in range(2):
			if world.tile_at(x, y) != map_script.T_MOUNTAIN or world.tile_at(world.width - 1 - x, y) != map_script.T_MOUNTAIN:
				fence_ok = false
	failed += _check(fence_ok, "世界边界 2 格应为山脉围栏")

	# 5. 名山：每区域至少 1 座
	var landmark_regions := {}
	for lm in world.landmarks:
		landmark_regions[lm["region_id"]] = true
	failed += _check(
		landmark_regions.size() == content.regions.size(),
		"每区域应有名山，实际覆盖 %d/%d" % [landmark_regions.size(), content.regions.size()]
	)

	# 6. 秘境层生成：首层有上行+下行山径；最深层无下行（BOSS 层）
	var realm_id: String = content.realms.keys()[0]
	var realm_def: Dictionary = content.realms[realm_id]
	state.enter_realm(realm_id, world.spawn_xy)
	failed += _check(state.current.map_type == "realm", "入秘境后地图类型应为 realm")
	failed += _check(
		state.player_xy() == state.current.upstairs_xy,
		"入秘境应落在上行山径"
	)
	failed += _check(
		state.current.downstairs_xy.x >= 0,
		"非最深层应有下行山径"
	)
	failed += _check(
		state.current.is_walkable(state.current.upstairs_xy.x, state.current.upstairs_xy.y),
		"上行山径应可走"
	)

	# 7. 层间往返：下行 → 深度+1；回上层 → 深度-1；第 1 层回世界
	state.next_floor()
	failed += _check(state.current.realm_depth == 2, "下行后应为第 2 层")
	state.previous_floor()
	failed += _check(state.current.realm_depth == 1, "回上层后应为第 1 层")
	state.previous_floor()
	failed += _check(
		state.current.map_type == "world" and state.player_xy() == world.spawn_xy,
		"第 1 层回世界应落在入口"
	)

	# 8. 最深层（BOSS 层）无下行山径
	var max_depth := int(realm_def["depth"])
	state.enter_realm(realm_id, world.spawn_xy)  # 重新踏入再下探
	for _d in range(max_depth):
		state.next_floor()
	failed += _check(
		state.current.realm_depth == max_depth and state.current.downstairs_xy.x < 0,
		"最深层（第 %d 层）应无下行山径" % max_depth
	)
	state.next_floor()  # 已最深：应无操作
	failed += _check(state.current.realm_depth == max_depth, "最深层下行应被拒绝")

	# 9. 层缓存复用：回世界再进同一秘境，第 1 层应保持已探索状态
	state.previous_floor()  # 逐层回到第 1 层（走缓存）
	while state.current.map_type == "realm" and state.current.realm_depth > 1:
		state.previous_floor()
	var explored_before := 0
	for i in range(state.current.explored.size()):
		explored_before += state.current.explored[i]
	state.exit_realm()
	state.enter_realm(realm_id, world.spawn_xy)
	var explored_after := 0
	for i in range(state.current.explored.size()):
		explored_after += state.current.explored[i]
	failed += _check(
		explored_after == explored_before and explored_before > 0,
		"秘境层缓存应保留探索状态（%d → %d）" % [explored_before, explored_after]
	)

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 世界/秘境生成与切换全部不变式")
		quit(0)


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
