extends SceneTree
## godot --headless -s tests/run_tests.gd — unit checks with no window.
## Each test_* method asserts with check(); the run fails if any check fails.

var _fails := 0
var _count := 0


func _init() -> void:
	for m in get_method_list():
		var n: String = m.name
		if n.begins_with("test_"):
			print("-- ", n)
			call(n)
	print("%d checks, %d failed" % [_count, _fails])
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	_count += 1
	if not cond:
		_fails += 1
		print("  FAIL: ", msg)


func near(a: float, b: float, eps := 1e-6) -> bool:
	return absf(a - b) <= eps


# ------------------------------------------------------------------- hex grid --

func test_axial_world_roundtrip() -> void:
	for orient in [HexGrid.Orient.POINTY, HexGrid.Orient.FLAT]:
		for off in [HexGrid.Offset.ODD, HexGrid.Offset.EVEN]:
			var g := HexGrid.new(orient, off, 12, 9)
			for cell in g.all_cells():
				var c := g.cell_center(cell)
				check(g.world_to_axial(c) == cell, "centre roundtrip %s %s %s" % [orient, off, cell])
				# A point near a corner still lands in the right cell.
				var corners := g.cell_corners(cell)
				for k in corners:
					var p: Vector2 = c.lerp(k, 0.9)
					check(g.world_to_axial(p) == cell, "near-corner roundtrip %s %s %s" % [orient, off, cell])


func test_offset_roundtrip() -> void:
	for orient in [HexGrid.Orient.POINTY, HexGrid.Orient.FLAT]:
		for off in [HexGrid.Offset.ODD, HexGrid.Offset.EVEN]:
			var g := HexGrid.new(orient, off, 7, 5)
			for row in g.rows:
				for col in g.columns:
					var a := g.offset_to_axial(col, row)
					check(g.axial_to_offset(a) == Vector2i(col, row), "offset roundtrip %s %s (%d,%d)" % [orient, off, col, row])
					check(g.in_bounds(a), "in bounds")
			check(not g.in_bounds(g.offset_to_axial(-1, 0)), "out of bounds left")
			check(not g.in_bounds(g.offset_to_axial(g.columns, 0)), "out of bounds right")


func test_layout_matches_foundry_convention() -> void:
	# Pointy, odd: cell (0,0) bounding box at origin; row 1 is shifted right.
	var g := HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 4, 4)
	var c00 := g.cell_center(g.offset_to_axial(0, 0))
	check(near(c00.x, 0.5) and near(c00.y, HexGrid.R), "pointy origin cell centre %s" % c00)
	var c01 := g.cell_center(g.offset_to_axial(0, 1))
	check(near(c01.x, 1.0), "odd row shifted right: %s" % c01)
	check(near(c01.y, HexGrid.R * 2.5), "row pitch is 1.5R: %s" % c01)
	var s := g.map_size()
	check(near(s.x, 4.5) and near(s.y, 2.0 * HexGrid.R + 3 * 1.5 * HexGrid.R), "pointy map size %s" % s)
	check(g.foundry_grid_type() == 2, "HEXODDR")
	# Flat, even: column 0 is shifted down.
	var f := HexGrid.new(HexGrid.Orient.FLAT, HexGrid.Offset.EVEN, 4, 4)
	var f00 := f.cell_center(f.offset_to_axial(0, 0))
	check(near(f00.x, HexGrid.R) and near(f00.y, 1.0), "flat/even origin cell shifted down %s" % f00)
	var f10 := f.cell_center(f.offset_to_axial(1, 0))
	check(near(f10.y, 0.5), "flat/even column 1 not shifted %s" % f10)
	check(f.foundry_grid_type() == 5, "HEXEVENQ")


func test_corners_are_unit_hex() -> void:
	var g := HexGrid.new()
	var pts := g.cell_corners(Vector2i.ZERO)
	check(pts.size() == 6, "six corners")
	var c := g.cell_center(Vector2i.ZERO)
	for p in pts:
		check(near(p.distance_to(c), HexGrid.R), "corner at circumradius")
	# Flat-to-flat width is exactly 1.
	var xs := []
	for p in pts:
		xs.append(p.x)
	xs.sort()
	check(near(xs[-1] - xs[0], 1.0), "flat-to-flat width 1 (pointy)")


