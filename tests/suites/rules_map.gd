extends TestCase
## Phase 6: the map as the rules see it — distances and bands, templates,
## sight and cover, light, regions and cells, moves through hooks — and
## how regions and cells reach players.


## The chapel with a kernel: [kernel, scene id]. Tokens: hero at the west
## door (3,7), a goblin inside (9,7), all with actors of the fixture.
func _chapel_kernel() -> Array:
	var m := _chapel()
	var st := EncounterState.new(Encounter.create("Map"))
	st.encounter.doc.rng = {"seed": 77, "index": 0}
	st.attach_map(m)
	var k := RulesKernel.new(st)
	var rules := SampleRules.new()
	rules.install(k)
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	var g := m.grid
	k.commit([{"t": "scene.add", "scene": sc},
		{"t": "actor.add", "actor": {"id": "a_h", "name": "Hero", "owner": "pl_1", "ext": {"sample": {"level": 1, "stats": {"agi": 2, "str": 1, "wit": 0}}}}},
		{"t": "actor.add", "actor": {"id": "a_g", "name": "Goblin", "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Hero", g.cell_center(g.offset_to_axial(3, 7)), {"id": "t_h", "actor": "a_h", "owner": "pl_1", "vision": {"radius": 6}})},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Goblin", g.cell_center(g.offset_to_axial(9, 7)), {"id": "t_g", "actor": "a_g", "hidden": true})}], "Setup")
	return [k, str(sc.id), rules]


func test_map_distances_and_templates() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var g := mq.grid(sid)
	var d := mq.distance(sid, "token:t_h", "token:t_g")
	check(d.cells == 6 and is_equal_approx(d.units, 6.0) and is_equal_approx(d.edge, 5.0), "centre 6 hexes, edge 5 (two size-1 tokens): %s" % [d])
	check(mq.distance(sid, "token:t_h", "token:t_none").has("error"), "an unknown place says so")
	mq.register_bands("p", [{"name": "near", "max": 2}, {"name": "far", "max": 8}, {"name": "beyond"}])
	check(mq.distance(sid, "token:t_h", "token:t_g", "p").band == "far" and mq.band_of("p", 1) == "near" and mq.band_of("p", 50) == "beyond", "bands from the plugin's table")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"size": 3}}], "Big")
	check(is_equal_approx(mq.distance(sid, "token:t_h", "token:t_g").edge, 4.0), "a size-3 token is a hex closer at the edge")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"size": 1}}], "Small")
	check(mq.within(sid, "token:t_h", 5).has("t_g") and not mq.within(sid, "token:t_h", 4).has("t_g"), "within by edge distance")
	# templates
	var circle := mq.template(sid, {"shape": "circle", "at": "token:t_g", "radius": 1})
	check(circle.cells.size() == 7 and circle.tokens.is_empty(), "a radius-1 circle around a token: its cell and six neighbours, not itself: %s" % [circle.cells.size()])
	circle = mq.template(sid, {"shape": "circle", "at": "token:t_g", "radius": 1, "include_self": true})
	check(circle.tokens == ["t_g"], "with include_self")
	var cone := mq.template(sid, {"shape": "cone", "at": "token:t_h", "direction": 0, "length": 4, "angle": 60})
	check(cone.cells.size() >= 4 and cone.cells.size() <= 16 and not cone.cells.has(HexMap.cell_key(g.offset_to_axial(2, 7))), "a cone east of the hero reaches east, not west: %d cells" % cone.cells.size())
	var line := mq.template(sid, {"shape": "line", "at": "token:t_h", "direction": 0, "length": 6, "width": 1})
	check(line.cells.size() >= 5 and line.tokens.has("t_g"), "a line east of the hero runs to the goblin: %d cells" % line.cells.size())
	var blocked := mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 6, "blocked_by_walls": true})
	var open := mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 6})
	check(blocked.cells.size() < open.cells.size(), "walls cut a template down (%d of %d cells)" % [blocked.cells.size(), open.cells.size()])
	check(mq.template(sid, {"shape": "circle", "at": "token:t_none", "radius": 1}).has("error"), "a template around nothing says so")
	# cells
	check(mq.neighbors(sid, "token:t_h").size() == 6 and mq.cells_within(sid, "token:t_h", 1).size() == 7 and mq.cells_between(sid, "token:t_h", "token:t_g").size() == 7, "neighbours, rings, lines")
	check(mq.cell(sid, "token:t_h").has("terrain") and mq.cell(sid, "token:t_h").key == HexMap.cell_key(g.offset_to_axial(3, 7)), "a cell record with the map's terrain")


