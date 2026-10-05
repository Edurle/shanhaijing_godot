class_name Board
extends Node2D
## 棋盘渲染（视图层）：阶段 1-2 用程序化水墨色块占位，AI 素材到位后切换为贴图绘制。
## 重绘时机由 main 驱动（地图/视野/单位变动 → queue_redraw），无逐帧开销。

const CELL := 32

# 色板唯一来源：ink_palette.gd（theme.json 可覆盖），本文件不持有颜色常量。

var map: GameMap
var player: Actor
var target_cell := Vector2i(-1, -1)  # 瞄准/查看高亮格
var landing_cell := Vector2i(-1, -1)  # 择向落点预览
var travel_cell := Vector2i(-1, -1)  # 点击旅行目标（淡金虚框）
var _jitter := {}  # Vector2i -> 0..2 纸面颗粒抖动，避免大色块呆板
var _beast_textures := {}  # monster_id -> Texture2D/null（AI 素材缓存，缺失回退程序化占位）


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
	draw_rect(Rect2(0, 0, map.width * CELL, map.height * CELL), InkPalette.PAPER)
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
	_draw_overlays()


## 交互态高亮：目标四角框（朱）/ 择向落点（金角）。
func _draw_overlays() -> void:
	if target_cell.x >= 0:
		var px := target_cell.x * CELL
		var py := target_cell.y * CELL
		var color := InkPalette.VERMILION
		for corner in [
			[Vector2(px + 2, py + 2), Vector2(px + 10, py + 2), Vector2(px + 2, py + 2), Vector2(px + 2, py + 10)],
			[Vector2(px + CELL - 10, py + 2), Vector2(px + CELL - 2, py + 2), Vector2(px + CELL - 2, py + 2), Vector2(px + CELL - 2, py + 10)],
			[Vector2(px + 2, py + CELL - 2), Vector2(px + 10, py + CELL - 2), Vector2(px + 2, py + CELL - 2), Vector2(px + 2, py + CELL - 10)],
			[Vector2(px + CELL - 10, py + CELL - 2), Vector2(px + CELL - 2, py + CELL - 2), Vector2(px + CELL - 2, py + CELL - 2), Vector2(px + CELL - 2, py + CELL - 10)],
		]:
			draw_line(corner[0], corner[1], color, 2.0)
			draw_line(corner[2], corner[3], color, 2.0)
	if landing_cell.x >= 0:
		draw_rect(Rect2(landing_cell.x * CELL + 2, landing_cell.y * CELL + 2, CELL - 4, CELL - 4), InkPalette.GOLD, false, 2.0)
	if travel_cell.x >= 0:
		var tpos := Vector2(travel_cell.x * CELL + 6, travel_cell.y * CELL + 6)
		var tsize := Vector2(CELL - 12, CELL - 12)
		var dash: Color = Color(InkPalette.GOLD, 0.55)
		for seg in range(0, 4):
			draw_line(tpos + Vector2(seg * tsize.x / 4.0, 0), tpos + Vector2((seg + 0.6) * tsize.x / 4.0, 0), dash, 1.5)
			draw_line(tpos + Vector2(0, seg * tsize.y / 4.0), tpos + Vector2(0, (seg + 0.6) * tsize.y / 4.0), dash, 1.5)
			draw_line(tpos + Vector2(tsize.x, seg * tsize.y / 4.0), tpos + Vector2(tsize.x, (seg + 0.6) * tsize.y / 4.0), dash, 1.5)
			draw_line(tpos + Vector2(seg * tsize.x / 4.0, tsize.y), tpos + Vector2((seg + 0.6) * tsize.x / 4.0, tsize.y), dash, 1.5)


func _terrain_color(kind: int, x: int, y: int, seen: bool) -> Color:
	var base: Color = InkPalette.TERRAIN_COLORS.get(kind, InkPalette.PAPER)
	if kind == GameMap.T_PLAIN:
		# 宣纸底 + 三档颗粒抖动，模拟纸面吸墨不匀
		var j := int(_jitter.get(Vector2i(x, y), 0))
		base = InkPalette.PAPER.lightened(0.0 if j == 0 else InkPalette.PLAIN_JITTER)
	if not seen:
		base = base.lerp(InkPalette.INK_LIGHT, InkPalette.FOG_LERP)  # 记忆态罩一层灰墨
	return base


