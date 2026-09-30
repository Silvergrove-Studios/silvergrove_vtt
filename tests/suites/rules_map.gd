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
	var centre := g.cell_center(g.offset_to_axial(3, 7))
	var rec_c: Array = mq.cell(sid, "token:t_h").get("center", [])
	check(rec_c.size() == 2 and Vector2(rec_c[0], rec_c[1]).distance_to(centre) < 0.001, "and where its centre is (a creature put where the DM tapped): %s" % [rec_c])


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
	check(closed.walls >= opened.walls and closed.walls + closed.seen <= closed.of, "the rays a wall stopped are counted: closed %d, open %d" % [closed.walls, opened.walls])
	# a token in between gives partial cover
	var g := mq.grid(sid)
	k.commit([{"t": "token.add", "scene": sid, "token": Encounter.new_token("Wall of goblins", g.cell_center(g.offset_to_axial(6, 7)), {"id": "t_mid", "size": 1})}], "Mid")
	var covered := mq.line_of_sight(sid, "token:t_h", "token:t_g")
	var ignoring := mq.line_of_sight(sid, "token:t_h", "token:t_g", false)
	check(covered.seen <= ignoring.seen and (covered.blocked_by.has("t_mid") or covered.seen == ignoring.seen), "a token between gives cover when tokens block: %s vs %s" % [covered.seen, ignoring.seen])
	check(covered.walls == ignoring.walls, "a creature in the way is not a wall")
	k.commit([{"t": "token.remove", "scene": sid, "id": "t_mid"}], "Gone")
	# light: the scene's own, then the map's lights and a torch on a token
	var dark_spot := g.cell_center(g.offset_to_axial(1, 1))
	check(mq.light_at(sid, dark_spot).level == "bright" and mq.light_at(sid, dark_spot).ambient == "daylight", "by day a corner far from any light is bright")
	k.commit([{"t": "scene.set", "id": sid, "changes": {"light": "dim"}}], "Dusk")
	check(mq.light_at(sid, dark_spot).level == "dim", "at dusk, dim")
	k.commit([{"t": "scene.set", "id": sid, "changes": {"light": "dark"}}], "Night")
	check(mq.light_at(sid, dark_spot).level == "dark", "at night a corner far from any light is dark")
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
	# can_see: eyes, sight, light, vision mode
	var see := mq.can_see(sid, "token:t_h", "token:t_g")
	check(see.has("sees") and see.has("why") or see.sees, "can_see answers with a reason: %s" % [see])
	# by day, how far is not the token's to say: a line of sight is enough
	k.commit([{"t": "scene.set", "id": sid, "changes": {"light": "daylight"}}, {"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}},
		{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 2}}}], "Short sight by day")
	var by_day := mq.can_see(sid, "token:t_h", "token:t_g")
	check(by_day.sees and not by_day.has("why"), "a radius of 2 sees a goblin six hexes off by day (no more 'out of range'): %s" % [by_day])
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 0}}}], "Blind")
	check(mq.can_see(sid, "token:t_h", "token:t_g").why == "no vision", "a radius of 0 sees nothing")
	k.commit([{"t": "scene.set", "id": sid, "changes": {"light": "dark"}}], "Night")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 10, "mode": "dark"}, "light": null}}], "Darkvision")
	var dv := mq.can_see(sid, "token:t_h", "token:t_g")
	check(dv.why != "dark" if not dv.sees else true, "dark vision does not fail for darkness: %s" % [dv])
	# darkvision with a range: the goblin is five hexes off at the edge, and the
	# goblins' fire in the nave is out
	k.commit([{"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}}], "Open")
	var fire_light := ""
	for l in st.level_for(sid).lights:
		if Vector2(float(l.pos[0]), float(l.pos[1])).distance_to(g.cell_center(g.offset_to_axial(11, 8))) < 0.01:
			fire_light = str(l.id)
	check(fire_light != "" and k.commit([{"t": "element.set", "scene": sid, "ref": LayerTree.ref("lights", fire_light), "changes": {"on": false}}], "The fire out") == "", "the goblins' fire put out")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 10, "dark_radius": 4}}}], "Short darkvision")
	var near_dark := mq.can_see(sid, "token:t_h", "token:t_g")
	check(mq.light_at(sid, "token:t_g").level == "dark", "the goblin stands in the dark")
	check(not near_dark.sees and near_dark.why == "dark", "four hexes of darkvision do not reach a goblin five away: %s" % [near_dark])
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 10, "dark_radius": 6}}}], "Darkvision 6")
	var in_dark := mq.can_see(sid, "token:t_h", "token:t_g")
	check(in_dark.sees and bool(in_dark.get("dark_sight", false)), "six hexes of darkvision see the goblin, marked as dark sight: %s" % [in_dark])
	# a ruleset's darkvision in feet: 20 feet is four five-foot hexes, 30 is six
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 1, "dark_radius": 20, "units": "ft"}}}], "Darkvision 20 ft")
	check(not mq.can_see(sid, "token:t_h", "token:t_g").sees, "20 feet of darkvision do not reach it")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 1, "dark_radius": 30, "units": "ft"}}}], "Darkvision 30 ft")
	check(mq.can_see(sid, "token:t_h", "token:t_g").sees, "30 feet do")
	# with none, nothing in the dark is seen, not even a goblin beside it (its edge is 0 too)
	var beside := Vision.token_pos(st.token(sid, "t_h")) + Vector2(1, 0)
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 1}}},
		{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"pos": [beside.x, beside.y]}}], "Side by side in the dark")
	var touching := mq.can_see(sid, "token:t_h", "token:t_g")
	check(mq.light_at(sid, "token:t_g").level == "dark" and not touching.sees and touching.why == "dark", "no darkvision, a goblin beside it in the dark: not seen (%s)" % [touching])
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"vision": {"radius": 1, "dark_radius": 5, "units": "ft"}}}], "Darkvision 5 ft")
	check(mq.can_see(sid, "token:t_h", "token:t_g").sees, "five feet of darkvision see it")
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


