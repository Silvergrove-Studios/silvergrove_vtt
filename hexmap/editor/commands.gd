class_name Commands
extends RefCounted
## Every change to a map goes through here so it is undoable and so the map
## emits `changed` exactly once per edit. Each method commits to the History
## and returns nothing; callers read the map afterwards.

var map: HexMap
var history: History


func _init(p_map: HexMap, p_history: History) -> void:
	map = p_map
	history = p_history


# --------------------------------------------------------------------- terrain --

## Paint `data` (or null to clear) onto cells of a level. One undo step.
func set_terrain(level_index: int, cells: Array[Vector2i], data) -> void:
	var lvl := map.level(level_index)
	var terrain: Dictionary = lvl["terrain"]
	var before := {}
	var after := {}
	for c in cells:
		if not map.grid.in_bounds(c):
			continue
		var k := HexMap.cell_key(c)
		before[k] = terrain.get(k, null)
		after[k] = data.duplicate() if data != null else null
	if after.is_empty():
		return
	var apply := func(state: Dictionary) -> void:
		for k in state:
			if state[k] == null:
				terrain.erase(k)
			else:
				terrain[k] = (state[k] as Dictionary).duplicate()
		map.touch("terrain")
	history.commit("Paint terrain", apply.bind(after), apply.bind(before))


## Paint with per-cell data (for random variants): cells -> data-or-null.
func set_terrain_cells(level_index: int, changes: Dictionary) -> void:
	var lvl := map.level(level_index)
	var terrain: Dictionary = lvl["terrain"]
	var before := {}
	for k in changes:
		before[k] = terrain.get(k, null)
	var apply := func(state: Dictionary) -> void:
		for k in state:
			if state[k] == null:
				terrain.erase(k)
			else:
				terrain[k] = (state[k] as Dictionary).duplicate()
		map.touch("terrain")
	history.commit("Paint terrain", apply.bind(changes), apply.bind(before))


# --------------------------------------------------------------------- objects --

## Add to "props" | "walls" | "lights" | "notes", with a leaf in the layer
## tree under `folder_id` ("" = the default folder for the collection).
func add_object(level_index: int, collection: String, obj: Dictionary, label := "", folder_id := "") -> void:
	var lvl := map.level(level_index)
	var arr: Array = lvl[collection]
	var id := str(obj.get("id", ""))
	var r := LayerTree.ref(collection, id)
	var tree: Array = lvl.tree
	if folder_id == "" or LayerTree.find(tree, folder_id).is_empty():
		folder_id = str(LayerTree.DEFAULT_FOR.get(collection, ""))
		if LayerTree.find(tree, folder_id).is_empty():
			folder_id = ""
	history.commit(label if label != "" else "Add " + collection.trim_suffix("s"),
		func() -> void:
			arr.append(obj)
			LayerTree.detach(tree, r)
			LayerTree.insert(tree, {"ref": r}, folder_id)
			map.touch(collection),
		func() -> void:
			var i := HexMap.index_in(lvl, collection, id)
			if i >= 0:
				arr.remove_at(i)
			LayerTree.detach(tree, r)
			map.touch(collection))


func remove_object(level_index: int, collection: String, id: String) -> void:
	var lvl := map.level(level_index)
	var arr: Array = lvl[collection]
	var i := HexMap.index_in(lvl, collection, id)
	if i < 0:
		return
	var obj: Dictionary = arr[i]
	var index := i
	var tree: Array = lvl.tree
	var r := LayerTree.ref(collection, id)
	var anc := LayerTree.ancestors(tree, r)
	var parent_id: String = anc[-1] if not anc.is_empty() else ""
	var loc := LayerTree.locate(tree, r)
	var leaf_index: int = loc[1] if not loc.is_empty() else -1
	var leaf := LayerTree.find(tree, r)
	if leaf.is_empty():
		leaf = {"ref": r}
	history.commit("Delete " + collection.trim_suffix("s"),
		func() -> void:
			var j := HexMap.index_in(lvl, collection, id)
			if j >= 0:
				arr.remove_at(j)
			LayerTree.detach(tree, r)
			map.touch(collection),
		func() -> void:
			arr.insert(mini(index, arr.size()), obj)
			if not LayerTree.insert(tree, leaf, parent_id, leaf_index):
				LayerTree.insert(tree, leaf, "")
			map.touch(collection))