func test_distance_and_line() -> void:
	check(HexGrid.axial_distance(Vector2i(0, 0), Vector2i(3, -1)) == 3, "distance")
	var l := HexGrid.line(Vector2i(0, 0), Vector2i(3, -1))
	check(l.size() == 4 and l[0] == Vector2i(0, 0) and l[-1] == Vector2i(3, -1), "line endpoints %s" % [l])
	check(HexGrid.spiral(Vector2i.ZERO, 1).size() == 7, "radius-1 spiral has 7 cells")
	check(HexGrid.spiral(Vector2i.ZERO, 2).size() == 19, "radius-2 spiral has 19 cells")


func test_snap_to_corner() -> void:
	var g := HexGrid.new()
	var corner := g.cell_corners(Vector2i(2, 1))[3]
	var snapped := g.snap_to_corner(corner + Vector2(0.03, -0.02))
	check(snapped.distance_to(corner) < 1e-6, "snaps to nearest corner")


# ------------------------------------------------------------------- document --

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


# ----------------------------------------------------------------------- pdf --

## Bytes as a same-length string, binary replaced by '.', so offsets line up.
static func _printable(b: PackedByteArray) -> String:
	var chars := PackedByteArray()
	chars.resize(b.size())
	for i in b.size():
		var c := b[i]
		chars[i] = c if (c >= 32 and c < 127) or c == 10 else 46
	return chars.get_string_from_ascii()


func test_pdf_writer_structure() -> void:
	var pdf := PdfWriter.new()
	pdf.title = "Test (map)"
	var p := pdf.add_page(612, 792)
	pdf.set_line(p, 2.0, Color.BLACK)
	pdf.polyline(p, PackedVector2Array([Vector2(72, 72), Vector2(200, 72), Vector2(200, 200)]), true)
	pdf.fill_rect(p, Rect2(300, 300, 100, 50), Color.RED)
	pdf.text(p, "Hello (world) \\ done", Vector2(72, 400), 12, Color.BLACK)
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.8, 0.5))
	var name := pdf.add_image(img)
	pdf.image(p, name, Rect2(72, 500, 160, 80))
	var jn := pdf.add_image(img, 0.9)
	pdf.image(p, jn, Rect2(300, 500, 160, 80))
	pdf.add_page(842, 595)
	var bytes := pdf.to_bytes()
	var s := _printable(bytes)
	check(s.begins_with("%PDF-1.5"), "header")
	check(s.ends_with("%%EOF\n"), "trailer end")
	check(s.contains("/Type /Catalog"), "catalog")
	check(s.contains("/Count 2"), "two pages")
	check(s.contains("/SMask"), "alpha became a soft mask")
	check(s.contains("/DCTDecode"), "jpeg image")
	check(s.contains("/FlateDecode"), "flate streams")
	# xref offsets must point at "N 0 obj".
	var xref_at := int(s.substr(s.rfind("startxref") + 10).strip_edges().split("\n")[0])
	check(s.substr(xref_at, 4) == "xref", "startxref points at xref table")
	var lines := s.substr(xref_at).split("\n")
	var count := int(lines[1].split(" ")[1])
	for i in range(1, count):
		var off := int(lines[2 + i].substr(0, 10))
		check(s.substr(off).begins_with("%d 0 obj" % i), "xref entry %d points at object" % i)
	# Deflate output is zlib-wrapped (FlateDecode needs the 0x78 header).
	var z := "hello hello hello".to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	check(z.size() > 0 and z[0] == 0x78, "COMPRESSION_DEFLATE is zlib format")
	check(PdfWriter.n(12.0) == "12" and PdfWriter.n(0.125) == "0.125" and PdfWriter.n(-2.5) == "-2.5", "number formatting")
	# Write it out so an external validator (pdfinfo / gs) can be run by hand or CI.
	var out := ProjectSettings.globalize_path("res://out")
	DirAccess.make_dir_recursive_absolute(out)
	check(pdf.save(out.path_join("test_writer.pdf")) == OK, "saved")


# ----------------------------------------------------------------- exporters --

