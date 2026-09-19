extends SceneTree
## godot --headless -s tests/run_tests.gd — unit checks with no window.
## Each test_* method asserts with check(); the run fails if any check fails.

var _fails := 0
var _count := 0


var _ran := false

## Tests run on the first frame, not from _init(): by then the root Window
## is inside the tree, so Controls added under it get _ready() and paths.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	for m in get_method_list():
		var n: String = m.name
		if n.begins_with("test_"):
			print("-- ", n)
			call(n)
	print("%d checks, %d failed" % [_count, _fails])
	quit(1 if _fails > 0 else 0)
	return true


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
	# Elements on hidden layers are left out of every export.
	var lvl := m.level(0)
	LayerTree.ensure(lvl)
	LayerTree.find(lvl.tree, "f_lights").visible = false
	check(FoundryExport.build(m, 0, 100, "x").lights.is_empty(), "hidden layer: no Foundry lights")
	check(UvttExport.build(m, 0, 100, PackedByteArray()).lights.is_empty(), "hidden layer: no UVTT lights")
	check(TiledExport.build(m, 0, 100).map.layers[3].objects.is_empty(), "hidden layer: no Tiled lights")
	check(SvgExport.overlay(m, 0, 100.0).contains('<g id="lights" fill="none" stroke-dasharray="4 4">\n</g>'), "hidden layer: no SVG lights")
	LayerTree.find(lvl.tree, "f_lights").visible = true


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


# ------------------------------------------------------------ layers/lighting --

func test_layer_tree() -> void:
	var lvl := HexMap.new_level("l", "L")
	lvl.props.append({"id": "p_a", "asset": "x", "pos": [0, 0], "layer": "overhead"})
	lvl.props.append({"id": "p_b", "asset": "x", "pos": [0, 0]})
	lvl.walls.append({"id": "w_a", "points": [[0, 0], [1, 0]]})
	lvl.lights.append({"id": "l_a", "pos": [0, 0]})
	lvl.erase("tree")
	LayerTree.ensure(lvl)
	var tree: Array = lvl.tree
	check(tree.size() == 6, "default folders created: %d" % tree.size())
	check(LayerTree.find(tree, "f_overhead").children.size() == 1 and LayerTree.find(tree, "f_overhead").children[0].ref == "props:p_a", "legacy layer field filed into Overhead")
	check(not lvl.props[0].has("layer"), "legacy field removed")
	check(LayerTree.find(tree, "f_props").children[0].ref == "props:p_b", "prop without layer goes to Props")
	check(LayerTree.find(tree, "f_walls").children[0].ref == "walls:w_a", "wall filed")
	var order := LayerTree.order(tree)
	check(order["props:p_b"] < order["props:p_a"], "Props folder draws under Overhead")
	# Dangling leaf and a missing element are reconciled.
	tree[0].children.append({"ref": "props:gone"})
	lvl.notes.append({"id": "n_a", "pos": [0, 0]})
	LayerTree.ensure(lvl)
	check(LayerTree.find(tree, "props:gone").is_empty(), "dangling leaf pruned")
	check(LayerTree.find(tree, "notes:n_a").ref == "notes:n_a", "new element got a leaf")
	# Move a prop into a new folder inside Props, without touching the prop.
	var f := LayerTree.new_folder("f_tables", "Tables")
	check(LayerTree.insert(tree, f, "f_props", 0), "folder inserted")
	var leaf := LayerTree.detach(tree, "props:p_a")
	check(LayerTree.insert(tree, leaf, "f_tables"), "leaf moved into folder")
	check(LayerTree.ancestors(tree, "props:p_a") == ["f_props", "f_tables"], "ancestors: %s" % [LayerTree.ancestors(tree, "props:p_a")])
	check(lvl.props[0].pos == [0, 0], "prop position untouched by move")
	check(not LayerTree.insert(tree, LayerTree.find(tree, "f_props"), "f_tables"), "cannot put a folder inside itself")
	# Visibility/lock inherit from folders.
	f.visible = false
	var vis := LayerTree.effective(tree, "visible")
	check(vis["props:p_a"] == false and vis["props:p_b"] == true, "folder hides its contents")
	LayerTree.find(tree, "f_props").locked = true
	var lock := LayerTree.effective(tree, "locked")
	check(lock["props:p_b"] == true and lock["walls:w_a"] == false, "locked inherited: %s" % [lock])
	check(LayerTree.refs_under(LayerTree.find(tree, "f_props")).size() == 2, "refs under folder")
	# Document upgrade path runs ensure on load.
	var m := HexMap.create("T", HexGrid.new())
	m.level(0).props.append({"id": "p_z", "asset": "x", "pos": [1, 1], "layer": "ground"})
	var m2 := HexMap.from_json(m.to_json())
	check(m2 != null and LayerTree.find(m2.level(0).tree, "f_ground").children.size() == 1, "load reconciles tree")


func test_lighting() -> void:
	var lvl := HexMap.new_level("l", "L")
	lvl.walls.append({"id": "w1", "points": [[2, -1], [2, 1]], "blocks": {"move": true, "sight": true, "light": true, "sound": true}, "door": "none", "state": "closed"})
	lvl.walls.append({"id": "w2", "points": [[-2, -1], [-2, 1]], "blocks": {"move": true, "sight": false, "light": false, "sound": false}})   # fence
	lvl.walls.append({"id": "w3", "points": [[0, 2], [1, 2]], "door": "door", "state": "open", "blocks": {"light": true}})
	var segs := Lighting.blocking_segments(lvl)
	check(segs.size() == 1, "only the light-blocking, closed things block: %d" % segs.size())
	var o := Vector2.ZERO
	check(Lighting.is_lit(o, 5.0, Vector2(1.5, 0), segs), "in front of the wall is lit")
	check(not Lighting.is_lit(o, 5.0, Vector2(3.0, 0), segs), "behind the wall is dark")
	check(Lighting.is_lit(o, 5.0, Vector2(3.0, 3.0), segs), "past the wall's end is lit")
	check(Lighting.is_lit(o, 5.0, Vector2(-3.0, 0), segs), "fence does not block light")
	check(not Lighting.is_lit(o, 2.0, Vector2(0, 2.5), segs), "outside radius is dark")
	var poly := Lighting.visibility_polygon(o, 3.0, segs)
	check(poly.size() >= 48, "polygon has ring rays plus endpoint rays: %d" % poly.size())
	var max_d := 0.0
	var shadowed := false
	for p in poly:
		max_d = maxf(max_d, p.length())
		if absf(p.y) < 0.5 and p.x > 1.9 and p.x < 2.1:
			shadowed = true
	check(max_d <= 3.0 + 1e-4, "polygon within radius")
	check(shadowed, "polygon hugs the wall")
	var monotonic := true
	for i in poly.size() - 1:
		var a0 := (poly[i] - o).angle()
		var a1 := (poly[i + 1] - o).angle()
		if a1 < a0 - 1e-4 and not (absf(absf(a0) - PI) < 1e-3 or absf(absf(a1) - PI) < 1e-3):
			monotonic = false
	check(monotonic, "polygon points are in angular order")
	var cone := Lighting.visibility_polygon(o, 3.0, segs, 48, 90.0, 0.0)
	check(cone[0] == o, "cone polygon starts at the origin")
	var in_cone := true
	for i in range(1, cone.size()):
		if absf((cone[i] - o).angle()) > deg_to_rad(45.0) + 1e-3:
			in_cone = false
	check(in_cone, "cone polygon stays within its angle")
	# One-way: blocks only from the right side.
	var one := [{"a": Vector2(0, -1), "b": Vector2(0, 1), "one_way": 2}]
	# a->b points +y, so the right-hand side is +x: a light at x=+1 strikes the right face.
	check(not Lighting.is_lit(Vector2(1, 0), 5.0, Vector2(-1, 0), one), "ray striking the right side is blocked")
	check(Lighting.is_lit(Vector2(-1, 0), 5.0, Vector2(1, 0), one), "ray striking the left side passes")
	var fan := Lighting.fan(o, 3.0, poly, 100.0)
	check(fan.vertices.size() == poly.size() * 3 and fan.uvs.size() == fan.vertices.size(), "fan triangles")
	check(fan.uvs[0] == Vector2(0.5, 0.5), "centre uv")


func test_tree_commands_and_picking() -> void:
	var ctx := _ctx()
	var lvl := ctx.level()
	var tree: Array = lvl.tree
	ctx.prop_ref = "woodland:boulder"
	var a := ctx.new_prop(Vector2(2, 2))
	var b := ctx.new_prop(Vector2(2, 2))
	var c := ctx.new_prop(Vector2(2, 2))
	ctx.commands.add_object(0, "props", a)
	ctx.commands.add_object(0, "props", b)
	ctx.commands.add_object(0, "props", c, "", "f_overhead")
	var ra := LayerTree.ref("props", a.id)
	var rb := LayerTree.ref("props", b.id)
	var rc := LayerTree.ref("props", c.id)
	check(LayerTree.ancestors(tree, ra) == ["f_props"] and LayerTree.ancestors(tree, rc) == ["f_overhead"], "leaves filed on add")
	ctx.history.undo()
	check(LayerTree.find(tree, rc).is_empty() and lvl.props.size() == 2, "undo add removes the leaf too")
	ctx.history.redo()
	# Draw order: c (Overhead) on top, then b, then a.
	ctx.canvas.refresh()
	var order := ctx.canvas.props_in_order()
	check(order[0].id == a.id and order[1].id == b.id and order[2].id == c.id, "draw order follows the tree")
	# Picking: topmost first; clicking again cycles down the stack.
	var sel := EditorTools.make("select", ctx)
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var all := sel.pick_all(Vector2(2, 2))
	check(all.size() == 3 and all[0].id == c.id and all[2].id == a.id, "pick_all lists top first: %s" % [all])
	sel.press(Vector2(2, 2), MOUSE_BUTTON_LEFT, mods)
	sel.release(Vector2(2, 2), MOUSE_BUTTON_LEFT, mods)
	check(ctx.selection[0].id == c.id, "first click picks the top")
	sel.press(Vector2(2, 2), MOUSE_BUTTON_LEFT, mods)
	sel.release(Vector2(2, 2), MOUSE_BUTTON_LEFT, mods)
	check(ctx.selection[0].id == b.id, "second click cycles to the next one down")
	# Locking hides from picking; hiding too.
	ctx.commands.tree_set(0, "f_overhead", {"locked": true})
	ctx.canvas.refresh()
	check(sel.pick_all(Vector2(2, 2)).size() == 2, "locked folder contents cannot be picked")
	ctx.commands.tree_set(0, rb, {"visible": false})
	ctx.canvas.refresh()
	check(sel.pick_all(Vector2(2, 2)).size() == 1 and ctx.canvas.props_in_order().size() == 2, "hidden leaf is neither picked nor drawn")
	ctx.history.undo()
	ctx.history.undo()
	ctx.canvas.refresh()
	# Move a into Overhead, on top of c: position untouched.
	var before: Array = a.pos.duplicate()
	ctx.commands.tree_move(0, ra, "f_overhead", -1)
	check(LayerTree.ancestors(tree, ra) == ["f_overhead"] and a.pos == before, "moved between folders without moving on canvas")
	ctx.canvas.refresh()
	check(ctx.canvas.props_in_order()[2].id == a.id, "now drawn on top")
	ctx.history.undo()
	check(LayerTree.ancestors(tree, ra) == ["f_props"], "move undone")
	# Folders: add, group, remove (unwrap).
	var f := ctx.commands.tree_add_folder(0, "Rocks", "f_props", 0)
	ctx.commands.tree_move_many(0, [ra, rb], f.id, -1)
	check(LayerTree.refs_under(f) == [ra, rb], "grouped in order: %s" % [LayerTree.refs_under(f)])
	check(not LayerTree.find(tree, "f_props").is_empty(), "parent folder still there")
	ctx.commands.tree_remove_folder(0, f.id)
	check(LayerTree.find(tree, f.id).is_empty() and LayerTree.ancestors(tree, ra) == ["f_props"], "folder unwrapped, children kept")
	ctx.history.undo()
	check(not LayerTree.find(tree, f.id).is_empty() and LayerTree.ancestors(tree, ra) == ["f_props", f.id], "unwrap undone")
	# Deleting an element and undoing restores its leaf in place.
	var idx_before: int = LayerTree.locate(tree, rb)[1]
	ctx.commands.remove_object(0, "props", b.id)
	check(LayerTree.find(tree, rb).is_empty(), "leaf gone with element")
	ctx.history.undo()
	check(LayerTree.locate(tree, rb)[1] == idx_before and LayerTree.ancestors(tree, rb) == ["f_props", f.id], "leaf restored at its old place")
	# Rename via update_object; saving keeps the tree consistent.
	ctx.commands.update_object(0, "props", a.id, {"name": "Big rock"})
	var m2 := HexMap.from_json(ctx.map.to_json())
	check(m2.level(0).props[0].name == "Big rock" and LayerTree.leaves(m2.level(0).tree).size() == 3, "round trip keeps names and leaves")
	ctx.canvas.free()


# ------------------------------------------------------------------------ ui --

## WCAG relative luminance contrast ratio.
static func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func test_theme_builder() -> void:
	var required := ["bg", "bg_deep", "canvas", "surface", "surface_hover", "surface_pressed", "border", "border_strong",
		"text", "text_dim", "text_disabled", "accent", "accent_text", "shadow", "radius", "spacing", "font_size", "icon", "stroke", "label", "dark"]
	for name in ThemeBuilder.names():
		var t := ThemeBuilder.tokens(name)
		for k in required:
			check(t.has(k), "%s has token %s" % [name, k])
		var th := ThemeBuilder.build(name)
		check(th != null and th.default_font != null and th.default_font_size == int(t.font_size), "%s builds with a default font" % name)
		for variation in ["ToolButton", "AccentButton", "HeaderLabel", "DimLabel", "MonoLabel"]:
			check(th.get_type_variation_base(variation) != "", "%s defines variation %s" % [name, variation])
		for kind in ["Button", "OptionButton", "LineEdit", "Tree", "ItemList", "TabContainer", "PopupMenu", "MenuBar", "HSlider", "Window"]:
			check(th.get_stylebox_list(kind).size() > 0, "%s styles %s" % [name, kind])
		# Readability: body text and hints against the panel, accent against the panel.
		var bg := ThemeBuilder.c(t, "bg")
		check(_contrast(ThemeBuilder.c(t, "text"), bg) >= 7.0, "%s text/bg contrast %.1f ≥ 7" % [name, _contrast(ThemeBuilder.c(t, "text"), bg)])
		check(_contrast(ThemeBuilder.c(t, "text_dim"), bg) >= 4.5, "%s dim text/bg contrast %.1f ≥ 4.5" % [name, _contrast(ThemeBuilder.c(t, "text_dim"), bg)])
		check(_contrast(ThemeBuilder.c(t, "text"), ThemeBuilder.c(t, "surface")) >= 4.5, "%s text on buttons" % name)
		check(_contrast(ThemeBuilder.c(t, "accent"), bg) >= 3.0, "%s accent/bg contrast %.1f ≥ 3" % [name, _contrast(ThemeBuilder.c(t, "accent"), bg)])
		check(_contrast(ThemeBuilder.c(t, "accent_text"), ThemeBuilder.c(t, "accent")) >= 4.5, "%s accent button text" % name)
		check(_contrast(ThemeBuilder.c(t, "text"), ThemeBuilder.c(t, "bg_deep")) >= 7.0, "%s text in inputs" % name)
	check(ThemeBuilder.tokens("nope") == ThemeBuilder.tokens("slate"), "unknown theme falls back to slate")
	for f in ["Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf", "JetBrainsMono-Regular.ttf"]:
		var font := ThemeBuilder.font(f)
		check(font != null and font != ThemeDB.fallback_font, "font %s loads" % f)


