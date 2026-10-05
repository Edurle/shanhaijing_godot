class_name InkPalette
extends RefCounted
## 水墨调色板（view 层唯一色源）：默认值 = 现行视觉；data/content/theme.json 加载后
## 经 apply() 覆盖。绘制代码不得再写死颜色（AI 素材期：贴图灰度 + 本色板运行时调制）。

# ---- 纸 ----
static var PAPER := Color("#E9E1CD")       # 宣纸（棋盘底/原野）
static var PAPER_UI := Color("#EFE8D6")    # 做旧纸（UI 面板）
static var PAPER_SHADOW := Color("#D8CFBA")

# ---- 墨阶 ----
static var INK := Color("#2B2620")         # 浓墨：正文/墨框
static var INK_DEEP := Color("#2B2620")    # 浓墨：山体/兽身/描边（与 INK 同值、语义分开便于调色）
static var INK_MID := Color("#6E675C")     # 中墨：山径/五行环回退
static var INK_SOFT := Color("#6E675C")    # 中墨：次级文字/虚框
static var INK_LIGHT := Color("#B9B2A2")   # 淡墨：记忆态罩色/血条底

# ---- 角色/重点色 ----
static var PLAYER_INK := Color("#3A5A6E")  # 青墨（行者）
static var VERMILION := Color("#C3272B")   # 朱砂（印/血/点睛/警示）
static var GOLD := Color("#C9A662")        # 鎏金（经验/选中/落点）
static var ELITE_GOLD := Color("#D9A404")  # 精英兽墨底（绘制时再 darken）
static var OCHRE := Color("#8C5A3C")       # 赭墨（材料/地面物）
static var WARN := Color("#B4652A")        # 警示（朱偏赭）
static var SAFE := Color("#4A7C59")        # 稳妥/增益（石绿）
static var MP_BAR := Color("#2E5977")      # 真气条（石青）
static var SP_BAR := Color("#7B5EA7")      # 灵力条（紫）

# ---- 词表 ----
static var ELEMENT_COLORS := {
	"metal": Color("#C9A662"), "wood": Color("#4A7C59"), "water": Color("#2E5977"),
	"fire": Color("#C3272B"), "earth": Color("#8C5A3C"),
}
static var RARITY_COLORS := {
	"magic": Color("#3465A4"), "rare": Color("#B8860B"),
	"legendary": Color("#D2691E"), "mythic": Color("#C3272B"),
}
static var SET_COLOR := Color("#3E8E58")
static var KIND_COLORS := {
	"combat": Color("#2B2620"), "warn": Color("#B4652A"), "death": Color("#C3272B"),
	"kill": Color("#7A2E2E"), "loot": Color("#8C5A3C"), "heal": Color("#4A7C59"),
	"buff": Color("#C9A662"), "levelup": Color("#C9A662"), "info": Color("#6E675C"),
	"summon": Color("#3A5A6E"), "descend": Color("#3A5A6E"),
}
static var TERRAIN_COLORS := {
	GameMap.T_FLOOR: Color("#D8CFBA"), GameMap.T_WALL: Color("#4A443A"),
	GameMap.T_PLAIN: Color("#E9E1CD"), GameMap.T_FOREST: Color("#8A8674"),
	GameMap.T_HILL: Color("#C4B99F"), GameMap.T_MOUNTAIN: Color("#2B2620"),
	GameMap.T_WATER: Color("#9FB6C4"), GameMap.T_RIVER: Color("#B7C9D4"),
	GameMap.T_BRIDGE: Color("#A8815C"), GameMap.T_ABYSS: Color("#191414"),
	GameMap.T_SNOW: Color("#F4EFE2"), GameMap.T_SHORE: Color("#D9C9A3"),
}

# ---- 画面参数 ----
static var FOG_LERP := 0.45        # 记忆态罩灰墨比例
static var PLAIN_JITTER := -0.025  # 原野纸面颗粒抖动

const _TERRAIN_KEYS := {
	GameMap.T_FLOOR: "floor", GameMap.T_WALL: "wall", GameMap.T_PLAIN: "plain",
	GameMap.T_FOREST: "forest", GameMap.T_HILL: "hill", GameMap.T_MOUNTAIN: "mountain",
	GameMap.T_WATER: "water", GameMap.T_RIVER: "river", GameMap.T_BRIDGE: "bridge",
	GameMap.T_ABYSS: "abyss", GameMap.T_SNOW: "snow", GameMap.T_SHORE: "shore",
}


## theme.json 内容覆盖默认值；缺键保留默认（换肤/缺文件回退友好）。
static func apply(theme: Dictionary) -> void:
	if theme.is_empty():
		return
	PAPER = _c(theme, "paper", PAPER)
	PAPER_UI = _c(theme, "paper_ui", PAPER_UI)
	PAPER_SHADOW = _c(theme, "paper_shadow", PAPER_SHADOW)
	INK = _c(theme, "ink", INK)
	INK_DEEP = _c(theme, "ink_deep", INK_DEEP)
	INK_MID = _c(theme, "ink_mid", INK_MID)
	INK_SOFT = _c(theme, "ink_soft", INK_SOFT)
	INK_LIGHT = _c(theme, "ink_light", INK_LIGHT)
	PLAYER_INK = _c(theme, "player_ink", PLAYER_INK)
	VERMILION = _c(theme, "vermilion", VERMILION)
	GOLD = _c(theme, "gold", GOLD)
	ELITE_GOLD = _c(theme, "elite_gold", ELITE_GOLD)
	OCHRE = _c(theme, "ochre", OCHRE)
	WARN = _c(theme, "warn", WARN)
	SAFE = _c(theme, "safe", SAFE)
	MP_BAR = _c(theme, "mp_bar", MP_BAR)
	SP_BAR = _c(theme, "sp_bar", SP_BAR)
	SET_COLOR = _c(theme, "set_color", SET_COLOR)
	var terrain: Dictionary = theme.get("terrain", {})
	for tid in _TERRAIN_KEYS:
		TERRAIN_COLORS[tid] = _c(terrain, String(_TERRAIN_KEYS[tid]), TERRAIN_COLORS[tid])
	var elements: Dictionary = theme.get("elements", {})
	for element in ELEMENT_COLORS:
		ELEMENT_COLORS[element] = _c(elements, String(element), ELEMENT_COLORS[element])
	var rarity: Dictionary = theme.get("rarity", {})
	for grade in RARITY_COLORS:
		RARITY_COLORS[grade] = _c(rarity, String(grade), RARITY_COLORS[grade])
	var messages: Dictionary = theme.get("messages", {})
	for kind in KIND_COLORS:
		KIND_COLORS[kind] = _c(messages, String(kind), KIND_COLORS[kind])
	var params: Dictionary = theme.get("params", {})
	FOG_LERP = float(params.get("fog_lerp", FOG_LERP))
	PLAIN_JITTER = float(params.get("plain_jitter", PLAIN_JITTER))


static func _c(dict: Dictionary, key: String, fallback: Color) -> Color:
	return Color.from_string(String(dict.get(key, "")), fallback)
