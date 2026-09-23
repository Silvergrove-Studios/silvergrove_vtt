class_name ContentImport
extends RefCounted
## Content brought into a campaign: a pack directory, a one-file pack, or
## a file of entries for one collection. What is imported is checked
## against the ruleset's schemas, copied into the campaign's own
## `packs/` folder (so the campaign stays self-contained and can be
## copied), listed in the campaign's `packs`, and noted in
## `content.imported` with the session it arrived in. It layers over
## what the rulesets ship, by pack order, so an import may also override
## a shipped entry by id.
##
## The schema contract (docs/campaign-packages.md): a pack may declare
## the `content_api` of the ruleset it was written against. A pack from
## a newer content API than the installed ruleset is refused; an older
## one loads. Unknown fields in an entry are kept, never dropped.

## What a path holds, without importing it:
## {ok, why, id, name, plugin, content_api, collections: {name: count}, entries, kind}
static func inspect(path: String) -> Dictionary:
	var out := {"ok": false, "why": "", "id": "", "name": "", "plugin": "", "content_api": 0, "collections": {}, "entries": 0, "kind": ""}
	if DirAccess.dir_exists_absolute(path):
		var mp := path.path_join("pack.json")
		if not FileAccess.file_exists(mp):
			out.why = "no pack.json in %s" % path
			return out
		var manifest := _json(mp)
		if manifest.is_empty():
			out.why = "%s could not be read" % mp
			return out
		out.kind = "pack directory"
		_fill(out, manifest)
		for name in manifest.get("collections", {}):
			var f := path.path_join(str(manifest.collections[name]))
			if not FileAccess.file_exists(f):
				out.why = "%s names %s, which is not there" % [str(manifest.get("id", "?")), str(manifest.collections[name])]
				return out
			out.collections[str(name)] = _entries_of(_json(f)).size()
		out.ok = true
		return out
	if not FileAccess.file_exists(path):
		out.why = "nothing at %s" % path
		return out
	var doc := _json(path)
	if doc.is_empty():
		out.why = "%s is not JSON this build reads" % path.get_file()
		return out
	if doc.get("pack") is Dictionary:
		out.kind = "pack file"
		_fill(out, doc.pack)
		for name in doc.get("collections", {}):
			out.collections[str(name)] = _entries_of(doc.collections[name]).size()
		out.ok = true
		return out
	# a file of entries for one collection: {collection, entries} (or {collection, id, …} for one)
	var coll := str(doc.get("collection", ""))
	if coll == "":
		out.why = "%s says no collection: an entry file needs \"collection\"" % path.get_file()
		return out
	out.kind = "entries"
	out.id = str(doc.get("id", path.get_file().get_basename()))
	out.name = str(doc.get("name", out.id))
	out.plugin = str(doc.get("plugin", ""))
	out.content_api = int(doc.get("content_api", 0))
	out.collections[coll] = _entries_of(doc).size()
	out.ok = true
	return out