func test_ui_icons() -> void:
	# Every icon named anywhere in the editor code exists and rasterises.
	var named := {}
	var re := RegEx.new()
	re.compile('get_icon\\("([a-z0-9-]+)"|set_meta\\("icon", "([a-z0-9-]+)"\\)|_button\\("([a-z0-9-]+)"')
	for path in ["res://hexmap/editor/editor_window.gd", "res://hexmap/shell/home.gd", "res://hexmap/ui/theme_builder.gd", "res://hexmap/editor/layers_panel.gd", "res://hexmap/editor/palette.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			for g in [1, 2, 3]:
				if m.get_string(g) != "":
					named[m.get_string(g)] = true
	var main_src := FileAccess.get_file_as_string("res://hexmap/editor/editor_window.gd")
	var tools_re := RegEx.new()
	tools_re.compile('"[a-z]+": "([a-z0-9-]+)"')
	var start := main_src.find("TOOL_ICONS")
	for m in tools_re.search_all(main_src.substr(start, main_src.find("}", start) - start)):
		named[m.get_string(1)] = true
	for m in HomeScreen.MODE_ICONS:
		named[HomeScreen.MODE_ICONS[m]] = true
	check(named.size() >= 20, "found %d icon names in code" % named.size())
	var missing := []
	for n in named:
		if not FileAccess.file_exists(UiIcons.dir().path_join(n + ".svg")):
			missing.append(n)
	check(missing.is_empty(), "icons missing on disk: %s" % [missing])
	var tex := UiIcons.get_icon("eye", 20, Color.RED)
	check(tex.get_width() == 20 and tex.get_height() == 20, "icon rasterised at requested size")
	var img := tex.get_image()
	var red := 0
	for y in 20:
		for x in 20:
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.8 and c.g < 0.2:
				red += 1
	check(red > 20, "icon takes the requested colour (%d red px)" % red)
	check(UiIcons.get_icon("eye", 20, Color.RED) == tex, "icon cached")
	check(UiIcons.get_icon("no-such-icon", 16) != null, "missing icon gives a placeholder")


func test_layout_store() -> void:
	var d := LayoutStore.default_layout()
	var names := Array(LayoutStore.names(d))
	names.sort()
	var expected := LayoutStore.PANELS.duplicate()
	expected.sort()
	check(names == expected, "default layout names every panel once: %s" % [names])
	var path := "user://test_layout.tres"
	check(LayoutStore.save(d, path) == OK, "layout saves")
	var back := LayoutStore.load_or_default(path)
	var back_names := Array(LayoutStore.names(back))
	back_names.sort()
	check(back_names == expected, "layout round-trips: %s" % [back_names])
	check(back.root is DockableLayoutSplit and (back.root as DockableLayoutSplit).percent == 0.2, "split geometry preserved")
	check((back.root as DockableLayoutSplit).first is DockableLayoutSplit and ((back.root as DockableLayoutSplit).first as DockableLayoutSplit).direction == DockableLayoutSplit.Direction.VERTICAL, "nested vertical split preserved")
	# A saved layout from an older build lacks a panel: it is added back.
	var old := DockableLayout.new()
	var leaf := DockableLayoutPanel.new()
	leaf.names = PackedStringArray(["Palette", "Canvas"])
	old.root = leaf
	var repaired := LayoutStore.repair(old)
	var rn := Array(LayoutStore.names(repaired))
	rn.sort()
	check(rn == expected, "missing panels restored: %s" % [rn])
	check(LayoutStore.load_or_default("user://does_not_exist.tres").get_names().size() == LayoutStore.PANELS.size(), "no file → default")
	var f := FileAccess.open("user://broken.tres", FileAccess.WRITE)
	f.store_string("not a resource")
	f.close()
	check(LayoutStore.load_or_default("user://broken.tres").get_names().size() == LayoutStore.PANELS.size(), "unreadable file → default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://broken.tres"))


func test_native_menu_accelerators() -> void:
	var k := NativeMenuMirror._native_accel(KEY_S | KEY_MASK_CMD_OR_CTRL)
	check((k & KEY_MASK_CMD_OR_CTRL) == 0, "placeholder mask resolved")
	if OS.get_name() == "macOS":
		check((k & KEY_MASK_META) != 0 and (k & KEY_CODE_MASK) == KEY_S, "Cmd+S on macOS")
	else:
		check((k & KEY_MASK_CTRL) != 0 and (k & KEY_CODE_MASK) == KEY_S, "Ctrl+S elsewhere")
	check(NativeMenuMirror._native_accel(KEY_NONE) == KEY_NONE, "none stays none")
	check(NativeMenuMirror._native_accel(KEY_G) == KEY_G, "plain key untouched")


func test_dock_pane_drag() -> void:
	# A pane's title bar produces the drag data the DockableContainer accepts
	# from its own tabs, pointing at the panel that currently holds the pane.
	var dock := DockableContainer.new()
	dock.size = Vector2(800, 600)
	root.add_child(dock)
	var a := DockPane.new("Palette", Control.new())
	var b := DockPane.new("Canvas", Control.new())
	dock.add_child(a)
	dock.add_child(b)
	dock.layout = LayoutStore.default_layout()
	dock.notification(Container.NOTIFICATION_SORT_CHILDREN)
	check(a.dock() == dock, "pane finds its dock")
	var data = a.drag_data()
	check(data is Dictionary and data.get("type") == "tabc_element", "drag data has the tab type: %s" % [data])
	if data is Dictionary:
		var panel := root.get_node(data.from_path) as TabContainer
		check(panel != null, "from_path resolves to a panel")
		if panel != null:
			var tab := panel.get_tab_control(int(data.tabc_element))
			check(tab == a or (tab != null and tab.get("reference_to") == a), "tab index points at this pane")
		check(dock._can_drop_data(Vector2.ZERO, data), "dock accepts the drag")
	check(b.drag_data() != null and b.drag_data().from_path != data.from_path, "second pane is in a different panel")
	var stray := DockPane.new("Loose", Control.new())
	root.add_child(stray)
	check(stray.drag_data() == null, "a pane outside a dock has no drag data")
	stray.free()
	dock.free()


func test_select_gizmos() -> void:
	var ctx := _ctx()
	ctx.zoom = 1.0
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var shift := {"shift": true, "ctrl": false, "alt": false}
	ctx.prop_ref = "dungeons_and_castles:table"    # 1.4 x 0.8 hex, anchor centre
	var prop := ctx.new_prop(Vector2(4.0, 4.0))
	ctx.commands.add_object(0, "props", prop)
	ctx.select_one("props", prop.id)
	var sel := EditorTools.make("select", ctx) as EditorTools.SelectTool
	var hs := sel.handles()
	check(hs.has("tl") and hs.has("br") and hs.has("rotate"), "prop has corner and rotate handles: %s" % [hs.keys()])
	check(near(hs["tl"].x, 4.0 - 0.7, 1e-3) and near(hs["tl"].y, 4.0 - 0.4, 1e-3), "top-left corner at the unrotated bounds: %s" % hs["tl"])
	check(hs["rotate"].y < hs["tl"].y, "rotate handle sits above the top edge")
	check(sel.handle_at(hs["br"] + Vector2(0.01, 0.01)) == "br", "handle hit within tolerance")
	check(sel.handle_at(Vector2(4.0, 4.0)) == "", "no handle at the centre")
	# Scale: drag the bottom-right corner outward, doubling its distance.
	var br: Vector2 = hs["br"]
	sel.press(br, MOUSE_BUTTON_LEFT, mods)
	sel.drag(Vector2(4.0, 4.0) + (br - Vector2(4.0, 4.0)) * 2.0, MOUSE_BUTTON_LEFT, mods)
	sel.release(br, MOUSE_BUTTON_LEFT, mods)
	check(near(float(ctx.level().props[0].scale), 2.0, 1e-3), "corner drag doubled the scale: %s" % ctx.level().props[0].scale)
	check(ctx.level().props[0].pos == [4.0, 4.0], "scaling keeps the anchor put")
	ctx.history.undo()
	check(near(float(ctx.level().props[0].get("scale", 1.0)), 1.0), "scale undone in one step")
	# Rotate: drag the rotate handle a quarter turn clockwise; Shift snaps to 15°.
	hs = sel.handles()
	var rh: Vector2 = hs["rotate"]
	sel.press(rh, MOUSE_BUTTON_LEFT, mods)
	var a0 := (rh - Vector2(4.0, 4.0)).angle()
	var target := Vector2(4.0, 4.0) + Vector2(cos(a0 + PI / 2.0 + 0.05), sin(a0 + PI / 2.0 + 0.05)) * (rh - Vector2(4.0, 4.0)).length()
	sel.drag(target, MOUSE_BUTTON_LEFT, shift)
	sel.release(target, MOUSE_BUTTON_LEFT, shift)
	check(near(float(ctx.level().props[0].rot), 90.0, 1e-3), "rotate handle with Shift snapped to 90°: %s" % ctx.level().props[0].rot)
	hs = sel.handles()
	check(near(hs["rotate"].x, 4.0 + 0.4 + sel.handle_hex(28.0), 1e-3), "rotated gizmo follows the prop: rotate handle now on the right (%s)" % hs["rotate"])
	# Hover state drives the cursor.
	sel.move(Vector2(4.0, 4.0))
	check(sel.cursor() == Control.CURSOR_MOVE, "hovering the prop body: move cursor")
	sel.move(hs["rotate"])
	check(sel.cursor() == Control.CURSOR_POINTING_HAND, "hovering the rotate handle: hand cursor")
	sel.move(Vector2(0.5, 0.5))
	check(sel.cursor() == Control.CURSOR_ARROW, "hovering nothing: arrow")
	check(EditorTools.make("terrain", ctx).cursor() == Control.CURSOR_CROSS, "paint tool uses a crosshair")
	# Handles scale with zoom: zooming in shrinks them in hex units.
	ctx.zoom = 4.0
	check(near(sel.handle_hex(), 7.0 / (256.0 * 4.0)), "handle size is constant on screen")
	ctx.zoom = 1.0
	# Light radius handles.
	ctx.light_preset = {"bright": 1.0, "dim": 2.0, "color": "#ffffff"}
	var l := ctx.new_light(Vector2(6.0, 6.0))
	ctx.commands.add_object(0, "lights", l)
	ctx.select_one("lights", l.id)
	hs = sel.handles()
	check(hs.has("dim") and near(hs["dim"].x, 8.0) and hs.has("bright"), "light has ring handles: %s" % [hs])
	sel.press(hs["dim"], MOUSE_BUTTON_LEFT, mods)
	sel.drag(Vector2(9.0, 6.0), MOUSE_BUTTON_LEFT, mods)
	sel.release(Vector2(9.0, 6.0), MOUSE_BUTTON_LEFT, mods)
	check(near(float(ctx.level().lights[0].dim), 3.0), "dragging the dim ring sets dim = 3: %s" % ctx.level().lights[0].dim)
	hs = sel.handles()
	sel.press(hs["bright"], MOUSE_BUTTON_LEFT, mods)
	sel.drag(Vector2(6.0, 6.0) + Vector2(3.5, 0.0), MOUSE_BUTTON_LEFT, mods)
	sel.release(Vector2.ZERO, MOUSE_BUTTON_LEFT, mods)
	check(near(float(ctx.level().lights[0].bright), 3.5) and near(float(ctx.level().lights[0].dim), 3.5), "bright pushed past dim drags dim along")
	ctx.canvas.free()


func test_palette_model() -> void:
	var lib := PackLibrary.new()
	lib.reload()
	var props := lib.all("props")
	check(PaletteModel.matches(props[0], ""), "empty query matches everything")
	var torch := PaletteModel.count(props, "torch")
	check(torch >= 1, "search finds the torch sconce: %d" % torch)
	check(PaletteModel.count(props, "TORCH") == torch, "search is case-insensitive")
	check(PaletteModel.count(props, "dungeons tree") == 0 and PaletteModel.count(props, "woodland tree") >= 3, "all words must match (pack + tag): %d" % PaletteModel.count(props, "woodland tree"))
	check(PaletteModel.count(props, "swamp:mangrove") == 1, "search by ref")
	var names := {"woodland": "Woodland", "swamp": "Swamp", "dungeons_and_castles": "Dungeons & Castles"}
	var secs := PaletteModel.sections(props, "", ["woodland:oak"], ["swamp:mangrove", "woodland:oak"], names)
	check(secs[0].id == "favorites" and secs[0].items.size() == 1 and secs[0].items[0]._ref == "woodland:oak", "favourites first")
	check(secs[1].id == "recent" and secs[1].items.size() == 1 and secs[1].items[0]._ref == "swamp:mangrove", "recent skips favourites")
	check(secs.size() == 5 and secs[2].title == "Dungeons & Castles", "one section per pack, named: %s" % [secs.map(func(s): return s.title)])
	var filtered := PaletteModel.sections(props, "oak", ["woodland:oak"], [], names)
	check(filtered.size() == 2 and filtered[1].id == "pack:woodland" and filtered[1].items.size() == 2, "filter empties other packs: %s" % [filtered.map(func(s): return "%s:%d" % [s.id, s.items.size()])])
	var r := PaletteModel.push_recent([], "a")
	r = PaletteModel.push_recent(r, "b")
	r = PaletteModel.push_recent(r, "a")
	check(r == ["a", "b"], "recent is most-recent-first and deduplicated: %s" % [r])
	for i in 20:
		r = PaletteModel.push_recent(r, "x%d" % i)
	check(r.size() == PaletteModel.RECENT_MAX, "recent capped at %d" % PaletteModel.RECENT_MAX)
	check(PaletteModel.toggle(["a"], "a") == [] and PaletteModel.toggle([], "a") == ["a"], "toggle favourite")
	var st := PaletteModel.default_state()
	st.favorites.props = ["woodland:oak"]
	st.recent.terrain = ["woodland:grass"]
	st.collapsed["props/pack:swamp"] = true
	check(PaletteModel.save_state(st, "user://test_palette.json") == OK, "state saves")
	var back := PaletteModel.load_state("user://test_palette.json")
	check(back.favorites.props == ["woodland:oak"] and back.recent.terrain == ["woodland:grass"] and back.collapsed["props/pack:swamp"] == true, "state round-trips")
	var f := FileAccess.open("user://test_palette.json", FileAccess.WRITE)
	f.store_string("[1,2]")
	f.close()
	check(PaletteModel.load_state("user://test_palette.json").favorites.props == [], "garbage file → defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_palette.json"))