func remove_objects(level_index: int, items: Array) -> void:
	# items: [{collection, id}]
	if items.is_empty():
		return
	history.begin_group()
	for it in items:
		remove_object(level_index, it.collection, it.id)
	history.end_group("Delete %d objects" % items.size())


## Change fields of one object. `changes` is key -> new value; a value of
## null removes the key.
func update_object(level_index: int, collection: String, id: String, changes: Dictionary, label := "Edit") -> void:
	var lvl := map.level(level_index)
	var obj := HexMap.find_in(lvl, collection, id)
	if obj.is_empty():
		return
	var before := {}
	for k in changes:
		before[k] = obj.get(k, null)
	var same := true
	for k in changes:
		if before[k] != changes[k]:
			same = false
			break
	if same:
		return
	var apply := func(state: Dictionary) -> void:
		for k in state:
			if state[k] == null:
				obj.erase(k)
			else:
				obj[k] = state[k]
		map.touch(collection)
	history.commit(label, apply.bind(_deep(changes)), apply.bind(_deep(before)))


## Move several objects by a canvas delta (hex units). Walls move all points.
func move_objects(level_index: int, items: Array, delta: Vector2, label := "Move") -> void:
	if items.is_empty() or delta == Vector2.ZERO:
		return
	history.begin_group()
	for it in items:
		var obj := HexMap.find_in(map.level(level_index), it.collection, it.id)
		if obj.is_empty():
			continue
		if it.collection == "walls":
			var pts: Array = []
			for p in obj.get("points", []):
				pts.append([snappedf(float(p[0]) + delta.x, 0.0001), snappedf(float(p[1]) + delta.y, 0.0001)])
			update_object(level_index, "walls", it.id, {"points": pts}, label)
		else:
			var pos: Array = obj.get("pos", [0, 0])
			update_object(level_index, it.collection, it.id, {"pos": [snappedf(float(pos[0]) + delta.x, 0.0001), snappedf(float(pos[1]) + delta.y, 0.0001)]}, label)
	history.end_group(label)


func move_wall_point(level_index: int, id: String, index: int, to: Vector2) -> void:
	var obj := HexMap.find_in(map.level(level_index), "walls", id)
	if obj.is_empty():
		return
	var pts: Array = (obj.get("points", []) as Array).duplicate(true)
	if index < 0 or index >= pts.size():
		return
	pts[index] = [snappedf(to.x, 0.0001), snappedf(to.y, 0.0001)]
	update_object(level_index, "walls", id, {"points": pts}, "Move wall point")


# ------------------------------------------------------------------ layer tree --

## Move a folder or leaf to `parent_id` ("" = root) at `index` (-1 = end).
## Positions on the canvas are untouched; only order/grouping changes.
func tree_move(level_index: int, key: String, parent_id: String, index: int = -1) -> void:
	var lvl := map.level(level_index)
	var tree: Array = lvl.tree
	var loc := LayerTree.locate(tree, key)
	if loc.is_empty():
		return
	var from_anc := LayerTree.ancestors(tree, key)
	var from_parent: String = from_anc[-1] if not from_anc.is_empty() else ""
	var from_index: int = loc[1]
	if from_parent == parent_id and (from_index == index or (index < 0 and from_index == (loc[0] as Array).size() - 1)):
		return
	# Moving within the same list to a later index: account for the removal.
	var to_index := index
	if from_parent == parent_id and index > from_index:
		to_index = index - 1
	var node: Dictionary = loc[0][from_index]
	# Validate before committing (no folder into itself).
	if LayerTree.is_folder(node) and parent_id != "" and (node.id == parent_id or not LayerTree.find(node.children, parent_id).is_empty()):
		return
	history.commit("Move layer",
		func() -> void:
			LayerTree.detach(tree, key)
			if not LayerTree.insert(tree, node, parent_id, to_index):
				LayerTree.insert(tree, node, from_parent, from_index)
			map.touch("tree"),
		func() -> void:
			LayerTree.detach(tree, key)
			LayerTree.insert(tree, node, from_parent, from_index)
			map.touch("tree"))


## Move several keys into a folder, keeping their relative order.
func tree_move_many(level_index: int, keys: Array, parent_id: String, index: int = -1) -> void:
	if keys.is_empty():
		return
	history.begin_group()
	var i := index
	for k in keys:
		tree_move(level_index, k, parent_id, i)
		if i >= 0:
			i += 1
	history.end_group("Move layers")