## Lights creatures carry, in a ruleset's feet and on its effects: a paladin's
## Sacred Weapon ("Bright Light in a 20-foot radius and Dim Light 20 feet
## beyond that") lights the goblin in the dark for a hero with no
## darkvision, and goes out with the effect. (A playtest's Sun Blade lit
## nothing: the creatures beside it stayed under the fog.)
func test_carried_lights() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var st := k.state
	var door := {}
	for w in st.level_for(sid).walls:
		if w.get("door", "none") == "door":
			door = w
			break
	k.commit([{"t": "scene.set", "id": sid, "changes": {"light": "dark"}}, {"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}},
		{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"hidden": false}}], "Night, the door open")
	for l in st.level_for(sid).lights:
		k.commit([{"t": "element.set", "scene": sid, "ref": LayerTree.ref("lights", str(l.id)), "changes": {"on": false}}], "Every light out")
	check(mq.light_at(sid, "token:t_g").level == "dark", "the goblin, six hexes off, stands in the dark")
	check(not mq.can_see(sid, "token:t_h", "token:t_g").sees, "the hero, with no darkvision, doesn't see it")
	# a light on the hero's token in feet: 20 bright, 40 in all, is 4 and 8 five-foot hexes
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"light": {"bright": 20, "dim": 40, "units": "ft"}}}], "A light in feet")
	check(mq.light_at(sid, "token:t_g").level == "dim", "six hexes off: in its dim light (feet made hexes)")
	check(mq.can_see(sid, "token:t_h", "token:t_g").sees, "and seen")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"light": {"bright": 20, "dim": 40}}}], "A light in hexes")
	check(mq.light_at(sid, "token:t_g").level == "bright", "with no units, hexes: bright")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"light": null}}], "Out")
	check(mq.light_at(sid, "token:t_g").level == "dark", "out: dark again")
	# the same light on an effect on the hero's creature: it lights its token, and ends with the effect
	var fx := {"id": "e_sacred", "on": "actor:a_h", "plugin": "sample", "key": "sacred_weapon", "label": "Sacred Weapon", "stack": "none", "changes": [],
		"duration": {"kind": "until_cleared"}, "light": {"bright": 20, "dim": 40, "units": "ft", "color": "#fff1c0"}}
	check(k.commit([{"t": "effect.apply", "effect": fx}], "Sacred Weapon") == "", "an effect with a light")
	var here := mq.light_at(sid, "token:t_g")
	check(here.level == "dim" and here.sources.has("token:t_h"), "the goblin in its dim light, from the hero's token: %s" % [here])
	check(mq.can_see(sid, "token:t_h", "token:t_g").sees, "seen by its light")
	var sight := Vision.of(st, sid, [st.token(sid, "t_h")])
	check(Vision.sees(sight.polygons, Vision.token_pos(st.token(sid, "t_g"))), "and in the hero's sight on the players' screens")
	var drawn := WebScene.lights(st, sid, st.effective_level(sid), [WebScene.token_out(st, st.token(sid, "t_h"), false)])
	check(drawn.size() == 1 and is_equal_approx(float(drawn[0].bright), 4.0) and is_equal_approx(float(drawn[0].dim), 8.0), "the web screens draw it, in hexes: %s" % [drawn.map(func(l: Dictionary) -> String: return "%s/%s" % [l.bright, l.dim])])
	# a hidden creature's light gives nothing away
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"hidden": true}}], "Hidden")
	check(mq.light_at(sid, "token:t_g").level == "dim", "light_at counts every light (the map's own question)")
	check(Vision.lights(st, sid, st.effective_level(sid)).all(func(l: Dictionary) -> bool: return str(l.id) != "token:t_h"), "but sight doesn't count a hidden token's")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"hidden": false}}, {"t": "effect.remove", "id": "e_sacred"}], "It ends")
	check(mq.light_at(sid, "token:t_g").level == "dark", "the effect over: dark again")
	# a light an effect puts at a place (a rod planted in the ground): it lights
	# that place, stays when its creature moves, and goes out with the effect
	var g_pos := Vision.token_pos(st.token(sid, "t_g"))
	var planted := {"id": "e_rod", "on": "actor:a_h", "plugin": "sample", "key": "rod", "label": "A rod planted", "stack": "none", "changes": [],
		"duration": {"kind": "until_cleared"}, "light": {"bright": 60, "dim": 120, "units": "ft", "at": [g_pos.x, g_pos.y], "scene": sid}}
	check(k.commit([{"t": "effect.apply", "effect": planted}], "A rod planted") == "", "an effect with a light at a place")
	here = mq.light_at(sid, "token:t_g")
	check(here.level == "bright" and here.sources.has("effect:e_rod") and not here.sources.has("token:t_h"), "the goblin in its bright light, from the place, not the hero's token: %s" % [here])
	check(mq.can_see(sid, "token:t_h", "token:t_g").sees, "seen by it")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_h", "changes": {"pos": [g_pos.x - 3.0, g_pos.y]}}], "The hero steps off")
	check(mq.light_at(sid, "token:t_g").sources.has("effect:e_rod"), "the light stays where it was put")
	check(Vision.lights(st, sid, st.effective_level(sid)).any(func(l: Dictionary) -> bool: return str(l.id) == "effect:e_rod"), "sight counts it")
	drawn = WebScene.lights(st, sid, st.effective_level(sid), [WebScene.token_out(st, st.token(sid, "t_h"), false)])
	check(drawn.size() == 1 and is_equal_approx(float(drawn[0].bright), 12.0) and is_equal_approx(float(drawn[0].pos[0]), g_pos.x), "the web screens draw it there, in hexes: %s" % [drawn.map(func(l: Dictionary) -> String: return "%s at %s" % [l.bright, l.pos])])
	check(Vision.carried_lights(st, st.token(sid, "t_h"), mq.grid(sid)).is_empty(), "and the hero carries none")
	k.commit([{"t": "effect.remove", "id": "e_rod"}], "Pulled up")
	check(mq.light_at(sid, "token:t_g").level == "dark", "pulled up: dark again")
	# a light of dim light only (an outline of faerie fire) lights its creature dimly, not brightly
	k.commit([{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"light": {"bright": 0, "dim": 10, "units": "ft"}}}], "Outlined")
	check(mq.light_at(sid, "token:t_g").level == "dim", "dim where it stands: %s" % [mq.light_at(sid, "token:t_g")])
	k.commit([{"t": "token.set", "scene": sid, "id": "t_g", "changes": {"light": null}}], "Out")


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
	# after_move: runs once the move is done, may wait on a prompt, and its
	# events land as their own step once the answer is in
	var after := []
	k.hooks.on("after_move", func(p: Dictionary) -> Variant:
		after.append([p.token, p.cells])
		return HookBus.Wait.make({"kind": "prompt", "to": "pl_1", "form": {"title": "React?"}, "opts": {"default": {"react": false}, "deadline": 30}},
			func(payload: Dictionary, answer: Variant) -> Dictionary:
				if answer is Dictionary and bool(answer.get("react", false)):
					payload.events.append({"t": "log.add", "entry": {"id": JsonDoc.new_id("n_react"), "kind": "note", "text": "reacted"}})
				return payload), "after")
	var log_before := st.encounter.log.size()
	var back := g.cell_center(g.offset_to_axial(3, 7))
	check(k.move_token(sid, "t_h", back, "pl_1") == "" and Vision.token_pos(st.token(sid, "t_h")) == back, "the move is done at once")
	check(after == [["t_h", 3]] and k.pending.prompts().size() == 1 and str(k.pending.prompts().values()[0].to) == "pl_1", "after_move ran and is waiting on pl_1: %s" % [after])
	check(k.log.undo_label() == "Prompt", "the open question is its own step after the move's")
	var prompt_id := str(k.pending.prompts().keys()[0])
	check(k.pending.answer(prompt_id, {"react": true}, "pl_1") == "" and st.encounter.log.size() == log_before + 1 and st.encounter.log[-1].text == "reacted", "the answer's events were committed after the move")
	check(k.log.undo_label() == "After move", "as their own step")
	k.hooks.off("after")
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