func test_tool_options() -> void:
	var ctx := _ctx()
	var opts := ToolOptions.new(ctx)
	root.add_child(opts)
	opts.show_for("prop")
	check(opts._controls.has("snap") and opts._controls.has("rot") and opts._controls.has("scale") and opts._controls.has("flip"), "prop tool options")
	(opts._controls.rot as SpinBox).value = 45.0
	check(near(ctx.prop_rotation, 45.0), "rotation spin writes to the context")
	ctx.prop_scale = 1.5
	opts.sync()
	check(near((opts._controls.scale as SpinBox).value, 1.5), "sync pulls context values back")
	(opts._controls.snap as OptionButton).item_selected.emit(2)
	check(ctx.snap == EditorContext.Snap.CORNER, "snap option writes to the context")
	opts.show_for("terrain")
	check(opts._controls.has("brush") and opts._controls.has("variant"), "terrain tool options")
	ctx.terrain_ref = "woodland:grass"
	opts.sync()
	check((opts._controls.variant as OptionButton).item_count == 4, "variant list follows the picked terrain (random + 3)")
	opts.show_for("wall")
	(opts._controls.type as OptionButton).item_selected.emit(1)
	check(ctx.wall_preset == "door", "wall type writes to the context: %s" % ctx.wall_preset)
	opts.show_for("light")
	(opts._controls.dim as SpinBox).value = 4.5
	check(ctx.light_preset.dim == 4.5, "light dim writes to the preset")
	opts.show_for("erase")
	check(opts._controls.is_empty() and opts.get_child_count() == 1, "erase shows only a hint")
	opts.free()
	ctx.canvas.free()


# ---------------------------------------------------------------------- shell --