## 山体/石壁飞白：两笔浅色横皴，让浓墨块有笔触感（占位手法，素材期替换）。
func _draw_mountain_stroke(x: int, y: int) -> void:
	var px := x * CELL
	var py := y * CELL
	var stroke := InkPalette.INK_DEEP.lightened(0.28)
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
		draw_colored_polygon(pts, InkPalette.INK_MID if map.is_visible(down.x, down.y) else InkPalette.INK_LIGHT)
	var up := map.upstairs_xy
	if up.x >= 0 and map.is_explored(up.x, up.y):
		var c := _cell_center(up)
		var pts := PackedVector2Array([
			c + Vector2(-7, 6), c + Vector2(7, 6), c + Vector2(0, -7),
		])
		draw_colored_polygon(pts, InkPalette.VERMILION if map.is_visible(up.x, up.y) else InkPalette.INK_LIGHT)


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
		var seal: Color = InkPalette.INK_LIGHT if gate.get("sealed", false) else InkPalette.VERMILION
		draw_rect(Rect2(c - Vector2(10, 10), Vector2(20, 20)), seal, false, 2.5)
		draw_circle(c, 3.0, seal)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0)


## 地面物品：装备按品级着色（白装/材料/消耗品维持赭墨小方点）。
func _draw_items() -> void:
	for item in map.items:
		var x: int = item["x"]
		var y: int = item["y"]
		if not map.is_visible(x, y):
			continue
		var c := _cell_center(Vector2i(x, y))
		var dot := UiPanel.rarity_color(item, InkPalette.OCHRE)
		draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), dot)
		draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), InkPalette.INK_DEEP, false, 1.0)


func _draw_actor(actor: Actor) -> void:
	if not map.is_visible(actor.x, actor.y) and actor != player:
		return
	var center := _cell_center(Vector2i(actor.x, actor.y))
	if actor == player:
		draw_circle(center, 9.0, InkPalette.PLAYER_INK)
		draw_arc(center, 11.0, 0, TAU, 24, InkPalette.PAPER, 1.5)
		# 行者朝向剑锋（占位：一短笔）
		draw_line(center + Vector2(4, -4), center + Vector2(11, -11), InkPalette.INK_DEEP, 2.0)
		return
	var radius := 8.0 if not actor.elite else 10.0
	var texture := _beast_texture(actor)
	var below := radius + 7.0  # 血条距中心的纵向偏移
	if texture != null:
		# AI 素材期：40px 贴图（略溢出格子换辨识度，贴图自带留白边距）+ 右下五行小印；
		# 不画整环避免框住美术，金环仅精英保留（稀有反馈）
		var size := CELL + 8.0
		draw_texture_rect(texture, Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size)), false)
		var dot := center + Vector2(CELL / 2.0 - 6.0, CELL / 2.0 - 6.0)
		draw_circle(dot, 2.5, InkPalette.ELEMENT_COLORS.get(actor.element, InkPalette.INK_MID))
		draw_arc(dot, 3.5, 0, TAU, 12, InkPalette.PAPER, 1.0)
		if actor.elite:
			draw_arc(center, size / 2.0 + 1.0, 0, TAU, 32, InkPalette.GOLD, 1.5)
		below = size / 2.0 + 5.0
	else:
		if actor.elite:
			draw_circle(center, radius, InkPalette.ELITE_GOLD.darkened(0.25))
		else:
			draw_circle(center, radius, InkPalette.INK_DEEP)
		# 点睛：异兽唯一的亮色（贴图自带墨眼，素材期仅程序占位兽使用）
		draw_circle(center + Vector2(-2, -2), 1.6, InkPalette.VERMILION)
		var ring: Color = InkPalette.ELEMENT_COLORS.get(actor.element, InkPalette.INK_MID)
		draw_arc(center, radius + 3.0, 0, TAU, 24, ring, 2.0)
	# 血条细线（受伤才显示）
	var hp_ratio := float(actor.fighter.hp()) / maxf(1.0, actor.fighter.max_hp())
	if hp_ratio < 1.0:
		var bar_w := 22.0
		draw_rect(Rect2(center - Vector2(bar_w / 2, below), Vector2(bar_w, 3)), InkPalette.INK_LIGHT)
		draw_rect(Rect2(center - Vector2(bar_w / 2, below), Vector2(bar_w * hp_ratio, 3)), InkPalette.VERMILION)


## 异兽贴图（AI 素材期；缺失返回 null 回退程序化墨点占位）。
func _beast_texture(actor: Actor) -> Texture2D:
	var key := String(actor.monster_id)
	if key == "":
		return null
	if not _beast_textures.has(key):
		var path := "res://assets/art/beasts/%s.png" % key
		_beast_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _beast_textures[key]
