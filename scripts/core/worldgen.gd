class_name WorldGen
extends RefCounted
## 大世界（山海大陆）生成——Python 版 worldgen.py 的完整移植。
## 噪声地形 + 区域环带 + 河流雕刻 + 深渊 + 名山 + 秘境门 + 连通性保障。
## 阶段 2 范围：地形/门/地标（游荡异兽与物品投放待阶段 3 实体模型接入）。

const WORLD_WIDTH := 240
const WORLD_HEIGHT := 150
const WORLD_FOV_RADIUS := 14

# 地形阈值（elevation/moisture 归一化 0-1）
const ELEV_SNOW := 0.86
const ELEV_MOUNTAIN := 0.70
const ELEV_HILL := 0.56
const ELEV_WATER := 0.30
const MOIST_FOREST := 0.62

# 区域环带（归一化椭圆距离 d：中心 0，角落最大 √2）
const CENTER_RADIUS := 0.38
const RIDGE_INNER := 0.41
const RIDGE_INNER_WIDTH := 0.055
const OUTER_RADIUS := 0.86
const RIDGE_OUTER := 0.855
const RIDGE_OUTER_WIDTH := 0.06

const WORLD_MARGIN := 2
const RIVER_SOURCES := 9
const RIVER_BRIDGE_EVERY := 9
const LANDMARK_MIN_GAP := 16
const SPAWN_CLEAR_RADIUS := 2


