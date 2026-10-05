extends TestCase
## The table's shared marks — rulers, templates, spells' previews, pings —
## and how far a ruler says: kept on the Table, sent to everyone allowed to
## see them, gone when let go or when their time is up unless pinned, never
## in the saved game or the undo history; the ruler's distances on squares
## and hexes by each diagonal rule, the walk round a wall.

const WebSuite := preload("res://tests/suites/web.gd")


## A square map `cols` × `rows` with a wall down x = 5 from the top to y = 8
## (a way round below it): [kernel, scene id].
func _walled_kernel(cols := 12, rows := 10) -> Array:
	var g := HexGrid.square(cols, rows)
	var m := HexMap.create("Walled", g)
	var lvl := m.level(0)
	lvl.walls.append({"id": "w_long", "points": [[5, 0], [5, 8]], "blocks": {"move": true, "sight": true, "light": true, "sound": true}, "door": "none", "state": "closed"})
	var st := EncounterState.new(Encounter.create("Walled"))
	st.attach_map(m)
	var k := RulesKernel.new(st)
	var sc := Encounter.new_scene(m, str(lvl.id), "Walled", "")
	k.commit([{"t": "scene.add", "scene": sc}], "Setup")
	return [k, str(sc.id)]


func _pts(list: Array) -> Array:
	return list.map(func(p: Array) -> Vector2: return Vector2(p[0], p[1]))


func test_ruler_distances() -> void:
	var sq := HexGrid.square(20, 14)
	# three squares across and two down: two diagonals and one straight
	var a := _pts([[0.5, 0.5], [3.5, 2.5]])
	check(near(Measure.straight(sq, a, "5-5-5"), 15.0), "5-5-5: every square five feet, the diagonals too (%s)" % Measure.straight(sq, a, "5-5-5"))
	check(near(Measure.straight(sq, a, "5-10-5"), 20.0), "5-10-5: the second diagonal ten (%s)" % Measure.straight(sq, a, "5-10-5"))
	check(near(Measure.straight(sq, a, "euclid"), sqrt(13.0) * 5.0), "as the crow flies: √13 squares (%s)" % Measure.straight(sq, a, "euclid"))
	check(Measure.amount(Measure.straight(sq, a, "euclid"), "ft") == "18 ft", "said to the foot: %s" % Measure.amount(Measure.straight(sq, a, "euclid"), "ft"))
	# a path's diagonals are counted along all of it: one, then another, is 5 + 10
	var bent := _pts([[0.5, 0.5], [1.5, 1.5], [2.5, 2.5]])
	check(near(Measure.straight(sq, bent, "5-10-5"), 15.0), "5-10-5 counts the second diagonal on the next leg (%s)" % Measure.straight(sq, bent, "5-10-5"))
	check(near(Measure.straight(sq, _pts([[0.5, 0.5], [1.5, 1.5], [2.5, 2.5], [3.5, 3.5]]), "5-10-5"), 20.0), "three diagonals over three legs: 5 + 10 + 5")
	check(near(Measure.straight(sq, _pts([[0.2, 0.3], [0.9, 0.7]]), "5-5-5"), 0.0), "two points in one square: no distance")
	# a waypoint: there and back is the sum
	check(near(Measure.straight(sq, _pts([[0.5, 0.5], [4.5, 0.5], [4.5, 3.5]]), "5-5-5"), 35.0), "four along, three down: 35 feet")
	# hexes: steps, whatever the diagonal rule says
	var hex := HexGrid.new()
	var h0 := hex.cell_center(hex.offset_to_axial(2, 3))
	var h1 := hex.cell_center(hex.offset_to_axial(6, 3))
	for rule in Measure.RULES:
		check(near(Measure.straight(hex, [h0, h1], rule), 20.0), "hexes: four steps, twenty feet (%s): %s" % [rule, Measure.straight(hex, [h0, h1], rule)])
	var h2 := hex.cell_center(hex.offset_to_axial(4, 7))
	check(near(Measure.straight(hex, [h0, h2], "5-5-5"), float(hex.steps(hex.world_to_axial(h0), hex.world_to_axial(h2))) * 5.0), "and down the rows by the hexes' own steps")
	# metres: the map's own scale and unit
	var metric := HexGrid.square(20, 14)
	metric.units = "m"
	metric.distance = 1.5
	var m3 := Measure.straight(metric, _pts([[0.5, 0.5], [3.5, 0.5]]), "5-5-5")
	check(near(m3, 4.5) and Measure.amount(m3, "m") == "4.5 m", "three squares of 1.5 m: %s" % Measure.amount(m3, "m"))
	# a map with no grid drawn (a painted region): point to point
	check(near(Measure.straight(sq, _pts([[1.0, 1.0], [4.0, 5.0]]), "5-5-5", true), 25.0), "no grid: as the points lie, five squares' worth")
	# the open walk (nothing in the way) a detour is weighed against
	check(near(Measure.open_walk(sq, a, "euclid"), (1.0 + 2.0 * sqrt(2.0)) * 5.0), "the open walk as the crow flies is a square and two diagonals")
	check(Measure.words({"straight": 30.0, "walk": 45.0, "units": "ft"}) == "30 ft straight, 45 ft to walk round", "both, in words")
	check(Measure.words({"straight": 30.0, "units": "ft"}) == "30 ft", "one, when the walk is the same")


