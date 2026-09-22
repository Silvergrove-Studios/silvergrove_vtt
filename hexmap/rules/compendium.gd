class_name Compendium
extends RefCounted
## Content packs, indexed: the rulesets' shipped compendia and the tables'
## own homebrew, layered by id, searched on the Table and served to Lua a
## page at a time — a compendium can be tens of thousands of entries and
## never goes into a VM wholesale.
##
## A pack is a directory:
##   pack.json         {format: "silvergrove.content", version: 1, id, name,
##                      pack_version, plugin, provenance: {source, license,
##                      attribution, url}, collections: {name: "file.json"}}
##   <collection>.json [ {id, name, …}, … ]   (or {"entries": [...]})
## or one file holding {"pack": {…}, "collections": {name: [entries]}}.
## Entries are plain records with an `id` unique within their collection;
## a later pack's entry with the same id replaces an earlier one (a table's
## homebrew over a ruleset's core). Every indexed entry carries `__pack`.
##
## Queries: filter on top-level fields (equal, or any of a list), full
## text over string fields, sort, pages; the result says which facet
## values the matches have and how many, so a browser can narrow.

const FORMAT := "silvergrove.content"
const VERSION := 1
const PAGE := 50
## Fields never indexed as facets.
const NO_FACET := ["id", "name", "text", "description", "__pack"]

## pack id -> {id, name, pack_version, plugin, provenance, layer, dir, user}
var packs: Dictionary = {}
## collection -> id -> entry (the winning layer)
var _entries: Dictionary = {}
## collection -> field -> value (as string) -> {id: true}
var _facets: Dictionary = {}
## collection -> word -> {id: true}
var _words: Dictionary = {}
## collection -> pack id -> {id: entry} (every layer, for unloading and saving)
var _by_pack: Dictionary = {}
var _layer := 0
## collection -> sort key -> ids in order (the sort of a whole collection
## is the costly part of a query; it only changes when entries do)
var _sorted: Dictionary = {}
## Where this table's writable packs live: the open campaign's own
## `packs/` folder. Empty until the campaign has been saved — content
## belongs to a campaign on disk, so there is nowhere to put it before.
var user_dir := ""
## Entries this table does not use: {collection: {id: true}}. They stay
## in their packs and answer by id (a character built on one still
## works); they are kept out of every *offer* — searches, pickers, the
## compendium's lists — until the campaign turns them on again.
var disabled: Dictionary = {}
## How many times a user pack was written to (put, remove, a new user
## pack): a reader that caches an index knows when it went stale.
var writes := 0


# --------------------------------------------------------------- loading --

## Load a pack directory or single-file pack. "" or why not.
func load_path(path: String) -> String:
	if FileAccess.file_exists(path):
		var err := []
		var doc := JsonDoc.parse(FileAccess.get_file_as_string(path), err)
		if doc.is_empty() or not (doc.get("pack") is Dictionary):
			return "%s: not a pack file" % path
		return load_pack(doc.pack, doc.get("collections", {}), path)
	var mp := path.path_join("pack.json")
	if not FileAccess.file_exists(mp):
		return "no pack.json in %s" % path
	var err := []
	var manifest := JsonDoc.parse(FileAccess.get_file_as_string(mp), err)
	if manifest.is_empty():
		return "%s: %s" % [mp, ", ".join(PackedStringArray(err))]
	var collections := {}
	for name in manifest.get("collections", {}):
		var f := path.path_join(str(manifest.collections[name]))
		if not FileAccess.file_exists(f):
			return "%s: missing %s" % [str(manifest.get("id", "?")), str(manifest.collections[name])]
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(f)) != OK:
			return "%s: %s: %s" % [str(manifest.get("id", "?")), str(manifest.collections[name]), json.get_error_message()]
		collections[str(name)] = json.data.get("entries", []) if json.data is Dictionary else json.data
	return load_pack(manifest, collections, path)


