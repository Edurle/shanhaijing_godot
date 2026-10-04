class_name Actor
extends RefCounted
## 战斗单位模型——Python 版 entity.Actor 战斗子集的移植。
## team："player"（行者与契约兽）/"wild"（异兽）；AI 据此选取敌对目标。

var x: int
var y: int
var label := ""
var team := "wild"
var monster_id := ""
var char := "?"
var color := Color.WHITE
var attack_tags: PackedStringArray = []
var element := ""  # 本命五行（怪专属；玩家为空 = 不受生克影响）
var fighter: Fighter
var ai  # BaseAI 或 null
var equipment: Equipment
var level  # Level（玩家专用）
var inventory = null  # Inventory（行囊模型，build_player 装配）
var summon_ttl := -1  # -1 = 非召唤
var elite := false
var tags: Array = []  # 风味/投放标签（dragon/boss/elite/serpent/bird/beast/shanhaijing）
# 玩家专用：双职业与技能（skill_levels：1-10，0=未学）
var class_ids: Array = []
var skill_points := 0
var skill_levels := {}
var skill_bar: Array = []  # 16 槽动作条绑定（技能 id 或 ""；玩家自由编排）
# 怪物技能绑定（monsters.json skills；顺序即 AI 使用优先级）与冷却账本（id→剩余回合）
var skill_ids: PackedStringArray = []
var skill_cooldowns := {}


func _init(p_x: int, p_y: int, p_label := "") -> void:
	x = p_x
	y = p_y
	label = p_label


func is_alive() -> bool:
	return fighter != null


func distance_to(other: Actor) -> float:
	return Vector2(x - other.x, y - other.y).length()
