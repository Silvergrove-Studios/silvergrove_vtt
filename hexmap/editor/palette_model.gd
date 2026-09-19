class_name PaletteModel
extends RefCounted
## The palette's data side, kept free of Controls so it can be unit-tested:
## which assets match a search, how they group into sections (Favourites,
## Recent, then one per pack), and the per-user favourites/recent lists.

const KINDS := ["terrain", "props", "walls", "lights"]
const COLLECTION := {"terrain": "terrains", "props": "props", "walls": "walls", "lights": "lights"}
const RECENT_MAX := 8


## Case-insensitive match on name, ref (pack:id), pack name and tags.
static func matches(asset: Dictionary, query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q == "":
		return true
	var hay := PackedStringArray([str(asset.get("name", "")), str(asset.get("_ref", "")), str(asset.get("_pack", "")), str(asset.get("_pack_name", ""))])
	for t in asset.get("tags", []):
		hay.append(str(t))
	var joined := " ".join(hay).to_lower()
	for word in q.split(" ", false):
		if not joined.contains(word):
			return false
	return true


## Sections for one tab. `assets` are PackLibrary.all(collection) entries
## (with _ref/_pack), `favorites`/`recent` are refs. Returns
## [{id, title, items: [asset...]}], empty sections omitted.
static func sections(assets: Array, query: String, favorites: Array, recent: Array, pack_names: Dictionary = {}) -> Array:
	var by_ref := {}
	for a in assets:
		by_ref[str(a._ref)] = a
	var visible := assets.filter(func(a): return matches(a, query))
	var vis_refs := {}
	for a in visible:
		vis_refs[str(a._ref)] = true
	var out: Array = []
	var fav_items: Array = []
	for r in favorites:
		if vis_refs.has(r):
			fav_items.append(by_ref[r])
	if not fav_items.is_empty():
		out.append({"id": "favorites", "title": "Favourites", "items": fav_items})
	var recent_items: Array = []
	for r in recent:
		if vis_refs.has(r) and not favorites.has(r):
			recent_items.append(by_ref[r])
	if not recent_items.is_empty():
		out.append({"id": "recent", "title": "Recent", "items": recent_items})
	var packs := {}
	var order := PackedStringArray()
	for a in visible:
		var pid := str(a._pack)
		if not packs.has(pid):
			packs[pid] = []
			order.append(pid)
		packs[pid].append(a)
	for pid in order:
		out.append({"id": "pack:" + pid, "title": str(pack_names.get(pid, pid)), "items": packs[pid]})
	return out


## Number of matching assets, for tab titles.
static func count(assets: Array, query: String) -> int:
	var n := 0
	for a in assets:
		if matches(a, query):
			n += 1
	return n


## Most recent first, deduplicated, capped.
static func push_recent(recent: Array, ref: String) -> Array:
	var out := [ref]
	for r in recent:
		if r != ref and out.size() < RECENT_MAX:
			out.append(r)
	return out


static func toggle(list: Array, ref: String) -> Array:
	var out := list.duplicate()
	if out.has(ref):
		out.erase(ref)
	else:
		out.append(ref)
	return out


# ------------------------------------------------------------------ persistence --

static func default_state() -> Dictionary:
	var st := {"favorites": {}, "recent": {}, "collapsed": {}}
	for k in KINDS:
		st.favorites[k] = []
		st.recent[k] = []
	return st


static func load_state(path: String = "user://palette.json") -> Dictionary:
	var st := default_state()
	if not FileAccess.file_exists(path):
		return st
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return st
	for k in KINDS:
		if d.get("favorites", {}).has(k) and d.favorites[k] is Array:
			st.favorites[k] = Array(d.favorites[k]).filter(func(x): return x is String)
		if d.get("recent", {}).has(k) and d.recent[k] is Array:
			st.recent[k] = Array(d.recent[k]).filter(func(x): return x is String).slice(0, RECENT_MAX)
	if d.get("collapsed", {}) is Dictionary:
		st.collapsed = d.collapsed
	return st


static func save_state(st: Dictionary, path: String = "user://palette.json") -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(st, "  "))
	f.close()
	return OK