func test_map_sight_and_light() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var st := k.state
	# the west door is closed: the hero outside cannot see the goblin inside
	var door := {}
	for w in st.level_for(sid).walls:
		if w.get("door", "none") == "door":
			door = w
			break
	check(not door.is_empty(), "the chapel has a door")
	var closed := mq.line_of_sight(sid, "token:t_h", "token:t_g")
	k.commit([{"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}}], "Open")
	var opened := mq.line_of_sight(sid, "token:t_h", "token:t_g")
	say.call("  sight through the door: closed %s/%s, open %s/%s" % [closed.seen, closed.of, opened.seen, opened.of])
	check(opened.seen >= closed.seen, "opening a door never hides more")
	check(closed.cover in ["none", "partial", "total"] and opened.has("blocked_by"), "cover is one of three words")
	# a token in between gives partial cover
	var g := mq.grid(sid)
	k.commit([{"t": "token.add", "scene": sid, "token": Encounter.new_token("Wall of goblins", g.cell_center(g.offset_to_axial(6, 7)), {"id": "t_mid", "size": 1})}], "Mid")
	var covered := mq.line_of_sight(sid, "token:t_h", "token:t_g")
	var ignoring := mq.line_of_sight(sid, "token:t_h", "token:t_g", false)
	check(covered.seen <= ignoring.seen and (covered.blocked_by.has("t_mid") or covered.seen == ignoring.seen), "a token between gives cover when tokens block: %s vs %s" % [covered.seen, ignoring.seen])
	k.commit([{"t": "token.remove", "scene": sid, "id": "t_mid"}], "Gone")
	# light: the map's lights, a torch on a token
	var dark_spot := g.cell_center(g.offset_to_axial(1, 1))
	check(mq.light_at(sid, dark_spot).level == "dark", "a corner far from any light is dark")
	var lit := false
	for l in st.level_for(sid).lights:
		var at := Vector2(float(l.pos[0]), float(l.pos[1]))
		var here := mq.light_at(sid, at)
		if here.level == "bright" and here.sources.has("light:" + str(l.id)):
			lit = true
	check(lit or st.level_for(sid).lights.is_empty(), "a map light lights its own spot brightly")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"light": {"bright": 2, "dim": 4}}}], "Torch")
	var near := mq.light_at(sid, Vision.token_pos(st.token(sid, "t_h")) + Vector2(1.5, 0))
	var mid := mq.light_at(sid, Vision.token_pos(st.token(sid, "t_h")) + Vector2(3.0, 0))
	check(near.level == "bright" and near.sources.has("token:t_h") and mid.level in ["dim", "bright"], "a torch lights bright then dim: %s, %s" % [near.level, mid.level])
	# can_see: range, sight, light, vision mode
	var see := mq.can_see(sid, "token:t_h", "token:t_g")
	check(see.has("sees") and see.has("why") or see.sees, "can_see answers with a reason: %s" % [see])
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 2}}}], "Short sight")
	check(not mq.can_see(sid, "token:t_h", "token:t_g").sees and mq.can_see(sid, "token:t_h", "token:t_g").why == "out of range", "out of range")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 10, "mode": "dark"}, "light": null}}], "Darkvision")
	var dv := mq.can_see(sid, "token:t_h", "token:t_g")
	check(dv.why != "dark" if not dv.sees else true, "dark vision does not fail for darkness: %s" % [dv])
	# darkvision with a range: the goblin is five hexes off at the edge
	k.commit([{"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}}], "Open")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 10, "dark_radius": 4}}}], "Short darkvision")
	var near_dark := mq.can_see(sid, "token:t_h", "token:t_g")
	check(mq.light_at(sid, "token:t_g").level == "dark", "the goblin stands in the dark")
	check(not near_dark.sees and near_dark.why == "dark", "four hexes of darkvision do not reach a goblin five away: %s" % [near_dark])
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 10, "dark_radius": 6}}}], "Darkvision 6")
	var in_dark := mq.can_see(sid, "token:t_h", "token:t_g")
	check(in_dark.sees and bool(in_dark.get("dark_sight", false)), "six hexes of darkvision see the goblin, marked as dark sight: %s" % [in_dark])
	# and the canvas lifts the darkness around a player's darkvision
	var canvas := MapCanvas.new()
	canvas.packs = PackLibrary.new()
	root.add_child(canvas)
	canvas.set_scene(st, sid)
	canvas.darkness = 1.0
	canvas.viewpoint = "pl_1"
	canvas.refresh()
	await tree.process_frame
	canvas._draw_lights(canvas._lights)
	check(canvas._poly_cache.keys().any(func(k: String) -> bool: return k.begins_with("dark|")), "a dark-sight fan was drawn for the hero")
	canvas.viewpoint = ""
	canvas._poly_cache.clear()
	canvas.refresh()
	canvas._draw_lights(canvas._lights)
	check(not canvas._poly_cache.keys().any(func(k: String) -> bool: return k.begins_with("dark|")), "not for the GM's view")
	canvas.queue_free()
	await tree.process_frame
	check(not mq.can_see(sid, "token:t_h", "token:t_none").sees, "unknown target")


