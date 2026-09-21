extends TestCase
## Exporters (UVTT, Foundry, Tiled, PDF layout, SVG).


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


func test_square_grid_exports() -> void:
	var m := _sample_map()
	m.grid = HexGrid.square(6, 4)
	m.doc.grid = m.grid.to_dict()
	# Foundry: a SQUARE scene whose pixel size is columns × rows × size
	var s := FoundryExport.build(m, 0, 100, "sample.webp")
	check(s.grid.type == 1 and s.width == 600 and s.height == 400, "Foundry SQUARE scene %s %dx%d" % [s.grid.type, s.width, s.height])
	# Tiled: orthogonal, square tiles, no stagger keys
	var t: Dictionary = TiledExport.build(m, 0, 100).map
	check(t.orientation == "orthogonal" and t.tilewidth == 100 and t.tileheight == 100, "Tiled orthogonal %s %dx%d" % [t.orientation, t.tilewidth, t.tileheight])
	check(not t.has("staggeraxis") and not t.has("hexsidelength"), "no hex keys on an orthogonal map")
	check(t.layers[0].data.size() == 24 and t.layers[0].data[0] == 1 and t.layers[0].data[1] == 2 and t.layers[0].data[6] == 3, "cells in row-major order: %s" % [t.layers[0].data.slice(0, 8)])
	# UVTT: the format is square-native; the map size is exact
	var u := UvttExport.build(m, 0, 200, "PNG".to_utf8_buffer())
	check(u.resolution.map_size.x == 6 and u.resolution.map_size.y == 4 and u.hexmap_grid.shape == "square", "UVTT map size %s" % [u.resolution.map_size])
	# SVG: four-cornered polygons, one per cell
	var svg := SvgExport.overlay(m, 0, 100.0)
	check(svg.count("<polygon") == 24, "one polygon per cell: %d" % svg.count("<polygon"))
	var first := svg.substr(svg.find("<polygon"), 120)
	check(first.substr(0, first.find("/>")).count(",") == 4, "a square has four corners: %s" % first)
	var probe := Image.new()
	check(probe.load_svg_from_string(svg) == OK and probe.get_width() == 600, "Godot's SVG loader accepts it (%d px wide)" % probe.get_width())
	# Tiled tile images on a square grid crop hex-shaped art to the square
	# inside the hexagon: no transparent corners on a square tile
	var packs := PackLibrary.new()
	packs.reload()
	var tex := packs.terrain_texture("woodland:grass", 0, 64.0)
	if tex != null:
		var img: Image = tex.get_image().duplicate()
		img.convert(Image.FORMAT_RGBA8)
		check(img.get_pixel(1, 1).a < 0.5, "hex art is transparent at its bounding box's corner")
		var k := HexGrid.INSCRIBED_SQUARE
		var w: int = img.get_width()
		var h: int = img.get_height()
		var cw := int(w * k)
		var ch := int(h * k / (2.0 * HexGrid.R))
		var inner := img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
		check(inner.get_pixel(0, 0).a > 0.5 and inner.get_pixel(cw - 1, ch - 1).a > 0.5 and inner.get_pixel(cw - 1, 0).a > 0.5, "the inscribed square is opaque at every corner")
	# PDF layout: 6 × 4 squares at 1" is one letter sheet
	var lay := PdfExport.layout(m.grid.map_size(), {"paper": "letter", "hex_size_in": 1.0})
	check(lay.pages.size() == 1 and lay.pages[0].region_pt.size == Vector2(6 * 72, 4 * 72), "one sheet, exact size")


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
