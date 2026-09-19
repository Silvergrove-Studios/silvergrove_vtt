class_name TableTools
extends RefCounted
## The Table's tools: small state machines fed pointer events in hex units by
## the canvas view. Select moves tokens and flips doors and lights with a
## click; Token places new ones; Fog reveals or hides cells with a brush.
## Every change goes through EncounterCommands so it is one undo step and,
## later, one message to the players.

static func make(tool_name: String, ctx: TableContext) -> Tool:
	var t: Tool
	match tool_name:
		"token": t = TokenTool.new()
		"fog": t = FogTool.new()
		_: t = SelectTool.new()
	t.ctx = ctx
	t.tool_name = tool_name
	return t


static func all_tools() -> Array[Dictionary]:
	return [
		{"name": "select", "label": "Select", "key": "V", "icon": "mouse-pointer-2", "hint": "Click a token to select, drag to move (Shift: free placement). Click a door to open or close it, a light to put it out or relight it."},
		{"name": "token", "label": "Token", "key": "T", "icon": "circle-dot", "hint": "Click to place a token. Set its name, colour and owner in Tool options."},
		{"name": "fog", "label": "Fog", "key": "F", "icon": "moon-star", "hint": "Drag to reveal cells to the players; right-drag hides them again. [ ] change the brush."},
	]


# =============================================================================

class Tool extends RefCounted:
	var ctx: TableContext
	var tool_name := ""

	func activate() -> void: pass
	func deactivate() -> void: pass
	func press(_p: Vector2, _button: int, _mods: Dictionary) -> bool: return false
	func drag(_p: Vector2, _button: int, _mods: Dictionary) -> void: pass
	func release(_p: Vector2, _button: int, _mods: Dictionary) -> void: pass
	func move(_p: Vector2) -> void: ctx.canvas.overlay.queue_redraw()
	func cursor() -> Control.CursorShape: return Control.CURSOR_ARROW
	func double_click(_p: Vector2) -> bool: return false
	func key(_event: InputEventKey) -> bool: return false
	func draw_overlay(_c: Node2D) -> void: pass

	func grid() -> HexGrid: return ctx.map().grid
	func px(p: Vector2) -> Vector2: return p * ctx.canvas.ppx

	## Screen-constant size in hex units.
	func handle_hex(px_size := 7.0) -> float:
		return px_size / maxf(1e-6, ctx.canvas.ppx * ctx.zoom)

	func outline_cell(c: Node2D, cell: Vector2i, color: Color, width := 2.0) -> void:
		var pts := PackedVector2Array()
		for k in grid().cell_corners(cell):
			pts.append(px(k))
		pts.append(pts[0])
		c.draw_polyline(pts, color, width, true)

	## Topmost token under a point (last drawn = last in the list).
	func token_at(p: Vector2) -> Dictionary:
		var toks: Array = ctx.state.tokens(ctx.scene_id)
		for i in range(toks.size() - 1, -1, -1):
			if ctx.canvas.token_hit(toks[i], p):
				return toks[i]
		return {}

	## A door segment within reach of a point: the effective wall, or {}.
	func door_at(p: Vector2) -> Dictionary:
		var best := {}
		var best_d := 0.12
		for w in ctx.level().get("walls", []):
			if str(w.get("door", "none")) == "none":
				continue
			var pts: Array = w.get("points", [])
			for i in pts.size() - 1:
				var a := Vector2(pts[i][0], pts[i][1])
				var b := Vector2(pts[i + 1][0], pts[i + 1][1])
				var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
				if d < best_d:
					best_d = d
					best = w
		return best

	func light_at(p: Vector2) -> Dictionary:
		for l in ctx.level().get("lights", []):
			if Vector2(l.pos[0], l.pos[1]).distance_to(p) < 0.22:
				return l
		return {}

	## A note or a prop under the point (effective objects), for selecting
	## and revealing. Notes first, then props from the top of the draw order.
	func element_at(p: Vector2) -> Dictionary:
		var canvas := ctx.canvas
		for n in ctx.level().get("notes", []):
			if Vector2(n.pos[0], n.pos[1]).distance_to(p) < 0.14:
				return {"collection": "notes", "id": n.id}
		var props: Array = canvas.props_in_order()
		for i in range(props.size() - 1, -1, -1):
			var pr: Dictionary = props[i]
			if canvas.prop_hit(pr, ctx.app.packs.prop(str(pr.get("asset", ""))), p * canvas.ppx):
				return {"collection": "props", "id": pr.id}
		return {}

	## Door and light markers so the DM can see what is clickable.
	func draw_markers(c: Node2D) -> void:
		if not ctx.canvas.gm_view():
			return
		var ppx := ctx.canvas.ppx
		var r := handle_hex(6.0) * ppx
		for w in ctx.level().get("walls", []):
			if str(w.get("door", "none")) == "none":
				continue
			var pts: Array = w.get("points", [])
			if pts.size() < 2:
				continue
			var mid := (Vector2(pts[0][0], pts[0][1]) + Vector2(pts[-1][0], pts[-1][1])) / 2.0 * ppx
			var st := str(w.get("state", "closed"))
			var col := Color("#e0d090") if st == "open" else (Color("#e06060") if st == "locked" else Color("#e0a040"))
			c.draw_circle(mid, r + 2.0, Color(0, 0, 0, 0.7))
			c.draw_circle(mid, r, col)
			if st == "locked":
				c.draw_rect(Rect2(mid - Vector2(r * 0.35, r * 0.1), Vector2(r * 0.7, r * 0.5)), Color.BLACK)
		if ctx.canvas.show_lights:
			for l in ctx.level().get("lights", []):
				var pos := Vector2(l.pos[0], l.pos[1]) * ppx
				var on := bool(l.get("on", true))
				c.draw_circle(pos, r + 2.0, Color(0, 0, 0, 0.7))
				c.draw_circle(pos, r, Color(str(l.get("color", "#ffb060"))) if on else Color("#555555"))
				if not on:
					c.draw_line(pos - Vector2(r, r) * 0.7, pos + Vector2(r, r) * 0.7, Color("#e06060"), 2.0, true)


