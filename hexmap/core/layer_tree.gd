class_name LayerTree
extends RefCounted
## The per-level layer tree: folders and element leaves, Photoshop style.
## The tree *is* the draw order for props (depth-first, first = bottom) and
## the place visibility and locking live. Elements are referenced by
## "collection:id" and keep their own position; moving a leaf between
## folders never moves anything on the canvas.
##
## Tree nodes:
##   folder: { "id": "f_…", "name": "Furniture", "children": [ … ],
##             "visible": true, "locked": false, "open": true }
##   leaf:   { "ref": "props:p_8f3a", "visible": true, "locked": false }
## Missing flags mean visible and unlocked. `ensure()` reconciles the tree
## with the level's collections so hand-edited files always work.

const COLLECTIONS := ["props", "walls", "lights", "notes"]

## Default folders for a fresh level, and where each kind of element goes.
const DEFAULT_FOLDERS := [
	["f_ground", "Ground"], ["f_props", "Props"], ["f_overhead", "Overhead"],
	["f_walls", "Walls & doors"], ["f_lights", "Lights"], ["f_notes", "Notes"],
]
const DEFAULT_FOR := {"walls": "f_walls", "lights": "f_lights", "notes": "f_notes", "props": "f_props"}
## Legacy prop `layer` field -> default folder.
const LEGACY_LAYER := {"ground": "f_ground", "objects": "f_props", "overhead": "f_overhead"}


static func new_folder(id: String, p_name: String) -> Dictionary:
	return {"id": id, "name": p_name, "children": [], "visible": true, "locked": false, "open": true}


static func default_tree() -> Array:
	var t: Array = []
	for f in DEFAULT_FOLDERS:
		t.append(new_folder(f[0], f[1]))
	return t


static func ref(collection: String, id: String) -> String:
	return "%s:%s" % [collection, id]


static func split(p_ref: String) -> PackedStringArray:
	var i := p_ref.find(":")
	return PackedStringArray([p_ref.substr(0, i), p_ref.substr(i + 1)]) if i > 0 else PackedStringArray()


static func is_folder(node: Dictionary) -> bool:
	return node.has("children")


# -------------------------------------------------------------------- ensure --

## Make the tree match the level: every element has exactly one leaf,
## no leaf points at a missing element, and a fresh level gets the default
## folders. Props with a legacy `layer` field are filed accordingly.
static func ensure(level: Dictionary) -> void:
	if not level.has("tree") or not (level.tree is Array):
		level["tree"] = default_tree()
	var tree: Array = level.tree
	var present := {}
	for c in COLLECTIONS:
		for o in level.get(c, []):
			present[ref(c, str(o.get("id", "")))] = true
	# Drop dangling / duplicate leaves.
	var seen := {}
	_prune(tree, present, seen)
	# Add leaves for elements not in the tree.
	for c in COLLECTIONS:
		for o in level.get(c, []):
			var r := ref(c, str(o.get("id", "")))
			if seen.has(r):
				continue
			var folder_id: String = DEFAULT_FOR.get(c, "")
			if c == "props" and o.has("layer"):
				folder_id = LEGACY_LAYER.get(str(o.layer), "f_props")
				o.erase("layer")
			var folder := find(tree, folder_id)
			if folder.is_empty():
				# A default folder the user deleted: recreate at the end.
				for f in DEFAULT_FOLDERS:
					if f[0] == folder_id:
						folder = new_folder(f[0], f[1])
						tree.append(folder)
			var target: Array = folder.children if not folder.is_empty() else tree
			target.append({"ref": r})
			seen[r] = true


static func _prune(children: Array, present: Dictionary, seen: Dictionary) -> void:
	var i := 0
	while i < children.size():
		var n = children[i]
		if not (n is Dictionary):
			children.remove_at(i)
			continue
		if is_folder(n):
			_prune(n.children, present, seen)
			i += 1
			continue
		var r := str(n.get("ref", ""))
		if not present.has(r) or seen.has(r):
			children.remove_at(i)
			continue
		seen[r] = true
		i += 1


# --------------------------------------------------------------------- lookup --