func test_walk_round_a_wall() -> void:
	var parts := _walled_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var g := st.map_for(sid).grid
	var across := [g.cell_center(Vector2i(3, 2)), g.cell_center(Vector2i(7, 2))]
	var me := Measure.ruler(k.map, st, sid, across)
	check(near(float(me.straight), 20.0), "four squares across: 20 feet straight (%s)" % me)
	check(me.has("walk") and near(float(me.walk), 65.0), "the wall runs down to the eighth row: thirteen squares to walk round it (%s)" % me)
	check(str(me.words) == "20 ft straight, 65 ft to walk round", "and said: %s" % me.words)
	check((me.cells as Array).size() == 14 and str(me.cells[0]) == "3,2" and str(me.cells[-1]) == "7,2", "the way, cell by cell: %s" % [me.cells])
	# the same rule as the moves': under 5-10-5 the way round costs its dear diagonals
	k.map.register_measure("t.rules", {"diagonals": "5-10-5"})
	var dear := Measure.ruler(k.map, st, sid, across)
	check(float(dear.walk) > float(me.walk), "5-10-5 makes the walk dearer: %s" % dear.words)
	k.map.measure_rules.clear()
	# with nothing in the way, only the one distance
	var beside := Measure.ruler(k.map, st, sid, [g.cell_center(Vector2i(6, 2)), g.cell_center(Vector2i(9, 4))])
	check(not beside.has("walk") and str(beside.words) == "15 ft", "nothing in the way: just the distance (%s)" % beside.words)
	# under fog a player's walk keeps to what the party knows: into the unknown, nothing
	st.apply({"t": "fog.set", "scene": sid, "enabled": true})
	var west := []
	for y in 10:
		for x in 5:
			west.append(HexMap.cell_key(Vector2i(x, y)))
	st.apply({"t": "fog.reveal", "scene": sid, "cells": west})
	var dark := Measure.ruler(k.map, st, sid, across, "pl_1")
	check(near(float(dark.straight), 20.0) and not dark.has("walk") and not dark.has("no_way") and str(dark.words) == "20 ft", "measuring into the dark: the distance, nothing of what is there (%s)" % dark.words)
	check(Measure.ruler(k.map, st, sid, across, "gm").has("walk"), "the DM's walk is the map's")
	# the east known too: the player's walk is priced, round the wall
	var east := []
	for y in 10:
		for x in range(5, 12):
			east.append(HexMap.cell_key(Vector2i(x, y)))
	st.apply({"t": "fog.reveal", "scene": sid, "cells": east})
	check(str(Measure.ruler(k.map, st, sid, across, "pl_1").words) == "20 ft straight, 65 ft to walk round", "known ground: the walk round it")
	# walled in: the DM hears there is no way
	st.map_for(sid).level(0).walls.append({"id": "w_foot", "points": [[5, 8], [5, 10]], "blocks": {"move": true, "sight": true, "light": true, "sound": true}, "door": "none", "state": "closed"})
	var none := Measure.ruler(k.map, st, sid, across)
	check(bool(none.get("no_way", false)) and str(none.words) == "20 ft straight; no way to walk there", "no way round: said (%s)" % none.words)
	check(not Measure.ruler(k.map, st, sid, across, "pl_1").has("no_way"), "but never to a player: the walls they haven't seen are the DM's")


## The walk priced as the rules price a move (hm.map.measure's `costs`):
## difficult ground at double — a region's, or the art's rubble — on a map
## with no walls at all; a player's priced only by the ground they are
## shown, and the DM's walk theirs only where nothing kept from them priced
## it; a ruler measured again when the ground changes.
func test_walk_over_rough_ground() -> void:
	var parts := _walled_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var g := st.map_for(sid).grid
	st.map_for(sid).level(0).walls.clear()
	var across := [g.cell_center(Vector2i(3, 2)), g.cell_center(Vector2i(7, 2))]
	# a band of rubble down x = 5, the map's whole height: no way round it
	var band := []
	for y in 10:
		band.append(Vector2i(5, y))
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_rubble", band, ["difficult"])}], "Rubble")
	var plain := Measure.ruler(k.map, st, sid, across)
	check(not plain.has("walk") and str(plain.words) == "20 ft", "with no price from the rules, rough ground is ground: %s" % plain.words)
	k.map.register_measure("t.rules", {"diagonals": "5-5-5", "costs": {"difficult": 2}})
	check(k.map.measure_rule().get("costs", {}) == {"difficult": 2.0}, "the rulers' rule carries the price: %s" % [k.map.measure_rule()])
	var rough := Measure.ruler(k.map, st, sid, across)
	check(str(rough.words) == "20 ft straight, 25 ft to walk round" and not rough.has("secret"), "over the rubble, a map with no walls: one square at double (%s)" % rough.words)
	var beside := Measure.ruler(k.map, st, sid, [g.cell_center(Vector2i(6, 2)), g.cell_center(Vector2i(9, 4))])
	check(not beside.has("walk") and str(beside.words) == "15 ft", "nothing dear on the way: the distance alone (%s)" % beside.words)
	# a gap in the band: the walk goes round it if that's cheaper, and says so
	k.commit([{"t": "region.set", "scene": sid, "id": "r_rubble", "changes": {"cells": band.filter(func(c: Vector2i) -> bool: return c.y != 3).map(func(c: Vector2i) -> String: return HexMap.cell_key(c))}}], "A way through")
	check(str(Measure.ruler(k.map, st, sid, across).words) == "20 ft", "a gap a square aside: the walk through it is no longer than the ground (%s)" % Measure.ruler(k.map, st, sid, across).words)
	k.commit([{"t": "region.remove", "scene": sid, "id": "r_rubble"}], "Cleared")
	# the art's rubble (terrain tagged difficult), once the Table has the art it draws with
	var lvl := st.level_for(sid)
	for y in 10:
		lvl.terrain[HexMap.cell_key(Vector2i(5, y))] = {"t": "dungeons_and_castles:rubble", "v": 0, "rot": 0, "z": 0}
	check(not Measure.ruler(k.map, st, sid, across).has("walk"), "with no art, terrain has no tags")
	var art := PackLibrary.new()
	art.reload()
	k.map.art = art
	check(str(Measure.ruler(k.map, st, sid, across).words) == "20 ft straight, 25 ft to walk round", "the pack's rubble is difficult: priced the same (%s)" % Measure.ruler(k.map, st, sid, across).words)
	lvl.terrain.clear()
	# ground the DM keeps from the players: priced for the DM, not for a player
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_quag", band, ["difficult"], {"audience": "gm"})}], "A hidden quag")
	var dm := Measure.ruler(k.map, st, sid, across, "gm")
	check(str(dm.words) == "20 ft straight, 25 ft to walk round" and bool(dm.get("secret", false)), "the DM's walk over it, marked as the DM's (%s)" % [dm])
	check(str(Measure.ruler(k.map, st, sid, across, "pl_1").words) == "20 ft", "a player's own ruler: the quag isn't theirs to know")
	# the Table's marks: the DM's ruler reaches a player as the distance alone
	st.apply({"t": "player.add", "player": {"id": "pl_1", "name": "Ana", "color": "#4f9cf6"}})
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = k
	host.marks.bind(st, k.map)
	check(host.marks.put("gm", {"id": "dm-ruler-quag", "kind": "ruler", "scene": sid, "points": [[3.5, 2.5], [7.5, 2.5]]}, {"name": "DM", "color": "#ffffff"}, true) == "", "the DM measures across the quag")
	var m: Dictionary = host.marks.marks["dm-ruler-quag"]
	check(str(m.measure.words) == "20 ft straight, 25 ft to walk round" and bool(m.get("_walk_secret", false)) and not (m.measure as Dictionary).has("secret"), "the DM's own: the walk, kept as the DM's (%s)" % [m.measure])
	var to_ana := host._mark_for({"player": "pl_1", "role": Views.ROLE_PLAYER, "joined": true}, m)
	check(str(to_ana.measure.words) == "20 ft" and not to_ana.has("_walk_secret"), "Ana sees the distance alone: %s" % [to_ana.get("measure")])
	# the quag shown to everyone: the walk is theirs too, the ruler measured again as it changed
	k.commit([{"t": "region.set", "scene": sid, "id": "r_quag", "changes": {"audience": "all"}}], "The quag shown")
	m = host.marks.marks["dm-ruler-quag"]
	check(not m.has("_walk_secret") and str(host._mark_for({"player": "pl_1", "role": Views.ROLE_PLAYER, "joined": true}, m).measure.words) == "20 ft straight, 25 ft to walk round",
		"once shown, Ana's screen says the walk too (%s)" % [m.measure])
	k.commit([{"t": "region.remove", "scene": sid, "id": "r_quag"}], "Gone")
	check(str(host.marks.marks["dm-ruler-quag"].measure.words) == "20 ft", "the ground plain again: the ruler is measured again (%s)" % host.marks.marks["dm-ruler-quag"].measure.words)
	host.marks.bind(null, null)
	# a price the rulers can't use is no price
	k.map.measure_rules.clear()
	k.map.register_measure("t.odd", {"costs": {"difficult": 1, "mud": "a lot", "bog": -2, "": 3}})
	check(not k.map.measure_rule().has("costs"), "a cost of 1, words, less than nothing or no tag: none kept (%s)" % [k.map.measure_rule()])
	k.map.measure_rules.clear()