# =============================================================================

class SelectTool extends Tool:
	## "" | move | box
	var _mode := ""
	var _start := Vector2.ZERO
	var _at := Vector2.ZERO
	var _box_end := Vector2.ZERO
	var _moved := false
	var _hover: Dictionary = {}

	func cursor() -> Control.CursorShape:
		return Control.CURSOR_POINTING_HAND if not _hover.is_empty() else Control.CURSOR_ARROW

	func press(p: Vector2, button: int, mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		var tk := token_at(p)
		if not tk.is_empty():
			if mods.shift:
				var sel := ctx.selection.duplicate()
				if ctx.is_token_selected(tk.id):
					sel = sel.filter(func(s) -> bool: return not (s.kind == "token" and s.id == tk.id))
				else:
					sel.append({"kind": "token", "id": tk.id})
				ctx.set_selection(sel)
			elif not ctx.is_token_selected(tk.id):
				ctx.select_token(tk.id)
			_mode = "move"
			_start = p
			_at = p
			_moved = false
			return true
		var door := door_at(p)
		if not door.is_empty():
			_toggle_door(door)
			return true
		var light := light_at(p)
		if not light.is_empty():
			ctx.commands.set_light(ctx.scene_id, light.id, not bool(light.get("on", true)))
			ctx.say("%s: light %s" % [str(light.get("name", "Light")), "off" if bool(light.get("on", true)) else "on"])
			return true
		var el := element_at(p)
		if not el.is_empty():
			ctx.select_element(el.collection, el.id)
			return true
		_mode = "box"
		_start = p
		_box_end = p
		if not mods.shift:
			ctx.clear_selection()
		return true

	func _toggle_door(door: Dictionary) -> void:
		var st := str(door.get("state", "closed"))
		if st == "locked":
			ctx.say("The door is locked. Unlock it in the Inspector.")
			ctx.select_element("walls", door.id)
			return
		ctx.commands.set_door(ctx.scene_id, door.id, "open" if st == "closed" else "closed")
		ctx.say("Door %s" % ("opened" if st == "closed" else "closed"))

	func drag(p: Vector2, _button: int, _mods: Dictionary) -> void:
		match _mode:
			"move":
				_at = p
				if p.distance_to(_start) > 0.05:
					_moved = true
			"box":
				_box_end = p
		ctx.canvas.overlay.queue_redraw()

	func release(p: Vector2, _button: int, mods: Dictionary) -> void:
		match _mode:
			"move":
				if _moved:
					var delta := p - _start
					var ids := ctx.selected_token_ids()
					if ids.size() > 1:
						ctx.commands.begin_group()
					for id in ids:
						var tk := ctx.state.token(ctx.scene_id, id)
						var to := Vision.token_pos(tk) + delta
						if not mods.shift:
							to = ctx.snapped(to)
						ctx.commands.move_token(ctx.scene_id, id, to)
					if ids.size() > 1:
						ctx.commands.end_group("Move %d tokens" % ids.size())
			"box":
				var r := Rect2(_start, Vector2.ZERO).expand(_box_end).abs()
				var sel := ctx.selection.duplicate() if mods.shift else []
				for tk in ctx.state.tokens(ctx.scene_id):
					if r.has_point(Vision.token_pos(tk)) and not ctx.is_token_selected(tk.id):
						sel.append({"kind": "token", "id": tk.id})
				ctx.set_selection(sel)
		_mode = ""
		_moved = false
		ctx.canvas.overlay.queue_redraw()

	func move(p: Vector2) -> void:
		var tk := token_at(p)
		var h := {}
		if not tk.is_empty():
			h = {"kind": "token", "id": tk.id}
		elif not door_at(p).is_empty():
			h = {"kind": "door", "id": door_at(p).id}
		elif not light_at(p).is_empty():
			h = {"kind": "light", "id": light_at(p).id}
		if h != _hover:
			_hover = h
		ctx.canvas.overlay.queue_redraw()

	func key(event: InputEventKey) -> bool:
		if not event.pressed:
			return false
		var ids := ctx.selected_token_ids()
		match event.keycode:
			KEY_DELETE, KEY_BACKSPACE:
				if ids.is_empty():
					return false
				ctx.commands.remove_tokens(ctx.scene_id, ids)
				return true
			KEY_H:
				if ids.is_empty():
					return false
				ctx.commands.begin_group()
				for id in ids:
					var tk := ctx.state.token(ctx.scene_id, id)
					ctx.commands.update_token(ctx.scene_id, id, {"hidden": not bool(tk.get("hidden", false))})
				ctx.commands.end_group("Hide" if not bool(ctx.state.token(ctx.scene_id, ids[0]).get("hidden", false)) else "Reveal")
				return true
		return false

	func draw_overlay(c: Node2D) -> void:
		draw_markers(c)
		var canvas := ctx.canvas
		for id in ctx.selected_token_ids():
			var tk := ctx.state.token(ctx.scene_id, id)
			if tk.is_empty():
				continue
			if _mode == "move" and _moved:
				var ghost: Dictionary = tk.duplicate(true)
				var to := Vision.token_pos(tk) + (_at - _start)
				to = ctx.snapped(to)
				ghost.pos = [to.x, to.y]
				canvas.draw_token(c, ghost, 0.6)
			else:
				var pos := px(Vision.token_pos(tk))
				c.draw_arc(pos, canvas.token_radius_px(tk) + handle_hex(4.0) * canvas.ppx, 0.0, TAU, 48, Color(1, 1, 0.3, 0.9), 2.0 / maxf(1e-6, ctx.zoom), true)
		if _mode == "box":
			var r := Rect2(px(_start), Vector2.ZERO).expand(px(_box_end)).abs()
			c.draw_rect(r, Color(0.4, 0.7, 1.0, 0.15))
			c.draw_rect(r, Color(0.4, 0.7, 1.0, 0.9), false, 1.0 / maxf(1e-6, ctx.zoom))
		if ctx.selection.size() == 1 and ctx.selection[0].kind == "element":
			var el := ctx.selected_element()
			if not el.is_empty():
				var s: Dictionary = ctx.selection[0]
				var w := 2.0 / maxf(1e-6, ctx.zoom)
				match s.collection:
					"walls":
						canvas.draw_wall(c, el, 1.0, true)
					"props":
						var r := canvas.prop_rect(el, ctx.app.packs.prop(str(el.get("asset", ""))))
						c.draw_rect(r, Color(1, 1, 0.3, 0.9), false, w)
					"notes", "lights":
						c.draw_circle(px(Vector2(el.pos[0], el.pos[1])), handle_hex(12.0) * canvas.ppx, Color(1, 1, 0.3, 0.9), false, w)


# =============================================================================

class TokenTool extends Tool:
	var _at := Vector2.ZERO
	var _has := false

	func cursor() -> Control.CursorShape:
		return Control.CURSOR_CROSS

	func press(p: Vector2, button: int, mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		var pos := p if mods.shift else ctx.snapped(p)
		var tk := ctx.new_token(pos)
		ctx.commands.add_token(ctx.scene_id, tk)
		ctx.select_token(tk.id)
		ctx.say("Placed %s" % str(tk.name))
		return true

	func move(p: Vector2) -> void:
		_at = ctx.snapped(p)
		_has = true
		ctx.canvas.overlay.queue_redraw()

	func draw_overlay(c: Node2D) -> void:
		draw_markers(c)
		if _has:
			ctx.canvas.draw_token(c, ctx.new_token(_at), 0.5)


# =============================================================================

class FogTool extends Tool:
	var _at := Vector2.ZERO
	var _has := false
	var _button := 0
	var _stroke := {}

	func cursor() -> Control.CursorShape:
		return Control.CURSOR_CROSS

	func _cells(p: Vector2) -> Array:
		var out := []
		for c in HexGrid.spiral(grid().world_to_axial(p), ctx.fog_brush - 1):
			if grid().in_bounds(c):
				out.append(c)
		return out

	func press(p: Vector2, button: int, _mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
			return false
		if not ctx.state.fog_enabled(ctx.scene_id):
			ctx.commands.set_fog(ctx.scene_id, true)
			ctx.say("Fog turned on for this scene")
		_button = button
		_stroke = {}
		ctx.commands.begin_group()
		_paint(p)
		return true

	func _paint(p: Vector2) -> void:
		var cells := []
		for c in _cells(p):
			var k := HexMap.cell_key(c)
			if not _stroke.has(k):
				_stroke[k] = true
				cells.append(k)
		if cells.is_empty():
			return
		if _button == MOUSE_BUTTON_LEFT:
			ctx.commands.reveal_cells(ctx.scene_id, cells)
		else:
			ctx.commands.hide_cells(ctx.scene_id, cells)

	func drag(p: Vector2, _button: int, _mods: Dictionary) -> void:
		if _button_active():
			_paint(p)
		move(p)

	func _button_active() -> bool:
		return _button != 0

	func release(_p: Vector2, _button_up: int, _mods: Dictionary) -> void:
		if _button != 0:
			ctx.commands.end_group("Reveal" if _button == MOUSE_BUTTON_LEFT else "Hide")
		_button = 0
		_stroke = {}

	func key(event: InputEventKey) -> bool:
		if not event.pressed:
			return false
		match event.keycode:
			KEY_BRACKETLEFT:
				ctx.fog_brush = maxi(1, ctx.fog_brush - 1)
				ctx.canvas.overlay.queue_redraw()
				return true
			KEY_BRACKETRIGHT:
				ctx.fog_brush = mini(6, ctx.fog_brush + 1)
				ctx.canvas.overlay.queue_redraw()
				return true
		return false

	func move(p: Vector2) -> void:
		_at = p
		_has = true
		ctx.canvas.overlay.queue_redraw()

	func draw_overlay(c: Node2D) -> void:
		if not _has:
			return
		for cell in _cells(_at):
			outline_cell(c, cell, Color(1, 1, 1, 0.8), 2.0 / maxf(1e-6, ctx.zoom))