## Load a pack from its manifest and {collection: [entries]}. "" or why not.
func load_pack(manifest: Dictionary, collections: Dictionary, dir := "") -> String:
	if str(manifest.get("format", FORMAT)) != FORMAT or int(manifest.get("version", VERSION)) > VERSION:
		return "not a content pack this build reads"
	var id := str(manifest.get("id", ""))
	if id == "":
		return "a pack needs an id"
	if packs.has(id):
		unload(id)
	_layer += 1
	packs[id] = {"id": id, "name": str(manifest.get("name", id)), "pack_version": str(manifest.get("pack_version", "1")), "plugin": str(manifest.get("plugin", "")),
		"provenance": JsonDoc.deep(manifest.get("provenance", {})), "layer": _layer, "dir": dir, "user": bool(manifest.get("user", false)), "collections": collections.keys(),
		"audience": str(manifest.get("audience", "all"))}
	for name in collections:
		var list: Variant = collections[name]
		if not (list is Array):
			continue
		for entry in list:
			if entry is Dictionary and str(entry.get("id", "")) != "":
				_put(str(name), entry, id)
	return ""


## Drop a pack and re-resolve the ids it had won.
func unload(id: String) -> void:
	if not packs.has(id):
		return
	for coll in _by_pack:
		if not _by_pack[coll].has(id):
			continue
		for eid in _by_pack[coll][id]:
			_unindex(coll, str(eid))
		_by_pack[coll].erase(id)
	packs.erase(id)
	# re-index what other layers still hold for those ids
	for coll in _by_pack:
		for pid in _by_pack[coll]:
			for eid in _by_pack[coll][pid]:
				if not _entries.get(coll, {}).has(eid):
					_index(coll, _by_pack[coll][pid][eid], str(pid))


## Make (or open) a writable pack for this campaign's own entries. It
## exists in memory at once; keeping it needs somewhere to write (a
## campaign that has been saved), which `save_user_pack` checks.
func user_pack(id: String, p_name := "", plugin := "") -> Dictionary:
	if not packs.has(id):
		writes += 1
		load_pack({"id": id, "name": p_name if p_name != "" else id, "plugin": plugin, "user": true, "pack_version": "1"}, {},
			user_dir.path_join(id) if user_dir != "" else "")
	return packs[id]


# ------------------------------------------------------------------ index --

func _put(coll: String, entry: Dictionary, pack_id: String) -> void:
	var e: Dictionary = JsonDoc.deep(entry)
	e.__pack = pack_id
	if not _by_pack.has(coll):
		_by_pack[coll] = {}
	if not _by_pack[coll].has(pack_id):
		_by_pack[coll][pack_id] = {}
	_by_pack[coll][pack_id][str(e.id)] = e
	var cur: Dictionary = _entries.get(coll, {}).get(str(e.id), {})
	if cur.is_empty() or int(packs[str(cur.__pack)].layer) <= int(packs[pack_id].layer):
		if not cur.is_empty():
			_unindex(coll, str(e.id))
		_index(coll, e, pack_id)


func _index(coll: String, e: Dictionary, _pack_id: String) -> void:
	if not _entries.has(coll):
		_entries[coll] = {}
		_facets[coll] = {}
		_words[coll] = {}
	var id := str(e.id)
	_entries[coll][id] = e
	_sorted.erase(coll)
	for k in e:
		var key := str(k)
		if NO_FACET.has(key):
			continue
		_index_value(coll, key, e[k], id, 0)
	for w in _tokens(e):
		if not _words[coll].has(w):
			_words[coll][w] = {}
		_words[coll][w][id] = true


## Scalars and lists of scalars become facets under their field; an
## object's scalars become facets under a path ("stats/level"), three
## levels down at most.
func _index_value(coll: String, key: String, v: Variant, id: String, depth: int) -> void:
	if v is String or v is float or v is int or v is bool:
		_facet(coll, key, str(v) if not (v is float) else JsonDoc.sorted(v), id)
	elif v is Array:
		for item in v:
			if item is String or item is float or item is int:
				_facet(coll, key, str(item) if not (item is float) else JsonDoc.sorted(item), id)
	elif v is Dictionary and depth < 3:
		for k in v:
			_index_value(coll, key + "/" + str(k), v[k], id, depth + 1)