## Bring it in. Returns {ok, why, id, added: {collection: n},
## refused: [reasons], missing: [what it names and nothing has]}.
## `host` may be null (nothing is checked against a schema then).
static func import_into(path: String, campaign: Campaign, host: PluginHost, comp: Compendium) -> Dictionary:
	var out := {"ok": false, "why": "", "id": "", "added": {}, "refused": [], "missing": []}
	var info := inspect(path)
	if not info.ok:
		out.why = str(info.why)
		return out
	if campaign == null or campaign.path == "":
		out.why = "save the campaign first: an import is copied into its folder"
		return out
	var collections := _collections_of(path, info)
	var plugin := str(info.plugin)
	if plugin == "" and host != null:
		plugin = _guess_plugin(host, collections.keys())
	# the schema contract: a pack from a newer content API than the ruleset
	var want := int(info.content_api)
	if want > 0 and host != null and host.plugins.has(plugin):
		var have := int((host.plugins[plugin] as PluginHost.Plugin).manifest.get("content_api", 1))
		if want > have:
			out.why = "%s was written for %s content API %d; this table has %d" % [str(info.name), plugin, want, have]
			return out
	# every entry against its collection's schema
	var bad := _check(collections, host, plugin)
	if not bad.is_empty():
		out.refused = bad
		out.why = "%d entr%s would not load: %s" % [bad.size(), "y" if bad.size() == 1 else "ies", str(bad[0])]
		return out
	# what it points at and nothing has (a class whose features are not there):
	# worth saying, not worth refusing — the rest of the pack is good content
	out.missing = dangling(collections, host, plugin, comp)
	var id := str(info.id)
	if id == "":
		out.why = "the pack has no id"
		return out
	var dest := campaign.base_dir().path_join("packs").path_join(id)
	var why := write_pack(dest, {"id": id, "name": str(info.name), "plugin": plugin, "pack_version": str(info.get("pack_version", "1")),
		"content_api": want, "provenance": info.get("provenance", {})}, collections)
	if why != "":
		out.why = why
		return out
	# the campaign remembers it: loaded next time, and how it arrived
	var rel := "packs/%s" % id
	var found := false
	for p in campaign.packs:
		if p is Dictionary and str(p.get("id", "")) == id:
			p.path = rel
			p.version = str(info.get("pack_version", "1"))
			found = true
	if not found:
		campaign.packs.append({"id": id, "path": rel, "version": str(info.get("pack_version", "1"))})
	var log: Array = campaign.content.imported
	log.append({"id": id, "name": str(info.name), "path": rel, "plugin": plugin,
		"session": int(campaign.clock.get("session", 0)), "at": JsonDoc.now(), "entries": info.entries})
	campaign.touch()
	if comp != null:
		var lw := comp.load_path(dest)
		if lw != "":
			out.why = lw
			return out
	for name in collections:
		out.added[name] = (collections[name] as Array).size()
	out.id = id
	out.ok = true
	return out


## Write a pack directory: pack.json and one file per collection.
static func write_pack(dir: String, manifest: Dictionary, collections: Dictionary) -> String:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return "cannot make %s" % dir
	var m: Dictionary = {"format": Compendium.FORMAT, "version": Compendium.VERSION, "collections": {}}
	for k in manifest:
		if manifest[k] != null and str(manifest[k]) != "" and not (manifest[k] is Dictionary and (manifest[k] as Dictionary).is_empty()):
			m[k] = manifest[k]
	for name in collections:
		m.collections[str(name)] = "%s.json" % str(name)
		var f := FileAccess.open(dir.path_join("%s.json" % str(name)), FileAccess.WRITE)
		if f == null:
			return "cannot write %s in %s" % [str(name), dir]
		f.store_string(JsonDoc.stringify({"entries": collections[name]}))
		f.close()
	var mf := FileAccess.open(dir.path_join("pack.json"), FileAccess.WRITE)
	if mf == null:
		return "cannot write pack.json in %s" % dir
	mf.store_string(JsonDoc.stringify(m))
	mf.close()
	return ""


## Every entry checked against its collection's schema: the reasons, empty when all pass.
static func _check(collections: Dictionary, host: PluginHost, plugin: String) -> Array:
	var out := []
	if host == null or not host.plugins.has(plugin):
		return out
	var p: PluginHost.Plugin = host.plugins[plugin]
	for name in collections:
		if not p.schemas.has(str(name)):
			continue
		var schema: JsonSchema = p.schemas[str(name)]
		for e in collections[name]:
			if not (e is Dictionary):
				out.append("%s: an entry is not an object" % str(name))
				continue
			if str((e as Dictionary).get("id", "")) == "":
				out.append("%s: an entry has no id" % str(name))
				continue
			var why := schema.first_error(e)
			if why != "":
				out.append("%s/%s: %s" % [str(name), str(e.id), why])
			if out.size() >= 8:
				return out
	return out


## {collection: [entries]} from whatever the path holds.
static func _collections_of(path: String, info: Dictionary) -> Dictionary:
	var out := {}
	if str(info.kind) == "pack directory":
		var manifest := _json(path.path_join("pack.json"))
		for name in manifest.get("collections", {}):
			out[str(name)] = _entries_of(_json(path.path_join(str(manifest.collections[name]))))
		return out
	var doc := _json(path)
	if doc.get("pack") is Dictionary:
		for name in doc.get("collections", {}):
			out[str(name)] = _entries_of(doc.collections[name])
		return out
	out[str(doc.get("collection", ""))] = _entries_of(doc)
	return out