func _sample_map() -> HexMap:
	var m := HexMap.create("Sample", HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 6, 4))
	var lvl := m.level(0)
	lvl["terrain"]["0,0"] = {"t": "woodland:grass", "v": 0, "rot": 0, "z": 0}
	lvl["terrain"]["1,0"] = {"t": "woodland:grass", "v": 1, "rot": 2, "z": 0}
	lvl["terrain"]["0,1"] = {"t": "swamp:mud", "v": 0, "rot": 0, "z": 0}
	lvl["props"].append({"id": "p_1", "asset": "woodland:oak_large", "pos": [1.5, 1.2], "rot": 0.0, "scale": 1.0, "hidden": false})
	lvl["walls"].append({"id": "w_1", "points": [[0.0, 0.0], [2.0, 0.0], [2.0, 1.0]],
		"blocks": {"move": true, "sight": true, "light": true, "sound": true}, "sight_mode": "normal",
		"door": "none", "state": "closed", "one_way": null, "z": [0, 1]})
	lvl["walls"].append({"id": "w_door", "points": [[2.0, 1.0], [3.0, 1.0]],
		"blocks": {"move": true, "sight": true, "light": true, "sound": true}, "sight_mode": "normal",
		"door": "door", "state": "open", "one_way": null})
	lvl["walls"].append({"id": "w_fence", "points": [[0.0, 2.0], [1.0, 2.0]],
		"blocks": {"move": true, "sight": false, "light": false, "sound": false}, "sight_mode": "normal",
		"door": "none", "state": "closed", "one_way": "left"})
	lvl["walls"].append({"id": "w_terrain", "points": [[3.0, 2.0], [4.0, 2.0]],
		"blocks": {"move": false, "sight": true, "light": true, "sound": false}, "sight_mode": "limited",
		"door": "none", "state": "closed", "one_way": null})
	lvl["lights"].append({"id": "l_1", "pos": [2.5, 1.5], "z": 0.5, "bright": 1.0, "dim": 2.0, "color": "#ffb060",
		"intensity": 1.0, "angle": 360, "direction": 0, "shadows": true, "animation": "torch", "hidden": false})
	lvl["notes"].append({"id": "n_1", "pos": [1.0, 1.0], "title": "Altar", "text": "Trapped.", "gm_only": true})
	return m


func test_uvtt_export() -> void:
	var m := _sample_map()
	var d := UvttExport.build(m, 0, 200, "PNG".to_utf8_buffer())
	check(d.format == 0.3, "format version")
	check(d.resolution.pixels_per_grid == 200, "ppg")
	check(d.resolution.map_size.x == 7 and d.resolution.map_size.y == 4, "map size rounds up: %s" % [d.resolution.map_size])
	check(d.line_of_sight.size() == 2, "wall + terrain wall exported, fence dropped: %d" % d.line_of_sight.size())
	check(d.line_of_sight[0].size() == 3, "polyline kept whole")
	check(d.portals.size() == 1 and d.portals[0].closed == false, "open door became an open portal")
	check(d.lights.size() == 1 and d.lights[0].range == 2.0 and d.lights[0].color == "ffffb060", "light range/colour %s" % [d.lights[0]])
	check(d.image == "UE5H", "image base64")
	var text := UvttExport.to_json(m, 0, 200, PackedByteArray())
	check(JSON.parse_string(text) != null, "valid json")


func test_foundry_export() -> void:
	var m := _sample_map()
	var s := FoundryExport.build(m, 0, 100, "sample.webp")
	check(s.grid.type == 2 and s.grid.size == 100 and s.grid.distance == 5.0 and s.grid.units == "ft", "grid %s" % [s.grid])
	check(s.padding == 0, "no padding")
	check(s.width == 650 and s.height == ceili((2 * HexGrid.R + 3 * 1.5 * HexGrid.R) * 100), "pixel size %d x %d" % [s.width, s.height])
	check(s.walls.size() == 2 + 1 + 1 + 1, "segments: %d" % s.walls.size())
	var first: Dictionary = s.walls[0]
	check(first.c == [0, 0, 200, 0] and first.sight == 20 and first.move == 20 and first.door == 0, "plain wall %s" % [first])
	check(first._id.length() == 16, "16-char id")
	check(first.flags.has("wall-height") and first.flags["wall-height"].top == 5.0, "wall height in feet")
	var door: Dictionary = s.walls[2]
	check(door.door == 1 and door.ds == 1, "open door")
	var fence: Dictionary = s.walls[3]
	check(fence.sight == 0 and fence.light == 0 and fence.move == 20 and fence.dir == 1, "fence: move only, one-way left %s" % [fence])
	var terrain: Dictionary = s.walls[4]
	check(terrain.sight == 10 and terrain.move == 0, "terrain wall limited sight, no move block")
	var l: Dictionary = s.lights[0]
	check(l.x == 250 and l.config.bright == 5.0 and l.config.dim == 10.0 and l.config.animation.type == "torch" and l.elevation == 2.5, "light %s" % [l])
	check(s.flags.hexmap.notes.size() == 1, "notes stashed in flags")
	m.grid.orientation = HexGrid.Orient.FLAT
	m.grid.offset = HexGrid.Offset.EVEN
	check(FoundryExport.build(m, 0, 100, "x").grid.type == 5, "HEXEVENQ")


