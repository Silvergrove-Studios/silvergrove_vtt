extends SceneTree
## godot --headless -s tools/make_examples.gd — write the example maps under
## examples/. Deterministic, so they can be regenerated after format changes.
## Also exercises the model the way the editor does, which makes it a decent
## smoke test on its own.

var rng := RandomNumberGenerator.new()
var packs := PackLibrary.new()


func _init() -> void:
	rng.seed = 20260919
	packs.reload()
	seed(20260919)   # HexMap.new_id uses the global RNG; keep ids stable too
	var dir := ProjectSettings.globalize_path("res://examples")
	DirAccess.make_dir_recursive_absolute(dir)
	_save(_forest_road(), dir.path_join("forest_road.hexmap"))
	_save(_bog_crossing(), dir.path_join("bog_crossing.hexmap"))
	var chapel := _ruined_chapel()
	_save(chapel, dir.path_join("ruined_chapel.hexmap"))
	_save_encounter(_chapel_ambush(chapel), dir.path_join("chapel_ambush.encounter"))
	# Last, so the older examples keep their random draws.
	_save(_cellar(), dir.path_join("cellar.hexmap"))
	print("examples written")
	quit(0)


func _save(m: HexMap, path: String) -> void:
	m.doc.meta.created = "2026-09-19T00:00:00"
	m.doc.meta.modified = "2026-09-19T00:00:00"
	m.doc.meta.author = "Silvergrove Studios"
	var err := m.save(path)
	print(path, " ", "ok" if err == OK else error_string(err))


func _save_encounter(e: Encounter, path: String) -> void:
	e.doc.meta.created = "2026-09-19T00:00:00"
	e.doc.meta.modified = "2026-09-19T00:00:00"
	e.doc.meta.author = "Silvergrove Studios"
	var err := e.save(path)
	print(path, " ", "ok" if err == OK else error_string(err))


# ------------------------------------------------------------------- helpers --

func _cell(m: HexMap, lvl: Dictionary, cell: Vector2i, t: String, variants: int, rot := 0) -> void:
	if not m.grid.in_bounds(cell):
		return
	lvl.terrain[HexMap.cell_key(cell)] = {"t": t, "v": rng.randi() % variants, "rot": rot, "z": 0}


func _fill(m: HexMap, lvl: Dictionary, t: String, variants: int) -> void:
	for c in m.grid.all_cells():
		_cell(m, lvl, c, t, variants)


func _prop(lvl: Dictionary, asset: String, pos: Vector2, rot := 0.0, scale := 1.0, layer := "", extra := {}) -> Dictionary:
	var p := {"id": HexMap.new_id("p"), "asset": asset, "pos": [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001)],
		"rot": rot, "scale": scale, "flip": rng.randf() < 0.3, "z": 0, "height": 0.5, "hidden": false}
	# The legacy `layer` hint files the prop into the right default folder
	# when the map is saved (LayerTree.ensure migrates it).
	p["layer"] = layer if layer != "" else str(packs.prop(asset).get("layer", "objects"))
	for k in extra:
		p[k] = extra[k]
	lvl.props.append(p)
	return p


func _light(lvl: Dictionary, pos: Vector2, bright: float, dim: float, color: String, anim := "torch") -> void:
	lvl.lights.append({"id": HexMap.new_id("l"), "pos": [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001)], "z": 0.5,
		"bright": bright, "dim": dim, "color": color, "intensity": 1.0, "angle": 360, "direction": 0,
		"shadows": true, "animation": anim, "hidden": false})


func _wall(lvl: Dictionary, pts: Array, preset: String, style := "", extra := {}) -> void:
	var w: Dictionary = (EditorContext.WALL_PRESETS[preset] as Dictionary).duplicate(true)
	w["id"] = HexMap.new_id("w")
	var arr: Array = []
	for p in pts:
		arr.append([snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)])
	w["points"] = arr
	w["one_way"] = null
	w["z"] = [0, 1]
	if not w.has("state"):
		w["state"] = "closed"
	if not w.has("hidden"):
		w["hidden"] = false
	if style != "":
		w["style"] = style
	for k in extra:
		w[k] = extra[k]
	lvl.walls.append(w)