## 生成大世界；失败（如秘境门无处安放）返回错误串，调用方换种子重试。
static func generate_world(content: ContentDb, rng: RandomNumberGenerator) -> Variant:
	var w := WORLD_WIDTH
	var h := WORLD_HEIGHT
	var map := GameMap.new(w, h, WORLD_FOV_RADIUS)
	map.map_type = "world"

	# ---- 1. 区域网格 ----
	_region_grid(map, content)

	# ---- 2. 高度/湿度噪声 ----
	var elev := _fbm(w, h, rng, [40, 16, 7])
	var moist := _fbm(w, h, rng, [28, 11])

	# ---- 3. 山脊环带抬升（区域屏障，噪声留山口） ----
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	var ridge := PackedFloat32Array()
	var gaps := _fbm(w, h, rng, [22, 9])
	ridge.resize(w * h)
	for x in range(w):
		var nx := (x - cx) / (w / 2.0)
		for y in range(h):
			var ny := (y - cy) / (h / 2.0)
			var d := sqrt(nx * nx + ny * ny)
			var band := maxf(_band(d, RIDGE_INNER, RIDGE_INNER_WIDTH), _band(d, RIDGE_OUTER, RIDGE_OUTER_WIDTH))
			var idx := x * h + y
			elev[idx] = elev[idx] * (1.0 - 0.85 * band) + band * (0.30 + 0.70 * gaps[idx])

	# ---- 4. 生物群系映射 ----
	for i in range(w * h):
		var e := elev[i]
		var kind: int
		if e >= ELEV_SNOW:
			kind = GameMap.T_SNOW
		elif e >= ELEV_MOUNTAIN:
			kind = GameMap.T_MOUNTAIN
		elif e >= ELEV_HILL:
			kind = GameMap.T_HILL
		elif e < ELEV_WATER:
			kind = GameMap.T_WATER
		elif moist[i] >= MOIST_FOREST:
			kind = GameMap.T_FOREST
		else:
			kind = GameMap.T_PLAIN
		map.terrain[i] = kind

	# ---- 5. 深渊裂谷（大荒经专属） ----
	var outer_index := _zone_index(content, "outer")
	var rift := _fbm(w, h, rng, [30, 12])
	for i in range(w * h):
		if map.region_ids[i] == outer_index and rift[i] > 0.68 and elev[i] < ELEV_HILL:
			map.terrain[i] = GameMap.T_ABYSS

	# ---- 6. 河流（山顶发源，最陡下降） ----
	var peaks: Array = []
	for x in range(w):
		for y in range(h):
			var idx := x * h + y
			if map.terrain[idx] == GameMap.T_MOUNTAIN:
				peaks.append([idx, elev[idx]])
	_shuffle(peaks, rng)
	peaks.sort_custom(func(a, b): return a[1] > b[1])
	var sources := minf(RIVER_SOURCES * 6, peaks.size())
	for i in range(minf(RIVER_SOURCES, sources)):
		var idx: int = peaks[i][0]
		_carve_river(map, elev, rng, idx % h, idx / h)

	# ---- 7. 水岸滩涂（水旁平原 → 岸；边界排除） ----
	for x in range(w):
		for y in range(h):
			if map.tile_at(x, y) != GameMap.T_PLAIN:
				continue
			if x < WORLD_MARGIN or y < WORLD_MARGIN or x >= w - WORLD_MARGIN or y >= h - WORLD_MARGIN:
				continue
			var near_water := false
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if map.tile_at(x + dx, y + dy) == GameMap.T_WATER:
						near_water = true
						break
				if near_water:
					break
			if near_water:
				map.set_tile(x, y, GameMap.T_SHORE)

	# ---- 8. 世界边界围栏 ----
	for x in range(w):
		for y in range(h):
			if x < WORLD_MARGIN or y < WORLD_MARGIN or x >= w - WORLD_MARGIN or y >= h - WORLD_MARGIN:
				map.set_tile(x, y, GameMap.T_MOUNTAIN)

	# ---- 9. 出生点（区域中心可走格，安全清场） ----
	var spawn := _find_spawn(map, w / 2, h / 2, rng)
	for dx in range(-SPAWN_CLEAR_RADIUS, SPAWN_CLEAR_RADIUS + 1):
		for dy in range(-SPAWN_CLEAR_RADIUS, SPAWN_CLEAR_RADIUS + 1):
			var px := spawn.x + dx
			var py := spawn.y + dy
			if map.in_bounds(px, py):
				var kind := map.tile_at(px, py)
				if kind in [GameMap.T_WATER, GameMap.T_RIVER, GameMap.T_ABYSS]:
					map.set_tile(px, py, GameMap.T_BRIDGE)
				elif kind in [GameMap.T_MOUNTAIN, GameMap.T_SNOW]:
					map.set_tile(px, py, GameMap.T_HILL)

	# ---- 10. 名山地标 + 连通锚点 ----
	map.landmarks = _place_landmarks(map, content, rng)
	var anchors: Array = [spawn]
	for region in content.regions:
		anchors.append(_region_anchor(map, content, String(region["zone"]), rng))
	var connectivity_error := _ensure_connectivity(map, spawn, anchors)
	if not connectivity_error.is_empty():
		return connectivity_error

	# ---- 11. 秘境入口（可达约束 + 按区域难度控制远近） ----
	var gate_error := _place_realm_gates(map, content, rng, spawn)
	if not gate_error.is_empty():
		return gate_error

	map.spawn_xy = spawn
	return map


# ---- 噪声 ----

