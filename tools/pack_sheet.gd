extends SceneTree
## godot --headless -s tools/pack_sheet.gd -- <pack_id> <out.png> [cell_px]
## Contact sheet of every terrain variant and prop in a pack, rasterised the
## way the editor does it. Works headless (SVG rasterisation is CPU-side).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <pack_id> <out.png> [cell_px]")
		quit(1)
		return
	var cell := int(args[2]) if args.size() > 2 else 128
	var lib := PackLibrary.new()
	lib.reload()
	if not lib.packs.has(args[0]):
		print("no such pack: ", args[0], " (have ", lib.pack_ids(), ")")
		quit(1)
		return
	var items: Array = []
	for t in lib.packs[args[0]].terrains:
		for shape in ["hex", "square"]:
			var art := lib.terrain_art("%s:%s" % [args[0], t.id], shape)
			if str(art.set) != ("textures_square" if shape == "square" else "textures_hex") and shape == "square":
				continue   # no square art of its own: the hex sheet shows it
			for v in (art.files as Array).size():
				items.append({"tex": lib.terrain_texture("%s:%s" % [args[0], t.id], v, cell, shape), "label": "%s %s %d" % [t.id, shape, v + 1]})
	for p in lib.packs[args[0]].props:
		items.append({"tex": lib.prop_texture("%s:%s" % [args[0], p.id], cell / maxf(1.0, float(p.size[0]))), "label": p.id})
	var cols := 8
	var rows := ceili(items.size() / float(cols))
	var pad := 6
	var label_h := 14
	var sheet := Image.create(cols * (cell + pad) + pad, rows * (cell + pad + label_h) + pad, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.16, 0.18))
	var font := ThemeDB.fallback_font
	for i in items.size():
		var img: Image = items[i].tex.get_image().duplicate()
		img.convert(Image.FORMAT_RGBA8)
		var scale := minf(float(cell) / img.get_width(), float(cell) / img.get_height())
		img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
		var x := pad + (i % cols) * (cell + pad) + (cell - img.get_width()) / 2
		var y := pad + (i / cols) * (cell + pad + label_h) + (cell - img.get_height()) / 2
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, y))
	sheet.save_png(args[1])
	print("wrote ", args[1], " with ", items.size(), " items")
	for w in lib.warnings:
		print("warning: ", w)
	quit(0)