func _note(lvl: Dictionary, pos: Vector2, title: String, text: String) -> void:
	lvl.notes.append({"id": HexMap.new_id("n"), "pos": [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001)], "title": title, "text": text, "gm_only": true})


## Boundary of a set of cells as chained polylines along hex edges.
## Walls around `cells` with a door in one edge: the boundary is cut where
## the door goes, so opening it really opens the room.
func _room(lvl: Dictionary, grid: HexGrid, cells: Dictionary, style: String, door: Array, door_preset := "door") -> void:
	for chain in _cut(_boundary(grid, cells), door[0], door[1]):
		_wall(lvl, chain, "wall", style)
	_wall(lvl, door, door_preset)


## Remove the segment a-b (either direction) from the chains that hold it,
## splitting them; a chain that closes on itself is re-opened at the cut.
func _cut(chains: Array, a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	for chain in chains:
		var pts: Array = chain
		var at := -1
		for i in pts.size() - 1:
			var p: Vector2 = pts[i]
			var q: Vector2 = pts[i + 1]
			if (p.distance_to(a) < 0.01 and q.distance_to(b) < 0.01) or (p.distance_to(b) < 0.01 and q.distance_to(a) < 0.01):
				at = i
				break
		if at < 0:
			out.append(pts)
			continue
		var closed: bool = pts.size() > 2 and (pts[0] as Vector2).distance_to(pts[-1]) < 0.01
		if closed:
			# Rotate so the cut edge is the last one, then drop it: one open chain.
			var ring: Array = pts.slice(0, pts.size() - 1)
			var rotated: Array = ring.slice(at + 1) + ring.slice(0, at + 1)
			out.append(rotated)
		else:
			var first: Array = pts.slice(0, at + 1)
			var second: Array = pts.slice(at + 1)
			if first.size() >= 2:
				out.append(first)
			if second.size() >= 2:
				out.append(second)
	return out


func _boundary(grid: HexGrid, cells: Dictionary) -> Array:
	var edges: Array = []   # [a, b]
	for key in cells:
		var cell := HexMap.key_cell(key)
		var corners := grid.cell_corners(cell)
		var nbs := grid.neighbors(cell)
		# Neighbour k lies across the edge from corner k to k+1 for pointy
		# grids with our corner ordering; check by midpoint instead to be safe.
		var n := corners.size()
		for i in n:
			var a := corners[i]
			var b := corners[(i + 1) % n]
			var mid := (a + b) / 2.0
			var outward := mid + (mid - grid.cell_center(cell)) * 0.5
			var other := grid.world_to_axial(outward)
			if not cells.has(HexMap.cell_key(other)):
				edges.append([a, b])
	# Chain edges sharing endpoints.
	var chains: Array = []
	var used := {}
	var key_of := func(p: Vector2) -> String: return "%.3f,%.3f" % [p.x, p.y]
	var by_start := {}
	for i in edges.size():
		var k: String = key_of.call(edges[i][0])
		if not by_start.has(k):
			by_start[k] = []
		by_start[k].append(i)
	for i in edges.size():
		if used.has(i):
			continue
		used[i] = true
		var chain: Array = [edges[i][0], edges[i][1]]
		var guard := 0
		while guard < 10000:
			guard += 1
			var k: String = key_of.call(chain[-1])
			var next := -1
			for j in by_start.get(k, []):
				if not used.has(j):
					next = j
					break
			if next < 0:
				break
			used[next] = true
			chain.append(edges[next][1])
		chains.append(chain)
	return chains


func _line_cells(grid: HexGrid, pts: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in pts.size() - 1:
		for c in grid.line(grid.world_to_axial(pts[i]), grid.world_to_axial(pts[i + 1])):
			out.append(c)
	return out


# ------------------------------------------------------------------- maps --

func _forest_road() -> HexMap:
	var m := HexMap.create("Forest Road", HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 24, 16))
	m.doc.meta.description = "A woodland track with a camp beside a stream. Ambush country."
	m.note_pack("woodland", "0.1.0")
	var lvl := m.level(0)
	var g := m.grid
	_fill(m, lvl, "woodland:grass", 3)
	# Forest floor patches
	for c in g.all_cells():
		var p := g.cell_center(c)
		if p.y < 3.5 + sin(p.x * 0.7) * 1.2 or p.y > 11.5 + cos(p.x * 0.5) * 1.2:
			_cell(m, lvl, c, "woodland:forest_floor", 3)
		elif rng.randf() < 0.12:
			_cell(m, lvl, c, "woodland:tall_grass", 2)
	# Road
	var road := [Vector2(0.5, 8.0), Vector2(6, 7.2), Vector2(12, 8.4), Vector2(18, 7.6), Vector2(24, 8.2)]
	for c in _line_cells(g, road):
		_cell(m, lvl, c, "woodland:dirt_path", 2)
	# Stream crossing the road
	var stream := [Vector2(15, 0.3), Vector2(14.2, 5), Vector2(15.5, 9), Vector2(14.5, 14)]
	for c in _line_cells(g, stream):
		_cell(m, lvl, c, "woodland:shallow_stream", 2)
	for c in g.all_cells():
		var t: String = lvl.terrain[HexMap.cell_key(c)].t
		if t == "woodland:grass" and rng.randf() < 0.04:
			_cell(m, lvl, c, "woodland:rocky_ground", 2)
	# Trees in the forest bands
	for c in g.all_cells():
		var t: String = lvl.terrain[HexMap.cell_key(c)].t
		var p := g.cell_center(c) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		if t == "woodland:forest_floor" and rng.randf() < 0.55:
			_prop(lvl, ["woodland:oak", "woodland:oak_large", "woodland:pine", "woodland:birch"][rng.randi() % 4], p, rng.randf_range(0, 360), rng.randf_range(0.8, 1.15))
		elif t == "woodland:grass" and rng.randf() < 0.05:
			_prop(lvl, ["woodland:bush", "woodland:boulder_small", "woodland:stump"][rng.randi() % 3], p, rng.randf_range(0, 360))
	# Camp
	var camp := Vector2(8.5, 5.2)
	_prop(lvl, "woodland:campfire", camp)
	_light(lvl, camp, 1.5, 3.0, "#ffa040", "torch")
	_prop(lvl, "woodland:tent", camp + Vector2(-1.4, -0.6), 20)
	_prop(lvl, "woodland:tent", camp + Vector2(1.3, -0.8), -15)
	_prop(lvl, "woodland:fallen_log", camp + Vector2(0.2, 1.1), 10)
	_prop(lvl, "woodland:boulder", Vector2(11.2, 10.4), 30)
	_prop(lvl, "woodland:boulder", Vector2(4.0, 10.8), 80)
	_prop(lvl, "woodland:stream_stones", Vector2(15.0, 8.3), 0, 1.0, "ground")
	_prop(lvl, "woodland:mushroom_ring", Vector2(19.5, 3.5), 0, 1.0, "ground")
	# A fence along part of the road
	var fence_pts := []
	for x in range(2, 7):
		fence_pts.append(g.snap_to_corner(Vector2(x, 9.3)))
	_wall(lvl, fence_pts, "fence", "woodland:wooden_fence")
	# Stream as a terrain wall (limited sight through reeds)
	_wall(lvl, [g.snap_to_corner(Vector2(15, 0.3)), g.snap_to_corner(Vector2(14.2, 5)), g.snap_to_corner(Vector2(15.5, 9))], "terrain", "woodland:stream_bank")
	_note(lvl, camp + Vector2(0, -1.8), "Bandit camp", "Three bandits and a lookout in the pine at 6,3. Loot under the left tent.")
	_note(lvl, Vector2(15.0, 8.3), "Ford", "Stepping stones: DC 10 to cross without slipping in armour.")
	return m


func _bog_crossing() -> HexMap:
	var m := HexMap.create("Bog Crossing", HexGrid.new(HexGrid.Orient.FLAT, HexGrid.Offset.ODD, 20, 14))
	m.doc.meta.description = "A rotting boardwalk across open bog to a hut on stilts. Flat-top hexes."
	m.grid.distance = 1.5
	m.grid.units = "m"
	m.note_pack("swamp", "0.1.0")
	var lvl := m.level(0)
	var g := m.grid
	_fill(m, lvl, "swamp:marsh_grass", 3)
	for c in g.all_cells():
		var p := g.cell_center(c)
		var d := (p - Vector2(10, 7)).length() / 7.0 + sin(p.x * 1.3) * 0.12 + cos(p.y * 1.7) * 0.12
		if d < 0.55:
			_cell(m, lvl, c, "swamp:deep_water" if d < 0.3 else "swamp:murky_water", 2)
		elif d < 0.75 and rng.randf() < 0.6:
			_cell(m, lvl, c, ["swamp:mud", "swamp:reeds", "swamp:peat"][rng.randi() % 3], 2)
	var walk := [Vector2(0.6, 7.5), Vector2(5, 7.3), Vector2(9, 6.9), Vector2(12, 7.8), Vector2(16, 6.5)]
	for c in _line_cells(g, walk):
		_cell(m, lvl, c, "swamp:rotting_boardwalk", 2)
	for c in g.all_cells():
		var t: String = lvl.terrain[HexMap.cell_key(c)].t
		var p := g.cell_center(c) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		match t:
			"swamp:murky_water":
				if rng.randf() < 0.3:
					_prop(lvl, "swamp:lily_pads", p, rng.randf_range(0, 360), 1.0, "ground")
				elif rng.randf() < 0.12:
					_prop(lvl, "swamp:mangrove", p, rng.randf_range(0, 360))
			"swamp:marsh_grass", "swamp:peat":
				if rng.randf() < 0.1:
					_prop(lvl, ["swamp:dead_tree", "swamp:mossy_stone", "swamp:cypress_knees"][rng.randi() % 3], p, rng.randf_range(0, 360))
	var hut := Vector2(17.3, 6.3)
	_prop(lvl, "swamp:witch_hut", hut)
	_prop(lvl, "swamp:rickety_dock", Vector2(15.6, 6.6), 15, 1.0, "ground")
	_light(lvl, hut + Vector2(-1.2, 0.9), 1.0, 2.0, "#ffd080", "flicker")
	_prop(lvl, "swamp:sunken_boat", Vector2(9.5, 9.6), -25)
	for i in 3:
		var p := Vector2(rng.randf_range(6, 13), rng.randf_range(3, 11))
		_prop(lvl, "swamp:will_o_wisp", p)
		_light(lvl, p, 0.5, 1.5, "#a0ffd0", "pulse")
	_prop(lvl, "swamp:frog_totem", Vector2(4.6, 8.4))
	_prop(lvl, "swamp:skull_pile", Vector2(12.3, 8.5), 40)
	# Rails along the boardwalk
	var rail := []
	for p in walk:
		rail.append(g.snap_to_corner(p + Vector2(0, -0.55)))
	_wall(lvl, rail, "fence", "swamp:boardwalk_rail")
	# Hut walls
	var hut_cells := {}
	for c in g.spiral(g.world_to_axial(hut), 1):
		hut_cells[HexMap.cell_key(c)] = true
	_room(lvl, g, hut_cells, "swamp:palisade", [g.snap_to_corner(hut + Vector2(-1.0, 0.5)), g.snap_to_corner(hut + Vector2(-1.0, -0.5))])
	_note(lvl, hut, "The hut", "Mother Sedge is home. She wants the frog totem back before she talks.")
	_note(lvl, Vector2(9.5, 9.6), "Sunken boat", "A strongbox in the mud beneath, guarded by a bog lurker.")
	return m


func _ruined_chapel() -> HexMap:
	var m := HexMap.create("Ruined Chapel", HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 22, 16))
	m.doc.meta.description = "A roofless chapel and its crypt. Two levels."
	m.note_pack("dungeons_and_castles", "0.1.0")
	m.note_pack("woodland", "0.1.0")
	var lvl := m.level(0)
	var g := m.grid
	_fill(m, lvl, "dungeons_and_castles:grass_courtyard", 2)
	for c in g.all_cells():
		if rng.randf() < 0.08:
			_cell(m, lvl, c, "woodland:rocky_ground", 2)
	# Chapel footprint: nave + apse
	var nave := {}
	for c in g.all_cells():
		var o := g.axial_to_offset(c)
		if o.x >= 5 and o.x <= 15 and o.y >= 4 and o.y <= 11:
			nave[HexMap.cell_key(c)] = true
		if o.x >= 16 and o.x <= 17 and o.y >= 6 and o.y <= 9:
			nave[HexMap.cell_key(c)] = true
	for key in nave:
		var c := HexMap.key_cell(key)
		var o := g.axial_to_offset(c)
		if o.x >= 16:
			_cell(m, lvl, c, "dungeons_and_castles:flagstone", 3)
		elif o.y == 7 or o.y == 8:
			_cell(m, lvl, c, "dungeons_and_castles:carpet_red", 1)
		elif rng.randf() < 0.15:
			_cell(m, lvl, c, "dungeons_and_castles:rubble", 2)
		else:
			_cell(m, lvl, c, "dungeons_and_castles:flagstone", 3)
	# Door at the west end, gap (collapsed wall) on the south side
	var west := g.cell_center(g.offset_to_axial(5, 7))
	_room(lvl, g, nave, "dungeons_and_castles:stone_wall", [g.snap_to_corner(west + Vector2(-0.5, -0.3)), g.snap_to_corner(west + Vector2(-0.5, 0.3))])
	var cells: Array = nave.keys()
	# Pillars down both sides, pews, altar
	for x in [7, 9, 11, 13]:
		for y in [5, 10]:
			var p := g.cell_center(g.offset_to_axial(x, y))
			_prop(lvl, "dungeons_and_castles:pillar", p)
			if rng.randf() < 0.5:
				_wall(lvl, g.cell_corners(g.offset_to_axial(x, y)) as Array, "wall", "", {"hidden": true})
	for x in [8, 10, 12]:
		for y in [6, 9]:
			var p := g.cell_center(g.offset_to_axial(x, y))
			_prop(lvl, "dungeons_and_castles:table", p, 0, 0.8)
	var altar := g.cell_center(g.offset_to_axial(16, 7)) + Vector2(0.5, 0.55)
	_prop(lvl, "dungeons_and_castles:altar", altar)
	_prop(lvl, "dungeons_and_castles:candelabra", altar + Vector2(-0.45, -0.25))
	_light(lvl, altar + Vector2(-0.45, -0.25), 0.5, 1.5, "#ffe0a0", "flicker")
	_prop(lvl, "dungeons_and_castles:candelabra", altar + Vector2(0.45, -0.25))
	_light(lvl, altar + Vector2(0.45, -0.25), 0.5, 1.5, "#ffe0a0", "flicker")
	_prop(lvl, "dungeons_and_castles:statue", g.cell_center(g.offset_to_axial(6, 5)))
	_prop(lvl, "dungeons_and_castles:statue", g.cell_center(g.offset_to_axial(6, 10)))
	for pos in [Vector2(6.0, 5.0), Vector2(14.9, 5.0), Vector2(6.0, 11.4), Vector2(14.9, 11.4)]:
		_prop(lvl, "dungeons_and_castles:brazier", pos)
		_light(lvl, pos, 1.5, 3.0, "#ff9040", "flicker")
	_prop(lvl, "dungeons_and_castles:trapdoor", g.cell_center(g.offset_to_axial(13, 8)), 0, 1.0, "ground")
	_prop(lvl, "dungeons_and_castles:bones", g.cell_center(g.offset_to_axial(9, 8)) + Vector2(0.3, 0.2), 30, 1.0, "ground")
	# Trees and a well outside
	for i in 18:
		var p := Vector2(rng.randf_range(0.5, 21.5), rng.randf_range(0.5, 15.0))
		if g.in_bounds(g.world_to_axial(p)) and not nave.has(HexMap.cell_key(g.world_to_axial(p))):
			_prop(lvl, ["woodland:oak", "woodland:birch", "woodland:bush", "woodland:boulder"][rng.randi() % 4], p, rng.randf_range(0, 360))
	_prop(lvl, "dungeons_and_castles:well", Vector2(3.0, 12.5))
	_note(lvl, g.cell_center(g.offset_to_axial(13, 8)), "Trapdoor", "Iron-banded, locked (DC 15). Leads to the crypt level.")
	_note(lvl, altar, "Altar", "The chalice is silver, not holy. The candles relight themselves.")

	# Crypt level
	var crypt := HexMap.new_level("crypt", "Crypt")
	crypt.elevation_range = [-2, -1]
	m.doc.levels.append(crypt)
	var room := {}
	for c in g.all_cells():
		var o := g.axial_to_offset(c)
		if o.x >= 9 and o.x <= 15 and o.y >= 6 and o.y <= 10:
			room[HexMap.cell_key(c)] = true
	for key in room:
		var c := HexMap.key_cell(key)
		crypt.terrain[key] = {"t": "dungeons_and_castles:rough_stone" if rng.randf() < 0.7 else "dungeons_and_castles:dirt_floor", "v": rng.randi() % 2, "rot": 0, "z": -2}
	var secret := [g.snap_to_corner(g.cell_center(g.offset_to_axial(9, 8)) + Vector2(-0.5, -0.3)), g.snap_to_corner(g.cell_center(g.offset_to_axial(9, 8)) + Vector2(-0.5, 0.3))]
	_room(crypt, g, room, "dungeons_and_castles:brick_wall", secret, "secret")
	crypt.terrain[HexMap.cell_key(g.offset_to_axial(13, 8))] = {"t": "dungeons_and_castles:stairs", "v": 0, "rot": 0, "z": -2}
	for x in [10, 12, 14]:
		for y in [6, 10]:
			_prop(crypt, "dungeons_and_castles:chest" if rng.randf() < 0.4 else "dungeons_and_castles:crate", g.cell_center(g.offset_to_axial(x, y)), rng.randf_range(-20, 20))
	_prop(crypt, "dungeons_and_castles:altar", g.cell_center(g.offset_to_axial(9, 8)), 90)
	_prop(crypt, "dungeons_and_castles:torch_sconce", g.cell_center(g.offset_to_axial(11, 8)) + Vector2(0, -1.2))
	_light(crypt, g.cell_center(g.offset_to_axial(11, 8)) + Vector2(0, -1.2), 1.0, 2.0, "#ffa040", "torch")
	_note(crypt, g.cell_center(g.offset_to_axial(9, 8)) + Vector2(-1.0, 0), "Secret door", "Leads to a collapsed tunnel heading west.")
	# The goblins' fire of broken pews in the nave, where The Ruined Chapel puts
	# them: made last, with ids of its own and no random draws, so the rest of
	# every example stays as it was
	var fire := g.cell_center(g.offset_to_axial(11, 8))
	var at := [snappedf(fire.x, 0.001), snappedf(fire.y, 0.001)]
	lvl.props.append({"id": "p_f1ee0001", "asset": "woodland:campfire", "pos": at, "rot": 0.0, "scale": 1.0, "flip": false, "z": 0, "height": 0.5, "hidden": false, "layer": "objects"})
	lvl.lights.append({"id": "l_f1ee0001", "pos": at, "z": 0.5, "bright": 1.5, "dim": 3.0, "color": "#ffa040", "intensity": 1.0, "angle": 360, "direction": 0,
		"shadows": true, "animation": "torch", "hidden": false})
	lvl.notes.append({"id": "n_f1ee0001", "pos": at, "title": "Fire of broken pews", "text": "The goblins burn the pews they broke up, and sit round the fire, loud and careless.", "gm_only": true})
	return m


