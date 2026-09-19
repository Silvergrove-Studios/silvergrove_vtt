extends SceneTree
## Export a map from the command line (needs a window: rendering happens on
## the GPU, so this is run without --headless; run.sh does that for you).
##
##   godot --path . -s tools/export_cli.gd -- <map.hexmap> <target> <out> [options]
##
## targets:
##   png <out.png> [ppx] [grid|nogrid] [gm]
##   uvtt <out.dd2vtt> [ppx] [level]
##   foundry <out.json> [ppx]
##   tiled <out.tmj> [ppx] [level]
##   pdf <out.pdf> [key=value ...]       keys as in PdfExport.DEFAULTS
##   bundle <out_dir> [dpi] [hex_size_in] [level]
##   all <out_dir>                        one of everything, for smoke tests

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <map.hexmap> <png|uvtt|foundry|tiled|pdf|bundle|all> <out> [options]")
		quit(1)
		return
	var host := Node.new()
	root.add_child(host)
	_run(host, args)


func _run(host: Node, args: PackedStringArray) -> void:
	var err: Array = []
	var map := HexMap.load_file(_abs(args[0]), err)
	if map == null:
		print("cannot load ", args[0], ": ", err)
		quit(1)
		return
	var packs := PackLibrary.new()
	packs.reload()
	for w in packs.warnings:
		print("warning: ", w)
	var target := args[1]
	var out := _abs(args[2])
	var rest := args.slice(3)
	var result := OK
	# The window needs a frame before viewports render reliably.
	await process_frame
	match target:
		"png":
			var ppx := int(rest[0]) if rest.size() > 0 else map.reference_ppx
			var grid := not (rest.size() > 1 and rest[1] == "nogrid")
			var gm := rest.has("gm")
			result = await Exporter.png(host, map, packs, out, ppx, {"show_grid": grid, "show_walls": gm, "show_lights": gm, "show_notes": gm, "show_hidden": gm})
		"uvtt":
			result = await Exporter.uvtt(host, map, packs, out, int(rest[0]) if rest.size() > 0 else 140, int(rest[1]) if rest.size() > 1 else 0)
		"foundry":
			result = await Exporter.foundry(host, map, packs, out, int(rest[0]) if rest.size() > 0 else 140)
		"tiled":
			result = Exporter.tiled(map, packs, out, int(rest[0]) if rest.size() > 0 else map.reference_ppx, int(rest[1]) if rest.size() > 1 else 0)
		"pdf":
			var opts := {}
			for kv in rest:
				var parts := kv.split("=")
				if parts.size() == 2:
					opts[parts[0]] = _value(parts[1])
			result = await Exporter.pdf(host, map, packs, out, opts)
		"bundle":
			result = await Exporter.bundle(host, map, packs, out, int(rest[0]) if rest.size() > 0 else 300, float(rest[1]) if rest.size() > 1 else 1.0, int(rest[2]) if rest.size() > 2 else 0)
		"all":
			DirAccess.make_dir_recursive_absolute(out)
			var base := out.path_join(map.name.to_snake_case())
			for step in [
				func(): return await Exporter.png(host, map, packs, base + ".png", 128, {}),
				func(): return await Exporter.uvtt(host, map, packs, base + ".dd2vtt", 140, 0),
				func(): return await Exporter.foundry(host, map, packs, base + "_foundry.json", 140),
				func(): return Exporter.tiled(map, packs, base + ".tmj", 128, 0),
				func(): return await Exporter.pdf(host, map, packs, base + ".pdf", {"dpi": 100, "gm_layers": true}),
				func(): return await Exporter.pdf(host, map, packs, base + "_fit.pdf", {"mode": "fit", "landscape": true, "dpi": 120}),
				func(): return await Exporter.bundle(host, map, packs, base + "_bundle", 150, 1.0, 0),
			]:
				result = await step.call()
				print(Exporter.last_message if result == OK else "FAILED: " + error_string(result))
				if result != OK:
					break
		_:
			print("unknown target ", target)
			result = ERR_INVALID_PARAMETER
	if target != "all":
		print(Exporter.last_message if result == OK else "FAILED: " + error_string(result))
	quit(0 if result == OK else 1)


static func _abs(p: String) -> String:
	return p if p.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(p)


static func _value(s: String) -> Variant:
	if s == "true": return true
	if s == "false": return false
	if s.is_valid_int(): return int(s)
	if s.is_valid_float(): return float(s)
	return s
