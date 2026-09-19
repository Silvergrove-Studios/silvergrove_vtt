class_name EditorTools
extends RefCounted
## The editing tools. Each is a small state machine fed mouse and key events
## in canvas hex-unit coordinates by MapView, drawing its own preview on the
## canvas overlay. `make(name, ctx)` builds one.

static func make(tool_name: String, ctx: EditorContext) -> Tool:
	var t: Tool
	match tool_name:
		"select": t = SelectTool.new()
		"terrain": t = TerrainTool.new()
		"fill": t = FillTool.new()
		"prop": t = PropTool.new()
		"wall": t = WallTool.new()
		"light": t = LightTool.new()
		"note": t = NoteTool.new()
		"erase": t = EraseTool.new()
		_: t = SelectTool.new()
	t.ctx = ctx
	t.tool_name = tool_name
	return t


static func all_tools() -> Array[Dictionary]:
	return [
		{"name": "select", "label": "Select", "key": "V", "hint": "Click to select, drag to move. Arrows nudge one pixel (Shift: ten). Delete removes."},
		{"name": "terrain", "label": "Paint", "key": "B", "hint": "Paint the palette terrain. Right-drag clears. [ ] change brush size."},
		{"name": "fill", "label": "Fill", "key": "G", "hint": "Fill a connected region of the same terrain."},
		{"name": "prop", "label": "Prop", "key": "P", "hint": "Click to place. R rotates 15° (Shift: 1°), F flips, [ ] scale, S cycles snapping."},
		{"name": "wall", "label": "Wall", "key": "W", "hint": "Click to add points, Enter/double-click to finish, Esc cancels. Shift disables corner snap."},
		{"name": "light", "label": "Light", "key": "L", "hint": "Click to place the palette light."},
		{"name": "note", "label": "Note", "key": "N", "hint": "Click to place a GM note."},
		{"name": "erase", "label": "Erase", "key": "E", "hint": "Click an object to delete it, or a cell to clear its terrain."},
	]


# =============================================================================

class Tool extends RefCounted:
	var ctx: EditorContext
	var tool_name := ""

	func activate() -> void: pass
	func deactivate() -> void: pass
	## Buttons: MOUSE_BUTTON_LEFT / RIGHT. `p` in hex units. Return true if handled.
	func press(_p: Vector2, _button: int, _mods: Dictionary) -> bool: return false
	func drag(_p: Vector2, _button: int, _mods: Dictionary) -> void: pass
	func release(_p: Vector2, _button: int, _mods: Dictionary) -> void: pass
	func move(_p: Vector2) -> void: ctx.canvas.overlay.queue_redraw()
	func double_click(_p: Vector2) -> bool: return false
	func key(_event: InputEventKey) -> bool: return false
	func draw_overlay(_c: Node2D) -> void: pass

	func grid() -> HexGrid: return ctx.map.grid
	func px(p: Vector2) -> Vector2: return p * ctx.canvas.ppx
	func level() -> Dictionary: return ctx.level()

	## Draw a hex outline at a cell, in overlay pixels.
	func outline_cell(c: Node2D, cell: Vector2i, color: Color, width := 2.0) -> void:
		var pts := PackedVector2Array()
		for k in grid().cell_corners(cell):
			pts.append(px(k))
		pts.append(pts[0])
		c.draw_polyline(pts, color, width, true)

	## What is under a point, most specific first: notes, lights, props (top
	## layer first, last drawn first), wall points, wall segments.
	func pick(p: Vector2) -> Dictionary:
		var lvl := level()
		var ppx := ctx.canvas.ppx
		var r_note := 0.14
		var show_hidden := ctx.canvas.show_hidden
		if ctx.canvas.show_notes:
			for n in lvl.get("notes", []):
				if not show_hidden and n.get("gm_only", true):
					continue
				if Vector2(n.pos[0], n.pos[1]).distance_to(p) < r_note:
					return {"collection": "notes", "id": n.id}
		if ctx.canvas.show_lights:
			for l in lvl.get("lights", []):
				if not show_hidden and l.get("hidden", false):
					continue
				if Vector2(l.pos[0], l.pos[1]).distance_to(p) < 0.2:
					return {"collection": "lights", "id": l.id}
		var props: Array = lvl.get("props", [])
		for layer_name in ["overhead", "objects", "ground"]:
			for i in range(props.size() - 1, -1, -1):
				var pr: Dictionary = props[i]
				if not show_hidden and pr.get("hidden", false):
					continue
				var def := ctx.packs.prop(str(pr.get("asset", "")))
				var layer := str(pr.get("layer", def.get("layer", "objects")))
				if layer != layer_name:
					continue
				if ctx.canvas.prop_hit(pr, def, p * ppx):
					return {"collection": "props", "id": pr.id}
		if ctx.canvas.show_walls:
			var best := {}
			var best_d := 0.12
			for w in lvl.get("walls", []):
				if not show_hidden and w.get("hidden", false):
					continue
				var pts: Array = w.get("points", [])
				for i in pts.size():
					var d := Vector2(pts[i][0], pts[i][1]).distance_to(p)
					if d < best_d:
						best_d = d
						best = {"collection": "walls", "id": w.id, "point": i}
			if not best.is_empty():
				return best
			for w in lvl.get("walls", []):
				if not show_hidden and w.get("hidden", false):
					continue
				var pts: Array = w.get("points", [])
				for i in pts.size() - 1:
					var a := Vector2(pts[i][0], pts[i][1])
					var b := Vector2(pts[i + 1][0], pts[i + 1][1])
					var q := Geometry2D.get_closest_point_to_segment(p, a, b)
					if q.distance_to(p) < 0.08:
						return {"collection": "walls", "id": w.id, "segment": i}
		return {}