## A square-grid map: a merchant's cellar. The same packs, a square grid.
func _cellar() -> HexMap:
	var m := HexMap.create("Cellar", HexGrid.square(20, 14))
	m.doc.meta.description = "A merchant's cellar: storeroom, wine racks and a walled-off vault. Square cells."
	m.note_pack("dungeons_and_castles", "0.1.0")
	var lvl := m.level(0)
	var g := m.grid
	_fill(m, lvl, "dungeons_and_castles:rough_stone", 2)
	# The storeroom, the vault beside it
	var store := {}
	var vault := {}
	for c in g.all_cells():
		if c.x >= 2 and c.x <= 12 and c.y >= 2 and c.y <= 11:
			store[HexMap.cell_key(c)] = true
			_cell(m, lvl, c, "dungeons_and_castles:flagstone", 3, rng.randi() % 4)
		elif c.x >= 14 and c.x <= 18 and c.y >= 4 and c.y <= 9:
			vault[HexMap.cell_key(c)] = true
			_cell(m, lvl, c, "dungeons_and_castles:dirt_floor", 2)
	# Doors: the store's on its north wall, the vault's through the shared wall
	var north := g.cell_center(Vector2i(7, 2))
	_room(lvl, g, store, "dungeons_and_castles:stone_wall", [north + Vector2(-0.5, -0.5), north + Vector2(0.5, -0.5)])
	var shared := g.cell_center(Vector2i(14, 6))
	_room(lvl, g, vault, "dungeons_and_castles:brick_wall", [shared + Vector2(-0.5, -0.5), shared + Vector2(-0.5, 0.5)], "secret")
	# Racks along the west wall, crates in the middle, a table by the door
	for y in [3, 5, 7, 9]:
		_prop(lvl, "dungeons_and_castles:crate", g.cell_center(Vector2i(3, y)), 0, 0.9)
	for x in [6, 7, 8]:
		_prop(lvl, "dungeons_and_castles:crate" if x != 7 else "dungeons_and_castles:chest", g.cell_center(Vector2i(x, 7)), rng.randf_range(-15, 15))
	_prop(lvl, "dungeons_and_castles:table", g.cell_center(Vector2i(10, 3)), 90, 0.8)
	_prop(lvl, "dungeons_and_castles:torch_sconce", g.cell_center(Vector2i(7, 3)) + Vector2(0, -0.4))
	_light(lvl, g.cell_center(Vector2i(7, 3)) + Vector2(0, -0.4), 1.0, 2.0, "#ffa040", "torch")
	_prop(lvl, "dungeons_and_castles:candelabra", g.cell_center(Vector2i(10, 10)))
	_light(lvl, g.cell_center(Vector2i(10, 10)), 0.5, 1.5, "#ffe0a0", "flicker")
	_prop(lvl, "dungeons_and_castles:chest", g.cell_center(Vector2i(17, 6)), 0, 1.0)
	_prop(lvl, "dungeons_and_castles:bones", g.cell_center(Vector2i(16, 8)), 20, 1.0, "ground")
	_note(lvl, g.cell_center(Vector2i(14, 6)), "Secret door", "Hidden behind the empty wine rack; DC 14 to notice the draught.")
	_note(lvl, g.cell_center(Vector2i(17, 6)), "The strongbox", "Ledgers, and the deed the merchant was killed for.")
	return m


