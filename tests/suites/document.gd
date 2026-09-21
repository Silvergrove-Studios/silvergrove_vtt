extends TestCase
## Map documents and history.


func test_map_json_roundtrip() -> void:
	var m := HexMap.create("Test", HexGrid.new(HexGrid.Orient.FLAT, HexGrid.Offset.EVEN, 5, 4))
	var lvl := m.level(0)
	lvl["terrain"]["0,0"] = {"t": "woodland:grass", "v": 1, "rot": 0, "z": 0}
	lvl["props"].append({"id": "p_1", "asset": "woodland:oak_large", "pos": [1.25, 2.5], "rot": 15.0, "scale": 1.0})
	var text := m.to_json()
	var err := []
	var m2 := HexMap.from_json(text, err)
	check(m2 != null, "parses back: %s" % [err])
	if m2 == null:
		return
	check(m2.grid.orientation == HexGrid.Orient.FLAT and m2.grid.offset == HexGrid.Offset.EVEN, "grid preserved")
	check(m2.level(0)["terrain"]["0,0"]["t"] == "woodland:grass", "terrain preserved")
	check(m2.level(0)["props"][0]["pos"][0] == 1.25, "prop position preserved")
	check(m2.to_json() == text, "stable serialisation")
	var bad := HexMap.from_json("{\"format\": \"nope\"}", err)
	check(bad == null, "rejects foreign documents")


## A 4×4 PNG of one colour, for backdrops in tests.
static func _png(color: Color, w := 4, h := 4) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


