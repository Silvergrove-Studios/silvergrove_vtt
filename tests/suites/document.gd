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