## The Table's Template tool, as the web screens' is: a circle, a cone, a line
## or a cube of any size in feet, put down on a cell, moved, turned with [ ]
## or its handle, changed by the tool options, taken off; and a ruleset's
## action on a template (target "template": Damage those caught) offered to
## the DM and sent as theirs with the creatures it catches.
func test_the_template_tool_on_the_table() -> void:
	var ctx := _table_ctx()
	var sid := ctx.scene_id
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var g := ctx.map().grid
	var tool := TableTools.make("template", ctx) as TableTools.TemplateTool
	tool.activate()
	var at := g.cell_center(g.offset_to_axial(9, 5))
	tool.press(at, MOUSE_BUTTON_LEFT, mods)
	var held: Array = ctx.marks.of_scene(sid).filter(func(m: Dictionary) -> bool: return str(m.kind) == "template")
	check(held.size() == 1 and bool(held[0].live) and str(held[0].owner) == "gm" and str(held[0].shape.type) == "circle" and is_equal_approx(float(held[0].shape.size), 4.0) and str(held[0].label) == "20-ft circle",
		"a click puts down a 20-ft circle, four cells round, the DM's: %s" % [held])
	check(ctx.template_mark == str(held[0].id) and Marks.point(held[0]).distance_to(at) < 0.01, "on the cell's middle; the tool options act on it")
	tool.release(at, MOUSE_BUTTON_LEFT, mods)
	check(not bool(ctx.marks.marks[ctx.template_mark].live), "let go: it lingers")
	# dragged: it moves
	var to := g.cell_center(g.offset_to_axial(11, 6))
	tool.press(at, MOUSE_BUTTON_LEFT, mods)
	tool.drag(to + Vector2(0.1, 0.1), MOUSE_BUTTON_LEFT, mods)
	tool.release(to, MOUSE_BUTTON_LEFT, mods)
	check(Marks.point(ctx.marks.marks[ctx.template_mark]).distance_to(to) < 0.01 and ctx.marks.of_scene(sid).size() == 1, "dragged to another cell: the same template, there")
	# the options: a 15-ft cone, turned by [ ] and by its handle
	ctx.template_type = "cone"
	ctx.template_feet = 15.0
	tool.reshape()
	var m: Dictionary = ctx.marks.marks[ctx.template_mark]
	check(str(m.shape.type) == "cone" and is_equal_approx(float(m.shape.size), 3.0) and str(m.label) == "15-ft cone", "the options make it a 15-ft cone: %s" % [m.shape])
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_BRACKETRIGHT
	check(tool.key(ev) and is_equal_approx(float(ctx.marks.marks[ctx.template_mark].direction), 15.0), "] turns it 15°")
	var k := tool.knob(ctx.marks.marks[ctx.template_mark])
	check(k != Vector2.INF and k.distance_to(to) > 2.9, "its handle at its far end: %s" % k)
	tool.press(k, MOUSE_BUTTON_LEFT, mods)
	tool.drag(to + Vector2(0, 3), MOUSE_BUTTON_LEFT, mods)
	tool.release(to + Vector2(0, 3), MOUSE_BUTTON_LEFT, mods)
	check(absf(float(ctx.marks.marks[ctx.template_mark].direction) - 90.0) < 0.5, "its handle dragged south: it faces south (%s)" % ctx.marks.marks[ctx.template_mark].direction)
	# a 30-ft line, 10 ft wide; a 20-ft cube on the corner between four cells
	ctx.template_type = "line"
	ctx.template_feet = 30.0
	ctx.template_width_feet = 10.0
	tool.reshape()
	m = ctx.marks.marks[ctx.template_mark]
	check(str(m.label) == "30-ft line" and is_equal_approx(float(m.shape.size), 6.0) and is_equal_approx(float(m.shape.width), 2.0), "a 30-ft line, 10 ft wide: %s" % [m.shape])
	ctx.template_type = "square"
	ctx.template_feet = 20.0
	tool.reshape()
	m = ctx.marks.marks[ctx.template_mark]
	var c := g.snap_to_center(Marks.point(m) - Vector2(0.5, 0.5))
	check(str(m.label) == "20-ft cube" and Marks.point(m).distance_to(c + Vector2(0.5, 0.5)) < 0.01, "a 20-ft cube stands on the corner between four cells: %s" % [m.points])
	# Esc takes it off
	ev.keycode = KEY_ESCAPE
	check(tool.key(ev) and ctx.template_mark == "" and ctx.marks.of_scene(sid).is_empty(), "Esc takes it off")
	# a ruleset's action on a template: offered, and sent as the DM's with whom it catches
	check(GmIntents.template_actions(ctx).is_empty(), "no ruleset's: nothing offered")
	if not PluginHost.available():
		ctx.canvas.free()
		skip("no Lua runtime in this build")
		return
	var why := ctx.host.load_source({"id": "t.areas", "version": "1", "api": 1, "name": "Areas", "capabilities": ["actions", "log"]}, [["main.lua", """
		local hm = hexmap
		hm.actions.register("boom", { label = "Damage those caught", target = "template", hint = "Its damage on each",
			run = function(ctx)
				hm.log("caught " .. table.concat(ctx.caught or {}, ",") .. " by " .. tostring(ctx.label) .. (ctx.gm and ", the DM's" or ""), "gm")
				return true
			end })
		hm.actions.register("other", { label = "Not this", target = "token", run = function(ctx) return true end })
	"""]])
	check(why == "", "the plugin loads: %s" % why)
	var acts := GmIntents.template_actions(ctx)
	check(acts.size() == 1 and str(acts[0].label) == "Damage those caught" and str(acts[0].plugin) == "t.areas" and str(acts[0].action) == "boom", "a template's actions, theirs alone: %s" % [acts])
	var goblin: Dictionary = ctx.state.tokens(sid).filter(func(t: Dictionary) -> bool: return str(t.name) == "Goblin")[0]
	ctx.template_type = "circle"
	ctx.template_feet = 5.0
	tool = TableTools.make("template", ctx) as TableTools.TemplateTool
	tool.activate()
	tool.press(Vision.token_pos(goblin), MOUSE_BUTTON_LEFT, mods)
	tool.release(Vision.token_pos(goblin), MOUSE_BUTTON_LEFT, mods)
	var before := ctx.state.encounter.log.size()
	check(GmIntents.on_template(ctx, ctx.marks.marks[ctx.template_mark], acts[0]) == "", "Damage those caught on it")
	var said := str(ctx.state.encounter.log[-1].get("text", "")) if ctx.state.encounter.log.size() > before else ""
	var fighter: Dictionary = ctx.state.tokens(sid).filter(func(t: Dictionary) -> bool: return str(t.name) == "Ana's fighter")[0]
	check(said.begins_with("caught ") and said.contains(str(goblin.id)) and not said.contains(str(fighter.id)) and said.ends_with("by 5-ft circle, the DM's"),
		"sent with the goblin it catches (not Ana's fighter, far off), its words, as the DM's: %s" % said)
	ev.keycode = KEY_ESCAPE
	tool.key(ev)
	check(GmIntents.on_template(ctx, {}, acts[0]).contains("template"), "no template: said")
	tool.press(g.cell_center(g.offset_to_axial(0, 0)), MOUSE_BUTTON_LEFT, mods)
	check(GmIntents.on_template(ctx, ctx.marks.marks[ctx.template_mark], acts[0]) == "the template catches nobody", "over nobody: said")
	ctx.marks.clear("gm", "all", true)
	ctx.canvas.free()


