class_name Equipment
extends RefCounted
## 装备栏：五槽（兵/甲/履/佩/冠）聚合查询——Python 版 equipment.py 的移植。
## 物品为 dict（id/label/slot/bonuses/affixes/damage/rarity/set_id），由 ContentDb.build_item 构造。
## 套装加成：set_defs 为 ContentDb 注入的套装登记表，集齐档位件数的 bonuses/affixes 累积生效。

const SLOT_ORDER: PackedStringArray = ["weapon", "armor", "boots", "amulet", "helm"]

var slots := {}
var set_defs := {}  # 套装登记表（空 = 无套装数据，聚合跳过）


func _init() -> void:
	for slot in SLOT_ORDER:
		slots[slot] = null


## 装备一件（dict）；被顶替的旧件返回（空 dict = 原槽为空）。
func equip(item: Dictionary) -> Dictionary:
	var slot: String = item["slot"]
	var replaced: Dictionary = slots.get(slot) if slots.get(slot) != null else {}
	slots[slot] = item
	return replaced


func unequip_slot(slot: String) -> Dictionary:
	if slots.get(slot) == null:
		return {}
	var item: Dictionary = slots[slot]
	slots[slot] = null
	return item


func is_equipped(item: Dictionary) -> bool:
	return slots.get(item.get("slot", "")) == item


func equipped_items() -> Array:
	var result: Array = []
	for slot in slots:
		if slots[slot] != null:
			result.append(slots[slot])
	return result


## 全部已装备件的基础加成求和：power/defense/max_hp/max_mp/max_sp；套装档位加成并入。
func bonus(key: String) -> int:
	var total := 0
	for item in equipped_items():
		total += int(item.get("bonuses", {}).get(key, 0))
	total += _set_bonus_sum(key)
	return total


## 指定词条 id 的叠加值（按技能 tag 加伤/减耗等）；套装档位词条并入。
func affix(affix_id: String) -> int:
	var total := 0
	for item in equipped_items():
		for affix in item.get("affixes", []):
			if affix["id"] == affix_id:
				total += int(affix["value"])
	for tier in active_set_tiers():
		for affix in tier["affixes"]:
			if affix["id"] == affix_id:
				total += int(affix["value"])
	return total


# ---- 套装聚合 ----

## 指定套装已穿戴件数。
func set_piece_count(set_id: String) -> int:
	var count := 0
	for item in equipped_items():
		if String(item.get("set_id", "")) == set_id:
			count += 1
	return count


## 当前激活的套装档位清单（去重）：[{set_id, threshold, bonuses, affixes}]。
## 档位累积生效——已穿件数 ≥ 阈值的每一档都计入。
func active_set_tiers() -> Array:
	var result: Array = []
	if set_defs.is_empty():
		return result
	var seen := {}
	for item in equipped_items():
		var set_id := String(item.get("set_id", ""))
		if set_id == "" or not set_defs.has(set_id):
			continue
		var tiers: Dictionary = set_defs[set_id].get("tiers", {})
		var count := set_piece_count(set_id)
		for tier_text in tiers:
			var mark := "%s:%s" % [set_id, tier_text]
			if int(tier_text) <= count and not seen.has(mark):
				seen[mark] = true
				var tier_def: Dictionary = tiers[tier_text]
				result.append({
					"set_id": set_id,
					"threshold": int(tier_text),
					"bonuses": tier_def.get("bonuses", {}),
					"affixes": tier_def.get("affixes", []),
				})
	return result


## 已激活套装档位的某加成键求和。
func _set_bonus_sum(key: String) -> int:
	var total := 0
	for tier in active_set_tiers():
		total += int(tier["bonuses"].get(key, 0))
	return total


## 武器伤害面 [physical, element]：无武器/无伤害面返回 [0, ""]。
func weapon_damage() -> Array:
	if slots.get("weapon") == null:
		return [0, ""]
	var weapon: Dictionary = slots["weapon"]
	if weapon.get("damage") == null:
		return [0, ""]
	var damage: Dictionary = weapon["damage"]
	return [int(damage.get("physical", 0)), String(damage.get("element", ""))]
