extends TestCase
## Layers, lighting and the layer tree.


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
	# Limited (terrain: a stream bank, tall grass): seen across, not through.
	# (a playtest's players saw nothing across a stream: its bank hid the far side)
	var vale := HexMap.new_level("v", "V")
	vale.walls.append({"id": "bank", "points": [[2, -3], [2.2, 0], [2, 3]], "blocks": {"move": false, "sight": true, "light": true, "sound": false}, "sight_mode": "limited"})
	var sight := Lighting.blocking_segments(vale, {}, "sight")
	check(sight.size() == 2 and bool(sight[0].limited), "a stream bank's segments are limited: %s" % [sight])
	check(Lighting.is_lit(o, 9.0, Vector2(4, 1.5), sight), "across one bank: seen")
	check(Lighting.is_lit(o, 9.0, Vector2(4, 0), sight), "and where the bank's two segments meet (at 2.2, 0), still one crossing")
	vale.walls.append({"id": "far bank", "points": [[5, -3], [5, 3]], "blocks": {"move": false, "sight": true, "light": true, "sound": false}, "sight_mode": "limited"})
	sight = Lighting.blocking_segments(vale, {}, "sight")
	check(Lighting.is_lit(o, 9.0, Vector2(4, 0), sight) and not Lighting.is_lit(o, 9.0, Vector2(6, 0), sight), "through two: not seen past the second")
	var tall := Lighting.visibility_polygon(o, 9.0, sight)
	var reach := 0.0
	for p in tall:
		if absf(p.y) < 0.3 and p.x > 0.0:
			reach = maxf(reach, p.x)
	check(reach > 4.9 and reach < 5.1, "the polygon stops at the second bank: %.2f" % reach)
	vale.walls.append({"id": "wall", "points": [[3, -3], [3, 3]], "blocks": {"move": true, "sight": true, "light": true, "sound": true}})
	check(not Lighting.is_lit(o, 9.0, Vector2(4, 0), Lighting.blocking_segments(vale, {}, "sight")), "a wall after one bank still blocks")
	var fan := Lighting.fan(o, 3.0, poly, 100.0)
	check(fan.vertices.size() == poly.size() * 3 and fan.uvs.size() == fan.vertices.size(), "fan triangles")
	check(fan.uvs[0] == Vector2(0.5, 0.5), "centre uv")


## A field for the light tests: 30 by 12 pointy hexes of five feet, a wall
## across the lower rows at x 10 (row 8 is behind it, row 3 is not), and a
## room at the east end with a door in its west wall and a brazier inside.
## [state, scene id, map].
func _field(map_light := "") -> Array:
	var m := HexMap.create("Field", HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 30, 12))
	var lvl := m.level(0)
	if map_light != "":
		lvl.light = map_light
	var solid := {"move": true, "sight": true, "light": true, "sound": true}
	lvl.walls.append({"id": "w_low", "points": [[10, 5.0], [10, 12.0]], "blocks": solid, "door": "none", "state": "closed"})
	lvl.walls.append({"id": "w_room", "points": [[20, 2.4], [20, 0.5], [26, 0.5], [26, 5.5], [20, 5.5], [20, 3.6]], "blocks": solid, "door": "none", "state": "closed"})
	lvl.walls.append({"id": "w_door", "points": [[20, 2.4], [20, 3.6]], "blocks": solid, "door": "door", "state": "closed"})
	lvl.lights.append({"id": "l_brazier", "pos": [23.0, 3.0], "bright": 1.5, "dim": 3.0, "color": "#ff9040", "on": true})
	var st := EncounterState.new(Encounter.create("Light"))
	st.attach_map(m)
	var sc := Encounter.new_scene(m, str(lvl.id), "Field", "")
	st.apply({"t": "scene.add", "scene": sc})
	return [st, str(sc.id), m]