## A move's way across the map, as a ruleset counts it (a creature's feet on
## its turn): round the walls, through doors only when they are open, never
## cutting a wall's corner on squares, rough ground dearer by the tags the
## ruleset prices — the cells' regions' and their terrain's art's — and
## single cells (another creature's space) dearer or closed. In the cellar:
## the hero stands just inside the storeroom's north door.
func test_paths_round_walls_and_rough_ground() -> void:
	var parts := _cellar_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var p := mq.path(sid, "token:t_h", "7,6")
	check(p.ok and p.steps == 4 and is_equal_approx(p.cost, 4.0) and is_equal_approx(p.length, 4.0) and p.cells[0] == "7,2" and p.cells[-1] == "7,6", "four squares down the storeroom: %s" % [p])
	check(mq.path(sid, "7,2", "7,2").ok and mq.path(sid, "7,2", "7,2").steps == 0, "going nowhere costs nothing")
	# diagonals: every one a square (the 2024 grid), every second two (5-10-5), or √2
	var d := mq.path(sid, "7,2", "10,5")
	check(d.ok and d.steps == 3 and d.diagonals == 3 and is_equal_approx(d.cost, 3.0), "three diagonals, three squares: %s" % [d])
	check(is_equal_approx(mq.path(sid, "7,2", "10,5", {"diagonals": "5-10-5"}).cost, 4.0), "5-10-5: 1 + 2 + 1")
	check(is_equal_approx(mq.path(sid, "7,2", "10,5", {"diagonals": "euclid"}).cost, 3.0 * sqrt(2.0)), "as the crow flies: 3√2")
	# the storeroom's door is shut: nothing outside can be reached, until it opens
	var shut := mq.path(sid, "7,2", "7,0")
	check(not shut.ok and shut.why == "walls", "the closed door: no way out (%s)" % [shut.why])
	var door := {}
	for w in k.state.level_for(sid).walls:
		if str(w.get("door", "none")) == "door":
			door = w
	check(k.commit([{"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}}], "Open") == "", "the door opens")
	var out := mq.path(sid, "7,2", "7,0")
	check(out.ok and out.steps == 2, "through the open door: two squares north (%s)" % [out.cells])
	# a diagonal can't cut the corner where the wall ends at the door's post
	var corner := mq.path(sid, "6,2", "7,1")
	check(corner.ok and corner.steps == 2 and corner.cells == ["6,2", "7,2", "7,1"], "round the door post, not across its corner: %s" % [corner.cells])
	check(mq.path(sid, "7,2", "17,6").why == "walls", "the vault's secret door is shut: no way in")
	# rough ground: the ruleset says what a tag costs; the dearest applies, not the sum
	var row := []
	for x in range(3, 13):
		row.append(Vector2i(x, 4))
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_rubble", row, ["difficult"])},
		{"t": "region.add", "scene": sid, "region": MapQuery.region("r_mud", row, ["mud"])}], "Rough ground")
	check(is_equal_approx(mq.path(sid, "7,2", "7,6").cost, 4.0), "with no price for its tags, rough ground is plain ground")
	var rough := mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2, "mud": 2}})
	check(rough.ok and is_equal_approx(rough.cost, 5.0) and is_equal_approx(rough.length, 4.0) and rough.costly.size() == 1 and str(rough.costly[0]).ends_with(",4"),
		"across the row of rubble and mud: 5 squares of movement for 4 of ground, one square dear (both tags, 2 not 4): %s" % [rough])
	check(is_equal_approx(mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 3}}).cost, 6.0), "a dearer price is the ruleset's to say")
	# a single cell's price, and cells closed (a creature's space in a corridor)
	check(is_equal_approx(mq.path(sid, "7,2", "7,3", {"cell_costs": {"7,3": 2}}).cost, 2.0), "a cell of its own price")
	var round_it := mq.path(sid, "7,2", "7,6", {"blocked": ["7,3", "7,4", "7,5"]})
	check(round_it.ok and round_it.steps == 4 and not round_it.cells.has("7,4"), "cells closed in the way: round them, no dearer on squares: %s" % [round_it.cells])
	var walled_in := mq.path(sid, "7,2", "7,6", {"blocked": row.map(func(c: Vector2i) -> String: return HexMap.cell_key(c)) + ["2,4"]})
	check(not walled_in.ok and walled_in.why == "blocked" and walled_in.through.size() == 1, "a row of them from wall to wall: blocked, and which is in the way: %s" % [walled_in.get("through")])
	# too dear for what a ruleset is willing to look at
	var far := mq.path(sid, "7,2", "7,10", {"max": 3})
	check(not far.ok and far.why == "far" and far.cost > 3.0, "past the most it may cost: far (%s)" % [far.cost])
	check(mq.path(sid, "7,2", "40,40").why == "off the map", "off the map")