# =============================================================================

class SelectTool extends Tool:
	var _dragging := false
	var _drag_start := Vector2.ZERO
	var _last := Vector2.ZERO
	var _moved_total := Vector2.ZERO
	var _wall_point := -1
	var _wall_id := ""
	var _box := false
	var _box_start := Vector2.ZERO
	var _box_end := Vector2.ZERO

	func press(p: Vector2, button: int, mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		var hit := pick(p)
		if hit.is_empty():
			var cell := grid().world_to_axial(p)
			if grid().in_bounds(cell) and level().get("terrain", {}).has(HexMap.cell_key(cell)):
				ctx.set_selection([{"collection": "terrain", "id": HexMap.cell_key(cell)}])
			else:
				ctx.clear_selection()
			_box = true
			_box_start = p
			_box_end = p
			return true
		if hit.has("point"):
			# Grab a wall vertex.
			ctx.select_one("walls", hit.id)
			_wall_id = hit.id
			_wall_point = hit.point
			_dragging = true
			_last = p
			return true
		if mods.shift:
			if ctx.is_selected(hit.collection, hit.id):
				var sel := ctx.selection.duplicate()
				sel = sel.filter(func(s): return not (s.collection == hit.collection and s.id == hit.id))
				ctx.set_selection(sel)
			else:
				var sel := ctx.selection.duplicate()
				sel.append({"collection": hit.collection, "id": hit.id})
				ctx.set_selection(sel)
		elif not ctx.is_selected(hit.collection, hit.id):
			ctx.select_one(hit.collection, hit.id)
		_dragging = true
		_drag_start = p
		_last = p
		_moved_total = Vector2.ZERO
		_wall_point = -1
		ctx.history.begin_group()
		return true

	func drag(p: Vector2, _button: int, mods: Dictionary) -> void:
		if _box:
			_box_end = p
			ctx.canvas.overlay.queue_redraw()
			return
		if not _dragging:
			return
		if _wall_point >= 0:
			var to := p if mods.shift else grid().snap_to_corner(p)
			if not ctx.snap_walls:
				to = p
			ctx.commands.move_wall_point(ctx.level_index, _wall_id, _wall_point, to)
			return
		var delta := p - _last
		if ctx.snap != EditorContext.Snap.NONE and not mods.shift and ctx.selection.size() == 1:
			# Snap the object's position, not the mouse delta.
			var obj := ctx.selected_object()
			if obj.has("pos"):
				var pos := Vector2(obj.pos[0], obj.pos[1])
				var target := ctx.snapped_point(pos + (p - _last))
				delta = target - pos
				if delta.length() < 1e-6:
					return
		_last = p
		_moved_total += delta
		ctx.commands.move_objects(ctx.level_index, _movable(), delta, "Move")

	func release(_p: Vector2, button: int, _mods: Dictionary) -> void:
		if button != MOUSE_BUTTON_LEFT:
			return
		if _box:
			_box = false
			var r := Rect2(_box_start, _box_end - _box_start).abs()
			if r.size.length() > 0.05:
				_select_in_box(r)
			ctx.canvas.overlay.queue_redraw()
			return
		if _dragging and _wall_point < 0:
			ctx.history.end_group("Move")
		_dragging = false
		_wall_point = -1

	func _movable() -> Array:
		return ctx.selection.filter(func(s): return s.collection != "terrain")

	func _select_in_box(r: Rect2) -> void:
		var lvl := level()
		var sel := []
		for coll in ["props", "lights", "notes"]:
			for o in lvl.get(coll, []):
				if r.has_point(Vector2(o.pos[0], o.pos[1])):
					sel.append({"collection": coll, "id": o.id})
		for w in lvl.get("walls", []):
			var all_in := true
			for pt in w.get("points", []):
				if not r.has_point(Vector2(pt[0], pt[1])):
					all_in = false
					break
			if all_in and not (w.get("points", []) as Array).is_empty():
				sel.append({"collection": "walls", "id": w.id})
		ctx.set_selection(sel)

	func key(event: InputEventKey) -> bool:
		var step := ctx.ref_px() * (10.0 if event.shift_pressed else 1.0)
		var d := Vector2.ZERO
		match event.keycode:
			KEY_LEFT: d = Vector2(-step, 0)
			KEY_RIGHT: d = Vector2(step, 0)
			KEY_UP: d = Vector2(0, -step)
			KEY_DOWN: d = Vector2(0, step)
			KEY_DELETE, KEY_BACKSPACE:
				_delete_selection()
				return true
			KEY_R:
				var obj := ctx.selected_object()
				if obj.has("rot"):
					var by := 1.0 if event.shift_pressed else 15.0
					ctx.commands.update_object(ctx.level_index, ctx.selection[0].collection, obj.id, {"rot": fposmod(float(obj.rot) + by, 360.0)}, "Rotate")
					return true
			KEY_F:
				var obj := ctx.selected_object()
				if ctx.selection.size() == 1 and ctx.selection[0].collection == "props":
					ctx.commands.update_object(ctx.level_index, "props", obj.id, {"flip": not bool(obj.get("flip", false))}, "Flip")
					return true
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var obj := ctx.selected_object()
				if ctx.selection.size() == 1 and ctx.selection[0].collection == "props":
					var f := 1.1 if event.keycode == KEY_BRACKETRIGHT else 1.0 / 1.1
					ctx.commands.update_object(ctx.level_index, "props", obj.id, {"scale": snappedf(float(obj.get("scale", 1.0)) * f, 0.001)}, "Scale")
					return true
			KEY_PAGEUP, KEY_PAGEDOWN:
				if ctx.selection.size() == 1 and ctx.selection[0].collection == "props":
					var lvl := level()
					var i := HexMap.index_in(lvl, "props", ctx.selection[0].id)
					ctx.commands.reorder_object(ctx.level_index, "props", ctx.selection[0].id, i + (1 if event.keycode == KEY_PAGEUP else -1))
					return true
		if d != Vector2.ZERO:
			ctx.commands.move_objects(ctx.level_index, _movable(), d, "Nudge")
			return true
		return false

	func _delete_selection() -> void:
		var objs := _movable()
		var cells: Array[Vector2i] = []
		for s in ctx.selection:
			if s.collection == "terrain":
				cells.append(HexMap.key_cell(s.id))
		ctx.history.begin_group()
		if not objs.is_empty():
			ctx.commands.remove_objects(ctx.level_index, objs)
		if not cells.is_empty():
			ctx.commands.set_terrain(ctx.level_index, cells, null)
		ctx.history.end_group("Delete")
		ctx.clear_selection()

	func draw_overlay(c: Node2D) -> void:
		var lvl := level()
		var ppx := ctx.canvas.ppx
		for s in ctx.selection:
			match s.collection:
				"terrain":
					outline_cell(c, HexMap.key_cell(s.id), Color(1, 1, 0.3, 0.9), 3.0)
				"props":
					var pr := HexMap.find_in(lvl, "props", s.id)
					if pr.is_empty():
						continue
					var def := ctx.packs.prop(str(pr.get("asset", "")))
					var r := ctx.canvas.prop_rect(pr, def)
					var pos := Vector2(pr.pos[0], pr.pos[1]) * ppx
					c.draw_set_transform(pos, deg_to_rad(float(pr.get("rot", 0.0))), Vector2.ONE)
					c.draw_rect(Rect2(r.position - pos, r.size), Color(1, 1, 0.3, 0.9), false, 2.0)
					c.draw_set_transform(Vector2.ZERO)
					c.draw_circle(pos, 4.0, Color(1, 1, 0.3))
				"lights":
					var l := HexMap.find_in(lvl, "lights", s.id)
					if l.is_empty():
						continue
					var pos := Vector2(l.pos[0], l.pos[1]) * ppx
					c.draw_arc(pos, float(l.get("dim", 0)) * ppx, 0, TAU, 64, Color(1, 1, 0.3, 0.8), 2.0, true)
					c.draw_arc(pos, float(l.get("bright", 0)) * ppx, 0, TAU, 64, Color(1, 1, 0.3, 0.8), 2.0, true)
					c.draw_circle(pos, 6.0, Color(1, 1, 0.3))
				"notes":
					var n := HexMap.find_in(lvl, "notes", s.id)
					if n.is_empty():
						continue
					c.draw_arc(Vector2(n.pos[0], n.pos[1]) * ppx, 0.16 * ppx, 0, TAU, 32, Color(1, 1, 0.3, 0.9), 2.0, true)
				"walls":
					var w := HexMap.find_in(lvl, "walls", s.id)
					if w.is_empty():
						continue
					ctx.canvas.draw_wall(c, w, 1.0, true)
					for pt in w.get("points", []):
						c.draw_circle(Vector2(pt[0], pt[1]) * ppx, 6.0, Color(1, 1, 0.3))
		if _box:
			var r := Rect2(_box_start * ppx, (_box_end - _box_start) * ppx).abs()
			c.draw_rect(r, Color(0.4, 0.7, 1.0, 0.15))
			c.draw_rect(r, Color(0.4, 0.7, 1.0, 0.9), false, 1.5)
		# Hover
		var hover := grid().world_to_axial(ctx.mouse_hex())
		if grid().in_bounds(hover):
			outline_cell(c, hover, Color(1, 1, 1, 0.25), 1.5)


# =============================================================================

class TerrainTool extends Tool:
	var _painting := false
	var _erasing := false
	var _last_cell := Vector2i(-99999, -99999)
	var _stroke: Dictionary = {}   # key -> data (or null), what this stroke painted

	func press(p: Vector2, button: int, _mods: Dictionary) -> bool:
		if button == MOUSE_BUTTON_LEFT and ctx.terrain_ref == "":
			ctx.say("Pick a terrain in the palette first.")
			return true
		if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
			return false
		_painting = true
		_erasing = button == MOUSE_BUTTON_RIGHT
		_stroke.clear()
		_last_cell = grid().world_to_axial(p)
		ctx.history.begin_group()
		_paint_at(_last_cell)
		return true

	func drag(p: Vector2, _button: int, _mods: Dictionary) -> void:
		if not _painting:
			return
		var cell := grid().world_to_axial(p)
		if cell == _last_cell:
			return
		for c in HexGrid.line(_last_cell, cell):
			_paint_at(c)
		_last_cell = cell

	func release(_p: Vector2, _button: int, _mods: Dictionary) -> void:
		if _painting:
			ctx.history.end_group("Erase terrain" if _erasing else "Paint terrain")
		_painting = false

	func _paint_at(center: Vector2i) -> void:
		var changes := {}
		for c in HexGrid.spiral(center, ctx.brush_radius):
			if not grid().in_bounds(c):
				continue
			var k := HexMap.cell_key(c)
			if _stroke.has(k):
				continue
			var data = null if _erasing else ctx.new_terrain_cell()
			_stroke[k] = data
			changes[k] = data
		if not changes.is_empty():
			ctx.commands.set_terrain_cells(ctx.level_index, changes)

	func key(event: InputEventKey) -> bool:
		match event.keycode:
			KEY_BRACKETLEFT:
				ctx.brush_radius = maxi(0, ctx.brush_radius - 1)
				ctx.say("Brush radius %d" % ctx.brush_radius)
				return true
			KEY_BRACKETRIGHT:
				ctx.brush_radius = mini(6, ctx.brush_radius + 1)
				ctx.say("Brush radius %d" % ctx.brush_radius)
				return true
		return false

	func draw_overlay(c: Node2D) -> void:
		var center := grid().world_to_axial(ctx.mouse_hex())
		var col := Color(1, 0.4, 0.4, 0.8) if _erasing and _painting else Color(1, 1, 1, 0.7)
		for cell in HexGrid.spiral(center, ctx.brush_radius):
			if grid().in_bounds(cell):
				outline_cell(c, cell, col, 2.0)


# =============================================================================

class FillTool extends Tool:
	func press(p: Vector2, button: int, _mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
			return false
		var erase := button == MOUSE_BUTTON_RIGHT
		if not erase and ctx.terrain_ref == "":
			ctx.say("Pick a terrain in the palette first.")
			return true
		var start := grid().world_to_axial(p)
		if not grid().in_bounds(start):
			return true
		var terrain: Dictionary = level().get("terrain", {})
		var from = terrain.get(HexMap.cell_key(start), {}).get("t", "")
		if not erase and from == ctx.terrain_ref:
			return true
		var changes := {}
		var frontier: Array[Vector2i] = [start]
		var seen := {HexMap.cell_key(start): true}
		while not frontier.is_empty() and seen.size() < 20000:
			var cell: Vector2i = frontier.pop_back()
			var k := HexMap.cell_key(cell)
			changes[k] = null if erase else ctx.new_terrain_cell()
			for nb in grid().neighbors(cell):
				var nk := HexMap.cell_key(nb)
				if seen.has(nk) or not grid().in_bounds(nb):
					continue
				var t = terrain.get(nk, {}).get("t", "")
				if t == from:
					seen[nk] = true
					frontier.append(nb)
		ctx.commands.set_terrain_cells(ctx.level_index, changes)
		return true

	func draw_overlay(c: Node2D) -> void:
		var cell := grid().world_to_axial(ctx.mouse_hex())
		if grid().in_bounds(cell):
			outline_cell(c, cell, Color(1, 1, 1, 0.7), 2.0)


# =============================================================================

class PropTool extends Tool:
	func press(p: Vector2, button: int, mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		if ctx.prop_ref == "":
			ctx.say("Pick a prop in the palette first.")
			return true
		var pos := p if mods.shift else ctx.snapped_point(p)
		var prop := ctx.new_prop(pos)
		var def := ctx.packs.prop(ctx.prop_ref)
		var light = def.get("light", null)
		ctx.history.begin_group()
		ctx.commands.add_object(ctx.level_index, "props", prop, "Place prop")
		if light is Dictionary and mods.get("alt", false) == false:
			var l := ctx.new_light(pos)
			for k in light:
				l[k] = light[k]
			l["id"] = HexMap.new_id("l")
			l["pos"] = prop.pos
			ctx.commands.add_object(ctx.level_index, "lights", l, "Place light")
		ctx.history.end_group("Place " + str(def.get("name", "prop")))
		ctx.select_one("props", prop.id)
		return true

	func key(event: InputEventKey) -> bool:
		match event.keycode:
			KEY_R:
				ctx.prop_rotation = fposmod(ctx.prop_rotation + (1.0 if event.shift_pressed else 15.0), 360.0)
				ctx.say("Rotation %d°" % int(ctx.prop_rotation))
				return true
			KEY_F:
				ctx.prop_flip = not ctx.prop_flip
				return true
			KEY_BRACKETLEFT:
				ctx.prop_scale = snappedf(ctx.prop_scale / 1.1, 0.001)
				ctx.say("Scale %.2f" % ctx.prop_scale)
				return true
			KEY_BRACKETRIGHT:
				ctx.prop_scale = snappedf(ctx.prop_scale * 1.1, 0.001)
				ctx.say("Scale %.2f" % ctx.prop_scale)
				return true
			KEY_S:
				ctx.snap = (ctx.snap + 1) % 3 as EditorContext.Snap
				ctx.say("Snap: " + ["off", "hex centre", "hex corner"][ctx.snap])
				return true
		return false

	func draw_overlay(c: Node2D) -> void:
		if ctx.prop_ref == "":
			return
		var pos := ctx.snapped_point(ctx.mouse_hex()) if not Input.is_key_pressed(KEY_SHIFT) else ctx.mouse_hex()
		var ghost := ctx.new_prop(pos)
		ctx.canvas.draw_prop(c, ghost, ctx.packs.prop(ctx.prop_ref), 0.6)


# =============================================================================

class WallTool extends Tool:
	var _points: Array[Vector2] = []

	func _snap(p: Vector2, mods: Dictionary) -> Vector2:
		return p if mods.get("shift", false) or not ctx.snap_walls else grid().snap_to_corner(p)

	func press(p: Vector2, button: int, mods: Dictionary) -> bool:
		if button == MOUSE_BUTTON_RIGHT:
			_finish()
			return true
		if button != MOUSE_BUTTON_LEFT:
			return false
		var q := _snap(p, mods)
		if not _points.is_empty() and _points[-1].distance_to(q) < 1e-4:
			return true
		_points.append(q)
		# Doors are single segments: finish on the second click.
		var preset: Dictionary = EditorContext.WALL_PRESETS.get(ctx.wall_preset, {})
		if str(preset.get("door", "none")) != "none" and _points.size() == 2:
			_finish()
		return true

	func double_click(_p: Vector2) -> bool:
		_finish()
		return true

	func key(event: InputEventKey) -> bool:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_finish()
				return true
			KEY_ESCAPE:
				if _points.is_empty():
					return false
				_points.clear()
				ctx.canvas.overlay.queue_redraw()
				return true
			KEY_BACKSPACE:
				if _points.is_empty():
					return false
				_points.pop_back()
				ctx.canvas.overlay.queue_redraw()
				return true
		return false

	func _finish() -> void:
		if _points.size() >= 2:
			var w := ctx.new_wall()
			var pts: Array = []
			for q in _points:
				pts.append([snappedf(q.x, 0.0001), snappedf(q.y, 0.0001)])
			w["points"] = pts
			if ctx.wall_style != "":
				var parts := PackLibrary.split_ref(ctx.wall_style)
				if parts.size() == 2:
					ctx.map.note_pack(parts[0], ctx.packs.pack_version(parts[0]))
			ctx.commands.add_object(ctx.level_index, "walls", w, "Draw wall")
			ctx.select_one("walls", w.id)
		_points.clear()
		ctx.canvas.overlay.queue_redraw()

	func deactivate() -> void:
		_finish()

	func draw_overlay(c: Node2D) -> void:
		var mods := {"shift": Input.is_key_pressed(KEY_SHIFT)}
		var cursor := _snap(ctx.mouse_hex(), mods)
		var preview := ctx.new_wall()
		var pts: Array = []
		for q in _points:
			pts.append([q.x, q.y])
		pts.append([cursor.x, cursor.y])
		if pts.size() >= 2:
			preview["points"] = pts
			ctx.canvas.draw_wall(c, preview, 0.7)
		c.draw_circle(px(cursor), 5.0, Color(1, 1, 1, 0.9))


# =============================================================================

class LightTool extends Tool:
	func press(p: Vector2, button: int, mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		var pos := p if mods.shift else ctx.snapped_point(p)
		var l := ctx.new_light(pos)
		ctx.commands.add_object(ctx.level_index, "lights", l, "Place light")
		ctx.select_one("lights", l.id)
		return true

	func draw_overlay(c: Node2D) -> void:
		var pos := ctx.snapped_point(ctx.mouse_hex()) if not Input.is_key_pressed(KEY_SHIFT) else ctx.mouse_hex()
		ctx.canvas.draw_light(c, ctx.new_light(pos), 0.6)
		c.draw_circle(px(pos), 5.0, Color(1, 1, 1, 0.9))


# =============================================================================

class NoteTool extends Tool:
	func press(p: Vector2, button: int, _mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		var n := {"id": HexMap.new_id("n"), "pos": [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)], "title": "Note", "text": "", "gm_only": true}
		ctx.commands.add_object(ctx.level_index, "notes", n, "Add note")
		ctx.select_one("notes", n.id)
		return true


# =============================================================================

class EraseTool extends Tool:
	var _down := false

	func press(p: Vector2, button: int, _mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		_down = true
		var hit := pick(p)
		if not hit.is_empty():
			ctx.commands.remove_object(ctx.level_index, hit.collection, hit.id)
			ctx.clear_selection()
			return true
		var cell := grid().world_to_axial(p)
		if grid().in_bounds(cell):
			ctx.commands.set_terrain(ctx.level_index, [cell], null)
		return true

	func release(_p: Vector2, _button: int, _mods: Dictionary) -> void:
		_down = false

	func draw_overlay(c: Node2D) -> void:
		var cell := grid().world_to_axial(ctx.mouse_hex())
		if grid().in_bounds(cell):
			outline_cell(c, cell, Color(1, 0.4, 0.4, 0.8), 2.0)