func test_backdrop_and_local_assets() -> void:
	var m := HexMap.create("Backed", HexGrid.square(6, 4))
	check(m.assets_dir() == "" and m.asset_texture("local:x.png") == null, "an unsaved map has nowhere for assets yet and nothing to show")
	m.add_asset("floor.png", _png(Color.RED, 12, 8))
	m.level(0)["backdrop"] = {"image": "local:floor.png", "pos": [0, 0], "size": [6, 4], "opacity": 1.0, "hidden": false}
	check(m.asset_refs() == ["floor.png"] and m.asset_size("local:floor.png") == Vector2i(12, 8), "the reference and the image's size")
	check(m.asset_texture("local:floor.png") != null and m.asset_texture("local:floor.png") == m.asset_texture("local:floor.png"), "a texture from the bytes, cached")
	check(not m.to_json().contains("iVBOR"), "the document never embeds the image")
	# a plain file: assets beside it in <stem>.assets/
	var dir := ProjectSettings.globalize_path("user://backdrop_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var plain := dir.path_join("backed.hexmap")
	check(m.save(plain) == OK and FileAccess.file_exists(dir.path_join("backed.assets/floor.png")), "saved: the image landed in backed.assets/")
	var back := HexMap.load_file(plain)
	check(back != null and back.assets.is_empty() and back.asset_bytes("floor.png").size() > 0 and back.asset_texture("local:floor.png") != null, "loaded back: the asset is read from disk on first use")
	check(back.level(0).backdrop.image == "local:floor.png" and back.to_json() == m.to_json(), "the backdrop record round-trips")
	check(back.asset_bytes("../secret").is_empty() and back.asset_bytes("nope.png").is_empty(), "no escaping the assets dir; a missing asset is empty")
	# a bundle directory: name.hexmap/map.json with assets/ inside
	var bundle := dir.path_join("bundle.hexmap")
	DirAccess.make_dir_recursive_absolute(bundle)
	check(m.save(bundle) == OK and FileAccess.file_exists(bundle.path_join("map.json")) and FileAccess.file_exists(bundle.path_join("assets/floor.png")), "a bundle directory holds map.json and assets/")
	var b2 := HexMap.load_file(bundle)
	check(b2 != null and b2.assets_dir() == bundle.path_join("assets") and b2.asset_texture("local:floor.png") != null, "and loads from the directory")
	b2.remove_asset("floor.png")
	check(not FileAccess.file_exists(bundle.path_join("assets/floor.png")) and b2.asset_texture("local:floor.png") == null, "removing an asset deletes the file")
	# bad image bytes are not a texture
	m.add_asset("junk.jpg", "not a jpeg".to_utf8_buffer())
	check(m.asset_texture("local:junk.jpg") == null, "unreadable bytes give no texture")
	# the canvas draws the backdrop under the terrain, at its place, and skips a hidden one
	var canvas := MapCanvas.new()
	canvas.packs = PackLibrary.new()
	canvas.map = back
	root.add_child(canvas)
	canvas.refresh()
	await tree.process_frame
	check(canvas._backdrop != null and canvas.get_child(0) == canvas._backdrop, "the backdrop layer is the lowest")
	canvas.queue_free()
	await tree.process_frame


func test_history() -> void:
	var h := History.new()
	var v := [0]
	h.commit("set 1", func(): v[0] = 1, func(): v[0] = 0)
	h.commit("set 2", func(): v[0] = 2, func(): v[0] = 1)
	check(v[0] == 2, "commits run redo")
	h.undo()
	check(v[0] == 1, "undo one")
	h.undo()
	check(v[0] == 0, "undo two")
	check(not h.can_undo(), "stack empty")
	h.redo()
	h.redo()
	check(v[0] == 2 and not h.can_redo(), "redo both")
	h.begin_group()
	h.commit("a", func(): v[0] = 10, func(): v[0] = 2)
	h.commit("b", func(): v[0] = 11, func(): v[0] = 10)
	h.end_group("stroke")
	check(v[0] == 11, "group applied")
	h.undo()
	check(v[0] == 2, "group undone as one step: %d" % v[0])


func test_editor_backdrop_import_and_fit() -> void:
	var app := App.new("user://test_prefs_backdrop.json")
	var win := EditorWindow.new()
	win.app = app
	root.add_child(win)
	await tree.process_frame
	var dir := ProjectSettings.globalize_path("user://backdrop_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := dir.path_join("battle.png")
	var f := FileAccess.open(img, FileAccess.WRITE)
	f.store_buffer(_png(Color.BLUE, 400, 300))
	f.close()
	var ctx := win.ctx
	win._set_map(HexMap.create("Squares", HexGrid.square(20, 14)))
	check(win.import_backdrop(dir.path_join("nope.png")) != "" and win.import_backdrop(ProjectSettings.globalize_path("res://project.godot")) != "", "a missing file and a non-image are refused")
	check(win.import_backdrop(img) == "", "an image imports")
	var b: Dictionary = ctx.level().get("backdrop", {})
	check(b.get("image") == "local:battle.png" and ctx.map.assets.has("battle.png"), "the file became a local asset and the level's backdrop")
	check(is_equal_approx(float(b.size[0]), float(ctx.map.grid.columns)) and b.pos == [0.0, 0.0], "fitted to the map's width by default: %s" % [b])
	check(ctx.history.undo_label() == "Import backdrop", "undoable")
	ctx.history.undo()
	check(not ctx.level().has("backdrop"), "undo takes the backdrop off (the asset stays with the map)")
	ctx.history.redo()
	# the fit dialog's arithmetic: 50 px per cell, origin at (10, 20), resize the map
	win._backdrop_dialog()
	await tree.process_frame
	var dlg: ConfirmationDialog = null
	for c in win.get_children():
		if c is ConfirmationDialog and (c as ConfirmationDialog).title == "Backdrop":
			dlg = c
	check(dlg != null, "the Backdrop dialog opened")
	var form: PropertyForm = _find_form(dlg)
	check(form != null and is_equal_approx(float(form.get_values().ppc), 20.0), "it shows the current pixels per cell (400 px / 20 columns): %s" % [form.get_values() if form != null else {}])
	form.set_values({"ppc": 50.0, "ox": 10.0, "oy": 20.0, "opacity": 0.8, "hidden": false, "resize": true})
	dlg.confirmed.emit()
	await tree.process_frame
	b = ctx.level().backdrop
	check(is_equal_approx(float(b.size[0]), 8.0) and is_equal_approx(float(b.size[1]), 6.0), "size in cells from pixels per cell: %s" % [b.size])
	check(is_equal_approx(float(b.pos[0]), -0.2) and is_equal_approx(float(b.pos[1]), -0.4) and is_equal_approx(float(b.opacity), 0.8), "the grid origin becomes a negative offset: %s" % [b.pos])
	check(ctx.map.grid.columns == 8 and ctx.map.grid.rows == 6, "the map was resized to cover the image (%d × %d)" % [ctx.map.grid.columns, ctx.map.grid.rows])
	check(ctx.history.undo_label() == "Backdrop", "one undo step for the fit and the resize")
	ctx.history.undo()
	check(ctx.map.grid.columns == 20 and is_equal_approx(float(ctx.level().backdrop.size[0]), 20.0), "undone together")
	# saving writes the asset beside the map; a fresh load draws from it
	var path := dir.path_join("fitted.hexmap")
	check(ctx.map.save(path) == OK and FileAccess.file_exists(dir.path_join("fitted.assets/battle.png")), "saved with its asset")
	ctx.commands.set_backdrop(ctx.level_index, null, "Remove backdrop")
	check(not ctx.level().has("backdrop") and ctx.history.undo_label() == "Remove backdrop", "removed, undoably")
	win.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_backdrop.json"))


func _find_form(node: Node) -> PropertyForm:
	if node is PropertyForm:
		return node
	for c in node.get_children():
		var r := _find_form(c)
		if r != null:
			return r
	return null


## A battle-map-like image: mottled ground with grid lines every `ppc`
## pixels, offset by (ox, oy).
static func _gridded(w: int, h: int, ppc: float, ox: float, oy: float, line := Color(0.1, 0.1, 0.1)) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in h:
		for x in w:
			var t := rng.randf_range(-0.08, 0.08)
			img.set_pixel(x, y, Color(0.45 + t, 0.5 + t, 0.35 + t))
	var x := ox
	while x < w:
		for y in h:
			img.set_pixel(int(x), y, line)
		x += ppc
	var y := oy
	while y < h:
		for x2 in w:
			img.set_pixel(x2, int(y), line)
		y += ppc
	return img


func test_grid_detection() -> void:
	var r := GridDetect.detect(_gridded(700, 500, 50.0, 12.0, 30.0))
	check(r.error == "" and absf(r.ppc - 50.0) < 0.6, "the cell size of a 50 px grid: %.2f (confidence %.2f)" % [r.ppc, r.confidence])
	check(absf(r.ox - 12.0) < 1.5 and absf(r.oy - 30.0) < 1.5, "and where its lines fall: %.1f, %.1f" % [r.ox, r.oy])
	check(r.confidence > 0.3, "with confidence")
	r = GridDetect.detect(_gridded(1800, 1200, 70.0, 3.0, 61.0))
	check(r.error == "" and absf(r.ppc - 70.0) < 1.5 and absf(r.ox - 3.0) < 3.0 and absf(r.oy - 61.0) < 3.0, "a large image is downscaled and scaled back: %.2f at %.1f, %.1f" % [r.ppc, r.ox, r.oy])
	r = GridDetect.detect(_gridded(400, 300, 25.0, 0.0, 0.0, Color(0.42, 0.47, 0.32)))
	check(r.confidence < 0.3 or absf(r.ppc - 25.0) < 1.0, "faint lines: either found or admitted unsure (%.2f, %.2f)" % [r.ppc, r.confidence])
	var flat := Image.create(300, 200, false, Image.FORMAT_RGBA8)
	flat.fill(Color.GRAY)
	r = GridDetect.detect(flat)
	check(r.error != "" or r.confidence < 0.15, "a gridless image has no grid: %s" % [r])
	check(GridDetect.detect(Image.create(4, 4, false, Image.FORMAT_RGBA8)).error != "", "too small says so")


func test_backdrop_fit_by_detection_and_two_corners() -> void:
	# the arithmetic: pixels → cells, and two corners → a fit
	var img_size := Vector2i(1000, 700)
	var bd := {"image": "local:x.png", "pos": [0, 0], "size": [20, 14], "opacity": 1.0, "hidden": false}
	var f := GridDetect.fit_from_pixels(img_size, bd, 50.0, 50.0, 12.0, 30.0)
	check(f.size == [20.0, 14.0] and is_equal_approx(float(f.pos[0]), -0.24) and is_equal_approx(float(f.pos[1]), -0.6), "50 px cells with lines through (12, 30): the image starts 0.24 × 0.6 cells up-left of the origin: %s" % [f])
	f = GridDetect.fit_from_pixels(img_size, bd, 50.0, 50.0, 262.0, 130.0)
	check(is_equal_approx(float(f.pos[0]), -0.24) and is_equal_approx(float(f.pos[1]), -0.6), "any corner of the same grid gives the same fit")
	check(GridDetect.to_image_px(bd, img_size, Vector2(10, 7)) == Vector2(500, 350) and GridDetect.current_ppc(bd, img_size) == Vector2(50, 50), "hex units ↔ image pixels on the current fit")
	# two corners 4 cells apart on an image whose real cells are 40 px, starting at pixel 20
	var a := Vector2(20.0 / 50.0, 20.0 / 50.0)          # image px (20, 20) under the current 50-px fit
	var b := Vector2(180.0 / 50.0, 180.0 / 50.0)        # image px (180, 180): 4 cells of 40
	f = GridDetect.fit_from_corners(img_size, bd, a, b, 4, 4)
	check(is_equal_approx(float(f.size[0]), 25.0) and is_equal_approx(float(f.size[1]), 17.5), "the span's 160 px over 4 cells makes 40 px cells: %s" % [f.size])
	check(is_equal_approx(float(f.pos[0]), -0.5) and is_equal_approx(float(f.pos[1]), -0.5), "and the first corner at pixel 20 puts the origin half a cell in: %s" % [f.pos])
	f = GridDetect.fit_from_corners(img_size, bd, b, a, 4, 0)
	check(is_equal_approx(float(f.size[0]), 25.0) and is_equal_approx(float(f.size[1]), 17.5), "dragging the other way, with square cells assumed, is the same fit")
	# the editor: detect from the dialog, then drag two corners with the tool
	var app := App.new("user://test_prefs_fit.json")
	var win := EditorWindow.new()
	win.app = app
	root.add_child(win)
	await tree.process_frame
	win._set_map(HexMap.create("Squares", HexGrid.square(20, 14)))
	var dir := ProjectSettings.globalize_path("user://backdrop_test")
	DirAccess.make_dir_recursive_absolute(dir)
	_gridded(1000, 700, 50.0, 12.0, 30.0).save_png(dir.path_join("gridded.png"))
	check(win.import_backdrop(dir.path_join("gridded.png")) == "", "a gridded image imports")
	var ctx := win.ctx
	win._backdrop_dialog()
	await tree.process_frame
	var dlg: ConfirmationDialog = null
	for c in win.get_children():
		if c is ConfirmationDialog and (c as ConfirmationDialog).title == "Backdrop":
			dlg = c
	var detect: Button = dlg.find_child("detect", true, false)
	check(detect != null, "the dialog has a Detect grid button")
	detect.pressed.emit()
	var form: PropertyForm = _find_form(dlg)
	var vals := form.get_values()
	check(absf(float(vals.ppc) - 50.0) < 0.6 and absf(float(vals.ox) - 12.0) < 1.5 and absf(float(vals.oy) - 30.0) < 1.5, "Detect filled the fields from the image: %s" % [vals])
	vals.resize = true
	form.set_values(vals)
	dlg.confirmed.emit()
	await tree.process_frame
	var b2: Dictionary = ctx.level().backdrop
	check(absf(float(b2.size[0]) - 20.0) < 0.3 and ctx.map.grid.columns == 20 and ctx.map.grid.rows == 14, "applied: 20 × 14 cells over the image (%s, %d×%d)" % [b2.size, ctx.map.grid.columns, ctx.map.grid.rows])
	# drag two corners: the tool takes the canvas and hands back the span
	win._begin_fit_drag()
	check(win.view.tool is EditorTools.FitTool, "the fit tool is active")
	var tool := win.view.tool as EditorTools.FitTool
	var mods := {"shift": false, "ctrl": false, "alt": false}
	# on the current fit, image px (12, 30) is a corner; drag to (212, 230): 4 × 4 cells of 50
	var pa := Vector2(float(b2.pos[0]) + 12.0 / 50.0 * 1.0, float(b2.pos[1]) + 30.0 / 50.0)
	var pb := pa + Vector2(4, 4)
	tool.press(pa, MOUSE_BUTTON_LEFT, mods)
	tool.drag(pb, MOUSE_BUTTON_LEFT, mods)
	tool.release(pb, MOUSE_BUTTON_LEFT, mods)
	await tree.process_frame
	check(not (win.view.tool is EditorTools.FitTool), "after the drag the previous tool is back")
	var two: ConfirmationDialog = null
	for c in win.get_children():
		if c is ConfirmationDialog and (c as ConfirmationDialog).title == "Two corners":
			two = c
	check(two != null, "the Two corners dialog asks how many cells")
	var tf: PropertyForm = _find_form(two)
	check(int(tf.get_values().cols) == 4 and int(tf.get_values().rows) == 4, "guessing 4 × 4 from the current fit: %s" % [tf.get_values()])
	tf.set_values({"cols": 2, "rows": 2, "resize": false})   # the user says the span was two cells: cells are 100 px
	two.confirmed.emit()
	await tree.process_frame
	b2 = ctx.level().backdrop
	check(absf(float(b2.size[0]) - 10.0) < 0.05 and absf(float(b2.size[1]) - 7.0) < 0.05, "two cells over 200 px: 100 px cells, the image is 10 × 7 of them: %s" % [b2.size])
	check(absf(float(b2.pos[0]) + 0.12) < 0.01 and absf(float(b2.pos[1]) + 0.3) < 0.01, "lines through the dragged corner: %s" % [b2.pos])
	check(ctx.history.undo_label() == "Backdrop", "one undo step")
	# Esc cancels a drag
	win._begin_fit_drag()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	check((win.view.tool as EditorTools.FitTool).key(esc) and not (win.view.tool is EditorTools.FitTool), "Esc leaves the tool")
	win.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_fit.json"))