## What a scene is lit by, and what its tokens see by it: by day and in dim
## light everything in their line of sight, however far, walls permitting;
## in the dark only their darkvision and the lit places in their line of
## sight (a playtest's maps were black beyond six hexes, the sunlit road too).
func test_light_levels() -> void:
	var parts := _field()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var m: HexMap = parts[2]
	var g := m.grid
	# which setting wins
	check(st.light_level(sid) == "daylight", "a map that says nothing is lit by day")
	m.level(0).light = "dark"
	check(st.light_level(sid) == "dark", "the map's level says dark")
	st.apply({"t": "scene.set", "id": sid, "changes": {"light": "dim"}})
	check(st.light_level(sid) == "dim", "the scene's own light wins over the map's")
	check(st.validate({"t": "scene.set", "id": sid, "changes": {"light": "twilight"}}) != "", "a light that isn't daylight, dim or dark is refused")
	check(st.validate({"t": "scene.set", "id": sid, "changes": {"light": null}}) == "", "null goes back to the map's")
	st.apply({"t": "scene.set", "id": sid, "changes": {"light": null}})
	check(st.light_level(sid) == "dark" and not st.encounter.scene(sid).has("light"), "and back to the map's it is")
	m.level(0).light = "moonlit"
	check(st.light_level(sid) == "daylight", "a map level's word that isn't one of the three is daylight")
	m.level(0).erase("light")
	check(is_equal_approx(Vision.darkness("daylight"), 0.0) and is_equal_approx(Vision.darkness("dim"), 0.4) and is_equal_approx(Vision.darkness("dark"), 1.0)
		and is_equal_approx(Vision.darkness("dark", true), 0.5), "the darkness sheet: none, 0.4, whole; the DM's at half")
	# two tokens: A in the open on row 3, B on row 8 behind the low wall
	var at := func(col: int, row: int) -> Vector2: return g.cell_center(g.offset_to_axial(col, row))
	var a := Encounter.new_token("A", at.call(2, 3), {"id": "t_a"})
	var b := Encounter.new_token("B", at.call(2, 8), {"id": "t_b"})
	st.apply({"t": "token.add", "scene": sid, "token": a})
	st.apply({"t": "token.add", "scene": sid, "token": b})
	var both := func() -> Dictionary: return Vision.of(st, sid, [st.token(sid, "t_a"), st.token(sid, "t_b")])
	for light in ["daylight", "dim"]:
		st.apply({"t": "scene.set", "id": sid, "changes": {"light": light}})
		var v: Dictionary = both.call()
		check(Vision.sees(v.polygons, at.call(17, 3)) and v.cells.has(g.offset_to_axial(17, 3)), "%s: fifteen hexes across the grass, seen" % light)
		check(not Vision.sees(v.polygons, at.call(17, 8)) and not v.cells.has(g.offset_to_axial(17, 8)), "%s: not through the wall" % light)
		check(v.los == v.polygons and (v.dark as Array).is_empty(), "%s: what is in the line of sight is seen" % light)
	# in the dark: its own cell and no more, without a light or darkvision
	st.apply({"t": "scene.set", "id": sid, "changes": {"light": "dark"}})
	var alone := Vision.of(st, sid, [st.token(sid, "t_a")])
	check(alone.cells.size() == 1 and alone.cells[0] == g.offset_to_axial(2, 3), "in the dark a token sees its own cell and no more: %s" % [alone.cells])
	check(Vision.sees(alone.los, at.call(17, 3)), "though its line of sight goes on (the screens say it is too dark there)")
	# a torch: as far as its light
	st.apply({"t": "token.set", "scene": sid, "id": "t_a", "changes": {"light": {"bright": 2, "dim": 4}}})
	var torch := Vision.of(st, sid, [st.token(sid, "t_a")])
	check(torch.cells.has(g.offset_to_axial(5, 3)) and not torch.cells.has(g.offset_to_axial(7, 3)), "a torch's reach: three hexes off seen, five not")
	check(Vision.sees(torch.polygons, at.call(17, 3)) == false, "and the far field stays dark")
	# a brazier in the room: seen through the open door, not through its walls
	var c := Encounter.new_token("C", at.call(13, 3), {"id": "t_c"})
	st.apply({"t": "token.add", "scene": sid, "token": c})
	var lit_door: Vector2 = at.call(21, 3)    # lit, in line with the door
	var lit_corner: Vector2 = at.call(21, 1)  # lit, behind the room's west wall from C
	var from_c := func() -> Dictionary: return Vision.of(st, sid, [st.token(sid, "t_c")])
	check(not Vision.sees(from_c.call().polygons, lit_door), "the door shut: the brazier's light is not seen")
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:w_door", "changes": {"state": "open"}})
	check(Vision.sees(from_c.call().polygons, lit_door), "the door open: the lit floor beyond it is")
	check(not Vision.sees(from_c.call().polygons, lit_corner), "but not the lit corner behind the wall")
	st.apply({"t": "element.set", "scene": sid, "ref": "lights:l_brazier", "changes": {"on": false}})
	check(not Vision.sees(from_c.call().polygons, lit_door), "the brazier put out: dark again")
	# a hidden token's torch lights nothing a player sees by
	st.apply({"t": "token.set", "scene": sid, "id": "t_a", "changes": {"hidden": true}})
	check(Vision.lights(st, sid, st.effective_level(sid)).is_empty(), "a hidden token's light and a light put out are not counted")
	# darkvision in feet: 60 feet is twelve five-foot hexes
	var d := Encounter.new_token("D", at.call(2, 1), {"id": "t_d", "vision": {"radius": 6, "dark_radius": 60, "units": "ft"}})
	st.apply({"t": "token.add", "scene": sid, "token": d})
	check(is_equal_approx(float(Vision.eyes(d, g).dark), 12.0), "60 ft of darkvision on a five-foot grid: 12 hexes")
	var dv := Vision.of(st, sid, [st.token(sid, "t_d")])
	check(dv.cells.has(g.offset_to_axial(13, 1)) and not dv.cells.has(g.offset_to_axial(15, 1)), "eleven hexes off seen, thirteen not")
	check((dv.dark as Array).size() == 1, "the darkvision's reach, apart, for the screens to lift in grey")
	# and on a map of 1.5 m hexes (the bog): the same 60 feet is 12.2 hexes
	var bog := HexMap.load_file(example("bog_crossing.hexmap"))
	var bst := EncounterState.new(Encounter.create("Bog"))
	bst.attach_map(bog)
	var bsc := Encounter.new_scene(bog, str(bog.level(0).id), "Bog at night", "bog_crossing.hexmap")
	bsc.light = "dark"
	bst.apply({"t": "scene.add", "scene": bsc})
	var bg := bog.grid
	var e_at := bg.cell_center(bg.offset_to_axial(1, 0))
	var e := Encounter.new_token("E", e_at, {"id": "t_e", "vision": {"radius": 6, "dark_radius": 60, "units": "ft"}})
	bst.apply({"t": "token.add", "scene": bsc.id, "token": e})
	check(bg.units == "m" and is_equal_approx(bg.distance, 1.5) and absf(float(Vision.eyes(e, bg).dark) - 12.19) < 0.01, "60 ft on 1.5 m hexes: %.2f hexes" % float(Vision.eyes(e, bg).dark))
	var ev := Vision.of(bst, str(bsc.id), [bst.token(str(bsc.id), "t_e")])
	check(Vision.sees(ev.polygons, e_at + Vector2(0, 11)) and not Vision.sees(ev.polygons, e_at + Vector2(0, 13)), "eleven hexes off seen, thirteen not, on the bog too")
	check(is_equal_approx(Vision.hexes_per("ft", HexGrid.new()), 0.2) and is_equal_approx(Vision.hexes_per("", bg), 1.0) and is_equal_approx(Vision.hexes_per("leagues", bg), 1.0),
		"units: feet on five-foot hexes; none, or ones it can't turn into the map's, count as hexes")
	# a token that sees in the dark (`mode: "dark"`) sees as by day
	var f := Encounter.new_token("F", at.call(2, 3), {"id": "t_f", "vision": {"radius": 6, "mode": "dark"}})
	st.apply({"t": "token.add", "scene": sid, "token": f})
	check(Vision.sees(Vision.of(st, sid, [st.token(sid, "t_f")]).polygons, at.call(17, 3)), "mode dark: fifteen hexes off in the dark, seen")
	# and nothing for a marker that sees nothing
	st.apply({"t": "token.set", "scene": sid, "id": "t_f", "changes": {"vision": {"radius": 0, "mode": "dark"}}})
	check(Vision.of(st, sid, [st.token(sid, "t_f")]).polygons.is_empty(), "radius 0 sees nothing, in any light")


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