# --------------------------------------------------------------- encounter --

## An encounter on the chapel, built the way the Table will: through events
## on an EncounterState, so this is also the model's smoke test.
func _chapel_ambush(m: HexMap) -> Encounter:
	var e := Encounter.create("Chapel Ambush")
	e.doc.meta.description = "The party enters the chapel at dusk; goblins wait in the dark, their chief in the crypt."
	var st := EncounterState.new(e)
	st.attach_map(m)
	var g := m.grid
	var ana := Encounter.new_player("Ana", "#4f9cf6")
	var ben := Encounter.new_player("Ben", "#5bc86a")
	st.apply({"t": "player.add", "player": ana})
	st.apply({"t": "player.add", "player": ben})

	var ground := Encounter.new_scene(m, "ground", "Chapel at dusk", "ruined_chapel.hexmap")
	st.apply({"t": "scene.add", "scene": ground})
	var sid: String = ground.id
	var door := m.level_by_id("ground")
	# The party at the west door, one goblin per pillar, hidden until seen.
	var party := [
		Encounter.new_token("Ana's fighter", g.cell_center(g.offset_to_axial(3, 7)), {"label": "AF", "color": ana.color, "owner": ana.id, "light": {"bright": 1.5, "dim": 3.0, "color": "#ffa040"}}),
		Encounter.new_token("Ben's ranger", g.cell_center(g.offset_to_axial(3, 8)), {"label": "BR", "color": ben.color, "owner": ben.id, "vision": {"radius": 9}}),
	]
	for t in party:
		st.apply({"t": "token.add", "scene": sid, "token": t})
	var n := 1
	for x in [9, 13]:
		for y in [5, 10]:
			st.apply({"t": "token.add", "scene": sid, "token": Encounter.new_token("Goblin", g.cell_center(g.offset_to_axial(x, y)) + Vector2(0.6, 0),
				{"label": "G%d" % n, "color": "#8a9a3a", "hidden": true, "vision": {"radius": 6}})})
			n += 1
	# Braziers are out; only the altar candles burn. Fog on; the party has
	# seen the courtyard from the road.
	for l in door.lights:
		if str(l.color) == "#ff9040":
			st.apply({"t": "element.set", "scene": sid, "ref": LayerTree.ref("lights", l.id), "changes": {"on": false}})
	st.apply({"t": "fog.set", "scene": sid, "enabled": true})
	var cmds := EncounterCommands.new(st, EventLog.new(st))
	cmds.explore_from(sid, party)
	cmds.history.clear()   # the undo closures hold the state; drop the cycle

	var crypt := Encounter.new_scene(m, "crypt", "The crypt", "ruined_chapel.hexmap")
	st.apply({"t": "scene.add", "scene": crypt})
	st.apply({"t": "token.add", "scene": crypt.id, "token": Encounter.new_token("Goblin chief", g.cell_center(g.offset_to_axial(11, 8)),
		{"label": "GC", "color": "#a0402a", "size": 1, "vision": {"radius": 6}, "tags": ["boss"]})})
	st.apply({"t": "fog.set", "scene": crypt.id, "enabled": true})
	st.apply({"t": "scene.activate", "id": sid})
	var order := []
	for t in st.tokens(sid):
		order.append(t.id)
	st.apply({"t": "turns.set", "changes": {"mode": "ordered", "system": "list", "order": order, "round": 1, "turn": 0, "running": false}})
	e.doc.notes.append({"id": JsonDoc.new_id("n"), "title": "If the party lights the braziers", "text": "The goblins bolt for the trapdoor; the chief bars it from below."})
	return e