## Terrain tagged by its art (the Dungeons & Castles pack's rubble is
## "difficult"): a cell's record says so, and a path pays for it, once the
## kernel has the art the Table draws with — never without it.
func test_paths_price_terrain_by_its_art() -> void:
	var parts := _cellar_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var lvl := k.state.level_for(sid)
	for key in ["6,4", "7,4", "8,4"]:
		lvl.terrain[key] = {"t": "dungeons_and_castles:rubble", "v": 0, "rot": 0, "z": 0}
	check(mq.cell(sid, "7,4").terrain.get("tags", []) == [] and is_equal_approx(mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2}}).cost, 4.0), "with no art, the terrain has no tags and costs nothing more")
	var art := PackLibrary.new()
	art.reload()
	mq.art = art
	check(mq.cell(sid, "7,4").terrain.tags == ["difficult"] and mq.terrain_tags(sid, "7,4") == ["difficult"] and mq.terrain_tags(sid, "7,3") == [], "with the art: the rubble is difficult, the flagstones are nothing: %s" % [mq.cell(sid, "7,4").terrain])
	var p := mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2}})
	check(p.ok and is_equal_approx(p.cost, 4.0) and not p.cells.has("7,4"), "round three squares of rubble: no dearer on squares: %s" % [p.cells])
	var into := mq.path(sid, "7,2", "7,4", {"costs": {"difficult": 2}})
	check(into.ok and is_equal_approx(into.cost, 3.0) and into.costly == ["7,4"], "onto the rubble: 1 + 2 (%s)" % [into])
	# on hexes too: a step onto the chapel's rubble
	var m := _chapel()
	var st := EncounterState.new(Encounter.create("Hexes"))
	st.attach_map(m)
	var hk := RulesKernel.new(st)
	hk.map.art = art
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	hk.commit([{"t": "scene.add", "scene": sc}], "Setup")
	var rubble := ""
	for key in m.level(0).terrain:
		if str(m.level(0).terrain[key].t) == "dungeons_and_castles:rubble":
			rubble = str(key)
			break
	check(rubble != "", "the chapel has rubble")
	var there := HexMap.key_cell(rubble)
	var next_to: Vector2i = there
	for nb in m.grid.neighbors(there):
		var nk := HexMap.cell_key(nb)
		if m.grid.in_bounds(nb) and not ["dungeons_and_castles:rubble"].has(str(m.level(0).terrain.get(nk, {}).get("t", ""))) and hk.map.path(str(sc.id), nb, there).ok:
			next_to = nb
			break
	var step := hk.map.path(str(sc.id), next_to, there, {"costs": {"difficult": 2}})
	check(step.ok and step.steps == 1 and is_equal_approx(step.cost, 2.0), "a hex step onto rubble costs two: %s" % [step])