## A template mark's cells, as the rules lay them (MapQuery.template through
## Measure.template_spec) — the same cases the web screens' own test lays
## (web/tests/template.test.ts), so a preview covers what its cast would.
func test_templates_as_the_screens_lay_them() -> void:
	var parts := _walled_kernel(20, 14)
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	# (no wall in the way of these: the walled map's wall is at x = 5 down to y = 8; this one has none)
	k.state.map_for(sid).level(0).walls.clear()
	k.state.apply({"t": "token.add", "scene": sid, "token": Encounter.new_token("Sela", Vector2(5.5, 5.5), {"id": "t_sela", "size": 1})})
	var cells := func(mark: Dictionary) -> Array:
		mark.scene = sid
		var out: Array = k.map.template(sid, Measure.template_spec(mark)).cells
		out.sort()
		return out
	var circle: Array = cells.call({"points": [[5.5, 5.5]], "shape": {"type": "circle", "size": 2}})
	check(circle.size() == 13 and circle.has("7,5") and not circle.has("7,6"), "a circle at a point: thirteen squares (%d)" % circle.size())
	check((cells.call({"points": [[5.5, 5.5]], "token": "t_sela", "shape": {"type": "circle", "size": 1}}) as Array).size() == 9, "round a creature, its size added: nine")
	check((cells.call({"points": [[6.0, 6.0]], "shape": {"type": "square", "size": 4}}) as Array).size() == 16, "a cube of four squares on a corner: sixteen")
	var three: Array = cells.call({"points": [[5.5, 5.5]], "shape": {"type": "square", "size": 3}})
	check(three == ["4,4", "4,5", "4,6", "5,4", "5,5", "5,6", "6,4", "6,5", "6,6"], "a cube of three on a square: its nine (%s)" % [three])
	var cone: Array = cells.call({"points": [[5.5, 5.5]], "token": "t_sela", "direction": 0, "shape": {"type": "cone", "size": 3, "angle": 53, "origin": "edge"}})
	check(cone == ["6,5", "7,5", "8,4", "8,5", "8,6"], "a cone from a creature's edge: %s" % [cone])
	var south: Array = cells.call({"points": [[5.5, 5.5]], "token": "t_sela", "direction": 90, "shape": {"type": "cone", "size": 3, "angle": 53, "origin": "edge"}})
	check(south == ["4,8", "5,6", "5,7", "5,8", "6,8"], "turned south: %s" % [south])
	var line: Array = cells.call({"points": [[5.5, 5.5]], "token": "t_sela", "direction": 0, "shape": {"type": "line", "size": 6, "width": 1, "origin": "edge"}})
	check(line == ["10,5", "11,5", "6,5", "7,5", "8,5", "9,5"], "a line: %s" % [line])
	check((cells.call({"points": [[0.5, 0.5]], "shape": {"type": "circle", "size": 2}}) as Array).size() == 6, "on the map only")
	var hex := HexMap.create("Hexes", HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 20, 14))
	var st := EncounterState.new(Encounter.create("Hexes"))
	st.attach_map(hex)
	var hk := RulesKernel.new(st)
	var hsc := Encounter.new_scene(hex, str(hex.level(0).id), "Hexes", "")
	hk.commit([{"t": "scene.add", "scene": hsc}], "Setup")
	var c := hex.grid.cell_center(hex.grid.offset_to_axial(8, 6))
	check((hk.map.template(str(hsc.id), Measure.template_spec({"points": [[c.x, c.y]], "shape": {"type": "circle", "size": 1}})).cells as Array).size() == 7, "a hex of hexes: seven")
	check((hk.map.template(str(hsc.id), Measure.template_spec({"points": [[c.x, c.y]], "shape": {"type": "circle", "size": 2}})).cells as Array).size() == 19, "and nineteen")


func test_measure_rule_from_a_ruleset() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var parts := _walled_kernel()
	var k: RulesKernel = parts[0]
	check(str(k.map.measure_rule().diagonals) == "5-5-5", "with no ruleset's say, every step a square")
	var host := PluginHost.new(k)
	var why := host.load_source({"id": "t.measure", "version": "1", "api": 1, "name": "Measure"}, [["main.lua", """
		local hm = hexmap
		hm.map.measure({ diagonals = "5-10-5", costs = { difficult = 2 } })
	"""]])
	check(why == "", "the plugin loads: %s" % why)
	check(str(k.map.measure_rule().diagonals) == "5-10-5", "a ruleset says how the rulers count diagonals: %s" % [k.map.measure_rule()])
	check(float(k.map.measure_rule().get("costs", {}).get("difficult", 0)) == 2.0, "and what difficult ground costs to walk: %s" % [k.map.measure_rule()])
	host.unload("t.measure")
	check(str(k.map.measure_rule().diagonals) == "5-5-5", "and its say goes with it")
	k.map.register_measure("t.odd", {"diagonals": "7-14-7"})
	check(str(k.map.measure_rule().diagonals) == "5-5-5", "a rule nobody knows is the default")