## Find a node by folder id or leaf ref anywhere in the tree.
static func find(tree: Array, key: String) -> Dictionary:
	for n in tree:
		if is_folder(n):
			if n.id == key:
				return n
			var r := find(n.children, key)
			if not r.is_empty():
				return r
		elif n.get("ref", "") == key:
			return n
	return {}


## [parent_children_array, index] of a node, or [] if absent.
static func locate(tree: Array, key: String) -> Array:
	for i in tree.size():
		var n = tree[i]
		if is_folder(n):
			if n.id == key:
				return [tree, i]
			var r := locate(n.children, key)
			if not r.is_empty():
				return r
		elif n.get("ref", "") == key:
			return [tree, i]
	return []


## Folder ids from the root down to (not including) the node; [] if absent
## or at the root.
static func ancestors(tree: Array, key: String) -> Array:
	var path := []
	return path if _ancestors(tree, key, path) else []


static func _ancestors(children: Array, key: String, path: Array) -> bool:
	for n in children:
		if is_folder(n):
			if n.id == key:
				return true
			path.append(n.id)
			if _ancestors(n.children, key, path):
				return true
			path.pop_back()
		elif n.get("ref", "") == key:
			return true
	return false


## Leaves depth-first: the draw order, bottom first.
static func leaves(tree: Array, out: Array = []) -> Array:
	for n in tree:
		if is_folder(n):
			leaves(n.children, out)
		else:
			out.append(n)
	return out


## Every leaf ref under a node (the node itself if it is a leaf).
static func refs_under(node: Dictionary) -> Array:
	if is_folder(node):
		var out := []
		for l in leaves(node.children):
			out.append(l.ref)
		return out
	return [node.ref]


## Effective visibility / lock: an element is hidden or locked if it or any
## ancestor folder is. Returns {ref: bool} for every leaf.
static func effective(tree: Array, key: String) -> Dictionary:
	var out := {}
	if key == "locked":
		_effective_locked(tree, false, out)
	else:
		_effective_visible(tree, true, out)
	return out


static func _effective_visible(children: Array, inherited: bool, out: Dictionary) -> void:
	for n in children:
		var v := inherited and bool(n.get("visible", true))
		if is_folder(n):
			_effective_visible(n.children, v, out)
		else:
			out[n.ref] = v


static func _effective_locked(children: Array, inherited: bool, out: Dictionary) -> void:
	for n in children:
		var v := inherited or bool(n.get("locked", false))
		if is_folder(n):
			_effective_locked(n.children, v, out)
		else:
			out[n.ref] = v


## Convenience for exporters: is this element on a visible layer?
static func shown(level: Dictionary, collection: String, id: String) -> bool:
	if not level.has("tree"):
		return true
	return effective(level.tree, "visible").get(ref(collection, id), true)


## Visibility of every element of a level at once: {ref: bool}. Elements
## missing from the tree are absent; treat absent as visible.
static func visible_refs(level: Dictionary) -> Dictionary:
	if not level.has("tree"):
		return {}
	return effective(level.tree, "visible")


## Draw order index per ref: {ref: int}.
static func order(tree: Array) -> Dictionary:
	var out := {}
	var ls := leaves(tree)
	for i in ls.size():
		out[ls[i].ref] = i
	return out


# --------------------------------------------------------------------- editing --

## Detach a node and return it (or {} if not found).
static func detach(tree: Array, key: String) -> Dictionary:
	var loc := locate(tree, key)
	if loc.is_empty():
		return {}
	var arr: Array = loc[0]
	var node: Dictionary = arr[loc[1]]
	arr.remove_at(loc[1])
	return node


## Insert a node into folder `parent_id` ("" = root) at `index` (-1 = end).
## Refuses to put a folder inside itself.
static func insert(tree: Array, node: Dictionary, parent_id: String, index: int = -1) -> bool:
	var target: Array = tree
	if parent_id != "":
		var f := find(tree, parent_id)
		if f.is_empty() or not is_folder(f):
			return false
		if is_folder(node) and (node.id == parent_id or not find(node.children, parent_id).is_empty()):
			return false
		target = f.children
	if index < 0 or index > target.size():
		index = target.size()
	target.insert(index, node)
	return true


static func new_folder_id() -> String:
	return "f_%08x" % randi()
