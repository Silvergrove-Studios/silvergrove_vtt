class_name PlayerTools
extends RefCounted
## The Player's one tool: tap a token of yours to pick it up, drag it,
## let go to ask the table for the move. Everything else on the map is
## look-only. Written for a finger: no hover state matters, no modifiers
## are needed, a small wobble is still a tap.

class MoveTool extends RefCounted:
	var session: Session
	var canvas: MapCanvas
	var zoom := 1.0
	var selected := ""
	## A pick in flight: the intent waiting for its target (with `pick`
	## and `area` still on it), or empty.
	var pick: Dictionary = {}
	var _hover := Vector2.INF
	var _dragging := false
	var _start := Vector2.ZERO
	var _at := Vector2.ZERO
	var _moved := false

	func _init(p_session: Session, p_canvas: MapCanvas) -> void:
		session = p_session
		canvas = p_canvas

	func cursor() -> Control.CursorShape:
		return Control.CURSOR_ARROW

	## Tokens this player can pick up: theirs, on the shown scene.
	func token_at(p: Vector2) -> Dictionary:
		var toks: Array = session.my_tokens()
		for i in range(toks.size() - 1, -1, -1):
			if canvas.token_hit(toks[i], p):
				return toks[i]
		return {}

	## Start asking for a target: the next tap resolves it and sends the
	## intent; a tap on nothing (for a token pick) cancels.
	func begin_pick(payload: Dictionary) -> void:
		pick = payload.duplicate(true)
		selected = ""
		canvas.overlay.queue_redraw()
		session.status.emit("%s: tap a %s on the map" % [str(pick.get("label", "Pick")), str(pick.get("pick", "target"))])

	func cancel_pick() -> void:
		if pick.is_empty():
			return
		pick = {}
		canvas.overlay.queue_redraw()
		session.status.emit("Pick cancelled")

	## The spec MapQuery.pick_target wants for the pick in flight.
	func pick_spec() -> Dictionary:
		var ctx: Dictionary = pick.get("ctx", {}) if pick.get("ctx") is Dictionary else {}
		var from := str(ctx.get("token", ""))
		if from == "" and str(ctx.get("actor", "")) != "":
			for tk in session.state.tokens(session.scene_id()):
				if str(tk.get("actor", "")) == str(ctx.actor):
					from = str(tk.id)
					break
		return {"kind": str(pick.get("pick", "")), "area": pick.get("area", {}), "from": from}

	func _resolve_pick(p: Vector2) -> void:
		var target: Variant = MapQuery.pick_target(session.state, session.scene_id(), pick_spec(), p, session.is_gm())
		if target == null:
			cancel_pick()
			return
		var payload: Dictionary = pick.duplicate(true)
		pick = {}
		payload.erase("pick")
		payload.erase("area")
		payload.erase("label")
		if not (payload.get("ctx") is Dictionary):
			payload.ctx = {}
		payload.ctx.target = target
		payload.ctx.scene = session.scene_id()
		canvas.overlay.queue_redraw()
		var why := session.intent(payload)
		if why != "":
			session.status.emit(why)

	func press(p: Vector2, button: int, _mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
		if not pick.is_empty():
			_resolve_pick(p)
			return true
		var tk := token_at(p)
		if tk.is_empty():
			selected = ""
			canvas.overlay.queue_redraw()
			return false
		selected = str(tk.id)
		_dragging = true
		_start = p
		_at = p
		_moved = false
		canvas.overlay.queue_redraw()
		return true

	func drag(p: Vector2, _button: int, _mods: Dictionary) -> void:
		if not _dragging:
			return
		_at = p
		if p.distance_to(_start) > 0.08:
			_moved = true
		canvas.overlay.queue_redraw()

	func release(p: Vector2, _button: int, _mods: Dictionary) -> void:
		if _dragging and _moved and selected != "":
			var tk := session.state.token(session.scene_id(), selected)
			if not tk.is_empty():
				var to := _snap(Vision.token_pos(tk) + (p - _start))
				var why := session.request({"t": "token.set", "scene": session.scene_id(), "id": selected, "changes": {"pos": [to.x, to.y]}})
				if why != "":
					session.status.emit(why)
		_dragging = false
		_moved = false
		canvas.overlay.queue_redraw()

	func move(p: Vector2) -> void:
		if not pick.is_empty():
			_hover = p
			canvas.overlay.queue_redraw()

	func _snap(p: Vector2) -> Vector2:
		var m := canvas.map
		return m.grid.snap_to_center(p) if m != null else p

	func draw_overlay(c: Node2D) -> void:
		if not pick.is_empty():
			_draw_pick(c)
			return
		if selected == "":
			return
		var tk := session.state.token(session.scene_id(), selected)
		if tk.is_empty():
			return
		var ppx := canvas.ppx
		if _dragging and _moved:
			var ghost: Dictionary = tk.duplicate(true)
			var to := _snap(Vision.token_pos(tk) + (_at - _start))
			ghost.pos = [to.x, to.y]
			canvas.draw_token(c, ghost, 0.6)
		var pos := Vision.token_pos(tk) * ppx
		c.draw_arc(pos, canvas.token_radius_px(tk) + 6.0 / maxf(1e-6, zoom), 0.0, TAU, 48, Color(1, 1, 0.3, 0.9), 3.0 / maxf(1e-6, zoom), true)

	## The pick's preview at the pointer: the token, the cell or the area's
	## cells the tap would choose. The kernel is not here, so an area shows
	## its origin cell and a ring of the given reach.
	func _draw_pick(c: Node2D) -> void:
		var m := canvas.map
		if m == null or _hover == Vector2.INF:
			return
		var target: Variant = MapQuery.pick_target(session.state, session.scene_id(), pick_spec(), _hover, session.is_gm())
		if target == null:
			return
		var ppx := canvas.ppx
		var col := Color(1.0, 0.85, 0.4, 0.9)
		var w := 3.0 / maxf(1e-6, zoom)
		var cells := []
		if target is String and (target as String).begins_with("token:"):
			var tk := session.state.token(session.scene_id(), (target as String).substr(6))
			if not tk.is_empty():
				c.draw_arc(Vision.token_pos(tk) * ppx, canvas.token_radius_px(tk) + 6.0 / maxf(1e-6, zoom), 0.0, TAU, 48, col, w, true)
			return
		elif target is String:
			cells = [target]
		elif target is Dictionary:
			var at := str(target.get("at", ""))
			var origin := m.grid.cell_center(HexMap.key_cell(at)) if HexMap.is_cell_key(at) else Vision.token_pos(session.state.token(session.scene_id(), at.substr(6)))
			var reach := float(target.get("radius", target.get("length", 1)))
			for cell in m.grid.spiral(m.grid.world_to_axial(origin), int(ceil(reach))):
				if m.grid.in_bounds(cell) and m.grid.cell_center(cell).distance_to(origin) <= reach + 0.5:
					cells.append(HexMap.cell_key(cell))
		for key in cells:
			var pts := PackedVector2Array()
			for k in m.grid.cell_corners(HexMap.key_cell(str(key))):
				pts.append(k * ppx)
			pts.append(pts[0])
			c.draw_polyline(pts, col, w, true)