func test_tiled_export() -> void:
	var m := _sample_map()
	var b := TiledExport.build(m, 0, 100)
	var t: Dictionary = b.map
	check(t.orientation == "hexagonal" and t.staggeraxis == "y" and t.staggerindex == "odd", "hex stagger %s %s" % [t.staggeraxis, t.staggerindex])
	check(t.tilewidth == 100 and t.tileheight == 115 and t.hexsidelength == 58, "tile dims %d %d %d" % [t.tilewidth, t.tileheight, t.hexsidelength])
	var layer: Dictionary = t.layers[0]
	check(layer.data.size() == 24, "one gid per cell")
	check(layer.data[0] == 1 and layer.data[1] == 2 and layer.data[6] == 3, "gids assigned in first-use order: %s" % [layer.data.slice(0, 8)])
	check(b.tiles.size() == 3 and b.tiles[2].ref == "swamp:mud", "three distinct tiles")
	check(t.tilesets[0].tiles[0].image == "tiles/woodland_grass_0.png", "tile image path")
	check(t.layers[1].objects.size() == 1 and t.layers[1].objects[0].type == "prop", "prop object")
	check(t.layers[2].objects.size() == 4 and t.layers[2].objects[0].polyline.size() == 3, "wall polylines")
	check(t.layers[3].objects[0].ellipse == true and t.layers[3].objects[0].width == 400.0, "light as ellipse of dim radius")
	var flat := _sample_map()
	flat.grid.orientation = HexGrid.Orient.FLAT
	var tf: Dictionary = TiledExport.build(flat, 0, 100).map
	check(tf.staggeraxis == "x" and tf.tilewidth == 115 and tf.tileheight == 100, "flat-top tile dims")


func test_pdf_layout() -> void:
	# 24 x 16 pointy map at 1" hexes on letter, 0.5" margins, 0.25" overlap.
	var size := HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 24, 16).map_size()
	var lay := PdfExport.layout(size, {"paper": "letter", "hex_size_in": 1.0})
	check(lay.hex_pt == 72.0, "1 inch hexes")
	check(lay.printable.size == Vector2(612 - 72, 792 - 72), "printable area")
	# Map is 24.5" x 14.27"; step is 7.25" x 9.75" -> 4 x 2 sheets.
	check(lay.cols == 4 and lay.rows == 2, "sheet grid %d x %d" % [lay.cols, lay.rows])
	check(lay.pages.size() == 8, "eight pages")
	var last: Rect2 = lay.pages[-1].region_pt
	check(near(last.end.x, size.x * 72.0, 1e-3) and near(last.end.y, size.y * 72.0, 1e-3), "last page trimmed to map edge %s" % last)
	check(near(lay.pages[1].region_pt.position.x, (7.5 - 0.25) * 72.0), "second column starts one step over")
	# Fit mode is one page with hexes shrunk to fit.
	var fit := PdfExport.layout(size, {"mode": "fit", "paper": "a4", "landscape": true})
	check(fit.pages.size() == 1, "fit is one page")
	check(near(fit.hex_pt, (841.89 - 72.0) / size.x, 1e-3), "fit hex size limited by width: %f" % fit.hex_pt)
	# A small map fits on one sheet in tiled mode.
	var small := PdfExport.layout(Vector2(6.5, 5.0), {"hex_size_in": 1.0})
	check(small.pages.size() == 1 and small.pages[0].region_pt.size == Vector2(6.5 * 72, 5.0 * 72), "small map, one sheet")