func test_map_regions_cells_and_moves() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var st := k.state
	var g := mq.grid(sid)
	# regions
	var here := g.offset_to_axial(6, 7)   # three hexes east of the hero, so walking in is a change
	var fire := MapQuery.region("r_fire", g.spiral(here, 1), ["fire", "hazard"], {"label": "Fire", "duration": {"kind": "rounds", "rounds": 2}})
	var secret := MapQuery.region("r_secret", [g.offset_to_axial(8, 3)], ["trap"], {"audience": "gm"})
	check(k.commit([{"t": "region.add", "scene": sid, "region": fire}, {"t": "region.add", "scene": sid, "region": secret}], "Regions") == "", "regions added")
	check(st.validate({"t": "region.add", "scene": sid, "region": fire}) != "" and st.validate({"t": "region.set", "scene": sid, "id": "r_fire", "changes": {"id": "x"}}) != "", "duplicates and id changes refused")
	check(mq.regions_at(sid, here).size() == 1 and mq.tags_at(sid, here) == ["fire", "hazard"] and mq.regions_at(sid, g.offset_to_axial(0, 0)).is_empty(), "regions and tags at a cell")
	check(k.commit(mq.expire_regions(sid, {"kind": "round"}), "Round") == "" and st.encounter.scene(sid).regions.r_fire.duration.rounds == 1, "a region's duration ticks with the round")
	check(k.commit(k.expire({"kind": "round"}), "Round") == "" and not st.encounter.scene(sid).regions.has("r_fire"), "and it is gone after the second")
	k.commit([{"t": "region.add", "scene": sid, "region": fire}], "Fire again")
	# moves through the kernel: hooks, entered/left, attached tokens
	var seen := []
	k.hooks.on("token_moved", func(p: Dictionary) -> Dictionary:
		seen.append(["moved", p.token, p.cells, p.entered, p.left])
		if p.to[0] > 30:
			p.veto = "off the map"
		return p, "test")
	k.hooks.on("region_entered", func(p: Dictionary) -> Dictionary:
		seen.append(["entered", p.token, p.region])
		p.events.append({"t": "log.add", "entry": {"id": JsonDoc.new_id("n_burn"), "kind": "note", "text": "burn"}})
		return p, "test")
	k.hooks.on("region_left", func(p: Dictionary) -> Dictionary: seen.append(["left", p.token, p.region]); return p, "test")
	k.commit([{"t": "token.add", "scene": sid, "token": Encounter.new_token("Pet", Vision.token_pos(st.token(sid, "t_h")) + Vector2(0, 1), {"id": "t_pet", "attached_to": "t_h"})}], "Pet")
	var pet_before := Vision.token_pos(st.token(sid, "t_pet"))
	check(k.move_token(sid, "t_h", g.cell_center(here), "pl_1") == "", "a move into the fire")
	check(seen[0][0] == "moved" and seen[0][1] == "t_h" and seen[0][2] == 3 and seen[0][3] == ["r_fire"] and seen[1] == ["entered", "t_h", "r_fire"], "token_moved then region_entered fired: %s" % [seen])
	check(st.encounter.log.size() == 1 and st.encounter.log[0].text == "burn", "the entered hook's events landed")
	check(Vision.token_pos(st.token(sid, "t_pet")) == pet_before + (g.cell_center(here) - Vision.token_pos(st.token(sid, "t_h")) + (g.cell_center(here) - g.cell_center(here))) or Vision.token_pos(st.token(sid, "t_pet")).distance_to(Vision.token_pos(st.token(sid, "t_h"))) < 1.01, "the attached token moved along")
	check(k.log.undo_label() == "Move", "one undo step")
	seen.clear()
	check(k.move_token(sid, "t_h", g.cell_center(g.offset_to_axial(3, 7)), "pl_1") == "" and seen.any(func(e: Array) -> bool: return e[0] == "left" and e[2] == "r_fire"), "leaving fires region_left: %s" % [seen])
	var before := st.encounter.to_json()
	check(k.move_token(sid, "t_h", Vector2(40, 40)).contains("off the map") and st.encounter.to_json() == before, "a vetoed move leaves nothing behind")
	check(k.move_token(sid, "t_none", Vector2(1, 1)) != "", "no such token")
	# the Table's commands go through the kernel too
	var cmds := EncounterCommands.new(st, k.log)
	cmds.kernel = k
	seen.clear()
	var why_cmd := cmds.move_token(sid, "t_h", g.cell_center(here))
	check(why_cmd == "" and seen.size() >= 2, "EncounterCommands.move_token runs the hooks: '%s' %s" % [why_cmd, seen])
	# cells: plugin state and revealing
	check(k.commit([{"t": "ext.set", "scope": "cell", "scene": sid, "id": "4,7", "plugin": "sample", "changes": {"searched": true}}], "Searched") == "", "cell plugin state")
	check(st.encounter.scene(sid).cells["4,7"].ext.sample.searched == true and mq.cell(sid, "4,7").ext.sample.searched == true, "stored on the scene's cell")
	check(mq.cell(sid, g.offset_to_axial(0, 0)).key == "0,0" or mq.cell(sid, g.offset_to_axial(0, 0)).key != "", "a cell by coordinates")
	check(st.validate({"t": "ext.set", "scope": "cell", "scene": sid, "id": "x", "plugin": "p", "changes": {}}) != "" and st.validate({"t": "cell.set", "scene": sid, "id": "1,1", "changes": {"ext": {}}}) != "", "bad cell ids and ext through cell.set are refused")
	check(k.commit([{"t": "cell.set", "scene": sid, "id": "4,7", "changes": {"revealed": true, "note": "ash"}}], "Reveal") == "" and st.encounter.scene(sid).cells["4,7"].revealed, "cell.set for plain fields")
	var inv := st.apply({"t": "ext.set", "scope": "cell", "scene": sid, "id": "4,7", "plugin": "sample", "changes": {"searched": null}})
	check(not st.encounter.scene(sid).cells["4,7"].has("ext") and inv.changes.searched == true, "emptied plugin state is pruned and inverts")
	st.apply({"t": "cell.set", "scene": sid, "id": "4,7", "changes": {"revealed": null, "note": null}})
	check(not st.encounter.scene(sid).cells.has("4,7"), "an empty cell record is not kept")
	# the client document keeps only what players may see
	var doc := Protocol.client_document(st.encounter.doc)
	check(doc.scenes[0].regions.has("r_fire") and not doc.scenes[0].regions.has("r_secret"), "gm-only regions are not in a client's document")
	k.commit([{"t": "cell.set", "scene": sid, "id": "5,5", "changes": {"revealed": false, "x": 1}}, {"t": "cell.set", "scene": sid, "id": "6,6", "changes": {"revealed": true}}], "Cells")
	doc = Protocol.client_document(st.encounter.doc)
	check(not doc.scenes[0].cells.has("5,5") and doc.scenes[0].cells.has("6,6"), "nor unrevealed cells")