func _facet(coll: String, field: String, value: Variant, id: String) -> void:
	var sv := str(value)
	if not _facets[coll].has(field):
		_facets[coll][field] = {}
	if not _facets[coll][field].has(sv):
		_facets[coll][field][sv] = {}
	_facets[coll][field][sv][id] = true


func _unindex(coll: String, id: String) -> void:
	var e: Dictionary = _entries.get(coll, {}).get(id, {})
	if e.is_empty():
		return
	_entries[coll].erase(id)
	_sorted.erase(coll)
	for field in _facets[coll]:
		for sv in _facets[coll][field].keys():
			(_facets[coll][field][sv] as Dictionary).erase(id)
			if (_facets[coll][field][sv] as Dictionary).is_empty():
				(_facets[coll][field] as Dictionary).erase(sv)
	for w in _tokens(e):
		if _words[coll].has(w):
			(_words[coll][w] as Dictionary).erase(id)
			if (_words[coll][w] as Dictionary).is_empty():
				(_words[coll] as Dictionary).erase(w)


static var _word_re: RegEx
static func _tokens(e: Dictionary) -> Dictionary:
	if _word_re == null:
		_word_re = RegEx.new()
		_word_re.compile("[a-z0-9]+")
	var out := {}
	for k in e:
		if str(k) == "__pack":
			continue
		var v: Variant = e[k]
		if v is String:
			for m in _word_re.search_all((v as String).to_lower()):
				out[m.get_string()] = true
	return out


# ---------------------------------------------------------------- queries --

func collections() -> Array:
	var out := _entries.keys()
	out.sort()
	return out


func count(coll: String) -> int:
	return _entries.get(coll, {}).size()


## How many of a collection are turned off.
func disabled_count(coll: String) -> int:
	var off := 0
	for id in disabled.get(coll, {}):
		if _entries.get(coll, {}).has(id):
			off += 1
	return off


func is_disabled(coll: String, id: String) -> bool:
	return bool(disabled.get(coll, {}).get(id, false))


## The winning entry, or {}.
func get_entry(coll: String, id: String) -> Dictionary:
	return JsonDoc.deep(_entries.get(coll, {}).get(id, {}))


## Whether an entry is for players' eyes: its pack's `audience` and its
## own `audience` field must both be "all" (the default). The GM sees all.
func visible_to_players(entry: Dictionary) -> bool:
	if str(entry.get("audience", "all")) == "gm":
		return false
	var pack: Dictionary = packs.get(str(entry.get("__pack", "")), {})
	return str(pack.get("audience", "all")) != "gm"


## A query as a client sees it: `gm` false drops entries players may not
## see (before paging, so the counts are theirs) and the `__pack` key.
func query_for(coll: String, opts: Dictionary, gm: bool) -> Dictionary:
	if gm:
		return query(coll, opts)
	var o: Dictionary = opts.duplicate(true)
	# page the visible ones: ask for everything matching, then cut
	var per := maxi(1, int(o.get("per_page", PAGE)))
	var page := maxi(1, int(o.get("page", 1)))
	o.per_page = 100000
	o.page = 1
	var r := query(coll, o)
	var seen := []
	for e in r.entries:
		if visible_to_players(e):
			var slim: Dictionary = e.duplicate()
			slim.erase("__pack")
			seen.append(slim)
	var total := seen.size()
	var start := (page - 1) * per
	return {"total": total, "page": page, "per_page": per, "pages": int(ceil(float(total) / per)) if total > 0 else 0,
		"entries": seen.slice(start, mini(total, start + per)), "facets": r.facets}


