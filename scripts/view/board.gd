class_name Board
extends Node2D
## 棋盘渲染（视图层）：地形场由 paper_ground.gdshader 的全图 quad 渲染（像素级连续——
## 一片水是一整片水，格子只存在于数据纹理）；本节点自绘笔墨装饰（皴笔/点苔）与
## 楼梯/门/物品/单位，叠在 shader 层之上。重绘由 main 事件驱动。

const CELL := 32
const GROUND_SHADER := preload("res://assets/shaders/paper_ground.gdshader")

# 色板唯一来源：ink_palette.gd（theme.json 可覆盖），本文件不持有颜色常量。

# —— 洗染参数：喂给 shader 的各地形"墨在纸上的浓度"，越小纸纹越透 ——
const WASH_ALPHA := {
	GameMap.T_FLOOR: 0.55, GameMap.T_PLAIN: 0.30, GameMap.T_FOREST: 0.88,
	GameMap.T_HILL: 0.55, GameMap.T_MOUNTAIN: 0.94, GameMap.T_WATER: 0.78,
	GameMap.T_RIVER: 0.66, GameMap.T_BRIDGE: 0.85, GameMap.T_ABYSS: 0.96,
	GameMap.T_SNOW: 0.45, GameMap.T_SHORE: 0.60, GameMap.T_WALL: 0.85,
}
const GRAIN_STRENGTH := 0.05   # 连续明度颗粒幅度（shader 内像素尺度采样）

var map: GameMap
var player: Actor
var target_cell := Vector2i(-1, -1)  # 瞄准/查看高亮格
var landing_cell := Vector2i(-1, -1)  # 择向落点预览
var travel_cell := Vector2i(-1, -1)  # 点击旅行目标（淡金虚框）

var _paper: ImageTexture           # 宣纸底纹（shader 采样，四方连续）
var _ground: Sprite2D              # 全图地形 quad（z=-1 垫在自绘内容之下）
var _ground_mat: ShaderMaterial
var _field_tex: ImageTexture       # 每格地形+雾态的数据纹理
var _blank: ImageTexture           # 水贴图缺失时的透明兜底
var _deco := {}                    # Vector2i -> Dictionary 装饰参数
var _grain_noise := FastNoiseLite.new()
var _clump_noise := FastNoiseLite.new()

static var _beast_cache := {}  # monster_id -> Texture2D/null（AI 素材缓存，棋盘/查看卡共享）


func _ready() -> void:
	_grain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_grain_noise.frequency = 0.32
	_clump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_clump_noise.frequency = 0.11
	_build_paper()
	_blank = ImageTexture.create_from_image(_filled(1, 1, Color(0, 0, 0, 0)))
	_ground = Sprite2D.new()
	_ground.texture = ImageTexture.create_from_image(_filled(2, 2, Color.WHITE))
	_ground.centered = false
	_ground.visible = false  # setup 绑定 uniform 后才显示（避免空参数渲染）
	_ground.z_index = -1  # 垫在 Board 自绘内容（装饰/楼梯/单位）之下
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND_SHADER
	_ground.material = _ground_mat
	add_child(_ground)
	set_process(true)  # 水纹时间（一个 quad 的逐帧重绘，GPU 开销可忽略）


func _filled(w: int, h: int, color: Color) -> Image:
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


## 宣纸：Simplex + 对边交叉混合做真正的四方连续（256px，±2.5% 纤维斑驳）。
func _build_paper() -> void:
	var s := 256
	var image := Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var fiber := FastNoiseLite.new()
	fiber.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fiber.frequency = 0.05
	for y in range(s):
		for x in range(s):
			var fx := float(x) / float(s)
			var fy := float(y) / float(s)
			var g := (fiber.get_noise_2d(x, y) * (1.0 - fx) + fiber.get_noise_2d(x - s, y) * fx) * (1.0 - fy) \
				+ (fiber.get_noise_2d(x, y - s) * (1.0 - fx) + fiber.get_noise_2d(x - s, y - s) * fx) * fy
			image.set_pixel(x, y, InkPalette.PAPER.lightened(g * 0.025))
	_paper = ImageTexture.create_from_image(image)


func setup(p_map: GameMap, p_player: Actor = null) -> void:
	map = p_map
	player = p_player
	_precompute()
	_bind_material()
	_sync_field()
	queue_redraw()


## 逐格预计算：装饰参数。种子按地图稳定（重进同层不闪变）。
func _precompute() -> void:
	var field_seed := (String(map.realm_id).hash() + map.width * 131 + map.height * 17 + map.floor_number * 397) % 100000
	_grain_noise.seed = field_seed
	_clump_noise.seed = field_seed + 7
	var rng := RandomNumberGenerator.new()
	rng.seed = field_seed + 13
	_deco.clear()
	for y in range(map.height):
		for x in range(map.width):
			_deco[Vector2i(x, y)] = _build_deco(map.tile_at(x, y), x, y, rng)