func test_svg_overlay() -> void:
	var m := _sample_map()
	var svg := SvgExport.overlay(m, 0, 100.0)
	check(svg.begins_with("<svg") and svg.strip_edges().ends_with("</svg>"), "svg envelope")
	check(svg.count("<polygon") == 24, "one polygon per cell: %d" % svg.count("<polygon"))
	check(svg.count("<polyline") == 4, "walls")
	check(svg.contains('data-door="door"'), "door marked")
	check(svg.contains("Altar"), "note title")
	var probe := Image.new()
	check(probe.load_svg_from_string(svg) == OK and probe.get_width() == 650, "Godot's own SVG loader accepts it (%d px wide)" % probe.get_width())


# --------------------------------------------------------------- packs/tools --

func _ctx() -> EditorContext:
	var ctx := EditorContext.new()
	ctx.packs = PackLibrary.new()
	ctx.packs.reload()
	ctx.history = History.new()
	ctx.map = HexMap.create("T", HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 10, 8))
	ctx.commands = Commands.new(ctx.map, ctx.history)
	ctx.canvas = MapCanvas.new()
	ctx.canvas.map = ctx.map
	ctx.canvas.packs = ctx.packs
	ctx.canvas.ppx = 256.0
	return ctx


func test_pack_library() -> void:
	var lib := PackLibrary.new()
	lib.reload()
	check(lib.warnings.is_empty(), "no pack warnings: %s" % [lib.warnings])
	check(lib.pack_ids() == PackedStringArray(["dungeons_and_castles", "swamp", "woodland"]), "three example packs: %s" % [lib.pack_ids()])
	var grass := lib.terrain("woodland:grass")
	check(grass.get("id") == "grass" and grass.textures.size() == 3, "terrain lookup")
	check(lib.prop("dungeons_and_castles:end_table").size == [0.4, 0.4], "prop lookup")
	check(lib.prop("woodland:campfire").light.bright == 1.5, "prop carries a light")
	check(lib.wall_style("dungeons_and_castles:iron_bars").preset == "window", "wall style lookup")
	check(lib.light_preset("swamp:wisp").animation == "pulse", "light preset lookup")
	check(lib.terrain("nope:nothing").is_empty() and lib.prop("garbage").is_empty(), "unknown refs are empty")
	check(lib.all("props").size() == 15 + 13 + 25, "all props across packs: %d" % lib.all("props").size())
	var tex := lib.terrain_texture("woodland:grass", 1, 100)
	check(tex != null and tex.get_width() == 128 and tex.get_height() > tex.get_width(), "svg rasterised to the 128 bucket: %dx%d" % [tex.get_width(), tex.get_height()])
	check(lib.terrain_texture("woodland:grass", 1, 100) == tex, "texture cached")
	var big := lib.prop_texture("woodland:oak_large", 256)
	check(big.get_width() == 1024, "prop texture sized by footprint (2.2 hex × 256 → 1024 bucket): %d" % big.get_width())
	var missing := lib.terrain_texture("nope:x", 0, 64)
	check(missing != null, "missing texture gives a placeholder")
	# Every texture in every manifest exists and rasterises.
	var bad := 0
	for pid in lib.pack_ids():
		var p: Dictionary = lib.packs[pid]
		for t in p.terrains:
			for f in t.textures:
				if not FileAccess.file_exists(str(p._dir).path_join(f)):
					bad += 1
		for pr in p.props:
			if not FileAccess.file_exists(str(p._dir).path_join(pr.texture)):
				bad += 1
	check(bad == 0, "%d manifest textures missing on disk" % bad)