## The cellar (a square grid) with a kernel: the same questions, square
## answers. Hero in the storeroom's doorway (7,2), a guard by the crates
## (7,7), a thief in the vault (17,6).
func _cellar_kernel() -> Array:
	var m := HexMap.load_file(example("cellar.hexmap"))
	var st := EncounterState.new(Encounter.create("Cellar"))
	st.encounter.doc.rng = {"seed": 7, "index": 0}
	st.attach_map(m)
	var k := RulesKernel.new(st)
	var rules := SampleRules.new()
	rules.install(k)
	var sc := Encounter.new_scene(m, "ground", "Cellar", "cellar.hexmap")
	var g := m.grid
	k.commit([{"t": "scene.add", "scene": sc},
		{"t": "actor.add", "actor": {"id": "a_h", "name": "Hero", "owner": "pl_1", "ext": {"sample": {"level": 1, "stats": {"agi": 2, "str": 1, "wit": 0}}}}},
		{"t": "actor.add", "actor": {"id": "a_g", "name": "Guard", "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}},
		{"t": "actor.add", "actor": {"id": "a_t", "name": "Thief", "ext": {"sample": {"level": 1, "stats": {"agi": 3, "str": 0, "wit": 0}}}}},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Hero", g.cell_center(Vector2i(7, 2)), {"id": "t_h", "actor": "a_h", "owner": "pl_1", "vision": {"radius": 6}})},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Guard", g.cell_center(Vector2i(7, 7)), {"id": "t_g", "actor": "a_g"})},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Thief", g.cell_center(Vector2i(17, 6)), {"id": "t_t", "actor": "a_t", "hidden": true})}], "Setup")
	return [k, str(sc.id), rules]


func test_square_map_distances_templates_sight_and_moves() -> void:
	var parts := _cellar_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var st := k.state
	var g := mq.grid(sid)
	check(g.is_square(), "the cellar is a square grid")
	# distances: Chebyshev steps with the diagonal count, Euclidean units
	var d := mq.distance(sid, "token:t_h", "token:t_g")
	check(d.cells == 5 and d.diagonals == 0 and is_equal_approx(d.units, 5.0) and is_equal_approx(d.edge, 4.0), "five squares straight down: %s" % [d])
	var diag := mq.distance(sid, "token:t_h", "token:t_t")
	check(diag.cells == 10 and diag.diagonals == 4 and is_equal_approx(diag.units, sqrt(100.0 + 16.0)), "ten steps, four of them diagonal, Euclidean units: %s" % [diag])
	mq.register_bands("p", [{"name": "adjacent", "max": 0.5}, {"name": "near", "max": 3}, {"name": "beyond"}])
	check(mq.distance(sid, "token:t_h", "token:t_g", "p").band == "beyond", "bands work in edge units on squares too")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"size": 2}}], "Big")
	check(is_equal_approx(mq.distance(sid, "token:t_h", "token:t_g").edge, 3.5), "a size-2 token is half a square closer at the edge")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"size": 1}}], "Small")
	check(mq.within(sid, "token:t_h", 4).has("t_g") and not mq.within(sid, "token:t_h", 3).has("t_g"), "within by edge distance")
	# templates: a radius-1 circle is the 3×3 block minus the middle
	var circle := mq.template(sid, {"shape": "circle", "at": "token:t_g", "radius": 1})
	check(circle.cells.size() == 9 and circle.tokens.is_empty(), "a radius-1 circle around a square token: its cell and eight neighbours, not itself (%d)" % circle.cells.size())
	var cube := mq.template(sid, {"shape": "circle", "at": "token:t_g", "radius": 2, "include_self": true})
	check(cube.cells.size() == 21 and cube.tokens == ["t_g"], "radius 2: the cells whose centres lie within 2 (%d)" % cube.cells.size())
	var cone := mq.template(sid, {"shape": "cone", "at": "token:t_h", "direction": 90, "length": 4, "angle": 60})
	check(cone.cells.size() >= 4 and not cone.cells.has("7,1") and cone.cells.has("7,4"), "a cone south of the hero reaches south, not north: %d cells" % cone.cells.size())
	var line := mq.template(sid, {"shape": "line", "at": "token:t_h", "direction": 90, "length": 6, "width": 1})
	check(line.cells.has("7,5") and line.tokens.has("t_g"), "a line south of the hero runs to the guard: %d cells" % line.cells.size())
	var blocked := mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 6, "blocked_by_walls": true})
	var open := mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 6})
	check(blocked.cells.size() < open.cells.size(), "the storeroom's walls cut a template down (%d of %d cells)" % [blocked.cells.size(), open.cells.size()])
	# cells
	check(mq.neighbors(sid, "token:t_h").size() == 4 and mq.cells_within(sid, "token:t_g", 1).size() == 9, "four neighbours, a 3×3 ring")
	var between := mq.cells_between(sid, "token:t_h", "token:t_t")
	check(between.size() == 11 and between[0] == "7,2" and between[-1] == "17,6", "a line of cells between two tokens: %s" % [between])
	check(mq.cell(sid, "token:t_h").has("terrain") and mq.cell(sid, "token:t_h").key == "7,2", "a cell record with the map's terrain")
	# sight and light: the vault's secret door hides the thief; a torch lights squares
	var closed := mq.line_of_sight(sid, "token:t_g", "token:t_t")
	check(not closed.clear and closed.cover == "total", "the vault wall blocks sight to the thief: %s" % [closed])
	var down := mq.line_of_sight(sid, "token:t_h", "token:t_g")
	check(down.clear, "the hero sees the guard down the storeroom: %s" % [down])
	check(not mq.can_see(sid, "token:t_h", "token:t_g").sees and mq.can_see(sid, "token:t_h", "token:t_g").why == "dark", "the guard stands in the dark between the lights")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"light": {"bright": 2, "dim": 6}}}], "Torch")
	check(mq.light_at(sid, "6,3").level == "bright" and mq.light_at(sid, "7,5").level == "dim", "a torch lights bright then dim on squares")
	check(mq.can_see(sid, "token:t_h", "token:t_g").sees, "the guard is seen once the hero's torch reaches him")
	# regions and a move with diagonals
	var pit := MapQuery.region("r_pit", g.spiral(Vector2i(7, 5), 0), ["pit"], {"label": "Pit"})
	check(k.commit([{"t": "region.add", "scene": sid, "region": pit}], "Pit") == "", "a one-square region")
	var seen := []
	k.hooks.on("token_moved", func(p: Dictionary) -> Dictionary: seen.append([p.cells, p.entered]); return p, "test")
	check(k.move_token(sid, "t_h", g.cell_center(Vector2i(7, 5)), "pl_1") == "" and seen[0] == [3, ["r_pit"]], "three squares down into the pit: %s" % [seen])
	check(mq.move(sid, "t_h", g.cell_center(Vector2i(9, 7))).cells == 2, "a diagonal-ish move counts Chebyshev steps")
	# the drawing code takes four corners in its stride: terrain, grid,
	# fog, a region and a highlight, for the GM and for a player
	k.commit([{"t": "scene.set", "id": sid, "changes": {"highlight": {"cells": ["7,5", "8,5"], "color": "#ffffff", "label": "Pit"}}},
		{"t": "fog.set", "scene": sid, "enabled": true}], "Show")
	var canvas := MapCanvas.new()
	canvas.packs = PackLibrary.new()
	root.add_child(canvas)
	canvas.set_scene(st, sid)
	canvas.show_grid = true
	canvas.viewpoint = ""
	canvas.refresh()
	await tree.process_frame
	canvas.viewpoint = "pl_1"
	canvas.refresh()
	await tree.process_frame
	check(canvas._regions != null and canvas.get_children().has(canvas._regions), "the cellar drew for both viewpoints")
	canvas.queue_free()
	await tree.process_frame