## The registry on its own: what a mark is, whose, how many, how long.
func test_marks_kept_and_gone() -> void:
	var st := WebSuite.new()._chapel_state()
	var k := RulesKernel.new(st)
	var marks := Marks.new()
	var now := [1000]
	marks.clock = func() -> int: return now[0]
	marks.bind(st, k.map)
	var sid := st.encounter.active_scene_id
	var ana := "pl_fe0170c1"
	var heard := []
	marks.changed.connect(func(id: String) -> void: heard.append("+" + id))
	marks.removed.connect(func(id: String, _m: Dictionary) -> void: heard.append("-" + id))
	var doc_before := JsonDoc.sans_modified(st.encounter.to_json())
	var applied := []
	st.applied.connect(func(ev: Dictionary, _inv: Dictionary) -> void: applied.append(ev))
	var ruler := {"id": "ana-r1", "kind": "ruler", "scene": sid, "points": [[4.0, 6.64], [7.0, 6.64]], "live": true}
	check(marks.put(ana, ruler, {"name": "Ana", "color": "#4f9cf6"}) == "", "Ana's ruler")
	var m: Dictionary = marks.marks["ana-r1"]
	check(str(m.owner) == ana and str(m.name) == "Ana" and m.has("measure") and str(m.measure.words).ends_with(" ft"), "hers, named, measured: %s" % [m.get("measure")])
	check(heard == ["+ana-r1"], "said to whoever listens")
	# never the encounter's: no event, no undo step, nothing in the document
	check(applied.is_empty() and JsonDoc.sans_modified(st.encounter.to_json()) == doc_before, "nothing applied, the document as it was")
	# checked: someone else's, bad shapes, places off the map, ids
	check(marks.put("pl_393eb25a", ruler) != "", "Ben can't change Ana's")
	check(marks.put(ana, {"id": "x", "kind": "ruler", "scene": sid, "points": [[1, 1]]}) != "", "an id too short")
	check(marks.put(ana, {"id": "ana-bad1", "kind": "laser", "scene": sid, "points": [[1, 1]]}) != "", "a kind of mark there isn't")
	check(marks.put(ana, {"id": "ana-bad2", "kind": "ping", "scene": sid, "points": [[1e9, 1]]}) != "", "far off the map")
	check(marks.put(ana, {"id": "ana-bad3", "kind": "ping", "scene": "s_none", "points": [[1, 1]]}) != "", "no such scene")
	check(marks.put(ana, {"id": "ana-bad4", "kind": "template", "scene": sid, "points": [[1, 1]], "shape": {"type": "circle", "size": -2}}) != "", "a template of no size")
	check(marks.put(ana, {"id": "ana-bad5", "kind": "ping", "scene": sid, "points": [[1, 1]], "private": true}) == "" and not marks.marks["ana-bad5"].has("private"), "a player's mark is never private")
	check(marks.put(ana, {"id": "ana-bad6", "kind": "ruler", "scene": sid, "points": range(20).map(func(i: int) -> Array: return [1.0, float(i) * 0.1])}) != "", "a ruler of twenty points is too long")
	# held, it stays; let go, it lingers a few seconds and goes
	now[0] += Marks.HELD_MS - 1
	marks.tick()
	check(marks.marks.has("ana-r1"), "held: it stays while she holds it")
	ruler.live = false
	marks.put(ana, ruler)
	now[0] += int(Marks.LINGER_MS.ruler) - 1
	marks.tick()
	check(marks.marks.has("ana-r1"), "let go: it lingers")
	now[0] += 2
	marks.tick()
	check(not marks.marks.has("ana-r1") and heard.has("-ana-r1"), "and goes")
	# a held mark she says nothing more of goes too (her screen went)
	marks.put(ana, {"id": "ana-r2", "kind": "ruler", "scene": sid, "points": [[4.0, 6.64], [6.0, 6.64]], "live": true})
	now[0] += Marks.HELD_MS + 1
	marks.tick()
	check(not marks.marks.has("ana-r2"), "held with no word for half a minute: gone")
	# pinned: it stays until its owner or the DM takes it off
	var tpl := {"id": "ana-t1", "kind": "template", "scene": sid, "points": [[6.0, 6.0]], "shape": {"type": "circle", "size": 4.0}, "label": "20-ft circle", "pinned": true}
	check(marks.put(ana, tpl) == "", "a pinned template")
	now[0] += 3600000
	marks.tick()
	check(marks.marks.has("ana-t1"), "an hour on, still there")
	check(marks.remove("pl_393eb25a", "ana-t1") != "" and marks.marks.has("ana-t1"), "Ben can't take it off")
	check(marks.remove("gm", "ana-t1", true) == "" and not marks.marks.has("ana-t1"), "the DM can")
	# a ping fades in a moment
	marks.put(ana, {"id": "ana-p1", "kind": "ping", "scene": sid, "points": [[5.0, 5.0]], "live": true})
	check(not bool(marks.marks["ana-p1"].live), "a ping is never held")
	now[0] += int(Marks.LINGER_MS.ping) + 1
	marks.tick()
	check(not marks.marks.has("ana-p1"), "and fades")
	# how many: the oldest unpinned makes room; all pinned, no room
	marks.clear(ana)
	for i in Marks.MAX_PER_OWNER:
		marks.put(ana, {"id": "ana-many%d" % i, "kind": "ping", "scene": sid, "points": [[1.0 + i, 1.0]], "pinned": i > 0})
	check(marks.put(ana, {"id": "ana-many-x", "kind": "ping", "scene": sid, "points": [[3.0, 3.0]]}) == "" and not marks.marks.has("ana-many0") and marks.marks.has("ana-many-x"), "one more takes the place of her oldest unpinned")
	marks.put(ana, {"id": "ana-many-x", "kind": "ping", "scene": sid, "points": [[3.0, 3.0]], "pinned": true})
	check(marks.put(ana, {"id": "ana-many-y", "kind": "ping", "scene": sid, "points": [[3.0, 3.0]]}).contains("pinned"), "eight pinned: take one off first")
	# clear mine; the DM clears anyone's, or everyone's
	marks.put("pl_393eb25a", {"id": "ben-p1", "kind": "ping", "scene": sid, "points": [[2.0, 2.0]], "pinned": true})
	check(marks.clear("pl_393eb25a", ana).is_empty() and marks.marks.has("ana-many1"), "Ben can't clear Ana's")
	check(marks.clear(ana).size() == Marks.MAX_PER_OWNER and marks.of_scene(sid).size() == 1, "Ana clears hers")
	marks.put(ana, {"id": "ana-p2", "kind": "ping", "scene": sid, "points": [[2.0, 2.0]], "pinned": true})
	check(marks.clear("gm", "pl_393eb25a", true) == ["ben-p1"] and marks.clear("gm", "all", true) == ["ana-p2"] and marks.marks.is_empty(), "the DM clears Ben's, then everyone's")
	# on a token: where it stands, and gone with it
	var fighter := "t_bdb237f2"
	check(marks.put(ana, {"id": "ana-pv1", "kind": "preview", "scene": sid, "points": [[0.0, 0.0]], "token": fighter, "shape": {"type": "cone", "size": 3.0, "angle": 53, "origin": "edge"}, "label": "Burning Hands, 15-ft cone"}) == "", "a preview from her fighter")
	check(Marks.point(marks.marks["ana-pv1"]).distance_to(Vision.token_pos(st.token(sid, fighter))) < 0.01, "stands where the fighter is")
	heard.clear()
	st.apply({"t": "token.set", "scene": sid, "id": fighter, "changes": {"pos": [6.0, 6.64]}})
	check(Marks.point(marks.marks["ana-pv1"]).distance_to(Vector2(6.0, 6.64)) < 0.01 and heard.has("+ana-pv1"), "and goes where it goes")
	st.apply({"t": "token.remove", "scene": sid, "id": fighter})
	check(not marks.marks.has("ana-pv1"), "and goes with it")
	marks.bind(null, null)