## The plugin whose schemas cover these collections, or "".
static func _guess_plugin(host: PluginHost, names: Array) -> String:
	var best := ""
	var best_n := 0
	var ids := host.plugins.keys()
	ids.sort()
	for pid in ids:
		var p: PluginHost.Plugin = host.plugins[pid]
		var n := 0
		for name in names:
			if p.schemas.has(str(name)):
				n += 1
		if n > best_n:
			best_n = n
			best = str(pid)
	return best


static func _fill(out: Dictionary, manifest: Dictionary) -> void:
	out.id = str(manifest.get("id", ""))
	out.name = str(manifest.get("name", out.id))
	out.plugin = str(manifest.get("plugin", ""))
	out.content_api = int(manifest.get("content_api", 0))
	out.pack_version = str(manifest.get("pack_version", "1"))
	out.provenance = manifest.get("provenance", {})


static func _entries_of(v: Variant) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		var d: Dictionary = v
		if d.get("entries") is Array:
			return d.entries
		if str(d.get("id", "")) != "":
			var one: Dictionary = d.duplicate()
			one.erase("collection")
			one.erase("plugin")
			one.erase("content_api")
			return [one]
	return []


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var err := []
	return JsonDoc.parse(FileAccess.get_file_as_string(path), err)


## The paths in a collection's schema that name entries of another
## collection — a property annotated `"collection": "features"` — as
## {path: collection}, where a path is pointer-ish with `*` for a list
## ("features/*/id"). It is an annotation, so any JSON Schema tool
## ignores it and Hexmap uses it to check that what a class names exists.
static func reference_paths(schema: Dictionary) -> Dictionary:
	var out := {}
	_refs(schema, "", out, 0)
	return out


static func _refs(node: Variant, path: String, out: Dictionary, depth: int) -> void:
	if depth > 8 or not (node is Dictionary):
		return
	var d: Dictionary = node
	if str(d.get("collection", "")) != "" and path != "":
		out[path] = str(d.collection)
	for key in d.get("properties", {}):
		_refs(d.properties[key], path.path_join(str(key)) if path != "" else str(key), out, depth + 1)
	if d.has("items"):
		_refs(d["items"], path.path_join("*") if path != "" else "*", out, depth + 1)
	if d.has("additionalProperties") and d.additionalProperties is Dictionary:
		_refs(d.additionalProperties, path.path_join("*") if path != "" else "*", out, depth + 1)


## The values an entry holds at an annotated path.
static func values_at(entry: Variant, path: String) -> Array:
	var parts := path.split("/", false)
	var here: Array = [entry]
	for part in parts:
		var next := []
		for v in here:
			if str(part) == "*":
				if v is Array:
					next.append_array(v)
				elif v is Dictionary:
					next.append_array((v as Dictionary).values())
			elif v is Dictionary and (v as Dictionary).has(str(part)):
				next.append((v as Dictionary)[str(part)])
		here = next
	var out := []
	for v in here:
		if v is String and str(v) != "":
			out.append(str(v))
	return out


## What an import names but nothing has: ["classes/my-warden → features/warden_rage", …].
## Resolved against the import itself and the compendium already loaded.
static func dangling(collections: Dictionary, host: PluginHost, plugin: String, comp: Compendium) -> Array:
	var out := []
	if host == null or not host.plugins.has(plugin):
		return out
	var p: PluginHost.Plugin = host.plugins[plugin]
	for name in collections:
		if not p.schemas.has(str(name)):
			continue
		var paths := reference_paths((p.schemas[str(name)] as JsonSchema).root)
		if paths.is_empty():
			continue
		for e in collections[name]:
			if not (e is Dictionary):
				continue
			for path in paths:
				var want := str(paths[path])
				for id in values_at(e, str(path)):
					var here: Array = collections.get(want, [])
					if here.any(func(x: Variant) -> bool: return x is Dictionary and str((x as Dictionary).get("id", "")) == id):
						continue
					if comp != null and not comp.get_entry(want, id).is_empty():
						continue
					out.append("%s/%s names %s/%s, which is nowhere" % [str(name), str(e.get("id", "?")), want, id])
					if out.size() >= 8:
						return out
	return out