func test_app_prefs() -> void:
	var path := "user://test_prefs.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var app := App.new(path)
	check(app.theme_name == "slate", "fresh prefs → slate")
	check(app.recent().is_empty(), "fresh prefs → no recent files")
	var themed := []
	app.theme_changed.connect(func(n: String) -> void: themed.append(n))
	app.set_theme("forge")
	check(themed == ["forge"], "set_theme emits")
	app.set_theme("no-such-theme")
	check(app.theme_name == "slate", "unknown theme falls back to slate")
	var map_path := ProjectSettings.globalize_path("res://examples/forest_road.hexmap")
	app.note_recent("/nowhere/gone.hexmap")
	app.note_recent(map_path)
	app.note_recent(map_path)
	check(app.recent() == [map_path], "recent: newest first, deduplicated, missing files dropped")
	for i in App.RECENT_MAX + 3:
		app.note_recent(ProjectSettings.globalize_path("res://examples/forest_road.hexmap") if i % 2 == 0 else ProjectSettings.globalize_path("res://examples/bog_crossing.hexmap"))
	check((app.prefs.recent as Array).size() <= App.RECENT_MAX, "recent list is capped")
	var again := App.new(path)
	check(again.theme_name == "slate" and again.recent().size() == 2, "prefs round-trip through the file")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	check(App.new(path).theme_name == "slate", "garbage prefs file → defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(App.mode_available("player"), "the player runs on every build")
	check(App.available_modes().size() == (1 if OS.has_feature("mobile") or OS.has_feature("web") else 3), "desktop builds get all modes")
	for m in App.MODES:
		check(App.mode_label(m) != m and App.mode_blurb(m) != "", "mode %s has a label and a blurb" % m)


func test_shell_args() -> void:
	var Main = load("res://hexmap/shell/main.gd")
	check(Main._mode_from_args(PackedStringArray([])) == ["", ""], "no args → home")
	check(Main._mode_from_args(PackedStringArray(["--theme", "forge"])) == ["", ""], "theme alone → home")
	check(Main._mode_from_args(PackedStringArray(["examples/x.hexmap"])) == ["editor", "examples/x.hexmap"], "a map → editor")
	check(Main._mode_from_args(PackedStringArray(["examples/x.hexmap", "--shot", "o.png"])) == ["editor", "examples/x.hexmap"], "map plus --shot → editor")
	check(Main._mode_from_args(PackedStringArray(["--editor"])) == ["editor", ""], "--editor → new map")
	check(Main._mode_from_args(PackedStringArray(["--editor", "--theme", "forge"])) == ["editor", ""], "--editor before a flag takes no argument")
	check(Main._mode_from_args(PackedStringArray(["a.encounter"])) == ["table", "a.encounter"], "an encounter → table")
	check(Main._mode_from_args(PackedStringArray(["--table", "a.encounter"])) == ["table", "a.encounter"], "--table with a file")
	check(Main._mode_from_args(PackedStringArray(["--player", "192.168.1.4:7777"])) == ["player", "192.168.1.4:7777"], "--player with an address")


func test_home_screen() -> void:
	var app := App.new("user://test_prefs_home.json")
	app.note_recent(ProjectSettings.globalize_path("res://examples/forest_road.hexmap"))
	var home := HomeScreen.new()
	home.app = app
	root.add_child(home)
	var opened := []
	home.open_mode.connect(func(m: String, a: String) -> void: opened.append([m, a]))
	for m in App.MODES:
		var b: Button = home.find_child("Mode_" + m, true, false)
		check(b != null and b.disabled == not App.mode_available(m), "home has a %s button" % m)
		check(b.custom_minimum_size.y >= 44, "%s button is finger-sized" % m)
	(home.find_child("Mode_editor", true, false) as Button).pressed.emit()
	check(opened == [["editor", ""]], "mode button asks the shell for that mode")
	check(home._recent_box != null and home._recent_box.get_child_count() == 1, "recent files listed")
	(home._recent_box.get_child(0) as Button).pressed.emit()
	check(opened.size() == 2 and opened[1][0] == "editor" and opened[1][1].ends_with("forest_road.hexmap"), "recent map opens in the editor")
	home.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_home.json"))


# ----------------------------------------------------------------- encounter --

func _chapel() -> HexMap:
	return HexMap.load_file(ProjectSettings.globalize_path("res://examples/ruined_chapel.hexmap"))


## A small encounter on the chapel: one scene, a party token at the west
## door, one goblin. Returns [state, scene_id, party_token_id, goblin_id].
func _small_encounter() -> Array:
	var m := _chapel()
	var st := EncounterState.new(Encounter.create("Test"))
	st.attach_map(m)
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	st.apply({"t": "scene.add", "scene": sc})
	var g := m.grid
	var hero := Encounter.new_token("Hero", g.cell_center(g.offset_to_axial(3, 7)), {"owner": "pl_1", "vision": {"radius": 6}})
	var gob := Encounter.new_token("Goblin", g.cell_center(g.offset_to_axial(9, 7)), {"hidden": true})
	st.apply({"t": "token.add", "scene": sc.id, "token": hero})
	st.apply({"t": "token.add", "scene": sc.id, "token": gob})
	return [st, sc.id, hero.id, gob.id]


func test_json_doc() -> void:
	var d := {"b": 2.0, "a": {"z": [3.0, 1.5, {"y": 1}], "x": 1}}
	var text := JsonDoc.stringify(d)
	check(text.begins_with('{\n  "a": {\n    "x": 1,'), "keys sorted at every level")
	check(text.contains('"b": 2\n'), "whole floats written as ints")
	check(JsonDoc.same(d, JsonDoc.parse(text)), "parse(stringify) is the same document")
	var err: Array = []
	check(JsonDoc.parse("[1,2]", err).is_empty() and err.size() == 1, "an array is not a document")
	err.clear()
	check(JsonDoc.parse("{ nope", err).is_empty() and err[0].begins_with("line "), "parse error names the line")
	var target := {"keep": 1, "drop": 2, "change": 3}
	var before := JsonDoc.merge(target, {"drop": null, "change": 4, "add": 5})
	check(target == {"keep": 1, "change": 4, "add": 5}, "merge sets, adds and removes")
	check(before == {"drop": 2, "change": 3, "add": null}, "merge returns the inverse change set")
	JsonDoc.merge(target, before)
	check(target == {"keep": 1, "drop": 2, "change": 3}, "applying the inverse restores")
	check(JsonDoc.uuid().length() == 36 and JsonDoc.uuid() != JsonDoc.uuid(), "uuids")
	check(JsonDoc.new_id("t").begins_with("t_") and JsonDoc.new_id("t").length() == 10, "short ids")


func test_encounter_document() -> void:
	var m := _chapel()
	var e := Encounter.create("Chapel Ambush")
	check(e.doc.format == Encounter.FORMAT and e.doc.version == Encounter.VERSION, "created with format and version")
	check(e.scenes.is_empty() and e.active_scene().is_empty(), "empty encounter has no active scene")
	var sc := Encounter.new_scene(m, "crypt")
	check(sc.map == m.doc.id and sc.level == "crypt" and sc.name.contains("Crypt") and sc.map_path == "ruined_chapel.hexmap", "new_scene records the map, level and file")
	e.doc.scenes.append(sc)
	e.doc.active_scene = sc.id
	var tk := Encounter.new_token("Goblin", Vector2(1.5, 2.25), {"hidden": true})
	check(tk.label == "GO" and tk.pos == [1.5, 2.25] and tk.hidden == true and tk.vision.radius == 6 and not tk.has("owner"), "new_token defaults and extras")
	check(not Encounter.new_token("x", Vector2.ZERO, {"owner": null}).has("owner"), "a null extra is left out")
	sc.tokens.append(tk)
	var text := e.to_json()
	var back := Encounter.from_json(text)
	check(back != null and back.to_json() == text, "serialisation is stable through a round trip")
	check(back.scene(sc.id).tokens[0].name == "Goblin" and back.active_scene().id == sc.id, "scenes and tokens survive")
	check(back.map_ids() == PackedStringArray([m.doc.id]), "map_ids lists each map once")
	var err: Array = []
	check(Encounter.from_json('{"format": "silvergrove.hexmap"}', err) == null and err[0].contains("not a"), "a map is not an encounter")
	err.clear()
	check(Encounter.from_json('{"format": "silvergrove.encounter", "version": 99}', err) == null and err[0].contains("newer"), "newer version refused")
	# A hand-written minimal file is filled in.
	var thin := Encounter.from_json('{"format": "silvergrove.encounter", "version": 1, "scenes": [{"id": "s1", "map": "x", "level": "ground", "tokens": [{"id": "t1", "name": "Orc"}]}]}')
	check(thin.active_scene_id == "s1" and thin.scene("s1").fog.explored == [] and thin.scene("s1").overrides == {}, "missing fields filled in")
	check(thin.scene("s1").tokens[0].vision.radius == 6 and thin.scene("s1").tokens[0].label == "OR", "partial tokens filled in")
	var nulls := Encounter.from_json('{"format": "silvergrove.encounter", "version": 1, "scenes": [{"id": "s1", "map": "x", "level": "ground", "tokens": [{"id": "t1", "name": "Orc", "owner": null, "light": null}]}]}')
	check(not nulls.scene("s1").tokens[0].has("owner") and not nulls.scene("s1").tokens[0].has("light"), "stored nulls read as absent")
	check(thin.turns.round == 1 and thin.turns.mode == "free" and thin.players == [], "turns and players default")
	var old := Encounter.from_json('{"format": "silvergrove.encounter", "version": 1, "initiative": {"order": ["a"], "turn": 0, "round": 2, "running": true}}')
	check(not old.doc.has("initiative") and old.turns.mode == "ordered" and old.turns.order == ["a"] and old.turns.round == 2, "pre-release initiative block migrates to ordered turns")
	# Save/load through a file, and a bundle directory.
	var path := ProjectSettings.globalize_path("user://test.encounter")
	check(e.save(path) == OK and not e.dirty, "saves")
	var loaded := Encounter.load_file(path)
	check(loaded != null and loaded.path == path and loaded.name == "Chapel Ambush" and loaded.base_dir() == path.get_base_dir(), "loads with path and base_dir")
	DirAccess.remove_absolute(path)
	var bundle := ProjectSettings.globalize_path("user://test_bundle.encounter")
	DirAccess.make_dir_recursive_absolute(bundle)
	check(e.save(bundle) == OK and FileAccess.file_exists(bundle.path_join("encounter.json")), "a bundle directory gets encounter.json")
	check(Encounter.load_file(bundle) != null, "bundle loads")
	DirAccess.remove_absolute(bundle.path_join("encounter.json"))
	DirAccess.remove_absolute(bundle)
	err.clear()
	check(Encounter.load_file("/nowhere/x.encounter", err) == null and err[0].begins_with("no such file"), "missing file reported")


func test_encounter_resolve_maps() -> void:
	var path := ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter")
	var e := Encounter.load_file(path)
	check(e != null, "example encounter loads")
	var st := EncounterState.new(e)
	var warn := st.resolve_maps()
	check(warn.is_empty(), "example resolves its map without warnings: %s" % [warn])
	check(st.maps.size() == 1 and st.map_for(e.active_scene_id).name == "Ruined Chapel", "map found by path relative to the encounter")
	check(st.level_for(e.scenes[1].id).id == "crypt", "each scene finds its level")
	# Wrong id, missing file.
	var e2 := Encounter.create("x")
	e2.path = path
	e2.doc.scenes.append({"id": "s", "map": "not-the-chapel", "map_path": "ruined_chapel.hexmap", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	e2.doc.scenes.append({"id": "s2", "map": "m", "map_path": "gone.hexmap", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	e2.doc.scenes.append({"id": "s3", "map": "m", "map_path": "", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	var st2 := EncounterState.new(e2)
	warn = st2.resolve_maps()
	check(warn.size() == 3, "mismatch, missing and unnamed maps each warn: %s" % [warn])
	check(st2.map_for("s") != null and e2.scene("s").map == st2.map_for("s").doc.id, "a mismatched id is adopted, not fatal")
	check(st2.level_for("s2").is_empty() and st2.effective_level("s2").is_empty(), "a scene without a map has no level")


func test_encounter_events_roundtrip() -> void:
	# Every event's inverse restores the document exactly.
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var gob: String = parts[3]
	var m := st.map_for(sid)
	var door: Dictionary = {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	var light: Dictionary = m.level_by_id("ground").lights[0]
	var second := Encounter.new_scene(m, "crypt")
	st.apply({"t": "scene.add", "scene": second})
	var third := Encounter.new_scene(m, "crypt", "Third")
	var events := [
		{"t": "encounter.set", "changes": {"name": "Renamed", "notes": [{"id": "n", "title": "x", "text": ""}]}},
		{"t": "scene.add", "scene": third},
		{"t": "scene.add", "scene": third, "index": 0},
		{"t": "scene.remove", "id": sid},
		{"t": "scene.set", "id": sid, "changes": {"name": "Other", "extra": 1}},
		{"t": "scene.activate", "id": second.id},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Orc", Vector2(1, 1))},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Orc", Vector2(1, 1)), "index": 0},
		{"t": "token.remove", "scene": sid, "id": hero},
		{"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [4.5, 4.5], "hidden": true, "note": "new key", "light": {"bright": 1, "dim": 2, "color": "#fff"}}},
		{"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}},
		{"t": "element.set", "scene": sid, "ref": "lights:" + light.id, "changes": {"on": false, "hidden": true}},
		{"t": "fog.set", "scene": sid, "enabled": true},
		{"t": "fog.reveal", "scene": sid, "cells": ["0,0", "1,0", "0,0"]},
		{"t": "turns.set", "changes": {"mode": "ordered", "order": [hero, gob], "running": true, "turn": 1, "round": 3, "active": [hero]}},
		{"t": "player.add", "player": Encounter.new_player("Ana")},
		{"t": "player.add", "player": {"id": "pl_1", "name": "Ben", "color": "#fff"}},
	]
	for ev in events:
		var before := st.encounter.to_json()
		var why := st.validate(ev)
		check(why == "", "%s validates (%s)" % [ev.t, why])
		var got := []
		st.applied.connect(func(e: Dictionary, i: Dictionary) -> void: got.append([e, i]), CONNECT_ONE_SHOT)
		var inv := st.apply(ev)
		check(not inv.is_empty() and got.size() == 1 and got[0][0] == ev and got[0][1] == inv, "%s applied and announced" % ev.t)
		check(st.encounter.to_json() != before, "%s changed something" % ev.t)
		check(st.validate(inv) == "", "inverse of %s validates (%s)" % [ev.t, st.validate(inv)])
		var inv2 := st.apply(inv)
		check(st.encounter.to_json() == before, "inverse of %s restores the document" % ev.t)
		st.apply(inv2)
		check(st.encounter.to_json() != before, "inverse of the inverse re-applies %s" % ev.t)
		st.apply(inv)
		check(st.encounter.to_json() == before, "and undoes again")
	# fog.hide on top of revealed cells, then remove the player that owns a token.
	st.apply({"t": "fog.reveal", "scene": sid, "cells": ["0,0", "1,0"]})
	var before := st.encounter.to_json()
	var inv := st.apply({"t": "fog.hide", "scene": sid, "cells": ["1,0", "9,9"]})
	check(inv.cells == ["1,0"] and st.explored(sid).keys() == ["0,0"], "fog.hide drops only explored cells and inverts to exactly those")
	st.apply(inv)
	check(st.encounter.to_json() == before, "fog.hide inverse restores")
	st.apply({"t": "player.add", "player": {"id": "pl_1", "name": "Ben", "color": "#fff"}})
	st.apply({"t": "player.set", "id": "pl_1", "changes": {"name": "Benjamin"}})
	before = st.encounter.to_json()
	inv = st.apply({"t": "player.remove", "id": "pl_1"})
	st.apply(inv)
	check(st.encounter.to_json() == before, "player.remove inverse restores at the same index")
	check(st.encounter.dirty, "events mark the encounter dirty")


func test_encounter_validate() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var bad := [
		[{}, "unknown event"],
		[{"t": "nope"}, "unknown event"],
		[{"t": "encounter.set"}, "needs 'changes'"],
		[{"t": "encounter.set", "changes": {"scenes": []}}, "cannot change 'scenes'"],
		[{"t": "scene.add", "scene": {}}, "needs a scene with an id"],
		[{"t": "scene.add", "scene": {"id": sid}}, "already exists"],
		[{"t": "scene.remove", "id": "zz"}, "no scene"],
		[{"t": "scene.set", "id": sid, "changes": {"tokens": []}}, "cannot change 'tokens'"],
		[{"t": "token.add", "scene": "zz", "token": {"id": "t"}}, "no scene"],
		[{"t": "token.add", "scene": sid, "token": {"name": "no id"}}, "needs a token with an id"],
		[{"t": "token.add", "scene": sid, "token": {"id": hero}}, "already exists"],
		[{"t": "token.remove", "scene": sid, "id": "zz"}, "no token"],
		[{"t": "token.set", "scene": sid, "id": hero, "changes": {"id": "x"}}, "cannot change 'id'"],
		[{"t": "token.set", "scene": sid, "id": hero}, "needs 'changes'"],
		[{"t": "element.set", "scene": sid, "ref": "walls", "changes": {}}, "needs a ref"],
		[{"t": "element.set", "scene": sid, "ref": "terrain:0,0", "changes": {}}, "needs a ref"],
		[{"t": "element.set", "scene": sid, "ref": "walls:w_nope", "changes": {"state": "open"}}, "no walls:w_nope on the map"],
		[{"t": "fog.set", "scene": sid}, "needs 'enabled'"],
		[{"t": "fog.reveal", "scene": sid}, "needs 'cells'"],
		[{"t": "turns.set", "changes": {"mode": "chaos"}}, "mode must be one of"],
		[{"t": "turns.set", "changes": {"order": "t_1"}}, "must be a list"],
		[{"t": "player.add", "player": {}}, "needs a player with an id"],
		[{"t": "player.remove", "id": "zz"}, "no player"],
		[{"t": "player.set", "id": "zz", "changes": {}}, "no player"],
	]
	for b in bad:
		var why := st.validate(b[0])
		check(why.contains(b[1]), "rejects %s: '%s' should mention '%s'" % [b[0], why, b[1]])
	var before := st.encounter.to_json()
	check(st.apply({"t": "token.remove", "scene": sid, "id": "zz"}).is_empty() and st.encounter.to_json() == before, "apply of an invalid event is a no-op")
	# A scene without a map cannot check element refs, so it accepts them.
	var e := Encounter.create("x")
	e.doc.scenes.append({"id": "s", "map": "m", "map_path": "", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	check(EncounterState.new(e).validate({"t": "element.set", "scene": "s", "ref": "walls:w_1", "changes": {"state": "open"}}) == "", "without the map, element refs are trusted")


func test_encounter_permissions() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var gob: String = parts[3]
	var move := {"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [1, 1], "rot": 90}}
	# Ownership matters in dm mode with the hero ticked; free mode is tested below.
	st.apply({"t": "turns.set", "changes": {"mode": "dm", "active": [hero, gob]}})
	check(st.allowed(move, ""), "the table may do anything")
	check(st.allowed({"t": "scene.remove", "id": sid}, ""), "the table may do anything (2)")
	check(st.allowed(move, "pl_1"), "a player may move their own token")
	check(not st.allowed(move, "pl_2"), "another player may not")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_1"), "may not move an unowned token")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": hero, "changes": {"hidden": false}}, "pl_1"), "may not change other fields")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [1, 1], "name": "x"}}, "pl_1"), "one bad field rejects the whole request")
	check(not st.allowed({"t": "element.set", "scene": sid, "ref": "walls:x", "changes": {"state": "open"}}, "pl_1"), "players may not open doors")
	check(not st.allowed({"t": "token.remove", "scene": sid, "id": hero}, "pl_1"), "players may not remove tokens")
	# Turn modes. Free: any visible token, even someone else's.
	st.apply({"t": "turns.set", "changes": {"mode": "free", "active": []}})
	check(Encounter.create("x").turns.mode == "free", "encounters start in free mode")
	check(st.allowed({"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [1, 1]}}, "pl_2"), "free: another player may move it")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_2"), "free: but never a hidden one")
	st.apply({"t": "token.set", "scene": sid, "id": gob, "changes": {"hidden": false}})
	check(st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_2"), "free: a revealed unowned token is fair game")
	check(st.highlighted_token_ids().is_empty(), "free: nobody is 'up'")
	# DM picks: owned and ticked.
	st.apply({"t": "turns.set", "changes": {"mode": "dm"}})
	check(not st.allowed(move, "pl_1"), "dm: not until the DM ticks it")
	st.apply({"t": "turns.set", "changes": {"active": [hero]}})
	check(st.allowed(move, "pl_1") and not st.allowed(move, "pl_2"), "dm: ticked, the owner may move it and nobody else")
	check(st.highlighted_token_ids() == [hero], "dm: ticked tokens are up")
	st.apply({"t": "turns.set", "changes": {"active": [gob]}})
	check(not st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_2"), "dm: an unowned token ticked still needs an owner")
	# Ordered: only the owner of the current turn's token.
	st.apply({"t": "turns.set", "changes": {"mode": "ordered", "order": [gob, hero], "turn": 0, "round": 1, "running": false}})
	check(not st.allowed(move, "pl_1") and st.current_turn_token() == "", "ordered but not running: nobody moves")
	st.apply({"t": "turns.set", "changes": {"running": true}})
	check(st.current_turn_token() == gob and not st.allowed(move, "pl_1"), "ordered: goblin's turn, the hero waits")
	st.apply({"t": "turns.set", "changes": {"turn": 1}})
	check(st.current_turn_token() == hero and st.allowed(move, "pl_1") and not st.allowed(move, "pl_2") and st.highlighted_token_ids() == [hero], "ordered: hero's turn, only its owner")
	check(st.allowed({"t": "turns.set", "changes": {"turn": 0}}, ""), "the table may always step turns")
	check(not st.allowed({"t": "turns.set", "changes": {"turn": 0}}, "pl_1"), "a player may not")
	st.apply({"t": "turns.set", "changes": {"mode": "free", "running": false}})
	st.apply({"t": "token.set", "scene": sid, "id": gob, "changes": {"hidden": true}})
	check(st.tokens_owned_by(sid, "pl_1").size() == 1 and st.tokens_owned_by(sid, "pl_2").is_empty(), "tokens_owned_by")
	check(st.tokens_visible_to_players(sid).size() == 1 and st.tokens_visible_to_players(sid)[0].id == hero, "hidden tokens are not for players")


func test_encounter_effective() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var m := st.map_for(sid)
	var lvl := m.level_by_id("ground")
	var door: Dictionary = {}
	for w in lvl.walls:
		if w.get("door", "none") == "door":
			door = w
	check(st.effective(sid, "walls", door).state == "closed", "no override → as stored")
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}})
	var eff := st.effective(sid, "walls", door)
	check(eff.state == "open" and door.state == "closed", "override merged; the map untouched")
	check(eff.points == door.points and eff.id == door.id, "other fields come through")
	eff.points.append([0, 0])
	check(door.points.size() == eff.points.size() - 1, "effective() is a copy: editing it cannot reach the map")
	var el := st.effective_level(sid)
	var found := false
	for w in el.walls:
		if w.id == door.id:
			found = w.state == "open"
	check(found, "effective_level carries the override")
	check(el.terrain == lvl.terrain and el.tree == lvl.tree and el.id == lvl.id, "effective_level shares terrain and tree")
	check(lvl.walls[0].state != "open" or lvl.walls[0].id == door.id, "map walls unchanged")
	var light: Dictionary = lvl.lights[0]
	st.apply({"t": "element.set", "scene": sid, "ref": "lights:" + light.id, "changes": {"on": false}})
	check(st.effective(sid, "lights", light).on == false and not light.has("on"), "overlay-only field")
	st.apply({"t": "element.set", "scene": sid, "ref": "lights:" + light.id, "changes": {"on": null}})
	check(st.override_of(sid, "lights:" + light.id).is_empty() and not st.encounter.scene(sid).overrides.has("lights:" + light.id), "clearing the last key removes the override")
	check(st.effective(sid, "lights", light) == light, "back to as stored")
	check(m.to_json() == _chapel().to_json(), "after all that, the map document is byte-identical")


func test_vision() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var m := st.map_for(sid)
	var g := m.grid
	var door: Dictionary = {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	# The hero stands outside the west door; the goblin is inside the nave.
	var inside := g.cell_center(g.offset_to_axial(7, 7))
	var closed := Vision.of(st, sid, [st.token(sid, hero)])
	check(closed.polygons.size() == 1 and closed.cells.size() > 10, "one polygon, some cells seen (%d)" % closed.cells.size())
	check(closed.cells.has(g.world_to_axial(Vision.token_pos(st.token(sid, hero)))), "a token sees its own cell")
	check(not Vision.sees(closed.polygons, inside), "closed door: cannot see into the nave")
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}})
	var opened := Vision.of(st, sid, [st.token(sid, hero)])
	check(Vision.sees(opened.polygons, inside), "open door: sees into the nave")
	check(opened.cells.size() > closed.cells.size(), "open door reveals more cells (%d > %d)" % [opened.cells.size(), closed.cells.size()])
	# Vision is bounded by radius.
	for c in opened.cells:
		check(g.cell_center(c).distance_to(Vision.token_pos(st.token(sid, hero))) <= 6.0 + 0.6, "seen cell within radius")
	# No vision, no polygon; two tokens, two polygons; sight vs light walls.
	st.apply({"t": "token.set", "scene": sid, "id": hero, "changes": {"vision": {"radius": 0}}})
	check(Vision.of(st, sid, [st.token(sid, hero)]).cells.is_empty(), "radius 0 sees nothing")
	st.apply({"t": "token.set", "scene": sid, "id": hero, "changes": {"vision": {"radius": 3}}})
	check(Vision.of(st, sid, st.tokens(sid)).polygons.size() == 2, "each seeing token gets a polygon")
	var lvl := {"walls": [{"id": "w", "points": [[0, 0], [0, 2]], "blocks": {"sight": false, "light": true}, "door": "none", "state": "closed"}]}
	check(Vision.segments(lvl).is_empty() and Lighting.blocking_segments(lvl).size() == 1, "a window blocks light but not sight")
	check(Vision.of(st, "no-such-scene", []).cells.is_empty(), "unknown scene sees nothing")


func test_encounter_commands() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var gob: String = parts[3]
	var h := History.new()
	var c := EncounterCommands.new(st, h)
	var m := st.map_for(sid)
	var g := m.grid
	var door: Dictionary = {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	var start := st.encounter.to_json()
	check(c.run({"t": "token.remove", "scene": sid, "id": "zz"}) != "" and not h.can_undo(), "a refused event is not recorded")
	var applied := []
	st.applied.connect(func(e: Dictionary, _i: Dictionary) -> void: applied.append(e.t))
	var wolf := Encounter.new_token("Wolf", Vector2(2, 2))
	check(c.add_token(sid, wolf) == "" and applied == ["token.add"] and st.tokens(sid).size() == 3, "a command applies its event exactly once")
	h.undo()
	check(applied == ["token.add", "token.remove"] and st.tokens(sid).size() == 2, "undo applies the inverse once")
	h.redo()
	check(applied.size() == 3 and st.tokens(sid).size() == 3 and st.tokens(sid)[2].id == wolf.id, "redo re-adds it")
	h.undo()
	h.clear()
	applied.clear()
	check(c.set_door(sid, door.id, "open") == "" and h.undo_label() == "Open door", "set_door records a labelled step")
	check(st.effective(sid, "walls", door).state == "open", "door open")
	h.undo()
	check(st.effective(sid, "walls", door).state == "closed" and st.encounter.to_json() == start, "undo closes it and restores the document")
	h.redo()
	check(st.effective(sid, "walls", door).state == "open", "redo opens it again")
	c.set_light(sid, m.level_by_id("ground").lights[0].id, false)
	c.set_revealed(sid, "walls", door.id, false)
	c.reset_element(sid, "walls:" + door.id)
	check(st.override_of(sid, "walls:" + door.id).is_empty() and h.undo_label() == "Reset", "reset_element clears both keys in one step")
	h.undo()
	check(st.override_of(sid, "walls:" + door.id) == {"state": "open", "hidden": true}, "undo of reset brings both back")
	# Fog: a move reveals what the token sees, as one undo step.
	c.set_fog(sid, true)
	check(st.explored(sid).is_empty(), "fog on, nothing explored yet")
	var steps := h._undo.size()
	c.move_token(sid, hero, g.cell_center(g.offset_to_axial(4, 7)))
	check(h._undo.size() == steps + 1 and h.undo_label() == "Move Hero", "move + reveal is one step")
	var seen := st.explored(sid).size()
	check(seen > 10 and st.token(sid, hero).pos == [g.cell_center(g.offset_to_axial(4, 7)).x, g.cell_center(g.offset_to_axial(4, 7)).y], "moved and explored %d cells" % seen)
	c.move_token(sid, hero, g.cell_center(g.offset_to_axial(4, 7)))
	check(st.explored(sid).size() == seen, "moving in place reveals nothing new")
	h.undo()
	h.undo()
	check(st.explored(sid).is_empty(), "undoing the moves forgets what was seen")
	c.set_fog(sid, false)
	c.move_token(sid, hero, g.cell_center(g.offset_to_axial(2, 7)))
	check(st.explored(sid).is_empty(), "no fog, no exploring")
	c.set_fog(sid, true)
	c.reveal_cells(sid, [Vector2i(0, 0), "1,0", Vector2i(0, 0)])
	check(st.explored(sid).keys() == ["0,0", "1,0"], "reveal_cells takes cells or keys, once each")
	check(c.reveal_cells(sid, ["0,0"]) == "" and h.undo_label() == "Reveal", "revealing nothing new is a no-op")
	c.hide_cells(sid, [Vector2i(0, 0)])
	check(st.explored(sid).keys() == ["1,0"], "hide_cells")
	c.reset_fog(sid)
	check(st.explored(sid).is_empty(), "reset_fog")
	h.undo()
	check(st.explored(sid).keys() == ["1,0"], "reset_fog undoes")
	# Tokens.
	var orc := Encounter.new_token("Orc", Vector2(2, 2))
	c.add_token(sid, orc)
	check(st.token(sid, orc.id).name == "Orc" and h.undo_label() == "Add Orc", "add_token")
	c.remove_tokens(sid, [orc.id, gob])
	check(st.tokens(sid).size() == 1 and h.undo_label() == "Remove 2 tokens", "remove_tokens is one step")
	h.undo()
	check(st.tokens(sid).size() == 3 and st.tokens(sid)[1].id == gob and st.tokens(sid)[2].id == orc.id, "undo restores both at their places")
	c.update_token(sid, gob, {"hidden": false, "tags": ["surprised"]})
	check(st.token(sid, gob).hidden == false and st.token(sid, gob).tags == ["surprised"], "update_token")
	# Turns: modes, DM picks, and the list system wrapping rounds both ways.
	c.set_turn_mode("dm")
	c.toggle_active_token(hero)
	c.toggle_active_token(gob)
	var turns := st.encounter.turns
	check(turns.mode == "dm" and turns.active == [hero, gob] and h.undo_label() == "Who may move", "toggle_active_token adds")
	c.toggle_active_token(hero)
	check(turns.active == [gob], "toggle_active_token removes")
	check(c.start_turns(sid) == "" and turns.mode == "ordered" and turns.system == "list" and turns.order == [hero, gob, orc.id] and turns.running and turns.turn == 0 and turns.round == 1, "start_turns orders the scene's tokens with the list system: %s" % [turns.order])
	check(st.current_turn_token() == hero, "first turn")
	c.next_turn(); c.next_turn(); c.next_turn()
	check(turns.turn == 0 and turns.round == 2, "next_turn wraps to a new round")
	c.previous_turn()
	check(turns.turn == 2 and turns.round == 1, "previous_turn wraps back")
	c.previous_turn(); c.previous_turn()
	check(c.previous_turn() != "" and turns.turn == 0 and turns.round == 1, "cannot go before the start")
	c.set_turn_order([orc.id, hero, gob])
	check(turns.order[0] == orc.id and st.current_turn_token() == orc.id, "set_turn_order")
	c.stop_turns()
	check(not turns.running and st.current_turn_token() == "", "stop_turns")
	c.set_turn_order([])
	check(c.next_turn() != "", "no order, no turns")
	# Restarting keeps the surviving order and appends newcomers.
	c.set_turn_order([gob, hero])
	c.start_turns(sid)
	check(turns.order == [gob, hero, orc.id], "restart keeps the arranged order and appends the rest")
	c.set_turn_mode("free")
	# Scenes and players.
	var crypt := Encounter.new_scene(m, "crypt")
	c.add_scene(crypt)
	check(st.encounter.active_scene_id == crypt.id and h.undo_label() == "Show scene", "add_scene activates")
	h.undo(); h.undo()
	check(st.encounter.active_scene_id == sid and st.encounter.scenes.size() == 1, "undo of add_scene, twice, is back to one scene")
	c.add_scene(crypt, false)
	check(st.encounter.active_scene_id == sid, "add_scene without activating")
	c.rename_scene(crypt.id, "Below")
	check(st.encounter.scene(crypt.id).name == "Below", "rename_scene")
	c.remove_scene(sid)
	check(st.encounter.active_scene_id == crypt.id, "removing the active scene moves to another")
	h.undo()
	check(st.encounter.active_scene_id == sid, "undo restores it as active")
	var p := Encounter.new_player("Ana")
	c.add_player(p)
	c.update_player(p.id, {"name": "Anna"})
	check(st.encounter.player(p.id).name == "Anna", "players")
	c.remove_player(p.id)
	check(st.encounter.player(p.id).is_empty(), "remove_player")
	c.rename("Ambush!")
	check(st.encounter.name == "Ambush!", "rename")
	# Everything undone is the starting document.
	while h.can_undo():
		h.undo()
	check(st.encounter.to_json() == start, "undoing everything restores the start")
	while h.can_redo():
		h.redo()
	check(st.encounter.name == "Ambush!" and st.encounter.scene(crypt.id).name == "Below", "redoing everything replays it")
	h.clear()


func test_example_encounter() -> void:
	# The example is built through events and must be a consistent document.
	var e := Encounter.load_file(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"))
	var st := EncounterState.new(e)
	st.resolve_maps()
	check(e.scenes.size() == 2 and e.active_scene().name == "Chapel at dusk", "two scenes, chapel active")
	var sid := e.active_scene_id
	check(st.tokens(sid).size() == 6 and st.tokens_visible_to_players(sid).size() == 2 and e.players.size() == 2, "party visible, goblins hidden")
	var off := 0
	for l in st.level_for(sid).lights:
		if st.effective(sid, "lights", l).get("on", true) == false:
			off += 1
	check(off == 4, "four braziers out")
	check(st.fog_enabled(sid) and st.explored(sid).size() > 20, "fog on with the approach explored")
	for k in st.explored(sid):
		check(st.map_for(sid).grid.in_bounds(HexMap.key_cell(k)), "explored cell %s in bounds" % k)
	check(e.turns.mode == "ordered" and e.turns.order.size() == 6 and not e.turns.running, "ordered turns set up, not running")
	for tid in e.turns.order:
		check(not st.token(sid, tid).is_empty(), "initiative token %s exists" % tid)
	check(e.map_ids().size() == 1, "one map")
	for p in e.players:
		check(st.tokens_owned_by(sid, p.id).size() == 1, "%s owns one token" % p.name)
	for s in e.scenes:
		for ref in s.overrides:
			check(st.validate({"t": "element.set", "scene": s.id, "ref": ref, "changes": {}}) == "", "override %s refers to a real element" % ref)


# --------------------------------------------------------------------- table --

## A TableContext on the example encounter, with a canvas but no window.
func _table_ctx() -> TableContext:
	var ctx := TableContext.new()
	ctx.app = App.new("user://test_prefs_table.json")
	var e := Encounter.load_file(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"))
	ctx.set_encounter(e)
	ctx.state.resolve_maps()
	ctx.canvas = MapCanvas.new()
	ctx.canvas.packs = ctx.app.packs
	ctx.canvas.set_scene(ctx.state, ctx.scene_id)
	ctx.zoom = 1.0
	return ctx


func _door_of(ctx: TableContext) -> Dictionary:
	for w in ctx.map().level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			return w
	return {}


func test_canvas_encounter_view() -> void:
	var ctx := _table_ctx()
	var canvas := ctx.canvas
	var st := ctx.state
	var sid := ctx.scene_id
	check(canvas.map != null and canvas.level().id == "ground" and canvas.gm_view(), "set_scene finds the map and level; GM by default")
	check(canvas.tokens_in_view().size() == 6, "the GM sees every token")
	var ana: Dictionary = st.encounter.players[0]
	canvas.viewpoint = str(ana.id)
	canvas.refresh()
	var seen := canvas.tokens_in_view()
	check(seen.size() == 2, "a player sees the unhidden party, not the hidden goblins (%d)" % seen.size())
	for t in seen:
		check(not bool(t.hidden), "seen tokens are not hidden")
	var g := canvas.map.grid
	var fighter: Dictionary = st.tokens_owned_by(sid, str(ana.id))[0]
	var own_cell := g.world_to_axial(Vision.token_pos(fighter))
	check(canvas.fog_of(own_cell) == 0 and canvas.point_seen(Vision.token_pos(fighter)), "own cell is in sight")
	var far := g.offset_to_axial(20, 14)
	check(canvas.fog_of(far) == 2 and not canvas.point_seen(g.cell_center(far)), "far corner is unseen")
	# The nave is behind a closed door: explored? no; seen? no. Open the door
	# and the fighter at the threshold sees in.
	var inside := g.offset_to_axial(7, 7)
	check(canvas.fog_of(inside) == 2, "the nave is unseen behind the closed door")
	var door := _door_of(ctx)
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}})
	st.apply({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [g.cell_center(g.offset_to_axial(4, 7)).x, g.cell_center(g.offset_to_axial(4, 7)).y]}})
	canvas.refresh()
	check(canvas.fog_of(inside) == 0, "open door: the nave is in sight from the threshold")
	var eff := canvas.level()
	var open := false
	for w in eff.walls:
		if w.id == door.id:
			open = w.state == "open"
	check(open, "the canvas draws the effective (open) door")
	# Explored-but-out-of-sight: move away, the cell dims instead of vanishing.
	st.apply({"t": "fog.reveal", "scene": sid, "cells": [HexMap.cell_key(inside)]})
	st.apply({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [1.0, 1.0]}})
	canvas.refresh()
	check(canvas.fog_of(inside) == 1, "explored cell out of sight is dim (1)")
	canvas.viewpoint = ""
	canvas.refresh()
	check(canvas.fog_of(inside) == 0 and canvas.fog_of(far) == 2, "the GM gets clear for explored and a hint for never-seen")
	st.apply({"t": "fog.set", "scene": sid, "enabled": false})
	canvas.viewpoint = str(ana.id)
	canvas.refresh()
	check(canvas.fog_of(far) == 0 and canvas.point_seen(g.cell_center(far)), "fog off: everything is seen")
	check(canvas.tokens_in_view().size() == 2, "fog off still hides hidden tokens from players")
	# A hidden token revealed becomes visible to players; is_shown honours the viewpoint for GM-only props.
	var gob: Dictionary = st.tokens(sid)[2]
	st.apply({"t": "token.set", "scene": sid, "id": gob.id, "changes": {"hidden": false}})
	canvas.refresh()
	check(canvas.tokens_in_view().size() == 3, "revealed goblin now in view")
	canvas.show_hidden = true
	check(not canvas.is_shown("props", {"id": "x", "hidden": true}), "a player never sees GM-only props even with show_hidden")
	canvas.viewpoint = ""
	check(canvas.is_shown("props", {"id": "x", "hidden": true}), "the GM does")
	check(canvas.token_hit(gob, Vision.token_pos(gob) + Vector2(0.3, 0)) and not canvas.token_hit(gob, Vision.token_pos(gob) + Vector2(0.6, 0)), "token_hit within its disc")
	canvas.free()