static func _smoothstep(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _band(dist: float, center: float, width: float) -> float:
	return 1.0 - _smoothstep(absf(dist - center) / width)


## 低分辨率随机网格 + 双线性插值，输出 0-1（w*h 平铺）。
static func _value_noise(w: int, h: int, rng: RandomNumberGenerator, cell: int) -> PackedFloat32Array:
	var gw := maxi(2, w / cell + 2)
	var gh := maxi(2, h / cell + 2)
	var grid := PackedFloat32Array()
	grid.resize(gw * gh)
	for i in range(gw * gh):
		grid[i] = rng.randf()
	var field := PackedFloat32Array()
	field.resize(w * h)
	for x in range(w):
		var gx := float(x) * (gw - 1) / float(w - 1)
		var x0 := int(gx)
		var x1 := mini(x0 + 1, gw - 1)
		var fx := gx - x0
		for y in range(h):
			var gy := float(y) * (gh - 1) / float(h - 1)
			var y0 := int(gy)
			var y1 := mini(y0 + 1, gh - 1)
			var fy := gy - y0
			var top: float = grid[y0 * gw + x0] * (1.0 - fx) + grid[y0 * gw + x1] * fx
			var bottom: float = grid[y1 * gw + x0] * (1.0 - fx) + grid[y1 * gw + x1] * fx
			field[x * h + y] = top * (1.0 - fy) + bottom * fy
	return field


## 3x3 均值模糊（环绕近似；世界四周是围栏山，边界影响可忽略）。
static func _blur(field: PackedFloat32Array, w: int, h: int, passes: int) -> PackedFloat32Array:
	var src := PackedFloat32Array(field)
	var out := PackedFloat32Array(field)
	for _pass in range(passes):
		var tmp := PackedFloat32Array(out)
		for x in range(w):
			var xp := (x + 1) % w
			var xm := (x - 1 + w) % w
			for y in range(h):
				var yp := (y + 1) % h
				var ym := (y - 1 + h) % h
				out[x * h + y] = (
					tmp[x * h + y] + tmp[xp * h + y] + tmp[xm * h + y]
					+ tmp[x * h + yp] + tmp[x * h + ym]
				) / 5.0
	return out


## 多倍频值噪声叠加（先粗后细），归一化 0-1。
static func _fbm(w: int, h: int, rng: RandomNumberGenerator, cells: Array) -> PackedFloat32Array:
	var fields: Array = []
	for cell in cells:
		var noise := _blur(_value_noise(w, h, rng, int(cell)), w, h, maxi(1, int(cell) / 8))
		fields.append(noise)
	var combined := PackedFloat32Array(fields[0])
	for i in range(1, fields.size()):
		var finer: PackedFloat32Array = fields[i]
		for j in range(combined.size()):
			combined[j] = combined[j] * 0.55 + finer[j] * 0.45
	var lo := combined[0]
	var hi := combined[0]
	for v in combined:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span := maxf(1e-9, hi - lo)
	for j in range(combined.size()):
		combined[j] = (combined[j] - lo) / span
	return combined


# ---- 区域 ----

static func _zone_index(content: ContentDb, zone: String) -> int:
	for i in range(content.regions.size()):
		if String(content.regions[i]["zone"]) == zone:
			return i
	return 0


## 每格所属区域 id：中山经居中，四方四象限（y 大为南），最外围大荒经。
static func _region_grid(map: GameMap, content: ContentDb) -> void:
	var w := map.width
	var h := map.height
	var zone_of := {}
	for i in range(content.regions.size()):
		zone_of[String(content.regions[i]["zone"])] = i
	var cx := (w - 1) / 2.0
	var cy := (h - 1) / 2.0
	for x in range(w):
		var nx := (x - cx) / (w / 2.0)
		for y in range(h):
			var ny := (y - cy) / (h / 2.0)
			var dist := sqrt(nx * nx + ny * ny)
			var zone: int = zone_of["outer"]
			if dist < OUTER_RADIUS:
				var vertical := absf(ny) > absf(nx)
				if vertical and ny > 0:
					zone = zone_of["south"]
				elif vertical:
					zone = zone_of["north"]
				elif nx > 0:
					zone = zone_of["east"]
				else:
					zone = zone_of["west"]
			if dist < CENTER_RADIUS:
				zone = zone_of["center"]
			map.region_ids[x * h + y] = zone


static func _region_anchor(map: GameMap, content: ContentDb, zone: String, rng: RandomNumberGenerator) -> Vector2i:
	## 区域连通锚点的大致位置。
	var cx := map.width / 2
	var cy := map.height / 2
	if zone == "center":
		return _find_spawn(map, cx, cy, rng)
	if zone == "outer":
		return _find_spawn(map, cx, WORLD_MARGIN + 6, rng)
	var delta: Array = {"south": [0, 1], "north": [0, -1], "east": [1, 0], "west": [-1, 0]}[zone]
	var rx := int(cx + delta[0] * map.width * 0.28)
	var ry := int(cy + delta[1] * map.height * 0.28)
	return _find_spawn(map, clampi(rx, 3, map.width - 4), clampi(ry, 3, map.height - 4), rng)


# ---- 地形雕刻 ----

## 自高处沿最陡下降雕刻一条河（宽 1），入湖/抵界/汇流即止；每隔 N 格架桥。
static func _carve_river(map: GameMap, elev: PackedFloat32Array, rng: RandomNumberGenerator, x: int, y: int) -> void:
	var w := map.width
	var h := map.height
	var visited := {}
	var bridge_countdown := RIVER_BRIDGE_EVERY
	for _step in range(400):
		if not (x > 0 and x < w - 1 and y > 0 and y < h - 1):
			return
		var key := Vector2i(x, y)
		if visited.has(key):
			return
		visited[key] = true
		var kind := map.tile_at(x, y)
		if kind == GameMap.T_WATER or kind == GameMap.T_ABYSS:
			return
		if kind == GameMap.T_RIVER:
			return  # 并入已有水系
		map.set_tile(x, y, GameMap.T_RIVER)
		bridge_countdown -= 1
		if bridge_countdown <= 0:
			map.set_tile(x, y, GameMap.T_BRIDGE)
			bridge_countdown = RIVER_BRIDGE_EVERY
		# 8 邻域最低者；平地随机下坡避免死锁
		var best := Vector2i(-1, -1)
		var best_e := elev[x * h + y]
		var candidates: Array = []
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				if not (nx > 0 and nx < w - 1 and ny > 0 and ny < h - 1):
					continue
				var e := elev[nx * h + ny]
				candidates.append([e, nx, ny])
				if e < best_e:
					best_e = e
					best = Vector2i(nx, ny)
		if best.x < 0:
			_shuffle(candidates, rng)
			if candidates.is_empty():
				return
			best = Vector2i(candidates[0][1], candidates[0][2])
		x = best.x
		y = best.y


# ---- 连通性 ----

## 从出生点 8 邻域泛洪的可走区域（BFS）。
static func _flood_reachable(map: GameMap, spawn: Vector2i) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(map.width * map.height)
	if not map.is_walkable(spawn.x, spawn.y):
		return reached
	var stack: Array = [spawn]
	reached[spawn.x * map.height + spawn.y] = 1
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cell.x + dx
				var ny := cell.y + dy
				if map.in_bounds(nx, ny) and reached[nx * map.height + ny] == 0 and map.is_walkable(nx, ny):
					reached[nx * map.height + ny] = 1
					stack.append(Vector2i(nx, ny))
	return reached


## 直线凿径：山/雪 → 丘，水/河 → 桥（连通性兜底）。
static func _carve_line(map: GameMap, start: Vector2i, target: Vector2i) -> void:
	var x := start.x
	var y := start.y
	for _step in range(maxi(absi(target.x - x), absi(target.y - y)) * 2 + 1):
		if x == target.x and y == target.y:
			return
		var dx := signi(target.x - x)
		var dy := signi(target.y - y)
		x += dx
		y += dy
		if not map.is_walkable(x, y):
			var kind := map.tile_at(x, y)
			if kind in [GameMap.T_WATER, GameMap.T_RIVER, GameMap.T_ABYSS]:
				map.set_tile(x, y, GameMap.T_BRIDGE)
			else:
				map.set_tile(x, y, GameMap.T_HILL)


## 验证锚点可达；不可达则向出生点方向直线凿径，最多补 3 轮。
static func _ensure_connectivity(map: GameMap, spawn: Vector2i, anchors: Array) -> String:
	for _round in range(3):
		var reached := _flood_reachable(map, spawn)
		var unreachable: Array = []
		for anchor in anchors:
			if reached[anchor.x * map.height + anchor.y] == 0:
				unreachable.append(anchor)
		if unreachable.is_empty():
			return ""
		for anchor in unreachable:
			_carve_line(map, anchor, spawn)
	return ""


# ---- 名山与秘境门 ----

## 每区域挑海拔最高的山峰作为名山（保持间距），取 regions.json 山名。
static func _place_landmarks(map: GameMap, content: ContentDb, rng: RandomNumberGenerator) -> Array:
	var landmarks: Array = []
	for idx in range(content.regions.size()):
		var region: Dictionary = content.regions[idx]
		var want := int(region.get("mountain_count", 3))
		var peaks: Array = []
		for x in range(map.width):
			for y in range(map.height):
				var i := x * map.height + y
				if map.terrain[i] == GameMap.T_MOUNTAIN and map.region_ids[i] == idx:
					peaks.append(Vector2i(x, y))
		if peaks.is_empty():
			for x in range(map.width):
				for y in range(map.height):
					var i := x * map.height + y
					if map.terrain[i] == GameMap.T_SNOW and map.region_ids[i] == idx:
						peaks.append(Vector2i(x, y))
		_shuffle(peaks, rng)
		var chosen: Array = []
		for name_index in range(region["mountains"].size()):
			if chosen.size() >= want:
				break
			var found := false
			for peak in peaks:
				if _gap_ok(peak, chosen, LANDMARK_MIN_GAP) and _gap_ok_l(peak, landmarks, LANDMARK_MIN_GAP):
					chosen.append(peak)
					found = true
					break
			if not found:
				break
			landmarks.append({
				"x": chosen[chosen.size() - 1].x,
				"y": chosen[chosen.size() - 1].y,
				"region_id": region["id"],
				"name": content.localize(region["mountains"][name_index]),
			})
	return landmarks


static func _gap_ok(peak: Vector2i, chosen: Array, min_gap: int) -> bool:
	for c in chosen:
		if absi(peak.x - c.x) + absi(peak.y - c.y) < min_gap:
			return false
	return true


static func _gap_ok_l(peak: Vector2i, landmarks: Array, min_gap: int) -> bool:
	for l in landmarks:
		if absi(peak.x - l["x"]) + absi(peak.y - l["y"]) < min_gap:
			return false
	return true


## 把 realms.json 的秘境入口撒到所属区域的可达格上（难度越高离出生点越远）。
## 不变量：每个秘境必有入口；间距约束逐级放宽，仍放不下则报错换种子。
static func _place_realm_gates(map: GameMap, content: ContentDb, rng: RandomNumberGenerator, spawn: Vector2i) -> String:
	var placed: Array = []
	var region_index := {}
	for i in range(content.regions.size()):
		region_index[String(content.regions[i]["id"])] = i
	var reached := _flood_reachable(map, spawn)
	var missing: Array = []
	for rid in content.realms:
		var realm: Dictionary = content.realms[rid]
		var idx: int = region_index[String(realm["region"])]
		var base := int(content.regions[idx]["base_difficulty"])
		var min_dist := 18 + base * 3
		var coords: Array = []
		var relaxed: Array = []
		for x in range(map.width):
			for y in range(map.height):
				var i := x * map.height + y
				if map.region_ids[i] == idx and reached[i] == 1 and map.is_walkable(x, y):
					if absi(x - spawn.x) + absi(y - spawn.y) >= min_dist:
						coords.append(Vector2i(x, y))
					relaxed.append(Vector2i(x, y))
		if coords.is_empty():
			coords = relaxed
		var done := false
		for min_gap in [12, 4, 1]:
			_shuffle(coords, rng)
			for cell in coords:
				if _gates_gap_ok(cell, placed, min_gap):
					map.gates.append({"realm_id": String(rid), "x": cell.x, "y": cell.y, "sealed": false})
					placed.append(cell)
					done = true
					break
			if done:
				break
		if not done:
			missing.append(rid)
	if not missing.is_empty():
		return "秘境入口无处安放：%s" % str(missing)
	return ""


static func _gates_gap_ok(cell: Vector2i, placed: Array, min_gap: int) -> bool:
	for p in placed:
		if absi(cell.x - p.x) + absi(cell.y - p.y) < min_gap:
			return false
	return true


## 从 (x, y) 螺旋向外找第一个可走格。
static func _find_spawn(map: GameMap, x: int, y: int, rng: RandomNumberGenerator) -> Vector2i:
	if map.is_walkable(x, y):
		return Vector2i(x, y)
	for radius in range(1, maxi(map.width, map.height)):
		for _try in range(24):
			var nx := x + rng.randi_range(-radius, radius)
			var ny := y + rng.randi_range(-radius, radius)
			if nx > 0 and nx < map.width - 1 and ny > 0 and ny < map.height - 1 and map.is_walkable(nx, ny):
				return Vector2i(nx, ny)
	return Vector2i(x, y)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