## 装饰参数（仅视野内绘制）：山脊笔高取平滑场（邻格连贯成脉），点苔/水纹密度取聚簇场（成片跨格）。
func _build_deco(kind: int, x: int, y: int, rng: RandomNumberGenerator) -> Dictionary:
	var clump := _clump_noise.get_noise_2d(x, y)
	match kind:
		GameMap.T_MOUNTAIN, GameMap.T_WALL:
			return {
				"r1": _grain_noise.get_noise_2d(x * 0.45, y * 1.7) * 0.5 + 0.5,
				"r2": _grain_noise.get_noise_2d(x * 0.45 + 31.0, y * 1.7 + 17.0) * 0.5 + 0.5,
				"peak": rng.randf() < 0.16,
			}
		GameMap.T_FOREST:
			var dots: Array = []
			if clump > -0.2:
				var count := 3 + int(clampf((clump + 0.2) * 4.0, 0.0, 1.0) * rng.randf_range(2.0, 5.0))
				for _i in range(count):
					dots.append([rng.randf_range(4.0, 28.0), rng.randf_range(4.0, 28.0),
						rng.randf_range(1.4, 2.6), rng.randf() < 0.5])
			return {"dots": dots}
		GameMap.T_WATER, GameMap.T_RIVER:
			return {
				"rip": clump > 0.05,
				"rip2": rng.randf() < 0.4,
				# 同行取一致相位 → 水纹横向流过邻格
				"ry": _grain_noise.get_noise_2d(17.3, y * 1.6) * 0.5 + 0.5,
			}
		GameMap.T_HILL:
			return {"phase": _grain_noise.get_noise_2d(x * 0.6, y * 0.9) * 0.5 + 0.5}
		GameMap.T_SHORE, GameMap.T_SNOW:
			var dots: Array = []
			for _i in range(3):
				dots.append([rng.randf_range(5.0, 27.0), rng.randf_range(5.0, 27.0)])
			return {"dots": dots}
	return {}


func _draw() -> void:
	if map == null:
		return
	# 地形场（宣纸/洗染/湿边/水纹）由 _ground 的 shader 渲染；此处只画笔墨装饰与实体
	for y in range(map.height):
		for x in range(map.width):
			if not map.is_visible(x, y):
				continue  # 记忆区只留 shader 的洗染+雾，干净的回忆
			_draw_decoration(x, y, map.tile_at(x, y))
	_draw_stairs()
	_draw_gates()
	_draw_items()
	for actor in map.actors:
		if actor.is_alive():
			_draw_actor(actor)
	_draw_overlays()


## 水纹时间：shader 的 time uniform + 单 quad 重绘（每帧一次，开销可忽略）。
func _process(_delta: float) -> void:
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("time", float(Time.get_ticks_msec()) / 1000.0)
		_ground.queue_redraw()


## 绑定 shader 材质：尺寸/纸纹/水纹/调色板（InkPalette → uniform，theme.json 换肤即生效）。
func _bind_material() -> void:
	_ground.scale = Vector2(map.width * CELL / 2.0, map.height * CELL / 2.0)  # 2px 白图 → 全图
	_ground.visible = true
	_ground_mat.set_shader_parameter("map_size", Vector2(map.width, map.height))
	_ground_mat.set_shader_parameter("cell_px", float(CELL))
	_ground_mat.set_shader_parameter("paper_tex", _paper)
	_ground_mat.set_shader_parameter("water_a", _load_texture("res://assets/art/terrain/water_flow.png"))
	_ground_mat.set_shader_parameter("water_b", _load_texture("res://assets/art/terrain/water_calm.png"))
	var colors := PackedColorArray()
	var alphas := PackedFloat32Array()
	for kind in range(12):
		colors.append(InkPalette.TERRAIN_COLORS.get(kind, InkPalette.PAPER))
		alphas.append(WASH_ALPHA.get(kind, 0.8))
	_ground_mat.set_shader_parameter("terrain_colors", colors)
	_ground_mat.set_shader_parameter("wash_alpha", alphas)
	_ground_mat.set_shader_parameter("fog_color", InkPalette.INK_LIGHT)
	_ground_mat.set_shader_parameter("fog_lerp", InkPalette.FOG_LERP)
	_ground_mat.set_shader_parameter("grain_strength", GRAIN_STRENGTH)


func _load_texture(path: String) -> ImageTexture:
	if ResourceLoader.exists(path):
		return load(path)
	return _blank