## A move's aftermath that waits on a player's answer (a reaction asked as an
## opportunity attack lands) has its time budget from when the answer came,
## not from the move: a player who thought it over for ten seconds still has
## the plugin's commits after it go through.
func test_a_hook_waiting_on_an_answer_has_its_time_from_the_answer() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var parts := _cellar_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var host := PluginHost.new(k)
	var why := host.load_source({"id": "t.react", "version": "1", "api": 1, "name": "React", "capabilities": ["prompts", "log", "state"]}, [["main.lua", """
		local hm = hexmap
		hm.on("after_move", function(p)
			local ans = hm.prompt("pl_1", { title = "React?", fields = {} }, { default = { react = false }, deadline = 30 })
			if ans and ans.react then hm.commit({ t = "log.add", entry = { id = "n_reacted", kind = "note", text = "reacted after the answer" } }, "Reacted") end
			return p
		end)
	"""]])
	check(why == "", "the plugin loads: %s" % why)
	host.call_ms_budget = 50
	var g: HexGrid = k.state.map_for(sid).grid
	check(k.move_token(sid, "t_h", g.cell_center(Vector2i(7, 3)), "pl_1") == "", "the hero moves")
	check(k.pending.prompts().size() == 1, "and the move's aftermath waits on its player")
	OS.delay_msec(150)
	var pid := str(k.pending.prompts().keys()[0]) if k.pending.prompts().size() > 0 else ""
	check(k.pending.answer(pid, {"react": true}, "pl_1") == "", "answered, later than the budget would run from the move")
	check(k.state.encounter.log.any(func(e: Dictionary) -> bool: return str(e.get("text", "")) == "reacted after the answer"), "its commit after the answer went through")


## A ruleset asks for a path from Lua (hm.map.path), its prices and closed
## cells as tables, and gets it back as one.
func test_paths_from_lua() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var parts := _cellar_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_rubble", [Vector2i(7, 3)], ["difficult"])}], "Rubble")
	var host := PluginHost.new(k)
	var why := host.load_source({"id": "t.path", "version": "1", "api": 1, "name": "Paths", "capabilities": ["actions"]}, [["main.lua", """
		local hm = hexmap
		hm.actions.register("walk", { label = "Walk", target = "", run = function(ctx)
			local p = hm.map.path(ctx.scene, "token:t_h", ctx.to, { costs = { difficult = 2 }, blocked = ctx.blocked or {}, max = ctx.max })
			return { ok = p.ok, cost = p.cost, steps = p.steps, why = p.why, first = p.cells[1], through = p.through and #p.through or 0 }
		end })
	"""]])
	check(why == "", "the plugin loads: %s" % why)
	var pc := host.dispatch("t.path", "walk", {"scene": sid, "to": "7,5"})
	check(pc.status == PluginHost.PluginCall.OK and pc.value.ok and is_equal_approx(float(pc.value.cost), 3.0) and int(pc.value.steps) == 3 and str(pc.value.first) == "7,2",
		"round a square of rubble, three squares down: %s" % [pc.value if pc.status == PluginHost.PluginCall.OK else pc.error])
	pc = host.dispatch("t.path", "walk", {"scene": sid, "to": "7,5", "blocked": ["6,3", "8,3"]})
	check(pc.status == PluginHost.PluginCall.OK and is_equal_approx(float(pc.value.cost), 4.0), "with the squares either side closed, through the rubble: 1 + 2 + 1 (%s)" % [pc.value])
	pc = host.dispatch("t.path", "walk", {"scene": sid, "to": "7,11", "max": 2})
	check(pc.status == PluginHost.PluginCall.OK and not pc.value.ok and str(pc.value.why) == "far", "and says when it is too far to look")
	# a big creature's way and space, and what swimming adds, from Lua too
	why = host.load_source({"id": "t.space", "version": "1", "api": 1, "name": "Spaces", "capabilities": ["actions"]}, [["main.lua", """
		local hm = hexmap
		hm.actions.register("big", { label = "Big", target = "", run = function(ctx)
			local p = hm.map.path(ctx.scene, ctx.from, ctx.to, { size = 2, extra = { water = 1 } })
			local s = hm.map.space(ctx.scene, ctx.to, 2, { blocked = ctx.blocked or {} })
			local c = 0
			for _, x in ipairs(p.step_costs or {}) do c = c + x end
			return { ok = p.ok, why = p.why, cost = p.cost, summed = c, space = #(p.space or {}), fits = s.fits, cells = #s.cells }
		end })
	"""]])
	check(why == "", "the second plugin loads: %s" % why)
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_pool", [Vector2i(5, 6), Vector2i(6, 6)], ["water"])}], "A pool")
	pc = host.dispatch("t.space", "big", {"scene": sid, "from": "5,3", "to": "5,8"})
	check(pc.status == PluginHost.PluginCall.OK and pc.value.ok and int(pc.value.space) == 4 and bool(pc.value.fits) and int(pc.value.cells) == 4
		and is_equal_approx(float(pc.value.cost), float(pc.value.summed)), "a Large creature's way down the storeroom, its space where it ends, each step's cost: %s" % [pc.value if pc.status == PluginHost.PluginCall.OK else pc.error])
	pc = host.dispatch("t.space", "big", {"scene": sid, "from": "7,4", "to": "7,0"})
	check(pc.status == PluginHost.PluginCall.OK and not pc.value.ok and str(pc.value.why) == "walls", "the door shut: no way out (%s)" % [pc.value])
	pc = host.dispatch("t.space", "big", {"scene": sid, "from": "5,3", "to": "5,8", "blocked": {"5,8": true, "6,8": true, "4,8": true}})
	check(pc.status == PluginHost.PluginCall.OK and not bool(pc.value.fits), "no room for it where others stand: %s" % [pc.value])