## Whether a screen has heard of a mark (put or changed).
func _heard(w: Variant, id: String) -> bool:
	for x in w.inbox:
		if str(x.get("t", "")) == "mark" and str(x.mark.get("id", "")) == id:
			return true
	return false


## Whether a screen has heard a mark is gone.
func _gone(w: Variant, id: String) -> bool:
	for x in w.inbox:
		if str(x.get("t", "")) == "unmark" and (x.get("ids", []) as Array).has(id):
			return true
	return false


## Over the wire: who hears of which mark, as the table's screens do.
func test_marks_over_the_wire() -> void:
	var web := WebSuite.new()
	var st := web._chapel_state()
	var kernel := RulesKernel.new(st)
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = kernel
	host.dm_token = "sesame"
	host.dm_state_source = func() -> Dictionary: return {}
	var now := [5000]
	host.marks.clock = func() -> int: return now[0]
	check(host.start(0, false, 0) == OK, "hosting")
	var sid := st.encounter.active_scene_id
	var seat := func(join: Dictionary) -> WebSuite.WebClient:
		var w := WebSuite.WebClient.new(host.port)
		web._pump(host, [w], func() -> bool: return w.open())
		w.send({"t": "hello", "version": Protocol.VERSION, "name": "screen", "web": true})
		w.send(join)
		web._pump(host, [w], func() -> bool: return not w.last("marks").is_empty())
		return w
	var ana: WebSuite.WebClient = seat.call({"t": "join", "role": "player", "name": "Ana"})
	var ben: WebSuite.WebClient = seat.call({"t": "join", "role": "player", "name": "Ben"})
	var dm: WebSuite.WebClient = seat.call({"t": "join", "role": "dm", "token": "sesame"})
	var all := [ana, ben, dm]
	check((ana.last("marks").marks as Array).is_empty(), "joining: the marks on the map, none yet")
	var history_before := kernel.log.entries.size()
	var doc_before := JsonDoc.sans_modified(st.encounter.to_json())
	# Ana's ruler, held: Ben and the DM see it as it goes, named and in her colour
	ana.send({"t": "mark", "op": "set", "mark": {"id": "ana-ruler-1", "kind": "ruler", "scene": sid, "points": [[4.0, 6.64], [9.0, 6.64]], "live": true}})
	check(web._pump(host, all, func() -> bool: return not ben.last("mark").is_empty() and not dm.last("mark").is_empty()), "Ben and the DM hear of Ana's ruler")
	var seen: Dictionary = ben.last("mark").mark
	check(str(seen.name) == "Ana" and str(seen.color) == "#4f9cf6" and str(seen.owner) == "pl_fe0170c1", "with her name and colour: %s / %s" % [seen.name, seen.color])
	check(seen.has("measure") and str(seen.measure.words).ends_with("ft") and not seen.has("_order"), "the Table's measure, none of its own keys: %s" % [seen.get("measure")])
	check(not ana.last("mark").is_empty() and str(ana.last("mark").mark.id) == "ana-ruler-1", "and Ana hears it back, measured")
	# dragged, ten times a second: the screens hear it at most every MARK_GAP_MS, and the last of it
	var before := ben.count("mark")
	for i in 10:
		ana.send({"t": "mark", "op": "set", "mark": {"id": "ana-ruler-1", "kind": "ruler", "scene": sid, "points": [[4.0, 6.64], [9.0 + i * 0.5, 6.64]], "live": true}})
	web._pump(host, all, func() -> bool: return false, 400)
	var got := ben.count("mark") - before
	check(got >= 1 and got < 10, "ten moves in a moment reach Ben as fewer: %d" % got)
	check(near(float(ben.last("mark").mark.points[1][0]), 13.5, 0.01), "and the last of them is where it ended: %s" % [ben.last("mark").mark.points])
	# the DM's marks: not over what a player can't see
	dm.send({"t": "mark", "op": "set", "mark": {"id": "dm-ping-goblin", "kind": "ping", "scene": sid, "points": [[10.6, 4.907]]}})
	dm.send({"t": "mark", "op": "set", "mark": {"id": "dm-ping-party", "kind": "ping", "scene": sid, "points": [[4.0, 6.64]]}})
	check(web._pump(host, all, func() -> bool: return _heard(dm, "dm-ping-goblin") and _heard(ana, "dm-ping-party")), "the DM's pings: the DM sees both")
	var ana_ids := ana.inbox.filter(func(x: Dictionary) -> bool: return str(x.get("t", "")) == "mark").map(func(x: Dictionary) -> String: return str(x.mark.id))
	check(ana_ids.has("dm-ping-party") and not ana_ids.has("dm-ping-goblin"), "Ana sees the one by her fighter, not the one on a goblin hidden from her: %s" % [ana_ids])
	check(str(ana.last("mark").mark.name) == "DM" and str(ana.last("mark").mark.color) == HostSession.DM_COLOR, "the DM's, so named")
	# …until the goblin is revealed where she sees it
	st.apply({"t": "token.set", "scene": sid, "id": "t_2c932f84", "changes": {"hidden": false, "pos": [5.0, 6.0]}})
	dm.send({"t": "mark", "op": "set", "mark": {"id": "dm-ping-goblin", "kind": "ping", "scene": sid, "points": [[5.0, 6.0]]}})
	check(web._pump(host, all, func() -> bool: return _heard(ana, "dm-ping-goblin")), "the goblin in sight: now she sees the DM's ping on it")
	# a private ruler: the DMs alone
	dm.send({"t": "mark", "op": "set", "mark": {"id": "dm-private-1", "kind": "ruler", "scene": sid, "points": [[4.0, 6.64], [6.0, 6.64]], "private": true}})
	check(web._pump(host, all, func() -> bool: return _heard(dm, "dm-private-1")), "the DM's private ruler, the DM's")
	web._pump(host, all, func() -> bool: return false, 150)
	check(not _heard(ben, "dm-private-1"), "Ben never hears of it")
	# a player may not touch another's; the DM may clear anyone's
	ben.send({"t": "mark", "op": "remove", "id": "ana-ruler-1"})
	check(web._pump(host, all, func() -> bool: return not ben.last("refused").is_empty()), "Ben can't take Ana's ruler off: %s" % [ben.last("refused")])
	ben.send({"t": "mark", "op": "set", "mark": {"id": "ana-ruler-1", "kind": "ruler", "scene": sid, "points": [[1.0, 1.0], [2.0, 2.0]]}})
	check(web._pump(host, all, func() -> bool: return ben.count("refused") >= 2) and host.marks.marks["ana-ruler-1"].owner == "pl_fe0170c1", "nor move it")
	ben.send({"t": "mark", "op": "set", "mark": {"id": "ben-tpl-1", "kind": "template", "scene": sid, "points": [[6.0, 6.0]], "shape": {"type": "circle", "size": 4.0}, "label": "20-ft circle", "pinned": true}})
	check(web._pump(host, all, func() -> bool: return _heard(ana, "ben-tpl-1")), "Ben's pinned template reaches Ana")
	# time passes: the let-go and the held go, the pinned stays
	ana.send({"t": "mark", "op": "set", "mark": {"id": "ana-ruler-1", "kind": "ruler", "scene": sid, "points": [[4.0, 6.64], [13.5, 6.64]], "live": false}})
	web._pump(host, all, func() -> bool: return false, 150)
	now[0] += 120000
	check(web._pump(host, all, func() -> bool: return _gone(ben, "ana-ruler-1")), "two minutes on: Ana's ruler is gone from Ben's screen")
	check(host.marks.marks.has("ben-tpl-1") and not host.marks.marks.has("dm-ping-party"), "Ben's pinned template stays; the pings have faded")
	# someone who joins now hears of what is on the map
	var cara: WebSuite.WebClient = seat.call({"t": "join", "role": "player", "name": "Cara"})
	var listed := (cara.last("marks").marks as Array).map(func(x: Dictionary) -> String: return str(x.id))
	check(listed.has("ben-tpl-1") and not listed.has("dm-private-1"), "a new screen: the pinned template, not the DM's private ruler: %s" % [listed])
	# the DM clears Ben's
	dm.send({"t": "mark", "op": "clear", "whose": "pl_393eb25a"})
	check(web._pump(host, all + [cara], func() -> bool: return _gone(cara, "ben-tpl-1")), "the DM clears Ben's marks: gone from every screen")
	ana.send({"t": "mark", "op": "clear", "whose": "pl_393eb25a"})
	check(web._pump(host, all, func() -> bool: return str(ana.last("refused").get("why", "")).contains("DM")), "Ana can't clear Ben's")
	# a display may put none
	var tv: WebSuite.WebClient = seat.call({"t": "join", "role": "display"})
	tv.send({"t": "mark", "op": "set", "mark": {"id": "tv-ping-1", "kind": "ping", "scene": sid, "points": [[4.0, 6.64]]}})
	check(web._pump(host, [tv], func() -> bool: return not tv.last("refused").is_empty()) and not host.marks.marks.has("tv-ping-1"), "a display puts no marks")
	# a held ruler whose screen goes is let go: it lingers, then goes
	ben.send({"t": "mark", "op": "set", "mark": {"id": "ben-ruler-held", "kind": "ruler", "scene": sid, "points": [[3.5, 7.5], [6.0, 7.5]], "live": true}})
	check(web._pump(host, all, func() -> bool: return host.marks.marks.has("ben-ruler-held")), "Ben holds a ruler")
	ben.ws.close()
	check(web._pump(host, [ana, dm], func() -> bool: return host.marks.marks.has("ben-ruler-held") and not bool(host.marks.marks["ben-ruler-held"].live)), "his screen goes: let go")
	now[0] += int(Marks.LINGER_MS.ruler) + 1
	check(web._pump(host, [ana, dm], func() -> bool: return not host.marks.marks.has("ben-ruler-held")), "and gone after a moment")
	# never the encounter's
	check((kernel.log.entries.size()) == history_before, "nothing in the undo history")
	var doc_now := JsonDoc.sans_modified(st.encounter.to_json())
	check(not doc_now.contains("ana-ruler") and not doc_now.contains("ben-tpl") and not doc_now.contains("dm-ping"), "nothing of them in the saved game")
	host.stop()


