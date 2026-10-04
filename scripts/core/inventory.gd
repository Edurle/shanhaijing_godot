class_name Inventory
extends RefCounted
## 行囊——Python 版 inventory.py 的移植：无上限物品列表 + 材料计数/支取。


var items: Array = []  # 物品 dict 列表


func add(item: Dictionary) -> void:
	## 材料同名堆叠，其余独立成件。
	if is_material(item):
		for held in items:
			if held["id"] == item["id"]:
				held["stack"] += item.get("stack", 1)
				return
	items.append(item)


func remove(item: Dictionary) -> void:
	items.erase(item)


func is_material(item: Dictionary) -> bool:
	return item.get("tags", []).has("material") and not item.has("consumable") and not item.has("slot")


## 材料计数（修习门槛判定用）。
func count_material(material_id: String) -> int:
	var total := 0
	for item in items:
		if item["id"] == material_id:
			total += int(item.get("stack", 1))
	return total


## 支取材料（调用方已确认存量充足）；返回是否成功。
func take_material(material_id: String, count: int) -> bool:
	if count_material(material_id) < count:
		return false
	var left := count
	for item in items.duplicate():
		if item["id"] != material_id:
			continue
		var stack: int = int(item.get("stack", 1))
		if stack <= left:
			left -= stack
			items.erase(item)
		else:
			item["stack"] = stack - left
			left = 0
		if left <= 0:
			break
	return true
