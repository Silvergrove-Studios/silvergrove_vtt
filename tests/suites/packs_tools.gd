extends TestCase
## Packs, editor commands and tools.


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
	# square-cell art: its own variants, square, opaque to the corners
	check(grass.textures_square.size() == 3 and lib.terrain_has_square_art("woodland:grass"), "grass ships square variants")
	var sq := lib.terrain_texture("woodland:grass", 1, 100, "square")
	check(sq != tex and sq.get_width() == sq.get_height(), "a square texture for square cells: %dx%d" % [sq.get_width(), sq.get_height()])
	var sq_img: Image = sq.get_image()
	sq_img = sq_img.duplicate()
	sq_img.convert(Image.FORMAT_RGBA8)
	check(sq_img.get_pixel(1, 1).a > 0.9 and sq_img.get_pixel(sq_img.get_width() - 2, sq_img.get_height() - 2).a > 0.9, "opaque to its corners")
	check(lib.terrain_texture("woodland:grass", 1, 100, "hex") == tex, "hex asks get the hex art")
	var only_hex := {"id": "solo", "name": "Solo", "color": "#123456", "textures": ["terrain/grass_1.svg"], "fit": "hex"}
	lib.packs.woodland.terrains.append(only_hex)
	check(not lib.terrain_has_square_art("woodland:solo") and lib.terrain_texture("woodland:solo", 0, 100, "square") == lib.terrain_texture("woodland:solo", 0, 100, "hex"), "a terrain without square art falls back to its hex art (the renderer crops it)")
	lib.packs.woodland.terrains.erase(only_hex)
	# Every texture in every manifest exists and rasterises.
	var bad := 0
	for pid in lib.pack_ids():
		var p: Dictionary = lib.packs[pid]
		for t in p.terrains:
			for f in t.textures + t.get("textures_square", []):
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