func test_commands_terrain_and_objects() -> void:
	var ctx := _ctx()
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(99, 99)]
	ctx.commands.set_terrain(0, cells, {"t": "woodland:grass", "v": 0, "rot": 0, "z": 0})
	var terrain: Dictionary = ctx.level().terrain
	check(terrain.size() == 2, "out-of-bounds cell ignored, two painted: %d" % terrain.size())
	ctx.history.undo()
	check(terrain.is_empty(), "undo clears paint")
	ctx.history.redo()
	check(terrain.size() == 2, "redo repaints")
	var prop := ctx.new_prop(Vector2(2.3, 1.7))
	ctx.prop_ref = "woodland:oak"
	prop = ctx.new_prop(Vector2(2.3, 1.7))
	ctx.commands.add_object(0, "props", prop)
	check(ctx.level().props.size() == 1, "prop added")
	check(ctx.map.doc.packs.has("woodland"), "pack usage recorded")
	ctx.commands.update_object(0, "props", prop.id, {"rot": 45.0, "scale": 1.5})
	check(ctx.level().props[0].rot == 45.0 and ctx.level().props[0].scale == 1.5, "update applied")
	ctx.history.undo()
	check(ctx.level().props[0].rot == 0.0 and ctx.level().props[0].scale == 1.0, "update undone")
	ctx.commands.move_objects(0, [{"collection": "props", "id": prop.id}], Vector2(0.5, -0.5))
	check(near(ctx.level().props[0].pos[0], 2.8) and near(ctx.level().props[0].pos[1], 1.2), "moved: %s" % [ctx.level().props[0].pos])
	ctx.commands.remove_object(0, "props", prop.id)
	check(ctx.level().props.is_empty(), "removed")
	ctx.history.undo()
	check(ctx.level().props.size() == 1 and ctx.level().props[0].id == prop.id, "remove undone restores same object")
	check(ctx.map.dirty, "map marked dirty")
	# Levels
	ctx.commands.add_level("Upper")
	check(ctx.map.levels.size() == 2 and ctx.map.level(1).id == "upper", "level added")
	ctx.commands.remove_level(1)
	check(ctx.map.levels.size() == 1, "level removed")
	ctx.commands.remove_level(0)
	check(ctx.map.levels.size() == 1, "last level cannot be removed")
	# Map settings
	ctx.commands.update_map({"grid": {"orientation": "flat", "offset": "even", "columns": 5, "rows": 5, "distance": 1, "units": "m"}})
	check(ctx.map.grid.orientation == HexGrid.Orient.FLAT and ctx.map.grid.columns == 5, "grid updated")
	ctx.history.undo()
	check(ctx.map.grid.orientation == HexGrid.Orient.POINTY and ctx.map.grid.columns == 10, "grid update undone")
	ctx.canvas.free()


