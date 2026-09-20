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