## The DM's ruler to a player: its walk only where the party knows the ground.
func test_the_dms_walk_and_the_players_ground() -> void:
	var parts := _walled_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	st.apply({"t": "player.add", "player": {"id": "pl_1", "name": "Ana", "color": "#4f9cf6"}})
	st.apply({"t": "token.add", "scene": sid, "token": Encounter.new_token("Ana's fighter", Vector2(3.5, 2.5), {"id": "t_f", "owner": "pl_1", "vision": {"radius": 6}})})
	st.apply({"t": "fog.set", "scene": sid, "enabled": true})
	var west := []
	for y in 10:
		for x in 5:
			west.append(HexMap.cell_key(Vector2i(x, y)))
	st.apply({"t": "fog.reveal", "scene": sid, "cells": west + ["7,2"]})
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = k
	host.marks.bind(st, k.map)
	check(host.marks.put("gm", {"id": "dm-ruler-wall", "kind": "ruler", "scene": sid, "points": [[3.5, 2.5], [7.5, 2.5]]}, {"name": "DM", "color": "#ffffff"}, true) == "", "the DM measures across the wall")
	var m: Dictionary = host.marks.marks["dm-ruler-wall"]
	check(str(m.measure.words) == "20 ft straight, 65 ft to walk round", "the DM's own: the walk round it (%s)" % m.measure.words)
	var to_ana := host._mark_for({"player": "pl_1", "role": Views.ROLE_PLAYER, "joined": true}, m)
	check(not to_ana.is_empty() and str(to_ana.measure.words) == "20 ft", "Ana sees it, and only the distance: its way goes over ground she hasn't seen (%s)" % [to_ana.get("measure")])
	check(not to_ana.has("_walk_cells"), "nothing of the Table's own keys")
	var east := []
	for y in 10:
		for x in range(5, 12):
			east.append(HexMap.cell_key(Vector2i(x, y)))
	st.apply({"t": "fog.reveal", "scene": sid, "cells": east})
	host._sight.clear()
	to_ana = host._mark_for({"player": "pl_1", "role": Views.ROLE_PLAYER, "joined": true}, host.marks.marks["dm-ruler-wall"])
	check(str(to_ana.measure.words) == "20 ft straight, 65 ft to walk round", "the ground known: the walk too (%s)" % [to_ana.measure])
	host.marks.bind(null, null)