## A map on grid `g` with a wall across it along the edges between row `row`
## and the next (a straight line on squares, the zigzag of hex edges on
## hexes), open below the cells in `gaps`: [kernel, scene id].
func _gap_kernel(g: HexGrid, row: int, gaps: Array) -> Array:
	var m := HexMap.create("Gaps", g)
	var lvl := m.level(0)
	_wall_below(lvl, g, row, gaps)
	var st := EncounterState.new(Encounter.create("Gaps"))
	st.attach_map(m)
	var k := RulesKernel.new(st)
	var sc := Encounter.new_scene(m, str(lvl.id), "Gaps", "")
	k.commit([{"t": "scene.add", "scene": sc}], "Setup")
	return [k, str(sc.id)]


## Walls on a level along the edges between row `row` and the next, but below
## the cells in `gaps`.
func _wall_below(lvl: Dictionary, g: HexGrid, row: int, gaps: Array) -> void:
	var solid := {"move": true, "sight": true, "light": true, "sound": true}
	for col in g.columns:
		var c := g.offset_to_axial(col, row)
		if gaps.has(c):
			continue
		var below: Array = [c + Vector2i(0, 1)] if g.is_square() else [c + Vector2i(0, 1), c + Vector2i(-1, 1)]
		for b in below:
			var shared := []
			for p in g.cell_corners(c):
				for q in g.cell_corners(b):
					if p.distance_to(q) < 1e-4:
						shared.append([p.x, p.y])
			if shared.size() == 2:
				lvl.walls.append({"id": "w_%d_%d" % [row, lvl.walls.size()], "points": shared, "blocks": solid, "door": "none", "state": "closed"})