func test_table_context() -> void:
	var ctx := _table_ctx()
	var sid := ctx.scene_id
	check(sid == ctx.encounter().active_scene_id and ctx.map() != null and ctx.level().id == "ground", "context opens on the active scene with its map")
	var changes := []
	ctx.selection_changed.connect(func() -> void: changes.append("sel"))
	ctx.scene_changed.connect(func() -> void: changes.append("scene"))
	var tk: Dictionary = ctx.state.tokens(sid)[0]
	ctx.select_token(tk.id)
	check(ctx.is_token_selected(tk.id) and ctx.selected_token().id == tk.id and ctx.selected_token_ids() == [tk.id], "select_token")
	ctx.select_element("walls", _door_of(ctx).id)
	check(ctx.selected_token().is_empty() and ctx.selected_element().door == "door", "select_element gives the effective element")
	var other := str(ctx.encounter().scenes[1].id)
	ctx.set_scene(other)
	check(ctx.scene_id == other and ctx.selection.is_empty() and changes.has("scene") and ctx.level().id == "crypt", "set_scene switches level and clears selection")
	ctx.set_scene(sid)
	# Removing a selected token drops it from the selection.
	ctx.select_token(tk.id)
	ctx.commands.remove_tokens(sid, [tk.id])
	check(ctx.selection.is_empty(), "removed token leaves the selection")
	ctx.history.undo()
	# Removing the scene being looked at moves to the active one.
	ctx.set_scene(other)
	ctx.commands.remove_scene(other)
	check(ctx.scene_id == sid, "removing the viewed scene falls back to the active scene")
	ctx.history.undo()
	# new_token from the picks, uniquely named.
	ctx.token_name = "Goblin"
	ctx.token_owner = ""
	var nt := ctx.new_token(Vector2(1, 1))
	check(nt.name == "Goblin 5" and nt.label == "G5" and nt.hidden == ctx.token_hidden and not nt.has("owner"), "new_token numbers a repeated name: %s / %s" % [nt.name, nt.label])
	ctx.token_name = "Ogre"
	ctx.token_owner = str(ctx.encounter().players[1].id)
	nt = ctx.new_token(Vector2(1, 1))
	check(nt.name == "Ogre" and nt.label == "OG" and nt.owner == ctx.token_owner, "first of a name keeps its initials and the owner")
	check(ctx.snapped(Vector2(1.1, 1.1)) == ctx.map().grid.snap_to_center(Vector2(1.1, 1.1)), "snapped to hex centre")
	ctx.snap_tokens = false
	check(ctx.snapped(Vector2(1.1, 1.1)) == Vector2(1.1, 1.1), "snap off")
	ctx.history.clear()
	ctx.canvas.free()


