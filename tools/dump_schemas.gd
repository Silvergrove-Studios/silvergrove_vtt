extends SceneTree
## Publish a ruleset's content shapes, so someone writing a pack can
## check their work without running the Table:
##
##   ./run.sh schemas <plugin dir> <out dir>
##
## Writes one JSON Schema per collection (`<collection>.schema.json`,
## draft 2020-12, with Hexmap's `collection` annotation on fields that
## name another collection's entries) and `content-api.json` — the
## ruleset, its `content_api` and its collections. Commit them with the
## ruleset's release and validate packs against them in CI with any
## JSON Schema tool. docs/content-format.md has the contract.

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: ./run.sh schemas <plugin dir> <out dir>")
		quit(2)
		return false
	var dir := str(args[0])
	var out := str(args[1])
	var st := EncounterState.new(Encounter.create("schemas"))
	var kernel := RulesKernel.new(st)
	var host := PluginHost.new(kernel)
	host.plugin_failed.connect(func(id: String, where: String, msg: String) -> void: print("  %s: %s: %s" % [id, where, msg]))
	var why := host.load_dir(dir)
	if why != "":
		print("could not load %s: %s" % [dir, why])
		quit(1)
		return false
	var pid: String = host.plugins.keys()[0]
	var p: PluginHost.Plugin = host.plugins[pid]
	DirAccess.make_dir_recursive_absolute(out)
	var api := int(p.manifest.get("content_api", 1))
	var index := {"plugin": pid, "name": str(p.manifest.get("name", pid)), "version": str(p.manifest.get("version", "")),
		"content_api": api, "collections": {}, "references": {}}
	var names: Array = p.schemas.keys()
	names.sort()
	for kind in names:
		if str(kind) == "actor":
			continue
		var schema: Dictionary = JsonDoc.deep((p.schemas[kind] as JsonSchema).root)
		schema["$schema"] = "https://json-schema.org/draft/2020-12/schema"
		schema["$id"] = "%s/%s.schema.json" % [pid, str(kind)]
		schema["title"] = "%s %s (content API %d)" % [pid, str(kind), api]
		var file := "%s.schema.json" % str(kind)
		var f := FileAccess.open(out.path_join(file), FileAccess.WRITE)
		if f == null:
			print("cannot write ", out.path_join(file))
			quit(1)
			return false
		f.store_string(JsonDoc.stringify(schema))
		f.close()
		index.collections[str(kind)] = file
		var refs := ContentImport.reference_paths(schema)
		if not refs.is_empty():
			index.references[str(kind)] = refs
		print("wrote %s (%d entries shipped)" % [out.path_join(file), kernel.comp.count(str(kind))])
	# the actor shape too: a character file is written against it
	if p.schemas.has("actor"):
		var a: Dictionary = JsonDoc.deep((p.schemas["actor"] as JsonSchema).root)
		a["$schema"] = "https://json-schema.org/draft/2020-12/schema"
		a["$id"] = "%s/actor.schema.json" % pid
		a["title"] = "%s actor (content API %d)" % [pid, api]
		var af := FileAccess.open(out.path_join("actor.schema.json"), FileAccess.WRITE)
		af.store_string(JsonDoc.stringify(a))
		af.close()
		index.actor = "actor.schema.json"
		print("wrote ", out.path_join("actor.schema.json"))
	var indexf := FileAccess.open(out.path_join("content-api.json"), FileAccess.WRITE)
	indexf.store_string(JsonDoc.stringify(index))
	indexf.close()
	print("wrote %s: %s content API %d, %d collections" % [out.path_join("content-api.json"), pid, api, index.collections.size()])
	quit(0)
	return false