## A creature's space, as the SRD 5.2's Creature Size and Space has it on a
## square grid ("Large 10 by 10 feet, 4 squares (2 by 2)"), and its hex
## equivalent; a big creature's way needs room for all of it: through a gap
## two cells wide, not one; its token on either cell of the gap; nowhere its
## space won't fit ("no room"); round others' spaces, or blocked by them.
func test_paths_fit_a_big_creature() -> void:
	var sq := HexGrid.square(12, 10)
	var hx := HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 12, 10)
	check(MapQuery.footprint(sq, 1).size() == 1 and MapQuery.footprint(sq, 0.5).size() == 1 and MapQuery.footprint(sq, 2).size() == 4
		and MapQuery.footprint(sq, 3).size() == 9 and MapQuery.footprint(sq, 4).size() == 16, "on squares: 1, 2 by 2, 3 by 3, 4 by 4")
	check(MapQuery.footprint(hx, 2).size() == 3 and MapQuery.footprint(hx, 3).size() == 7 and MapQuery.footprint(hx, 4).size() == 12
		and MapQuery.footprint(hx, 5).size() == 19, "on hexes: 3, 7, 12 and 19 hexes")
	for tri in [MapQuery.footprint(hx, 2)]:
		check(HexGrid.axial_distance(tri[0], tri[1]) == 1 and HexGrid.axial_distance(tri[0], tri[2]) == 1 and HexGrid.axial_distance(tri[1], tri[2]) == 1,
			"a Large creature's three hexes each beside the others: %s" % [tri])
	# squares: one square open in the wall
	var one := _gap_kernel(sq, 4, [Vector2i(5, 4)])
	var mq: MapQuery = one[0].map
	var sid: String = one[1]
	var small := mq.path(sid, "5,1", "5,8")
	check(small.ok and small.steps == 7 and small.space == ["5,8"], "one square across goes through the gap: %s" % [small])
	var big := mq.path(sid, "5,1", "5,8", {"size": 2})
	check(not big.ok and big.why == "narrow", "a Large creature can't: too narrow for it (%s)" % [big.why])
	check(not mq.path(sid, "5,1", "5,8", {"size": 3}).ok, "nor a Huge one")
	# two squares open: a Large creature goes through, a Huge one doesn't
	var two := _gap_kernel(sq, 4, [Vector2i(5, 4), Vector2i(6, 4)])
	mq = two[0].map
	sid = two[1]
	var through := mq.path(sid, "5,1", "5,8", {"size": 2})
	check(through.ok and through.steps == 7 and is_equal_approx(through.cost, 7.0) and through.space.size() == 4 and through.space.has("5,8"),
		"a Large creature through two squares open: 7 squares, its space at the end: %s" % [through])
	var summed := 0.0
	for c in through.step_costs:
		summed += float(c)
	check(through.step_costs.size() == 7 and is_equal_approx(summed, through.cost), "each step's cost: %s" % [through.step_costs])
	var diag := mq.path(sid, "2,1", "4,3", {"diagonals": "5-10-5"})
	check(diag.step_lengths == [1.0, 2.0] and diag.step_costs == [1.0, 2.0], "each step at 1 a cell (5-10-5's second diagonal 2): %s" % [diag.step_lengths])
	check(mq.path(sid, "6,1", "6,8", {"size": 2}).ok and mq.path(sid, "5,1", "6,8", {"size": 2}).ok, "its token on either square of the gap: its space spreads the way there is room")
	check(mq.path(sid, "5,1", "5,8", {"size": 3}).why == "narrow", "a Huge one (3 by 3) doesn't fit")
	var sp := mq.space(sid, "5,4", 2)
	check(sp.fits and sp.cells.size() == 4 and sp.cells.has("5,4") and sp.cells.has("6,5"), "standing in the gap, its space straddles the wall's line: %s" % [sp])
	check(mq.space(sid, "3,4", 2).fits and not mq.space(sid, "3,4", 2).cells.has("3,5"), "beside the wall, its space is on the wall's near side: %s" % [mq.space(sid, "3,4", 2)])
	# others in the way: their squares closed
	var shut := mq.path(sid, "5,1", "5,8", {"size": 2, "blocked": ["6,4"]})
	check(not shut.ok and shut.why == "blocked" and shut.through == ["6,4"], "one standing in the gap: blocked, and by which square: %s" % [shut.get("through")])
	check(mq.path(sid, "5,1", "5,8", {"blocked": ["6,4"]}).ok, "a creature of one square passes beside it")
	# rough ground (two columns of it): a step of the space pays the dearest of the cells it enters
	var strip := []
	for y in range(0, 4):
		strip.append(Vector2i(8, y))
		strip.append(Vector2i(9, y))
	two[0].commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_rough", strip, ["difficult"])}], "Rubble")
	var onto := mq.path(sid, "6,2", "8,2", {"size": 2, "costs": {"difficult": 2}})
	check(onto.ok and is_equal_approx(onto.cost, 3.0) and onto.costly.size() == 1, "two squares on into the rubble: its first column entered once, at 2 (%s)" % [onto])
	var inside := mq.path(sid, "8,2", "9,2", {"size": 2, "costs": {"difficult": 2}})
	check(inside.ok and is_equal_approx(inside.cost, 1.0), "standing in it, a token's step within its space enters nothing: 1 (%s)" % [inside])
	check(is_equal_approx(mq.path(sid, "7,2", "8,2", {"costs": {"difficult": 2}}).cost, 2.0) and is_equal_approx(mq.path(sid, "6,2", "7,2", {"size": 2, "costs": {"difficult": 2}}).cost, 1.0),
		"one square across pays for the square it enters; the space short of the rubble pays nothing more")
	# a corridor two squares wide (rows 4 and 5): a Large token nudged from one row to
	# the other is one step, its space staying where it fits
	var cor := _gap_kernel(sq, 3, [])
	_wall_below((cor[0] as RulesKernel).state.level_for(cor[1]), sq, 5, [])
	var cq: MapQuery = cor[0].map
	var nudge := cq.path(cor[1], "3,4", "4,5", {"size": 2})
	check(nudge.ok and nudge.steps == 1 and is_equal_approx(nudge.cost, 1.0), "a Large token nudged across a corridor two wide: one step (%s)" % [nudge])
	check(cq.path(cor[1], "3,4", "3,5", {"size": 2}).ok and is_equal_approx(cq.path(cor[1], "3,4", "9,5", {"size": 2}).cost, 6.0), "straight across it, and along it")
	check(cq.path(cor[1], "3,4", "3,5", {"size": 3}).why == "no room", "a Huge one: no room in it")
	# hexes: the same, the zigzag of hex edges
	var h1 := _gap_kernel(hx, 4, [hx.offset_to_axial(5, 4)])
	var hq: MapQuery = h1[0].map
	var hs: String = h1[1]
	var from := HexMap.cell_key(hx.offset_to_axial(5, 1))
	var to := HexMap.cell_key(hx.offset_to_axial(5, 8))
	check(hq.path(hs, from, to).ok, "on hexes one creature of a hex goes through a hex's gap")
	check(hq.path(hs, from, to, {"size": 2}).why == "narrow", "a Large one (three hexes) can't: %s" % [hq.path(hs, from, to, {"size": 2}).why])
	var h2 := _gap_kernel(hx, 4, [hx.offset_to_axial(5, 4), hx.offset_to_axial(6, 4)])
	hq = h2[0].map
	hs = h2[1]
	var hp := hq.path(hs, from, to, {"size": 2})
	check(hp.ok and hp.space.size() == 3, "through two hexes open it goes: %s" % [hp])
	check(hq.path(hs, from, to, {"size": 3}).why == "narrow", "a Huge one (seven hexes) doesn't")
	# the cellar: the storeroom's door is one square, and between the storeroom and the
	# vault a corridor one square wide
	var parts := _cellar_kernel()
	var k: RulesKernel = parts[0]
	var cs: String = parts[1]
	for w in k.state.level_for(cs).walls:
		if str(w.get("door", "none")) == "door":
			k.commit([{"t": "element.set", "scene": cs, "ref": "walls:" + str(w.id), "changes": {"state": "open"}}], "Open")
	check(k.map.path(cs, "7,4", "7,0").ok and k.map.path(cs, "7,4", "7,0", {"size": 2}).why == "narrow", "out through the door: a Medium creature, not a Large one")
	check(k.map.path(cs, "7,4", "13,6", {"size": 2}).why == "no room" and not k.map.space(cs, "13,6", 2).fits, "no room in the corridor for a Large one")
	check(k.map.space(cs, "token:t_h").cells == ["7,2"], "a token's own space, by its size: %s" % [k.map.space(cs, "token:t_h")])