## An entry as a client sees it, or {} when there is none for them.
func entry_for(coll: String, id: String, gm: bool) -> Dictionary:
	var e := get_entry(coll, id)
	if e.is_empty() or (not gm and not visible_to_players(e)):
		return {}
	if not gm:
		e.erase("__pack")
	return e


## The facet fields a collection has and how many distinct values each.
func facets(coll: String) -> Dictionary:
	var out := {}
	for field in _facets.get(coll, {}):
		out[field] = (_facets[coll][field] as Dictionary).size()
	return out


## Query a collection. opts: filter {field: value | [values]}, text
## (words, all must match, prefixes allowed), sort (field, "-field" for
## descending; default "name"), page (from 1), per_page, fields (which
## entry fields to return; default all), facets (fields to count),
## disabled (true: include the entries the campaign turned off).
## Result: {total, page, per_page, pages, entries, facets: {field: {value: n}}}.
func query(coll: String, opts: Dictionary = {}) -> Dictionary:
	var all: Dictionary = _entries.get(coll, {})
	var ids: Dictionary = {}
	var started := false
	# filters narrow through the facet index
	var filter: Dictionary = opts.get("filter", {}) if opts.get("filter") is Dictionary else {}
	for field in filter:
		var hit := _filter_hits(coll, str(field), filter[field], all)
		ids = hit if not started else _intersect(ids, hit)
		started = true
	# text: every word (prefix) must match
	var text := str(opts.get("text", "")).to_lower().strip_edges()
	if text != "":
		for w in text.split(" ", false):
			var hit := {}
			for word in _words.get(coll, {}):
				if str(word).begins_with(w):
					for id in _words[coll][word]:
						hit[id] = true
			ids = hit if not started else _intersect(ids, hit)
			started = true
	var sort := str(opts.get("sort", "name"))
	var list: Array
	if started:
		list = ids.keys()
		_sort(list, all, sort)
	else:
		# the whole collection in this order, cached until entries change
		if not _sorted.has(coll):
			_sorted[coll] = {}
		if not _sorted[coll].has(sort):
			var whole: Array = all.keys()
			_sort(whole, all, sort)
			_sorted[coll][sort] = whole
		list = _sorted[coll][sort]
	# what the campaign turned off is not offered (opts.disabled = true asks for it anyway)
	var off: Dictionary = disabled.get(coll, {})
	if not off.is_empty() and not bool(opts.get("disabled", false)):
		var kept := []
		for id in list:
			if not off.has(id):
				kept.append(id)
		list = kept
	# facets over the matches
	var facet_out := {}
	for field in opts.get("facets", []):
		var counts := {}
		for id in list:
			var v: Variant = JsonDoc.at_path(all[id], str(field)) if str(field).contains("/") else all[id].get(str(field))
			var vals: Array = v if v is Array else [v]
			for item in vals:
				if item == null:
					continue
				var sv := str(item) if not (item is float) else str(JsonDoc.sorted(item))
				counts[sv] = int(counts.get(sv, 0)) + 1
		facet_out[str(field)] = counts
	# page
	var per := maxi(1, int(opts.get("per_page", PAGE)))
	var page := maxi(1, int(opts.get("page", 1)))
	var total := list.size()
	var start := (page - 1) * per
	var entries := []
	var fields: Variant = opts.get("fields")
	for i in range(start, mini(total, start + per)):
		var e: Dictionary = all[list[i]]
		if fields is Array:
			var slim := {"id": e.id, "__pack": e.__pack}
			for f in fields:
				if e.has(f):
					slim[f] = JsonDoc.deep(e[f])
			entries.append(slim)
		else:
			entries.append(JsonDoc.deep(e))
	return {"total": total, "page": page, "per_page": per, "pages": int(ceil(float(total) / per)) if total > 0 else 0, "entries": entries, "facets": facet_out}