func test_table_tools() -> void:
	var ctx := _table_ctx()
	var sid := ctx.scene_id
	var st := ctx.state
	var g := ctx.map().grid
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var shift := {"shift": true, "ctrl": false, "alt": false}
	var sel := TableTools.make("select", ctx) as TableTools.SelectTool
	var fighter: Dictionary = st.tokens(sid)[0]
	var ranger: Dictionary = st.tokens(sid)[1]
	var fpos := Vision.token_pos(fighter)
	# Click selects; drag moves, snapped; one undo step including the fog reveal.
	check(sel.token_at(fpos).id == fighter.id and sel.token_at(Vector2(0.2, 0.2)).is_empty(), "token_at")
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	check(ctx.is_token_selected(fighter.id), "press selects the token")
	var to := g.cell_center(g.offset_to_axial(4, 8)) + Vector2(0.1, -0.1)
	sel.drag(to, MOUSE_BUTTON_LEFT, mods)
	var steps := ctx.history._undo.size()
	sel.release(to, MOUSE_BUTTON_LEFT, mods)
	var moved := st.token(sid, fighter.id)
	check(Vision.token_pos(moved) == g.cell_center(g.offset_to_axial(4, 8)), "released on a snapped centre: %s" % [moved.pos])
	check(ctx.history._undo.size() == steps + 1 and ctx.history.undo_label().begins_with("Move"), "move is one step")
	ctx.history.undo()
	check(Vision.token_pos(st.token(sid, fighter.id)) == fpos, "undo puts it back")
	# Shift: free placement, and shift-click extends the selection.
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(0.37, 0.0), MOUSE_BUTTON_LEFT, shift)
	sel.release(fpos + Vector2(0.37, 0.0), MOUSE_BUTTON_LEFT, shift)
	check(near(Vision.token_pos(st.token(sid, fighter.id)).x, fpos.x + 0.37, 1e-6), "shift-drag places freely")
	ctx.history.undo()
	sel.press(Vision.token_pos(ranger), MOUSE_BUTTON_LEFT, shift)
	sel.release(Vision.token_pos(ranger), MOUSE_BUTTON_LEFT, shift)
	check(ctx.selected_token_ids().size() == 2, "shift-click adds to the selection")
	# Dragging two moves both.
	var rpos := Vision.token_pos(ranger)
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(2, 0), MOUSE_BUTTON_LEFT, mods)
	sel.release(fpos + Vector2(2, 0), MOUSE_BUTTON_LEFT, mods)
	check(ctx.history.undo_label() == "Move 2 tokens" and Vision.token_pos(st.token(sid, ranger.id)) != rpos, "multi-move is one step and moves both")
	ctx.history.undo()
	# A tiny drag is a click, not a move.
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(0.01, 0.0), MOUSE_BUTTON_LEFT, mods)
	steps = ctx.history._undo.size()
	sel.release(fpos + Vector2(0.01, 0.0), MOUSE_BUTTON_LEFT, mods)
	check(ctx.history._undo.size() == steps, "a jitter is not a move")
	# Box select on empty ground.
	ctx.clear_selection()
	sel.press(fpos + Vector2(-1.5, -1.5), MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(1.5, 2.0), MOUSE_BUTTON_LEFT, mods)
	sel.release(fpos + Vector2(1.5, 2.0), MOUSE_BUTTON_LEFT, mods)
	check(ctx.selected_token_ids().size() == 2, "box selects both party tokens (%d)" % ctx.selected_token_ids().size())
	# Doors toggle with a click; a locked one refuses and selects itself.
	var door := _door_of(ctx)
	var mid := (Vector2(door.points[0][0], door.points[0][1]) + Vector2(door.points[1][0], door.points[1][1])) / 2.0
	check(sel.door_at(mid).id == door.id and sel.door_at(mid + Vector2(1, 1)).is_empty(), "door_at")
	sel.press(mid, MOUSE_BUTTON_LEFT, mods)
	sel.release(mid, MOUSE_BUTTON_LEFT, mods)
	check(st.effective(sid, "walls", door).state == "open" and ctx.history.undo_label() == "Open door", "click opens the door")
	sel.press(mid, MOUSE_BUTTON_LEFT, mods)
	sel.release(mid, MOUSE_BUTTON_LEFT, mods)
	check(st.effective(sid, "walls", door).state == "closed", "click again closes it")
	ctx.commands.set_door(sid, door.id, "locked")
	steps = ctx.history._undo.size()
	sel.press(mid, MOUSE_BUTTON_LEFT, mods)
	check(ctx.history._undo.size() == steps and ctx.selected_element().state == "locked", "a locked door does not open on click; it gets selected")
	ctx.commands.set_door(sid, door.id, "closed")
	check(door.state == "closed" and ctx.map().to_json() == _chapel().to_json(), "the map is untouched by all that")
	# Lights toggle.
	var light: Dictionary = ctx.map().level_by_id("ground").lights[0]
	var lpos := Vector2(light.pos[0], light.pos[1])
	check(sel.light_at(lpos).id == light.id, "light_at")
	var was := bool(st.effective(sid, "lights", light).get("on", true))
	sel.press(lpos, MOUSE_BUTTON_LEFT, mods)
	check(bool(st.effective(sid, "lights", light).get("on", true)) != was, "click toggles the light")
	# Keys: H hides/reveals, Delete removes.
	ctx.select_token(fighter.id)
	var kh := InputEventKey.new()
	kh.keycode = KEY_H
	kh.pressed = true
	check(sel.key(kh) and st.token(sid, fighter.id).hidden == true, "H hides")
	sel.key(kh)
	check(st.token(sid, fighter.id).hidden == false, "H again reveals")
	var kd := InputEventKey.new()
	kd.keycode = KEY_DELETE
	kd.pressed = true
	check(sel.key(kd) and st.token(sid, fighter.id).is_empty() and ctx.selection.is_empty(), "Delete removes the selected token")
	ctx.history.undo()
	check(not st.token(sid, fighter.id).is_empty(), "undo brings it back")
	# Token tool places from the picks.
	var tt := TableTools.make("token", ctx) as TableTools.TokenTool
	ctx.token_name = "Wolf"
	ctx.token_hidden = false
	var spot := g.cell_center(g.offset_to_axial(8, 8))
	tt.move(spot + Vector2(0.2, 0.1))
	check(tt._at == spot, "ghost snaps to the hex centre")
	check(tt.press(spot + Vector2(0.2, 0.1), MOUSE_BUTTON_LEFT, mods), "token tool press")
	var wolf: Dictionary = st.tokens(sid)[-1]
	check(wolf.name == "Wolf" and Vision.token_pos(wolf) == spot and ctx.is_token_selected(wolf.id), "placed, snapped and selected")
	check(not tt.press(spot, MOUSE_BUTTON_RIGHT, mods), "right button does nothing")
	# Fog tool: a stroke reveals once per cell, one undo step; right button hides.
	var ft := TableTools.make("fog", ctx) as TableTools.FogTool
	ctx.fog_brush = 2
	var far := g.cell_center(g.offset_to_axial(18, 3))
	var before := st.explored(sid).size()
	ft.press(far, MOUSE_BUTTON_LEFT, mods)
	ft.drag(far + Vector2(0.3, 0), MOUSE_BUTTON_LEFT, mods)
	ft.drag(far + Vector2(1.0, 0), MOUSE_BUTTON_LEFT, mods)
	steps = ctx.history._undo.size()
	ft.release(far + Vector2(1.0, 0), MOUSE_BUTTON_LEFT, mods)
	var after := st.explored(sid).size()
	check(after > before + 6 and ctx.history._undo.size() == steps + 1 and ctx.history.undo_label() == "Reveal", "brush stroke revealed %d cells as one step" % (after - before))
	ft.press(far, MOUSE_BUTTON_RIGHT, mods)
	ft.release(far, MOUSE_BUTTON_RIGHT, mods)
	check(st.explored(sid).size() < after and ctx.history.undo_label() == "Hide", "right button hides")
	var kb := InputEventKey.new()
	kb.keycode = KEY_BRACKETLEFT
	kb.pressed = true
	ft.key(kb)
	check(ctx.fog_brush == 1, "[ shrinks the brush")
	# Fog tool on a scene without fog turns it on first.
	var crypt := str(ctx.encounter().scenes[1].id)
	st.apply({"t": "fog.set", "scene": crypt, "enabled": false})
	ctx.set_scene(crypt)
	ctx.canvas.set_scene(st, crypt)
	ft.press(g.cell_center(g.offset_to_axial(11, 8)), MOUSE_BUTTON_LEFT, mods)
	ft.release(g.cell_center(g.offset_to_axial(11, 8)), MOUSE_BUTTON_LEFT, mods)
	check(st.fog_enabled(crypt) and st.explored(crypt).size() == 1, "painting fog turns fog on")
	ctx.history.clear()
	ctx.canvas.free()