func test_tools() -> void:
	var ctx := _ctx()
	var g := ctx.map.grid
	var mods := {"shift": false, "ctrl": false, "alt": false}
	# Terrain brush: a stroke is one undo step and paints the line between samples.
	ctx.terrain_ref = "woodland:grass"
	ctx.terrain_variant = 2
	var paint := EditorTools.make("terrain", ctx)
	paint.press(g.cell_center(g.offset_to_axial(1, 1)), MOUSE_BUTTON_LEFT, mods)
	paint.drag(g.cell_center(g.offset_to_axial(5, 1)), MOUSE_BUTTON_LEFT, mods)
	paint.release(g.cell_center(g.offset_to_axial(5, 1)), MOUSE_BUTTON_LEFT, mods)
	check(ctx.level().terrain.size() == 5, "stroke painted 5 cells: %d" % ctx.level().terrain.size())
	check(ctx.level().terrain.values()[0].v == 2, "fixed variant respected")
	ctx.history.undo()
	check(ctx.level().terrain.is_empty(), "stroke is one undo step")
	ctx.history.redo()
	# Right-drag erases.
	paint.press(g.cell_center(g.offset_to_axial(1, 1)), MOUSE_BUTTON_RIGHT, mods)
	paint.release(g.cell_center(g.offset_to_axial(1, 1)), MOUSE_BUTTON_RIGHT, mods)
	check(ctx.level().terrain.size() == 4, "right click erased one")
	# Fill: contiguous same-terrain region.
	ctx.terrain_ref = "swamp:mud"
	var fill := EditorTools.make("fill", ctx)
	fill.press(g.cell_center(g.offset_to_axial(3, 1)), MOUSE_BUTTON_LEFT, mods)
	var muds := 0
	for t in ctx.level().terrain.values():
		if t.t == "swamp:mud":
			muds += 1
	check(muds == 4, "fill replaced the 4 connected grass cells: %d" % muds)
	fill.press(g.cell_center(g.offset_to_axial(7, 5)), MOUSE_BUTTON_LEFT, mods)
	check(ctx.level().terrain.size() == 80, "fill on empty floods the rest of the map: %d" % ctx.level().terrain.size())
	# Prop with an attached light.
	ctx.prop_ref = "woodland:campfire"
	ctx.snap = EditorContext.Snap.CENTER
	var prop_tool := EditorTools.make("prop", ctx)
	prop_tool.press(g.cell_center(Vector2i(3, 2)) + Vector2(0.1, 0.1), MOUSE_BUTTON_LEFT, mods)
	check(ctx.level().props.size() == 1 and ctx.level().lights.size() == 1, "campfire placed with its light")
	check(Vector2(ctx.level().props[0].pos[0], ctx.level().props[0].pos[1]).distance_to(g.cell_center(Vector2i(3, 2))) < 1e-3, "snapped to hex centre")
	ctx.history.undo()
	check(ctx.level().props.is_empty() and ctx.level().lights.is_empty(), "prop + light undo together")
	ctx.history.redo()
	# Free placement with shift (a boulder: no light attached).
	ctx.prop_ref = "woodland:boulder"
	prop_tool.press(Vector2(1.234, 1.567), MOUSE_BUTTON_LEFT, {"shift": true, "ctrl": false, "alt": false})
	check(near(ctx.level().props[1].pos[0], 1.234, 1e-4) and near(ctx.level().props[1].pos[1], 1.567, 1e-4), "shift = no snap: %s" % [ctx.level().props[1].pos])
	# Wall: snapped to corners, finished with Enter.
	ctx.wall_preset = "wall"
	var wall_tool := EditorTools.make("wall", ctx)
	var c0 := g.cell_corners(Vector2i(4, 4))[0]
	var c1 := g.cell_corners(Vector2i(4, 4))[1]
	wall_tool.press(c0 + Vector2(0.05, -0.04), MOUSE_BUTTON_LEFT, mods)
	wall_tool.press(c1 + Vector2(-0.03, 0.02), MOUSE_BUTTON_LEFT, mods)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	wall_tool.key(enter)
	check(ctx.level().walls.size() == 1, "wall created")
	var w: Dictionary = ctx.level().walls[0]
	check(Vector2(w.points[0][0], w.points[0][1]).distance_to(c0) < 1e-3 and Vector2(w.points[1][0], w.points[1][1]).distance_to(c1) < 1e-3, "wall points snapped to corners")
	check(w.blocks.move and w.blocks.sight and w.door == "none", "wall preset semantics")
	# Door preset finishes itself after two clicks.
	ctx.wall_preset = "door"
	var door_tool := EditorTools.make("wall", ctx)
	door_tool.press(c0, MOUSE_BUTTON_LEFT, mods)
	door_tool.press(c1, MOUSE_BUTTON_LEFT, mods)
	check(ctx.level().walls.size() == 2 and ctx.level().walls[1].door == "door", "door made from two clicks")
	# Select: picks the boulder (the campfire has its light on top, and lights
	# win the pick), nudges by one authored pixel, deletes.
	var sel := EditorTools.make("select", ctx)
	var campfire: Dictionary = ctx.level().props[1]
	var cpos := Vector2(campfire.pos[0], campfire.pos[1])
	sel.press(cpos, MOUSE_BUTTON_LEFT, mods)
	sel.release(cpos, MOUSE_BUTTON_LEFT, mods)
	check(ctx.selection.size() == 1 and ctx.selection[0].id == campfire.id, "select picked the campfire: %s" % [ctx.selection])
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	sel.key(right)
	check(near(float(ctx.level().props[1].pos[0]), cpos.x + 1.0 / 256.0, 1e-5), "nudged one authored pixel: %s" % [ctx.level().props[1].pos])
	var del := InputEventKey.new()
	del.keycode = KEY_DELETE
	sel.key(del)
	check(ctx.level().props.size() == 1 and ctx.selection.is_empty(), "deleted selection")
	# Erase tool on a wall segment.
	var erase := EditorTools.make("erase", ctx)
	erase.press((c0 + c1) / 2.0, MOUSE_BUTTON_LEFT, mods)
	check(ctx.level().walls.size() == 1, "erase removed a wall by clicking its segment")
	# Light and note tools.
	ctx.light_preset = ctx.packs.light_preset("dungeons_and_castles:torch")
	EditorTools.make("light", ctx).press(Vector2(2, 2), MOUSE_BUTTON_LEFT, mods)
	check(ctx.level().lights.size() == 2 and ctx.level().lights[1].bright == 1.0 and ctx.level().lights[1].animation == "torch", "light from preset")
	EditorTools.make("note", ctx).press(Vector2(2, 3), MOUSE_BUTTON_LEFT, mods)
	check(ctx.level().notes.size() == 1 and ctx.selection[0].collection == "notes", "note placed and selected")
	ctx.canvas.free()
