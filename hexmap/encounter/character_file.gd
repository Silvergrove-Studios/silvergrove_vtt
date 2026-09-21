class_name CharacterFile
extends RefCounted
## A character that belongs to its player: an actor on its own, in a file
## the player's device keeps and brings to a table. The Table adopts it
## on request (validated by the rulesets like any actor), owns it while
## the session runs, and the player takes the updated record home from
## their view. Groups change DMs and players play in several groups; a
## character is theirs, not a file's.
##
##   { "format": "silvergrove.character", "version": 1,
##     "plugins": [ {"id": "sample.focus", "version": "0.1.0"} ],
##     "actor": { id, kind, name, ext, packs, token, audience },
##     "saved": "2026-09-21T…" }

const FORMAT := "silvergrove.character"
const VERSION := 1
const DIR := "user://characters"


## The file document for an actor (derived numbers are the Table's to
## make again; owner is whoever brings it).
static func make(actor: Dictionary, plugins: Array = []) -> Dictionary:
	var a: Dictionary = JsonDoc.deep(actor)
	for k in ["derived", "owner", "overlays", "mine", "sheets", "effects", "resources", "tokens"]:
		a.erase(k)
	return {"format": FORMAT, "version": VERSION, "plugins": JsonDoc.deep(plugins), "actor": a, "saved": JsonDoc.now()}


## From a projected actor in a Player's view (its `ext` is whole when the
## actor is theirs).
static func from_view(pa: Dictionary, plugins: Array = []) -> Dictionary:
	return make({"id": str(pa.get("id", "")), "kind": str(pa.get("kind", "pc")), "name": str(pa.get("name", "")), "ext": pa.get("ext", {}),
		"packs": pa.get("packs", {}), "token": pa.get("token", {}), "audience": pa.get("audience", {})}, plugins)


## The actor record a Table adds for the player who brought the file.
static func to_actor(doc: Dictionary, owner: String) -> Dictionary:
	var a: Dictionary = JsonDoc.deep(doc.get("actor", {}))
	a.owner = owner
	a.erase("derived")
	a.erase("overlays")
	if not a.has("kind"):
		a.kind = "pc"
	Encounter.fill_actor(a)
	return a


## "" when the document is a character file this build reads.
static func check(doc: Variant) -> String:
	if not (doc is Dictionary):
		return "not a character"
	if str(doc.get("format", "")) != FORMAT:
		return "not a character file"
	if int(doc.get("version", 0)) > VERSION:
		return "a newer character format than this build reads"
	if not (doc.get("actor") is Dictionary) or str(doc.actor.get("id", "")) == "" or str(doc.actor.get("name", "")) == "":
		return "a character needs an id and a name"
	return ""


static func save(doc: Dictionary, path := "") -> String:
	var p := path if path != "" else DIR.path_join("%s.json" % str(doc.get("actor", {}).get("id", "character")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return "cannot write %s" % p
	f.store_string(JsonDoc.stringify(doc))
	f.close()
	return ""


## The document, or {} with `error` filled.
static func load_file(path: String, error: Array = []) -> Dictionary:
	if not FileAccess.file_exists(path):
		error.append("no file " + path)
		return {}
	var doc := JsonDoc.parse(FileAccess.get_file_as_string(path), error)
	if doc.is_empty():
		return {}
	var why := check(doc)
	if why != "":
		error.append(why)
		return {}
	return doc


## The characters kept on this device: [{path, doc}], by name.
static func list(dir := DIR) -> Array:
	var out := []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not da.current_is_dir() and name.ends_with(".json"):
			var doc := load_file(dir.path_join(name))
			if not doc.is_empty():
				out.append({"path": dir.path_join(name), "doc": doc})
		name = da.get_next()
	da.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.doc.actor.name) < str(b.doc.actor.name))
	return out
