class_name HexMap
extends RefCounted
## The map document in memory. A thin wrapper over the JSON described in
## docs/map-format.md: `doc` is that dictionary, `grid` is the parsed
## `doc.grid`, and the helpers here are the few things everyone needs (ids,
## cell keys, level lookup, load/save). Edits go through editor commands
## (hexmap/editor/commands.gd) so they can be undone; this class does not
## enforce that, it just emits `changed` when asked.

signal changed(what: String)

const FORMAT := "silvergrove.hexmap"
const VERSION := 2
const DEFAULT_PPX := 256

var doc: Dictionary = {}
var grid: HexGrid = HexGrid.new()
## Where it was loaded from / last saved to. Empty for a new map.
var path: String = ""
var dirty: bool = false


static func create(p_name: String, p_grid: HexGrid) -> HexMap:
	var m := HexMap.new()
	m.grid = p_grid
	var now := JsonDoc.now()
	m.doc = {
		"format": FORMAT,
		"version": VERSION,
		"id": _uuid(),
		"name": p_name,
		"grid": p_grid.to_dict(),
		"reference_ppx": DEFAULT_PPX,
		"style": {"background": "#1c1a17", "grid_color": "#00000066", "grid_width": 0.012},
		"packs": {},
		"levels": [new_level("ground", "Ground floor")],
		"meta": {"author": "", "description": "", "created": now, "modified": now},
		"ext": {},
	}
	return m


static func new_level(id: String, p_name: String) -> Dictionary:
	return {
		"id": id, "name": p_name, "elevation_range": [0, 1],
		"terrain": {}, "props": [], "walls": [], "lights": [], "notes": [],
		"tree": LayerTree.default_tree(),
	}


# ------------------------------------------------------------------ accessors --

var name: String:
	get: return str(doc.get("name", "Untitled"))
	set(v):
		doc["name"] = v
		touch("name")

var reference_ppx: int:
	get: return int(doc.get("reference_ppx", DEFAULT_PPX))

var style: Dictionary:
	get: return doc.get("style", {})

var levels: Array:
	get: return doc.get("levels", [])


func level(i: int) -> Dictionary:
	var ls: Array = levels
	if i < 0 or i >= ls.size():
		return {}
	return ls[i]


func level_by_id(id: String) -> Dictionary:
	for l in levels:
		if l.get("id", "") == id:
			return l
	return {}


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func key_cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


## Find an object by id in any collection of a level. Returns {} if absent.
static func find_in(level: Dictionary, collection: String, id: String) -> Dictionary:
	for o in level.get(collection, []):
		if o.get("id", "") == id:
			return o
	return {}


static func index_in(level: Dictionary, collection: String, id: String) -> int:
	var arr: Array = level.get(collection, [])
	for i in arr.size():
		if arr[i].get("id", "") == id:
			return i
	return -1


## Record that a pack is in use (called when an asset from it is placed).
func note_pack(pack_id: String, pack_version: String) -> void:
	var packs: Dictionary = doc.get("packs", {})
	if not packs.has(pack_id):
		packs[pack_id] = pack_version
		doc["packs"] = packs


## Mark modified and tell listeners. `what` is a coarse hint ("terrain",
## "props", "walls", "lights", "notes", "grid", "style", "levels", "name").
func touch(what: String = "") -> void:
	dirty = true
	doc.get("meta", {})["modified"] = JsonDoc.now()
	changed.emit(what)


# ------------------------------------------------------------------- file IO --

func to_json() -> String:
	doc["format"] = FORMAT
	doc["version"] = VERSION
	doc["grid"] = grid.to_dict()
	for l in levels:
		LayerTree.ensure(l)
	return JsonDoc.stringify(doc)


## Parse a document. Returns null and fills `error` on failure.
static func from_json(text: String, error: Array = []) -> HexMap:
	var d := JsonDoc.parse(text, error)
	if d.is_empty():
		return null
	if d.get("format", "") != FORMAT:
		error.append("not a %s document (format is '%s')" % [FORMAT, d.get("format", "")])
		return null
	var version := int(d.get("version", 0))
	if version > VERSION:
		error.append("written by a newer editor (version %d, this reads %d)" % [version, VERSION])
		return null
	var m := HexMap.new()
	m.doc = d
	m.grid = HexGrid.from_dict(d.get("grid", {}))
	m._upgrade(version)
	return m


func _upgrade(_from_version: int) -> void:
	# Nothing to upgrade yet. Fill in anything a hand-written file omitted.
	if not doc.has("levels") or (doc["levels"] as Array).is_empty():
		doc["levels"] = [new_level("ground", "Ground floor")]
	for l in doc["levels"]:
		for k in ["props", "walls", "lights", "notes"]:
			if not l.has(k):
				l[k] = []
		if not l.has("terrain"):
			l["terrain"] = {}
		if not l.has("elevation_range"):
			l["elevation_range"] = [0, 1]
		# v1 had a fixed ground/objects/overhead `layer` on props; v2 has the
		# layer tree. ensure() migrates and reconciles either way.
		LayerTree.ensure(l)
	for k in ["style", "packs", "meta", "ext"]:
		if not doc.has(k):
			doc[k] = {}
	if not doc.has("reference_ppx"):
		doc["reference_ppx"] = DEFAULT_PPX
	if not doc.has("id"):
		doc["id"] = _uuid()


func save(p_path: String = "") -> Error:
	if p_path != "":
		path = p_path
	if path == "":
		return ERR_FILE_BAD_PATH
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	f.close()
	dirty = false
	return OK


static func load_file(p_path: String, error: Array = []) -> HexMap:
	var real := p_path
	# A bundle directory holds map.json.
	if DirAccess.dir_exists_absolute(p_path):
		real = p_path.path_join("map.json")
	if not FileAccess.file_exists(real):
		error.append("no such file: " + real)
		return null
	var text := FileAccess.get_file_as_string(real)
	var m := from_json(text, error)
	if m != null:
		m.path = p_path
	return m


# ---------------------------------------------------------------------- misc --

static func new_id(prefix: String) -> String:
	return JsonDoc.new_id(prefix)


static func _uuid() -> String:
	return JsonDoc.uuid()
