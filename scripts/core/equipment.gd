class_name Equipment
extends RefCounted
## 装备栏：五槽（兵/甲/履/佩/冠）聚合查询——Python 版 equipment.py 的移植。
## 物品为 dict（id/label/slot/bonuses/affixes/damage），由 ContentDb.build_item 构造。

const SLOT_ORDER: PackedStringArray = ["weapon", "armor", "boots", "amulet", "helm"]

var slots := {}


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


## 全部已装备件的基础加成求和：power/defense/max_hp/max_mp/max_sp。
func bonus(key: String) -> int:
	var total := 0
	for item in equipped_items():
		total += int(item.get("bonuses", {}).get(key, 0))
	return total


## 指定词条 id 的叠加值（按技能 tag 加伤/减耗等）。
func affix(affix_id: String) -> int:
	var total := 0
	for item in equipped_items():
		for affix in item.get("affixes", []):
			if affix["id"] == affix_id:
				total += int(affix["value"])
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