## What a cell's kinds add or waive: `extra` on top of the dearest of `costs`
## (swimming, a foot more for each: difficult water 2 + 1), `free` ground of a
## kind at no more than 1 (boots that ignore ice), by a region's tags or the
## terrain's own name (the art's rubble: "rubble").
func test_paths_add_and_waive_by_kind() -> void:
	var parts := _cellar_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var mq := k.map
	var row := []
	for x in range(3, 13):
		row.append(Vector2i(x, 4))
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_pool", row, ["water"])}], "A pool")
	check(is_equal_approx(mq.path(sid, "7,2", "7,6", {"extra": {"water": 1}}).cost, 5.0), "across a row of water: a square more")
	check(is_equal_approx(mq.path(sid, "7,2", "7,6").cost, 4.0), "priced by nothing, it costs nothing more")
	k.commit([{"t": "region.set", "scene": sid, "id": "r_pool", "changes": {"tags": ["water", "difficult"]}}], "Rough water")
	var rough := mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2}, "extra": {"water": 1}})
	check(is_equal_approx(rough.cost, 6.0) and rough.step_costs.has(3.0), "difficult water: 2, and a square more to swim it (%s)" % [rough.step_costs])
	check(is_equal_approx(mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2}, "extra": {"water": 1}, "free": ["water"]}).cost, 5.0),
		"its kind waived: the swim's square more, not the difficult ground's")
	k.commit([{"t": "region.set", "scene": sid, "id": "r_pool", "changes": {"tags": ["ice", "difficult"]}}], "Ice")
	check(is_equal_approx(mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2}, "free": ["ice"]}).cost, 4.0), "ice waived: plain ground")
	check(is_equal_approx(mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2}, "free": ["snow"]}).cost, 5.0), "snow waived is not ice")
	var spaces := {}
	for c in row:
		spaces[HexMap.cell_key(c)] = 2
	check(is_equal_approx(mq.path(sid, "7,2", "7,6", {"costs": {"difficult": 2}, "free": ["ice"], "cell_costs": spaces}).cost, 5.0), "a cell's own price (a creature's space) still stands")
	# the art's rubble, by its name
	k.commit([{"t": "region.remove", "scene": sid, "id": "r_pool"}], "Dry")
	var lvl := k.state.level_for(sid)
	for key in ["6,4", "7,4", "8,4"]:
		lvl.terrain[key] = {"t": "dungeons_and_castles:rubble", "v": 0, "rot": 0, "z": 0}
	var art := PackLibrary.new()
	art.reload()
	mq.art = art
	check(is_equal_approx(mq.path(sid, "7,2", "7,4", {"costs": {"difficult": 2}}).cost, 3.0), "onto the rubble: 1 + 2")
	check(is_equal_approx(mq.path(sid, "7,2", "7,4", {"costs": {"difficult": 2}, "free": ["rubble"]}).cost, 2.0), "rubble waived by the terrain's own name: 1 + 1")


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