## The Table's own: the ruler tool, a ping, a spell's preview, drawn.
func test_marks_on_the_table() -> void:
	var ctx := _table_ctx()
	var sid := ctx.scene_id
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var ruler := TableTools.make("ruler", ctx) as TableTools.RulerTool
	var g := ctx.map().grid
	var a := g.cell_center(g.offset_to_axial(3, 3))
	var b := g.cell_center(g.offset_to_axial(7, 3))
	ruler.press(a, MOUSE_BUTTON_LEFT, mods)
	ruler.drag(b, MOUSE_BUTTON_LEFT, mods)
	var held := ctx.marks.of_scene(sid)
	check(held.size() == 1 and str(held[0].kind) == "ruler" and bool(held[0].live) and str(held[0].owner) == "gm", "dragging: the DM's ruler, held")
	check(str(held[0].measure.words) == "20 ft", "four hexes: 20 ft (%s)" % held[0].measure.words)
	ruler.release(b, MOUSE_BUTTON_LEFT, mods)
	var done := ctx.marks.of_scene(sid)
	check(done.size() == 1 and not bool(done[0].live), "let go: it lingers")
	# a path: click, click, Enter
	ruler.press(a, MOUSE_BUTTON_LEFT, mods)
	ruler.release(a, MOUSE_BUTTON_LEFT, mods)
	var c := g.cell_center(g.offset_to_axial(3, 6))
	ruler.move(c)
	ruler.press(c, MOUSE_BUTTON_LEFT, mods)
	ruler.release(c, MOUSE_BUTTON_LEFT, mods)
	ruler.press(b, MOUSE_BUTTON_LEFT, mods)
	ruler.release(b, MOUSE_BUTTON_LEFT, mods)
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_ENTER
	ruler.key(ev)
	var path: Array = ctx.marks.of_scene(sid).filter(func(m: Dictionary) -> bool: return (m.points as Array).size() == 3)
	check(path.size() == 1 and not bool(path[0].live), "a path of three points, ended: %s" % [ctx.marks.of_scene(sid).map(func(m: Dictionary) -> int: return (m.points as Array).size())])
	# right-click: a ping
	ruler.press(b, MOUSE_BUTTON_RIGHT, mods)
	check(ctx.marks.of_scene(sid).any(func(m: Dictionary) -> bool: return str(m.kind) == "ping"), "right-click pings")
	# Only me: the DM's next marks are private
	ctx.marks_private = true
	TableTools.make("select", ctx).press(a, MOUSE_BUTTON_RIGHT, mods)
	check(ctx.marks.of_scene(sid).any(func(m: Dictionary) -> bool: return str(m.kind) == "ping" and bool(m.get("private", false))), "Only me: a private ping")
	ctx.marks_private = false
	# a spell's preview from the Table's sheets: a sphere where the DM clicks
	var why := GmIntents.run(ctx, {"kind": "preview", "area": {"from": "point", "type": "circle", "size": 4, "label": "Fireball, 20-ft sphere"}, "actor": ""})
	check(why == "" and not ctx.pick.is_empty(), "Preview asks where it goes: %s" % why)
	ctx.resolve_pick(g.cell_center(g.offset_to_axial(9, 5)))
	var pv: Array = ctx.marks.of_scene(sid).filter(func(m: Dictionary) -> bool: return str(m.kind) == "preview")
	check(pv.size() == 1 and str(pv[0].label) == "Fireball, 20-ft sphere" and str(pv[0].shape.type) == "circle", "a preview of it, labelled: %s" % [pv])
	# a cone from a creature: the DM points which way it goes, and it goes out from the creature
	var fighter: Dictionary = ctx.state.tokens(sid)[0]
	ctx.state.apply({"t": "actor.add", "actor": {"id": "a_fighter", "name": "Ana's fighter"}})
	ctx.state.apply({"t": "token.set", "scene": sid, "id": str(fighter.id), "changes": {"actor": "a_fighter"}})
	why = GmIntents.run(ctx, {"kind": "preview", "actor": "a_fighter", "area": {"from": "self", "type": "cone", "size": 3, "angle": 53, "origin": "edge", "label": "Burning Hands, 15-ft cone"}})
	check(why == "" and str(ctx.pick.get("kind", "")) == "area" and float(ctx.pick.area.get("length", 0)) == 3.0, "a cone from the fighter: the pick shows it as it will be (%s)" % [ctx.pick.get("area")])
	var east := Vision.token_pos(fighter) + Vector2(3, 0)
	ctx.resolve_pick(east)
	var cone: Array = ctx.marks.of_scene(sid).filter(func(m: Dictionary) -> bool: return str(m.get("label", "")) == "Burning Hands, 15-ft cone")
	check(cone.size() == 1 and str(cone[0].token) == str(fighter.id) and absf(float(cone[0].direction)) < 1.0, "out from the fighter, east as the DM pointed: %s" % [cone])
	check(GmIntents.run(ctx, {"kind": "preview", "actor": "a_nobody", "area": {"from": "self", "type": "cone", "size": 3}}).contains("isn't on this map"), "a creature not on the map: said")
	# drawn on the Table's map without trouble, the cells the rules would cover
	var own := ctx.canvas
	var view := TableView.new(ctx)
	root.add_child(view)
	await tree.process_frame
	var area := view.template_area(pv[0])
	check((area.cells as Array).size() > 20, "a 20-ft sphere covers its cells: %d" % (area.cells as Array).size())
	ctx.marks.clear("gm", "all", true)
	check(ctx.marks.marks.is_empty(), "Clear marks")
	view.queue_free()
	await tree.process_frame
	own.free()