func tree_add_folder(level_index: int, p_name: String, parent_id: String = "", index: int = -1) -> Dictionary:
	var lvl := map.level(level_index)
	var tree: Array = lvl.tree
	var folder := LayerTree.new_folder(LayerTree.new_folder_id(), p_name)
	history.commit("New folder",
		func() -> void:
			LayerTree.insert(tree, folder, parent_id, index)
			map.touch("tree"),
		func() -> void:
			LayerTree.detach(tree, folder.id)
			map.touch("tree"))
	return folder


## Remove a folder; its children move to where it was.
func tree_remove_folder(level_index: int, id: String) -> void:
	var lvl := map.level(level_index)
	var tree: Array = lvl.tree
	var folder := LayerTree.find(tree, id)
	if folder.is_empty() or not LayerTree.is_folder(folder):
		return
	var anc := LayerTree.ancestors(tree, id)
	var parent_id: String = anc[-1] if not anc.is_empty() else ""
	var loc := LayerTree.locate(tree, id)
	var index: int = loc[1]
	var children: Array = folder.children.duplicate()
	history.commit("Remove folder",
		func() -> void:
			LayerTree.detach(tree, id)
			var i := index
			for c in children:
				LayerTree.insert(tree, c, parent_id, i)
				i += 1
			map.touch("tree"),
		func() -> void:
			for c in children:
				LayerTree.detach(tree, c.id if LayerTree.is_folder(c) else c.ref)
			folder.children = children.duplicate()
			LayerTree.insert(tree, folder, parent_id, index)
			map.touch("tree"))


## Change a node's flags: visible, locked, name.
func tree_set(level_index: int, key: String, changes: Dictionary, label := "Layer") -> void:
	var lvl := map.level(level_index)
	var node := LayerTree.find(lvl.tree, key)
	if node.is_empty():
		return
	var before := {}
	for k in changes:
		before[k] = node.get(k, null)
	var apply := func(state: Dictionary) -> void:
		for k in state:
			if state[k] == null:
				node.erase(k)
			else:
				node[k] = state[k]
		map.touch("tree")
	history.commit(label, apply.bind(changes.duplicate()), apply.bind(before))


# ---------------------------------------------------------------------- levels --

func add_level(p_name: String) -> void:
	var id := p_name.to_lower().replace(" ", "_")
	var n := 1
	while not map.level_by_id(id).is_empty():
		n += 1
		id = "%s_%d" % [p_name.to_lower().replace(" ", "_"), n]
	var lvl := HexMap.new_level(id, p_name)
	var levels: Array = map.levels
	history.commit("Add level",
		func() -> void:
			levels.append(lvl)
			map.touch("levels"),
		func() -> void:
			levels.erase(lvl)
			map.touch("levels"))


func remove_level(index: int) -> void:
	var levels: Array = map.levels
	if levels.size() <= 1 or index < 0 or index >= levels.size():
		return
	var lvl = levels[index]
	history.commit("Remove level",
		func() -> void:
			levels.erase(lvl)
			map.touch("levels"),
		func() -> void:
			levels.insert(mini(index, levels.size()), lvl)
			map.touch("levels"))


func update_level(index: int, changes: Dictionary) -> void:
	var lvl := map.level(index)
	if lvl.is_empty():
		return
	var before := {}
	for k in changes:
		before[k] = lvl.get(k, null)
	var apply := func(state: Dictionary) -> void:
		for k in state:
			lvl[k] = state[k]
		map.touch("levels")
	history.commit("Edit level", apply.bind(_deep(changes)), apply.bind(_deep(before)))


# ------------------------------------------------------------------------- map --

## Grid / style / name changes. `changes` may hold "grid" (dict), "style"
## (dict), "name", "reference_ppx".
func update_map(changes: Dictionary) -> void:
	var before := {}
	for k in changes:
		match k:
			"grid": before[k] = map.grid.to_dict()
			"style": before[k] = map.style.duplicate()
			_: before[k] = map.doc.get(k, null)
	var apply := func(state: Dictionary) -> void:
		for k in state:
			match k:
				"grid":
					map.grid = HexGrid.from_dict(state[k])
					map.doc["grid"] = map.grid.to_dict()
				"style":
					map.doc["style"] = (state[k] as Dictionary).duplicate()
				_:
					map.doc[k] = state[k]
		map.touch("grid" if state.has("grid") else "style")
	history.commit("Map settings", apply.bind(_deep(changes)), apply.bind(_deep(before)))


static func _deep(v: Variant) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v