## The ids a filter value picks out of a field's facets: a value or a
## list of values (any of), {min, max} (a numeric range, either end
## optional), or {not: value | [values]} (everything else).
func _filter_hits(coll: String, field: String, wanted: Variant, all: Dictionary) -> Dictionary:
	var facets: Dictionary = _facets.get(coll, {}).get(field, {})
	var hit := {}
	if wanted is Dictionary and ((wanted as Dictionary).has("min") or (wanted as Dictionary).has("max")):
		var lo := float(wanted.get("min", -INF))
		var hi := float(wanted.get("max", INF))
		for sv in facets:
			if not str(sv).is_valid_float():
				continue
			var n := float(sv)
			if n >= lo and n <= hi:
				for id in facets[sv]:
					hit[id] = true
		return hit
	if wanted is Dictionary and (wanted as Dictionary).has("not"):
		var out := _filter_hits(coll, field, wanted["not"], all)
		for id in all:
			if not out.has(id):
				hit[id] = true
		return hit
	var values: Array = wanted if wanted is Array else [wanted]
	for v in values:
		var sv := str(v) if not (v is float) else str(JsonDoc.sorted(v))
		for id in facets.get(sv, {}):
			hit[id] = true
	return hit


static func _sort(list: Array, all: Dictionary, sort: String) -> void:
	var desc := sort.begins_with("-")
	var key := sort.trim_prefix("-")
	list.sort_custom(func(a, b) -> bool:
		var x: Variant = JsonDoc.at_path(all[a], key) if key.contains("/") else all[a].get(key, all[a].get("id"))
		var y: Variant = JsonDoc.at_path(all[b], key) if key.contains("/") else all[b].get(key, all[b].get("id"))
		if x == null:
			x = all[a].get("id")
		if y == null:
			y = all[b].get("id")
		var less: bool
		if (x is float or x is int) and (y is float or y is int):
			less = float(x) < float(y)
		else:
			less = str(x) < str(y)
		return not less if desc and x != y else less)