## 数据纹理（每格 1px：R=地形 id，G=雾态 0/1/2）在每次重绘前同步——FOV/地形变化即生效。
func _sync_field() -> void:
	var w := map.width
	var h := map.height
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var idx := 0
	for y in range(h):
		for x in range(w):
			data[idx] = map.tile_at(x, y)
			data[idx + 1] = 2 if map.is_visible(x, y) else (1 if map.is_explored(x, y) else 0)
			data[idx + 2] = 0
			data[idx + 3] = 255
			idx += 4
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	if _field_tex == null or _field_tex.get_size() != Vector2(w, h):
		_field_tex = ImageTexture.create_from_image(image)
	else:
		_field_tex.update(image)
	_ground_mat.set_shader_parameter("data_tex", _field_tex)


## FOV/地形变化后同步数据纹理（main._refresh 每回合调用；setup 内自动调一次）。
func sync_field() -> void:
	if map != null and _ground_mat != null:
		_sync_field()


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


## 笔墨装饰（仅视野内；记忆区只留 shader 的洗染+雾，干净的回忆）。
## 水面纹理由 shader 的水纹贴图层承担，此处不再画 canvas 水纹。
func _draw_decoration(x: int, y: int, kind: int) -> void:
	var deco: Dictionary = _deco.get(Vector2i(x, y), {})
	var px := x * CELL
	var py := y * CELL
	match kind:
		GameMap.T_MOUNTAIN, GameMap.T_WALL:
			# 斧劈皴两笔：笔高取平滑场，邻格连成山脊；偶发峰顶留白
			var stroke := InkPalette.INK_DEEP.lightened(0.30)
			var y1: float = py + 6.0 + float(deco.get("r1", 0.5)) * 14.0
			var y2: float = py + 8.0 + float(deco.get("r2", 0.5)) * 14.0
			draw_line(Vector2(px + 5, y1 + 2), Vector2(px + CELL - 6, y1 - 1), stroke, 2.0)
			draw_line(Vector2(px + 10, y2 + 2), Vector2(px + CELL - 5, y2 - 1), stroke, 1.3)
			if deco.get("peak", false):
				draw_line(Vector2(px + 12, py + 4), Vector2(px + 22, py + 3), InkPalette.PAPER.lightened(0.06), 2.0)
		GameMap.T_FOREST:
			# 点苔：聚簇场驱动疏密，成片跨格
			for dot in deco.get("dots", []):
				var dot_color := InkPalette.INK_DEEP if dot[3] else InkPalette.INK_MID
				draw_circle(Vector2(px + dot[0], py + dot[1]), dot[2], dot_color)
		GameMap.T_HILL:
			# 披麻皴：两短竖笔
			var phase: float = float(deco.get("phase", 0.5))
			draw_line(Vector2(px + 8.0, py + 8.0 + phase * 4.0), Vector2(px + 13.0, py + 22.0), InkPalette.INK_MID, 1.2)
			draw_line(Vector2(px + 19.0, py + 6.0 + phase * 4.0), Vector2(px + 24.0, py + 20.0), InkPalette.INK_MID, 1.2)
		GameMap.T_SHORE:
			for dot in deco.get("dots", []):
				draw_circle(Vector2(px + dot[0], py + dot[1]), 1.1, InkPalette.OCHRE.darkened(0.1))
		GameMap.T_SNOW:
			for dot in deco.get("dots", []):
				draw_circle(Vector2(px + dot[0], py + dot[1]), 1.0, InkPalette.INK_LIGHT)
		GameMap.T_BRIDGE:
			var plank: Color = InkPalette.TERRAIN_COLORS[GameMap.T_BRIDGE].darkened(0.3)
			for i in range(3):
				var yy: float = py + 8.0 + i * 8.0
				draw_line(Vector2(px + 3.0, yy), Vector2(px + 29.0, yy), plank, 1.0)
		GameMap.T_ABYSS:
			draw_rect(Rect2(px + 4.0, py + 4.0, 24.0, 24.0), Color(InkPalette.INK_DEEP, 0.3))


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
	var texture := beast_texture(String(actor.monster_id))
	var below := radius + 7.0  # 血条距中心的纵向偏移
	if texture != null:
		# AI 素材期：40px 贴图（略溢出格子换辨识度，贴图自带留白边距）。
		# 属性（五行/精英）不做贴图上标记，统一由查看卡（X）承载。
		var size := CELL + 8.0
		draw_texture_rect(texture, Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size)), false)
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


## 异兽贴图（AI 素材期；缺失返回 null 回退程序化墨点占位）。棋盘/查看卡共用。
static func beast_texture(monster_id: String) -> Texture2D:
	if monster_id == "":
		return null
	if not _beast_cache.has(monster_id):
		var path := "res://assets/art/beasts/%s.png" % monster_id
		_beast_cache[monster_id] = load(path) if ResourceLoader.exists(path) else null
	return _beast_cache[monster_id]
