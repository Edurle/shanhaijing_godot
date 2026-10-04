class_name Level
extends RefCounted
## 修为等级——Python 版 level.py 的移植：经验曲线 + 每级成长（气血/真气/灵力/攻防/技能点）。

var current_level := 1
var current_xp := 0
var base_xp := 60
var step_xp := 90
var bonuses := {}
var owner: Actor
var on_level_up: Callable  # 引擎注入（消息/特效钩子）


func experience_to_next() -> int:
	return base_xp + current_level * step_xp


func add_xp(xp: int, is_player: bool) -> int:
	## 加经验；返回升了几级（修为成长只对玩家生效）。
	if xp == 0 or not is_player:
		return 0
	current_xp += xp
	var gained := 0
	while current_xp > experience_to_next():
		current_xp -= experience_to_next()
		current_level += 1
		gained += 1
		_apply_level_up()
	return gained


func _apply_level_up() -> void:
	var fighter := owner.fighter
	fighter.base_max_hp += int(bonuses.get("max_hp", 0))
	fighter.heal(int(bonuses.get("max_hp", 0)))
	fighter.base_max_mp += int(bonuses.get("max_mp", 0))
	fighter.restore_mp(int(bonuses.get("max_mp", 0)))
	fighter.base_max_sp += int(bonuses.get("max_sp", 0))
	fighter.restore_sp(int(bonuses.get("max_sp", 0)))
	fighter.base_power += int(bonuses.get("power", 0))
	fighter.base_defense += int(bonuses.get("defense", 0))
	if owner != null:
		owner.skill_points += int(bonuses.get("skill_points", 0))
	if on_level_up.is_valid():
		on_level_up.call(current_level)