func test_table_window() -> void:
	var app := App.new("user://test_prefs_table_win.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	check(win.view != null and win.dock != null and win._panes.size() == 6, "table window builds with six panes")
	var names := LayoutStore.names(win.dock.layout)
	for n in LayoutStore.TABLE_PANELS:
		check(names.has(n), "table layout holds the %s panel: %s" % [n, names])
	check(win.scene_select.disabled and win.ctx.scene_id == "", "a new encounter has no scene yet")
	win._open_path(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"))
	var ctx := win.ctx
	check(ctx.encounter().name == "Chapel Ambush" and ctx.state.maps.size() == 1, "opens the example and resolves its map")
	check(win.scene_select.item_count == 2 and win.scene_select.get_item_text(win.scene_select.selected).begins_with("●"), "scene dropdown lists both, active marked")
	check(win.scenes.list.item_count == 2 and win.tokens.tree.get_root().get_child_count() == 6, "scenes and tokens panels filled")
	check(win.turns.list.get_root().get_child_count() == 6 and win.turns.mode() == "ordered" and win.players.list.item_count == 2, "turns and players panels filled")
	check(win.viewpoint_select.item_count == 3, "viewpoints: the DM and two players")
	check(win.view.canvas.map != null and win.view.canvas.scene_id == ctx.scene_id, "the canvas shows the scene")
	check(app.recent().size() == 1, "opening notes the file as recent")
	# See as Ana, then back.
	var ana: Dictionary = ctx.encounter().players[0]
	win._set_viewpoint(str(ana.id))
	check(win.view.canvas.viewpoint == str(ana.id) and win.viewpoint_select.selected == 1, "viewpoint set")
	win._set_viewpoint("")
	# Inspector follows the selection and edits through commands.
	var tk: Dictionary = ctx.state.tokens(ctx.scene_id)[0]
	ctx.select_token(tk.id)
	check(win.inspector._title.text == tk.name and win.inspector._form.control("name") != null, "inspector shows the token")
	win.inspector._on_value("name", "Renamed")
	check(ctx.state.token(ctx.scene_id, tk.id).name == "Renamed" and ctx.history.undo_label() != "", "inspector edit is a command")
	win.inspector._on_value("owner", "(the DM)")
	check(not ctx.state.token(ctx.scene_id, tk.id).has("owner"), "owner (the DM) clears the owner")
	win.inspector._on_value("owner", "Ben")
	check(ctx.state.token(ctx.scene_id, tk.id).owner == ctx.encounter().players[1].id, "owner by name")
	win.inspector._on_value("tags", "prone, marked")
	check(ctx.state.token(ctx.scene_id, tk.id).tags == ["prone", "marked"], "tags parsed")
	var door := _door_of(win.ctx)
	ctx.select_element("walls", door.id)
	check(win.inspector._title.text.begins_with("Door") and win.inspector._form.control("state") != null, "inspector shows a door")
	win.inspector._on_value("state", "locked")
	check(ctx.state.effective(ctx.scene_id, "walls", door).state == "locked", "door state from the inspector")
	check(win.inspector._buttons.get_child_count() == 1, "an overridden element offers 'As drawn'")
	(win.inspector._buttons.get_child(0) as Button).pressed.emit()
	check(ctx.state.override_of(ctx.scene_id, "walls:" + door.id).is_empty(), "'As drawn' resets it")
	# Menus: scene switch, fog toggle, initiative.
	win._on_menu(win.S_FOG)
	check(not ctx.state.fog_enabled(ctx.scene_id), "Scene → Fog toggles")
	win._on_menu(win.S_FOG)
	win._on_menu(win.T_START)
	win._on_menu(win.T_NEXT)
	check(ctx.encounter().turns.running and ctx.encounter().turns.turn == 1, "Turns menu")
	win._on_menu(win.T_DM)
	check(win.turns.mode() == "dm" and win.turns.list.get_root().get_child_count() == 6 and win.turns.list.get_root().get_first_child().get_cell_mode(2) == TreeItem.CELL_MODE_CHECK, "DM-picks mode lists tokens with a tick")
	win._on_menu(win.T_FREE)
	check(win.turns.mode() == "free" and win.turns.list.get_root().get_child_count() == 0 and not win.turns._ordered_row.visible, "free mode has nothing to arrange")
	win._on_menu(win.T_ORDERED)
	win.scene_select.select(1)
	win.scene_select.item_selected.emit(1)
	check(ctx.level().id == "crypt" and win.view.canvas.level().id == "crypt", "scene dropdown switches the canvas")
	win._on_menu(win.M_SELECT_ALL)
	check(ctx.selected_token_ids().size() == 1, "select all tokens on the crypt")
	# Tool switching by key and the token options row.
	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.pressed = true
	win._unhandled_key_input(ev)
	check(win.view.tool is TableTools.TokenTool and win.tool_options.visible, "T picks the token tool and shows its options")
	ev.keycode = KEY_ESCAPE
	win._unhandled_key_input(ev)
	check(win.view.tool is TableTools.SelectTool and not win.tool_options.visible, "Esc back to select")
	# Save to a temp path, reload, same document.
	var path := ProjectSettings.globalize_path("user://test_table_save.encounter")
	win._save_to(path)
	check(FileAccess.file_exists(path) and not ctx.encounter().dirty, "saved")
	var back := Encounter.load_file(path)
	check(back != null and back.scene(ctx.scene_id).tokens.size() == 1, "reloads")
	DirAccess.remove_absolute(path)
	# Adding a scene through the same path the dialog uses.
	var m := _chapel()
	var scene := Encounter.new_scene(m, "ground", "Again", "ruined_chapel.hexmap")
	ctx.state.attach_map(m)
	ctx.commands.add_scene(scene, false)
	ctx.set_scene(str(scene.id))
	check(win.scene_select.item_count == 3 and win.scenes.list.item_count == 3 and win.view.canvas.level().id == "ground", "added scene shows everywhere")
	win.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_table_win.json"))


func test_canvas_view_touch() -> void:
	var view := CanvasView.new()
	view.size = Vector2(800, 600)
	root.add_child(view)
	var m := HexMap.create("T", HexGrid.new())
	view.canvas.map = m
	view.canvas.packs = PackLibrary.new()
	view.set_zoom(1.0)
	var presses := []
	var handler := RefCounted.new()
	handler.set_meta("x", 1)
	# A handler with only press/release; the view must cope with missing methods.
	var h := TouchProbe.new()
	view.set_handler(h)
	var t1 := InputEventScreenTouch.new()
	t1.index = 0
	t1.pressed = true
	t1.position = Vector2(300, 300)
	view._gui_input(t1)
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.pressed = true
	t2.position = Vector2(500, 300)
	view._gui_input(t2)
	var z0 := view.zoom()
	var d := InputEventScreenDrag.new()
	d.index = 1
	d.position = Vector2(700, 300)
	d.relative = Vector2(200, 0)
	view._gui_input(d)
	check(view.zoom() > z0 * 1.5, "spreading two fingers zooms in (%.2f → %.2f)" % [z0, view.zoom()])
	var cam := view.camera.position
	var d0 := InputEventScreenDrag.new()
	d0.index = 0
	d0.position = Vector2(350, 350)
	d0.relative = Vector2(50, 50)
	var d1 := InputEventScreenDrag.new()
	d1.index = 1
	d1.position = Vector2(750, 350)
	d1.relative = Vector2(50, 50)
	view._gui_input(d0)
	view._gui_input(d1)
	check(view.camera.position != cam, "two fingers moving together pan")
	# A mouse event during a pinch is ignored.
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(400, 300)
	view._gui_input(mb)
	check(h.presses == 0, "mouse ignored while pinching")
	t1.pressed = false
	t2.pressed = false
	view._gui_input(t1)
	view._gui_input(t2)
	view._gui_input(mb)
	check(h.presses == 1, "after the pinch, presses reach the handler")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(400, 300)
	var z1 := view.zoom()
	view._gui_input(wheel)
	check(view.zoom() > z1, "wheel zooms")
	view.queue_free()
	await process_frame


class TouchProbe extends RefCounted:
	var presses := 0
	func press(_p: Vector2, _b: int, _m: Dictionary) -> bool:
		presses += 1
		return true


func test_turn_system_plugin() -> void:
	# A game system registers its own ordering; the encounter stores its
	# state without understanding it, and forgets nothing if it is missing.
	var sys := RollSystem.new()
	TurnSystem.register(sys)
	check(TurnSystem.get_system("roll") == sys and TurnSystem.all_systems().size() == 2 and TurnSystem.all_systems()[0].id == "list", "registered; the list system stays first")
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var c := EncounterCommands.new(st, History.new())
	c.start_turns(sid, "roll")
	var turns := st.encounter.turns
	check(turns.system == "roll" and turns.order.size() == 2 and turns.data.has("rolls"), "the plugin ordered the tokens and kept its rolls")
	check(turns.order[0] == parts[3] and turns.order[1] == parts[2], "ordered by the plugin's rule (goblin first)")
	check(sys.label(turns, parts[3]) == "20" and sys.label(turns, parts[2]) == "5", "labels come from the plugin's data")
	c.next_turn()
	check(turns.turn == 1 and turns.data.stepped == 1, "next goes through the plugin")
	var text := st.encounter.to_json()
	TurnSystem.unregister("roll")
	var back := Encounter.from_json(text)
	check(back.turns.system == "roll" and back.turns.data.rolls.size() == 2, "the plugin's state survives without the plugin")
	var st2 := EncounterState.new(back)
	check(EncounterCommands.new(st2, History.new()).next_turn() == "" and back.turns.turn == 0 and back.turns.round == 2, "without the plugin, the list system steps the stored order")
	check(TurnSystem.get_system("roll").label(back.turns, parts[3]) == "20", "labels are data, so a client without the plugin still shows them")
	c.history.clear()


class RollSystem extends TurnSystem:
	func _init() -> void:
		id = "roll"
		name = "Roll test"
	func build_order(state: EncounterState, scene_id: String) -> Dictionary:
		var rolls := {}
		var order := []
		for t in state.tokens(scene_id):
			rolls[str(t.id)] = 20 if str(t.name) == "Goblin" else 5
			order.append(str(t.id))
		order.sort_custom(func(a, b) -> bool: return rolls[a] > rolls[b])
		var labels := {}
		for id in rolls:
			labels[id] = str(rolls[id])
		return {"order": order, "data": {"rolls": rolls, "labels": labels, "stepped": 0}}
	func next(turns: Dictionary) -> Dictionary:
		var ch := super(turns)
		var data: Dictionary = (turns.get("data", {}) as Dictionary).duplicate(true)
		data.stepped = int(data.get("stepped", 0)) + 1
		ch["data"] = data
		return ch


# -------------------------------------------------------------------- player --

func test_local_session() -> void:
	var src := ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter")
	var path := ProjectSettings.globalize_path("user://test_session.encounter")
	# Copy beside the map so map_path resolves: point at the examples dir instead.
	var s := LocalSession.new(src, "nobody")
	var told := []
	s.status.connect(func(t: String) -> void: told.append(t))
	check(s.open() == "" and s.state != null and s.warnings.is_empty(), "opens the example and finds its map")
	check(told.size() == 1 and told[0].contains("no player"), "an unknown player id is reported")
	var ana: Dictionary = s.state.encounter.players[0]
	s.player_id = str(ana.id)
	check(s.player_name() == "Ana" and s.my_tokens().size() == 1 and s.scene_id() == s.state.encounter.active_scene_id, "player, tokens, scene")
	var sid := s.scene_id()
	var fighter: Dictionary = s.my_tokens()[0]
	var gob: Dictionary = s.state.tokens(sid)[2]
	var mv := {"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [1, 1]}}
	check(s.request(mv) == "Turns have not begun" and s.turn_summary() == "Waiting to begin", "ordered, not running: refused with a reason")
	s.state.apply({"t": "turns.set", "changes": {"running": true, "turn": 2}})
	check(s.request(mv) == "Not your turn" and s.turn_summary().begins_with("Goblin's turn"), "someone else's turn")
	s.state.apply({"t": "turns.set", "changes": {"turn": 0}})
	check(s.turn_summary().begins_with("Your turn: Ana's fighter") and s.request(mv) == "", "her turn: the move goes through")
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == Vector2(1, 1), "applied to the local copy")
	s.state.apply({"t": "turns.set", "changes": {"mode": "dm", "active": []}})
	check(s.request(mv) == "The DM has not given you the move" and s.turn_summary() == "Waiting for the DM", "dm mode, not ticked")
	s.state.apply({"t": "turns.set", "changes": {"active": [fighter.id]}})
	check(s.request(mv) == "" and s.turn_summary() == "You may move: Ana's fighter", "dm mode, ticked")
	s.state.apply({"t": "turns.set", "changes": {"mode": "free"}})
	check(s.turn_summary() == "Free movement", "free")
	check(s.request({"t": "token.set", "scene": sid, "id": gob.id, "changes": {"pos": [1, 1]}}) == "You cannot move that", "a hidden token is refused even in free mode")
	check(s.request({"t": "element.set", "scene": sid, "ref": "walls:x", "changes": {"state": "open"}}) == "Only the DM can do that", "non-move events are for the DM")
	check(s.request({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"hidden": true}}) == "You cannot move that", "other fields are refused")
	check(s.request({"t": "token.set", "scene": sid, "id": "zz", "changes": {"pos": [0, 0]}}) == "No such token", "unknown token")
	# The file changing on disk reloads the state; a missing file closes.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src).replace('"name": "Chapel Ambush"', '"name": "Copy"'))
	f.close()
	var s2 := LocalSession.new(path, str(ana.id))
	check(s2.open() == "" and s2.state.encounter.name == "Copy", "opens a copy (its map warning is fine: %s)" % [s2.warnings])
	var changes := []
	s2.changed.connect(func(w: String, _sc: String) -> void: changes.append(w))
	s2.poll()
	check(changes.is_empty(), "unchanged file: no reload")
	OS.delay_msec(1100)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src).replace('"name": "Chapel Ambush"', '"name": "Saved again"'))
	f.close()
	s2.tick(0.5)
	check(changes.is_empty(), "tick below the poll interval does nothing")
	s2.tick(0.6)
	check(changes == [""] and s2.state.encounter.name == "Saved again", "a newer file is reloaded")
	var closed := []
	s2.closed.connect(func(r: String) -> void: closed.append(r))
	DirAccess.remove_absolute(path)
	s2.poll()
	check(closed.size() == 1 and s2.path == "", "a vanished file closes the session")
	check(Session.new().request({}) == "no session" and Session.new().turn_summary() == "" and Session.new().player_name() == "the DM", "the base session is inert")


func test_player_tool() -> void:
	var s := LocalSession.new(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"), "")
	s.open()
	s.player_id = str(s.state.encounter.players[0].id)
	s.state.apply({"t": "turns.set", "changes": {"mode": "free"}})
	var canvas := MapCanvas.new()
	canvas.packs = PackLibrary.new()
	canvas.set_scene(s.state, s.scene_id())
	var tool := PlayerTools.MoveTool.new(s, canvas)
	var sid := s.scene_id()
	var fighter: Dictionary = s.my_tokens()[0]
	var ranger: Dictionary = s.state.tokens(sid)[1]
	var from := Vision.token_pos(fighter)
	var mods := {}
	check(tool.token_at(from).id == fighter.id and tool.token_at(Vision.token_pos(ranger)).is_empty(), "only my own tokens can be picked up")
	check(not tool.press(Vision.token_pos(ranger), MOUSE_BUTTON_LEFT, mods) and tool.selected == "", "pressing another's token does nothing")
	check(tool.press(from, MOUSE_BUTTON_LEFT, mods) and tool.selected == fighter.id, "press picks mine")
	tool.drag(from + Vector2(0.03, 0.02), MOUSE_BUTTON_LEFT, mods)
	tool.release(from + Vector2(0.03, 0.02), MOUSE_BUTTON_LEFT, mods)
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == from and tool.selected == fighter.id, "a wobble is a tap: no move, still selected")
	var g := canvas.map.grid
	var to := g.cell_center(g.world_to_axial(from) + Vector2i(1, 0))
	tool.press(from, MOUSE_BUTTON_LEFT, mods)
	tool.drag(to + Vector2(0.1, 0.05), MOUSE_BUTTON_LEFT, mods)
	check(tool._moved, "a real drag")
	tool.release(to + Vector2(0.1, 0.05), MOUSE_BUTTON_LEFT, mods)
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == to, "released on the snapped centre")
	var told := []
	s.status.connect(func(t: String) -> void: told.append(t))
	s.state.apply({"t": "turns.set", "changes": {"mode": "ordered", "running": true, "turn": 2}})
	tool.press(to, MOUSE_BUTTON_LEFT, mods)
	tool.drag(from, MOUSE_BUTTON_LEFT, mods)
	tool.release(from, MOUSE_BUTTON_LEFT, mods)
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == to and told == ["Not your turn"], "a refused move stays put and the player is told")
	check(not tool.press(Vector2(0.1, 0.1), MOUSE_BUTTON_LEFT, mods) and tool.selected == "", "tapping empty ground deselects")
	canvas.free()


func test_player_window() -> void:
	var app := App.new("user://test_prefs_player.json")
	var win := PlayerWindow.new()
	win.app = app
	root.add_child(win)
	check(win.screen == "join" and win._files.item_count >= 1, "starts on the join screen with the example listed")
	win._join_address()
	check((win._join.find_child("JoinStatus", true, false) as Label).text.begins_with("Type the address"), "joining an empty address asks for one")
	win._choose_file("/nowhere/x.encounter")
	check(win.screen == "join" and (win._join.find_child("JoinStatus", true, false) as Label).text.begins_with("Could not open"), "a bad file is reported")
	var path := ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter")
	win.open_argument("examples/chapel_ambush.encounter")
	check(win.screen == "pick" and win._players.item_count == 2 and win._pick_title.text == "Chapel Ambush", "a relative path from the shell reaches the player picker")
	win._start(str(win._players.get_item_metadata(1)))
	check(win.screen == "play" and win.session is LocalSession and win.session.player_name() == "Ben", "playing as Ben")
	check(win.view.canvas.viewpoint == win.session.player_id and win.view.canvas.scene_id == win.session.scene_id() and win.view.canvas.map != null, "the canvas shows the scene through Ben")
	check(win.view.canvas.tokens_in_view().size() == 2 and not win.view.canvas.show_hidden, "party visible, goblins not")
	check(win._token_bar.get_child_count() == 1 and (win._token_bar.get_child(0) as Button).text == "BR", "one token button, his ranger")
	check(win._turn.text == "Waiting to begin" and win._title.text.contains("Chapel at dusk"), "bars filled")
	check(app.recent().has(path), "noted as recent")
	# The DM switches the shown scene: the player follows.
	var st: EncounterState = win.session.state
	var crypt := str(st.encounter.scenes[1].id)
	st.apply({"t": "scene.activate", "id": crypt})
	check(win.view.canvas.scene_id == crypt and win.view.canvas.level().id == "crypt" and win._token_bar.get_child_count() == 0, "follows the active scene; no tokens of his there")
	st.apply({"t": "scene.activate", "id": str(st.encounter.scenes[0].id)})
	# Turn changes update the bar; his token lights up when it is his turn.
	st.apply({"t": "turns.set", "changes": {"mode": "ordered", "running": true, "turn": 1}})
	check(win._turn.text.begins_with("Your turn: Ben's ranger") and (win._token_bar.get_child(0) as Button).theme_type_variation == "AccentButton", "his turn shows on the bar and the button")
	# Focus a token, status messages fade, leave.
	var ranger: Dictionary = win.session.my_tokens()[0]
	win._focus_token(ranger.id)
	check(win.tool.selected == ranger.id and win.view.camera.position == Vision.token_pos(ranger) * win.view.canvas.ppx, "focus centres and selects")
	win._say("hello")
	check(win._status.text == "hello", "status shown")
	win._process(5.0)
	check(win._status.text == "", "and fades")
	win._leave()
	check(win.screen == "join" and win.session == null and win.view.canvas.state == null, "leave returns to join")
	win._stop_browsing()   # free the discovery port now; queue_free waits for the frame
	win.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_player.json"))