static func _intersect(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		if b.has(k):
			out[k] = true
	return out


# ------------------------------------------------------------ user packs --

## Put an entry into a user pack (validated against `schema` if given).
## "" or why not.
func put(coll: String, entry: Dictionary, pack_id: String, schema: JsonSchema = null) -> String:
	if not packs.has(pack_id):
		return "no pack '%s'" % pack_id
	if not bool(packs[pack_id].get("user", false)):
		return "pack '%s' is not writable" % pack_id
	if str(entry.get("id", "")) == "":
		return "an entry needs an id"
	if schema != null:
		var why := schema.first_error(entry)
		if why != "":
			return why
	var clean: Dictionary = JsonDoc.deep(entry)
	clean.erase("__pack")
	writes += 1
	if _by_pack.get(coll, {}).get(pack_id, {}).has(str(clean.id)):
		_remove_from_pack(coll, str(clean.id), pack_id)
	_put(coll, clean, pack_id)
	if not (packs[pack_id].collections as Array).has(coll):
		(packs[pack_id].collections as Array).append(coll)
	return ""


## Remove an entry from a user pack. "" or why not.
func remove(coll: String, id: String, pack_id: String) -> String:
	if not packs.has(pack_id) or not bool(packs[pack_id].get("user", false)):
		return "no writable pack '%s'" % pack_id
	if not _by_pack.get(coll, {}).get(pack_id, {}).has(id):
		return "no entry '%s' in %s" % [id, pack_id]
	writes += 1
	_remove_from_pack(coll, id, pack_id)
	return ""


func _remove_from_pack(coll: String, id: String, pack_id: String) -> void:
	(_by_pack[coll][pack_id] as Dictionary).erase(id)
	var cur: Dictionary = _entries.get(coll, {}).get(id, {})
	if not cur.is_empty() and str(cur.__pack) == pack_id:
		_unindex(coll, id)
		# the next layer down wins again
		var best := {}
		var best_layer := -1
		for pid in _by_pack[coll]:
			if _by_pack[coll][pid].has(id) and int(packs[pid].layer) > best_layer:
				best = _by_pack[coll][pid][id]
				best_layer = int(packs[pid].layer)
		if not best.is_empty():
			_index(coll, best, str(best.__pack))


## Write a user pack to its directory (pack.json + one file per collection).
func save_user_pack(pack_id: String) -> String:
	if not packs.has(pack_id) or not bool(packs[pack_id].get("user", false)):
		return "no writable pack '%s'" % pack_id
	var p: Dictionary = packs[pack_id]
	if str(p.dir) == "" and user_dir == "":
		return "nowhere to keep it: save the campaign first"
	var dir := str(p.dir) if str(p.dir) != "" else user_dir.path_join(pack_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var manifest := {"format": FORMAT, "version": VERSION, "id": pack_id, "name": p.name, "pack_version": p.pack_version, "plugin": p.plugin, "provenance": p.provenance, "user": true, "collections": {}}
	for coll in _by_pack:
		if not _by_pack[coll].has(pack_id):
			continue
		var list := []
		var ids: Array = _by_pack[coll][pack_id].keys()
		ids.sort()
		for id in ids:
			var e: Dictionary = JsonDoc.deep(_by_pack[coll][pack_id][id])
			e.erase("__pack")
			list.append(e)
		manifest.collections[coll] = "%s.json" % coll
		var f := FileAccess.open(dir.path_join("%s.json" % coll), FileAccess.WRITE)
		if f == null:
			return "cannot write %s" % dir
		f.store_string(JSON.stringify(JsonDoc.sorted({"entries": list}), "  ", false) + "\n")
		f.close()
	var mf := FileAccess.open(dir.path_join("pack.json"), FileAccess.WRITE)
	if mf == null:
		return "cannot write %s" % dir
	mf.store_string(JsonDoc.stringify(manifest))
	mf.close()
	packs[pack_id].dir = dir
	return ""


## One file holding a whole pack, for sharing.
func export_pack(pack_id: String, path: String) -> String:
	if not packs.has(pack_id):
		return "no pack '%s'" % pack_id
	var p: Dictionary = packs[pack_id]
	var doc := {"pack": {"format": FORMAT, "version": VERSION, "id": pack_id, "name": p.name, "pack_version": p.pack_version, "plugin": p.plugin, "provenance": p.provenance, "user": true}, "collections": {}}
	for coll in _by_pack:
		if _by_pack[coll].has(pack_id):
			var list := []
			for id in _by_pack[coll][pack_id]:
				var e: Dictionary = JsonDoc.deep(_by_pack[coll][pack_id][id])
				e.erase("__pack")
				list.append(e)
			doc.collections[coll] = list
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s" % path
	f.store_string(JsonDoc.stringify(doc))
	f.close()
	return ""


## Every user pack directory under user_dir, loaded.
func load_user_packs() -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(user_dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if da.current_is_dir() and not name.begins_with("."):
			var why := load_path(user_dir.path_join(name))
			out.append("%s: %s" % [name, "loaded" if why == "" else why])
			if why == "" and packs.has(name):
				packs[name].user = true
		name = da.get_next()
	da.list_dir_end()
	return out


## The pack versions an actor was built against, and which have changed
## since: {pack id: {was, now}} for the ones that differ.
func outdated(actor: Dictionary) -> Dictionary:
	var out := {}
	for pid in actor.get("packs", {}):
		var was := str(actor.packs[pid])
		var now := str(packs.get(str(pid), {}).get("pack_version", ""))
		if now != "" and now != was:
			out[str(pid)] = {"was": was, "now": now}
	return out


## The current versions of the packs a plugin has loaded, to stamp on a
## new actor.
func versions(plugin := "") -> Dictionary:
	var out := {}
	for pid in packs:
		if plugin == "" or str(packs[pid].plugin) == plugin:
			out[str(pid)] = str(packs[pid].pack_version)
	return out