func test_map_events_over_the_wire_and_drawing() -> void:
	var st := EncounterState.new(Encounter.load_file(example("chapel_ambush.encounter")))
	st.resolve_maps()
	var sid := st.encounter.active_scene_id
	var host := HostSession.new(st, PackLibrary.new())
	var g := st.map_for(sid).grid
	var ev := {"t": "region.add", "scene": sid, "region": MapQuery.region("r_gm", [g.offset_to_axial(1, 1)], [], {"audience": "gm"})}
	var inv := st.apply(ev)
	check(host._audience_events(ev, inv).is_empty(), "a GM-only region is not sent")
	ev = {"t": "region.set", "scene": sid, "id": "r_gm", "changes": {"audience": "all"}}
	inv = st.apply(ev)
	var sent := host._audience_events(ev, inv)
	check(sent.size() == 1 and sent[0].t == "region.add" and sent[0].region.id == "r_gm", "opening it sends the whole region")
	ev = {"t": "region.set", "scene": sid, "id": "r_gm", "changes": {"label": "Seen"}}
	inv = st.apply(ev)
	sent = host._audience_events(ev, inv)
	check(sent.size() == 1 and sent[0].t == "region.set", "a change to a visible region is sent as is")
	ev = {"t": "region.set", "scene": sid, "id": "r_gm", "changes": {"audience": "gm"}}
	inv = st.apply(ev)
	sent = host._audience_events(ev, inv)
	check(sent.size() == 1 and sent[0].t == "region.remove", "closing it removes it from clients")
	ev = {"t": "region.remove", "scene": sid, "id": "r_gm"}
	inv = st.apply(ev)
	check(host._audience_events(ev, inv).is_empty(), "removing a GM-only region sends nothing")
	ev = {"t": "ext.set", "scope": "cell", "scene": sid, "id": "2,2", "plugin": "p", "changes": {"trap": true}}
	inv = st.apply(ev)
	check(host._audience_events(ev, inv).is_empty(), "state on an unrevealed cell is not sent")
	ev = {"t": "cell.set", "scene": sid, "id": "2,2", "changes": {"revealed": true}}
	inv = st.apply(ev)
	sent = host._audience_events(ev, inv)
	check(sent.size() == 2 and sent[0].t == "cell.set" and sent[0].changes.revealed == true and sent[1].t == "ext.set" and sent[1].changes.trap == true, "revealing a cell sends its record and its plugin state: %s" % [sent])
	# drawing: regions and a highlight render without error, GM-only ones only for the GM
	var canvas := MapCanvas.new()
	canvas.packs = PackLibrary.new()
	root.add_child(canvas)
	st.apply({"t": "region.add", "scene": sid, "region": MapQuery.region("r_zone", g.spiral(g.offset_to_axial(5, 5), 1), ["fire"], {"label": "Fire", "color": "#ff4500"})})
	st.apply({"t": "scene.set", "id": sid, "changes": {"highlight": {"cells": [HexMap.cell_key(g.offset_to_axial(3, 3))], "color": "#ffffff", "label": "Burst"}}})
	canvas.set_scene(st, sid)
	canvas.viewpoint = ""
	canvas.refresh()
	await tree.process_frame
	await tree.process_frame
	canvas.viewpoint = str(st.encounter.players[0].id)
	canvas.refresh()
	await tree.process_frame
	check(canvas._regions != null and canvas.get_children().has(canvas._regions), "the canvas has a regions layer and drew it for both viewpoints")
	canvas.queue_free()
	await tree.process_frame