# ----------------------------------------------------------------------- net --

## Pump host and client until `done` says so, or give up.
func _pump(host: HostSession, clients: Array, done: Callable, max_ms := 4000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		host.poll(0.016)
		for c in clients:
			(c as NetSession).poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func test_protocol() -> void:
	check(Protocol.decode(Protocol.encode({"t": "ping"})) == {"t": "ping"}, "encode/decode")
	check(Protocol.decode("[1]").is_empty() and Protocol.decode("{}").is_empty() and Protocol.decode("nope").is_empty(), "not messages")
	check(Protocol.parse_address("192.168.1.4") == ["192.168.1.4", Protocol.DEFAULT_PORT], "bare host")
	check(Protocol.parse_address(" ws://table.local:5000/ ") == ["table.local", 5000], "url with port")
	check(Protocol.parse_address("10.0.0.2:abc") == ["10.0.0.2:abc", Protocol.DEFAULT_PORT], "a non-number is part of the host")
	var a := Protocol.parse_announcement(Protocol.encode(Protocol.announcement("Chapel", 47777, "mac")))
	check(a.name == "Chapel" and int(a.port) == 47777 and a.host == "mac", "announcement round trip")
	check(Protocol.parse_announcement('{"hexmap": 99, "name": "x", "port": 1}').is_empty() and Protocol.parse_announcement("junk").is_empty(), "other versions and junk ignored")
	var b := Discovery.Browser.new()
	var updates := []
	b.updated.connect(func() -> void: updates.append(1))
	check(b.heard({"name": "A", "port": 1}, "10.0.0.1") and not b.heard({"name": "A", "port": 1}, "10.0.0.1"), "heard: new then repeat")
	check(b.heard({"name": "A", "port": 1}, "10.0.0.2") and b.list().size() == 2, "same name, other host: another table")
	check(b.heard({"name": "B", "port": 1}, "10.0.0.1") and b.list()[0].name == "A" and b.list()[1].name == "B", "renamed; list sorted by name")


func test_discovery_loopback() -> void:
	# Best effort: multicast on this machine's loopback. Skipped, not
	# failed, where the OS or CI runner does not route it.
	var browser := Discovery.Browser.new()
	if browser.start() != OK:
		print("  (skipped: cannot bind the discovery port)")
		return
	var ann := Discovery.Announcer.new()
	check(ann.start("Loopback table", 47777) == OK, "announcer starts")
	var heard := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500 and not heard:
		ann.announce()
		OS.delay_msec(50)
		browser.poll(0.05)
		for t in browser.list():
			if str(t.name) == "Loopback table":
				heard = true
	if heard:
		check(int(browser.list()[0].port) == 47777, "the announced port is what the browser lists")
		print("  discovery over loopback works")
	else:
		print("  (skipped: no multicast on loopback here)")
	ann.stop()
	browser.stop()


func test_host_and_net_session() -> void:
	var packs := PackLibrary.new()
	packs.reload()
	var e := Encounter.load_file(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"))
	var st := EncounterState.new(e)
	st.resolve_maps()
	var history := History.new()
	var cmds := EncounterCommands.new(st, history)
	var host := HostSession.new(st, packs)
	var applied := []
	host.apply_request = func(ev: Dictionary, pid: String) -> String:
		applied.append(pid)
		return cmds.run(ev, "Player move")
	var joined := []
	host.client_joined.connect(func(p: String) -> void: joined.append(p))
	check(host.start(0, false) == OK and host.port > 0 and host.is_running(), "host listens on a free port (%d)" % host.port)
	# A client with its own pack library pointed at a scratch cache.
	var cache := "user://packs_test"
	var cpacks := PackLibrary.new()
	cpacks.reload()
	var client := NetSession.new("127.0.0.1", host.port, cpacks, "test client")
	client.cache_dir = cache
	var told := []
	client.status.connect(func(t: String) -> void: told.append(t))
	var closed := []
	client.closed.connect(func(r: String) -> void: closed.append(r))
	check(client.connect_to_host() == OK, "client connects")
	check(_pump(host, [client], func() -> bool: return client.state != null and client.maps_ready()), "welcome and maps arrive")
	check(client.state.encounter.name == "Chapel Ambush" and client.state.maps.size() == 1 and client.state.map_for(client.scene_id()).name == "Ruined Chapel", "the client has the encounter and its map")
	check(host.client_count() == 1 and host.connected_players().is_empty(), "connected, not yet joined")
	var ana: Dictionary = e.players[0]
	var sid := e.active_scene_id
	var fighter: Dictionary = st.tokens_owned_by(sid, str(ana.id))[0]
	var mv := {"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [1.5, 1.5]}}
	check(client.request(mv) == "Not joined yet", "requests need a join")
	client.join("pl_nobody")
	check(_pump(host, [client], func() -> bool: return told.has("no such player")), "an unknown player is refused")
	client.join(str(ana.id))
	check(_pump(host, [client], func() -> bool: return client.joined), "joined as Ana")
	check(joined == [str(ana.id)] and host.connected_players() == [str(ana.id)], "the host says so too")
	# The example is ordered-not-running: the client refuses locally with the reason, nothing is sent.
	check(client.request(mv) == "Turns have not begun" and applied.is_empty(), "pre-checked locally")
	cmds.set_turn_mode("free")
	check(_pump(host, [client], func() -> bool: return client.state.encounter.turns.mode == "free"), "the host's change reached the client as an event")
	check(client.request(mv) == "", "in free mode the request goes out")
	check(_pump(host, [client], func() -> bool: return Vision.token_pos(client.state.token(sid, fighter.id)) == Vector2(1.5, 1.5)), "applied at the host and echoed back")
	check(applied == [str(ana.id)] and history.undo_label() == "Player move" and Vision.token_pos(st.token(sid, fighter.id)) == Vector2(1.5, 1.5), "the host applied it through the table's commands, undoably")
	check(client.state.encounter.to_json() == st.encounter.to_json(), "host and client documents are identical")
	history.undo()
	check(_pump(host, [client], func() -> bool: return Vision.token_pos(client.state.token(sid, fighter.id)) != Vector2(1.5, 1.5)), "the DM's undo reaches the client")
	check(client.state.encounter.to_json() == st.encounter.to_json(), "still identical after undo")
	# A second client, as Ben, sees Ana's next move.
	var client2 := NetSession.new("127.0.0.1", host.port, cpacks, "second")
	client2.cache_dir = cache
	client2.connect_to_host()
	check(_pump(host, [client, client2], func() -> bool: return client2.state != null and client2.maps_ready()), "second client welcomed")
	client2.join(str(e.players[1].id))
	check(_pump(host, [client, client2], func() -> bool: return client2.joined), "Ben joined")
	client.request({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [2.5, 2.5]}})
	check(_pump(host, [client, client2], func() -> bool: return Vision.token_pos(client2.state.token(sid, fighter.id)) == Vector2(2.5, 2.5)), "Ben sees Ana's move")
	# A tampered request: the host refuses what allowed() forbids.
	client2._send({"t": "request", "ev": {"t": "element.set", "scene": sid, "ref": "walls:x", "changes": {"state": "open"}}})
	var told2 := []
	client2.status.connect(func(t: String) -> void: told2.append(t))
	check(_pump(host, [client, client2], func() -> bool: return told2.has("not allowed")), "the host refuses a forged request")
	# Packs: the client pretends it lacks the swamp pack and gets it streamed.
	cpacks.packs.erase("swamp")
	(st.maps.values()[0] as HexMap).doc.packs["swamp"] = "0.1.0"
	var ready := []
	client.assets_ready.connect(func() -> void: ready.append(1))
	client._send({"t": "need", "kind": "packs"})
	check(_pump(host, [client, client2], func() -> bool: return not ready.is_empty(), 8000), "pack files streamed")
	var cdir := ProjectSettings.globalize_path(cache.path_join("swamp"))
	check(FileAccess.file_exists(cdir.path_join("pack.json")) and FileAccess.file_exists(cdir.path_join("props/witch_hut.svg")), "files landed in the cache")
	check(FileAccess.get_file_as_bytes(cdir.path_join("props/witch_hut.svg")) == FileAccess.get_file_as_bytes(packs.pack_dir("swamp").path_join("props/witch_hut.svg")), "byte-identical")
	check(client.assets_pending() == 0, "nothing pending")
	# Path traversal is refused.
	client._send({"t": "need", "kind": "file", "pack": "swamp", "file": "../../project.godot"})
	check(_pump(host, [client, client2], func() -> bool: return told.any(func(t: String) -> bool: return t.begins_with("no file"))), "traversal refused")
	# Leaving and stopping.
	client2.leave()
	check(_pump(host, [client], func() -> bool: return host.client_count() == 1), "a client that leaves is dropped")
	host.stop()
	check(_pump(host, [client], func() -> bool: return not closed.is_empty()), "stopping the host closes the client (%s)" % [closed])
	check(not host.is_running(), "host stopped")
	# Clean the cache.
	for f in ["props/witch_hut.svg", "pack.json"]:
		DirAccess.remove_absolute(cdir.path_join(f))
	_rm_tree(cdir)
	history.clear()


func _rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in d.get_directories():
		_rm_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func test_table_hosts_player_joins() -> void:
	var app := App.new("user://test_prefs_net.json")
	var table := TableWindow.new()
	table.app = app
	root.add_child(table)
	table._open_path(ProjectSettings.globalize_path("res://examples/chapel_ambush.encounter"))
	table.ctx.commands.set_turn_mode("free")
	table._set_hosting(true)
	check(table.host != null and table.host.is_running() and table.host_button.button_pressed, "the table hosts")
	check(table.host_address().ends_with(":%d" % table.host.port), "and shows an address: %s" % table.host_address())
	var player := PlayerWindow.new()
	player.app = app
	root.add_child(player)
	check(player.screen == "join", "player on the join screen")
	var pump := func(done: Callable, max_ms := 4000) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < max_ms:
			table._process(0.05)
			player._process(0.05)
			if done.call():
				return true
			OS.delay_msec(10)
		return false
	# Discovery (where loopback multicast works) or the typed address.
	var found: bool = player._browsing and pump.call(func() -> bool: return player._tables.item_count > 0, 2500)
	if found:
		print("  found the table by discovery: %s" % player._tables.get_item_text(0))
		check(str(player._tables.get_item_text(0)).begins_with("Chapel Ambush"), "discovered table is named")
		player._tables.item_selected.emit(0)
	else:
		print("  (no discovery on loopback here; using the address)")
		player._address.text = "127.0.0.1:%d" % table.host.port
		player._join_address()
	check(player.session is NetSession, "connecting")
	check(pump.call(func() -> bool: return player.screen == "pick"), "welcomed: the player picker shows")
	check(player._players.item_count == 2 and player._pick_title.text == "Chapel Ambush", "players listed from the table's document")
	player._start(str(player._players.get_item_metadata(0)))
	check(pump.call(func() -> bool: return player.screen == "play" and player.view.canvas.map != null), "joined as Ana and the map arrived")
	check(table.players.online.size() == 1 and table.players.list.get_item_text(0).begins_with("●"), "the table shows Ana online")
	check(player.view.canvas.tokens_in_view().size() == 2, "Ana sees the party")
	# Ana moves her fighter; the table applies it as an undoable step and the DM sees it.
	var sid := player.session.scene_id()
	var fighter: Dictionary = player.session.my_tokens()[0]
	var from := Vision.token_pos(fighter)
	var g := player.view.canvas.map.grid
	var to := g.cell_center(g.world_to_axial(from) + Vector2i(1, 0))
	var mods := {"shift": false, "ctrl": false, "alt": false}
	player.tool.press(from, MOUSE_BUTTON_LEFT, mods)
	player.tool.drag(to, MOUSE_BUTTON_LEFT, mods)
	player.tool.release(to, MOUSE_BUTTON_LEFT, mods)
	check(pump.call(func() -> bool: return Vision.token_pos(table.ctx.state.token(sid, fighter.id)) == to), "the table got the move")
	check(table.ctx.history.undo_label().begins_with("Ana moves"), "as one labelled undo step: %s" % table.ctx.history.undo_label())
	check(pump.call(func() -> bool: return Vision.token_pos(player.session.state.token(sid, fighter.id)) == to), "echoed to the player")
	check(table.ctx.state.explored(sid).size() >= 88, "the move explored fog at the table")
	# The DM opens the door and switches turn mode; the player is told.
	var door := _door_of(table.ctx)
	table.ctx.commands.set_door(sid, door.id, "open")
	table.ctx.commands.set_turn_mode("ordered")
	table.ctx.commands.start_turns(sid)
	check(pump.call(func() -> bool: return player.session.state.effective(sid, "walls", door).state == "open" and player.session.state.encounter.turns.running), "door and turns reached the player")
	check(player._turn.text.begins_with("Your turn: Ana's fighter"), "the player's bar says it is her turn")
	check(player.session.state.encounter.to_json() == table.ctx.state.encounter.to_json(), "documents identical across the wire")
	# Leaving and stopping.
	player._leave()
	check(pump.call(func() -> bool: return table.players.online.is_empty()), "the table sees her leave")
	table._set_hosting(false)
	check(table.host == null and not table.host_button.button_pressed, "hosting stopped")
	player._stop_browsing()
	player.queue_free()
	table.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_net.json"))
