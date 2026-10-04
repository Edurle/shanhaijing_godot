class_name Fighter
extends RefCounted
## 战斗组件——Python 版 fighter.py 的移植（模型层）。
## 资源池（气血/真气/灵力）、攻防聚合（基础+buff+装备）、五行生克折算、
## 状态机（buff/DOT 多槽/眩晕/缠绕）。死亡结算由回合引擎回调，组件保持哑数据。

const RESIST_CAP := 80
const COUNTER_BONUS := 0.30  # 攻击元素克目标本命：伤害 ×1.30
const COUNTER_PENALTY := 0.25  # 目标本命克攻击元素：伤害 ×0.75

var base_max_hp := 1
var base_max_mp := 0
var base_max_sp := 0
var base_power := 0
var base_defense := 0
var base_resistances := {}
var xp_reward := 0

var _hp := 1
var _mp := 0
var _sp := 0
var dead := false

var buffs := {}  # stat -> [amount, turns]（amount 可为负 = 破甲/挫锐）
var dots := {}   # kind -> [damage, turns]（按五行分槽，同覆盖异共存）
var stun_turns := 0
var rooted_turns := 0
var owner: Actor  # 宿主（抗性装备聚合与生克本命读取）


func _init(hp: int, power: int, defense: int, p_xp := 0, p_max_mp := 0, p_max_sp := 0, p_resistances := {}) -> void:
	base_max_hp = hp
	_hp = hp
	base_power = power
	base_defense = defense
	xp_reward = p_xp
	base_max_mp = p_max_mp
	_mp = p_max_mp
	base_max_sp = p_max_sp
	_sp = p_max_sp
	base_resistances = p_resistances.duplicate()


# ---- 聚合属性 ----

func max_hp() -> int:
	return base_max_hp + _gear_bonus("max_hp")


func max_mp() -> int:
	return base_max_mp + _gear_bonus("max_mp")


func max_sp() -> int:
	return base_max_sp + _gear_bonus("max_sp")


func power() -> int:
	return base_power + buff_amount("power") + _gear_bonus("power")


func defense() -> int:
	return base_defense + buff_amount("defense") + _gear_bonus("defense")


func hp() -> int:
	return _hp


func mp() -> int:
	return _mp


func sp() -> int:
	return _sp


func _gear_bonus(key: String) -> int:
	var equip = owner.equipment if owner != null else null
	return equip.bonus(key) if equip != null else 0


## 受伤（含 clamp 与死亡标记）；返回是否因此陨落。
func hurt(amount: int) -> bool:
	_hp = maxi(0, mini(_hp - amount, max_hp()))
	if _hp == 0 and not dead:
		dead = true
		return true
	return false


func heal(amount: int) -> int:
	var actual := mini(amount, max_hp() - _hp)
	_hp += actual
	return actual


func restore_mp(amount: int) -> int:
	var actual := mini(amount, max_mp() - _mp)
	_mp += actual
	return actual


func restore_sp(amount: int) -> int:
	var actual := mini(amount, max_sp() - _sp)
	_sp += actual
	return actual


## 施法扣费（管线检查完毕后调用，直接落账）。
func spend_mp(amount: int) -> void:
	_mp = maxi(0, _mp - amount)


func spend_sp(amount: int) -> void:
	_sp = maxi(0, _sp - amount)


func clamp_vitals() -> void:
	_hp = mini(_hp, max_hp())
	_mp = mini(_mp, max_mp())
	_sp = mini(_sp, max_sp())


# ---- 抗性与生克 ----

func resistance(kind: String) -> int:
	var value: int = int(base_resistances.get(kind, 0))
	var equip = owner.equipment if owner != null else null
	if equip != null:
		value += equip.affix("resist_" + kind)
	return mini(RESIST_CAP, value)


## 五行折算：先乘生克系数（攻元素 vs 自身本命），再按最高元素抗性减伤，下限 1 点。
func mitigate_incoming(damage: int, tags: Array) -> int:
	var counter := counter_multiplier(tags)
	var resist := 0
	for t in tags:
		if ContentDb.ELEMENTS.has(t):
			resist = maxi(resist, resistance(t))
	if resist <= 0 and counter == 1.0:
		return damage
	return maxi(1, int(round(damage * counter * (100 - resist) / 100.0)))


## 生克系数：攻击 tags 的首个五行元素 vs 自身本命（多元素取首个，数据排列即主元素）。
func counter_multiplier(tags: Array) -> float:
	var innate: String = owner.element if owner != null else ""
	if not ContentDb.ELEMENT_BEATS.has(innate):
		return 1.0
	var attack_elem := ""
	for t in tags:
		if ContentDb.ELEMENTS.has(t):
			attack_elem = t
			break
	if attack_elem == "" or attack_elem == innate:
		return 1.0
	if ContentDb.ELEMENT_BEATS[attack_elem] == innate:
		return 1.0 + COUNTER_BONUS
	if ContentDb.ELEMENT_BEATS[innate] == attack_elem:
		return 1.0 - COUNTER_PENALTY
	return 1.0


# ---- 状态机 ----

## 同属性重复施加：数值叠加、时长刷新。
func apply_buff(stat: String, amount: int, turns: int) -> void:
	if buffs.has(stat):
		var entry: Array = buffs[stat]
		entry[0] += amount
		entry[1] = turns
	else:
		buffs[stat] = [amount, turns]


func buff_amount(stat: String) -> int:
	if not buffs.has(stat):
		return 0
	var entry: Array = buffs[stat]
	return int(entry[0])


## 回合边界递减；返回是否有 buff 到期。
func tick_buffs() -> bool:
	var expired := false
	for stat in buffs.keys():
		var entry: Array = buffs[stat]
		entry[1] -= 1
		if entry[1] <= 0:
			buffs.erase(stat)
			expired = true
	return expired


## 元素 DOT：同元素覆盖异元素共存；施加时按该元素抗性+生克折算一次（下限 1）。
func apply_dot(kind: String, damage: int, turns: int) -> void:
	if not ContentDb.ELEMENTS.has(kind) or damage <= 0 or turns <= 0:
		return
	dots[kind] = [mitigate_incoming(damage, [kind]), turns]


func has_dot() -> bool:
	for entry in dots.values():
		if entry[1] > 0:
			return true
	return false


func clear_dots() -> void:
	dots.clear()


## 结算本回合全部 DOT 并递减时长；返回 [[kind, damage, expired]]。
func tick_dots() -> Array:
	var settled: Array = []
	for kind in dots.keys():
		var entry: Array = dots[kind]
		if entry[1] <= 0 or entry[0] <= 0:
			continue
		entry[1] -= 1
		settled.append([kind, entry[0], entry[1] <= 0])
	return settled


## 眩晕（含水系冰封）与缠绕（木系）：定力按比例缩短时长，可为 0（完全抵抗）。
func apply_stun(turns: int) -> void:
	turns = int(turns * (100 - resistance("stun")) / 100.0)
	if turns > 0:
		stun_turns = maxi(stun_turns, turns)


func apply_root(turns: int) -> void:
	turns = int(turns * (100 - resistance("stun")) / 100.0)
	if turns > 0:
		rooted_turns = maxi(rooted_turns, turns)
