class_name WorldGen
extends RefCounted
## 占位世界生成：确定性的丘陵+山脊测试图（阶段 2 移植 Python 版完整六大经世界）。

const SEED_TABLE_SIZE := 256


## 生成一张 80x45 的开阔测试图：外圈山界 + 内部确定性山脊/林斑/水洼，玩家出生于中心。
static func make_test_map() -> GameMap:
	var map := GameMap.new(80, 45, 14)
	for x in range(map.width):
		for y in range(map.height):
			var kind := GameMap.T_PLAIN
			if x == 0 or y == 0 or x == map.width - 1 or y == map.height - 1:
				kind = GameMap.T_MOUNTAIN
			else:
				var n := _noise2(x, y)
				if n > 74:
					kind = GameMap.T_MOUNTAIN
				elif n < 22:
					kind = GameMap.T_FOREST
				elif n > 66 and n <= 70:
					kind = GameMap.T_WATER
			map.set_tile(x, y, kind)
	# 出生点周围 2 格清空，保证落脚与视野
	var cx := map.width / 2
	var cy := map.height / 2
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if map.in_bounds(cx + dx, cy + dy):
				map.set_tile(cx + dx, cy + dy, GameMap.T_PLAIN)
	return map


## 简易确定性值噪声（阶段 2 换 RandomNumberGenerator + 平滑/分区逻辑）。
static func _noise2(x: int, y: int) -> int:
	var v := (x * 374761393 + y * 668265263) % 997
	v = (v * (v + 11)) % 251
	return v
