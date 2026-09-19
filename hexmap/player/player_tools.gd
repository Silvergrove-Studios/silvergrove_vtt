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

	func press(p: Vector2, button: int, _mods: Dictionary) -> bool:
		if button != MOUSE_BUTTON_LEFT:
			return false
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

	func move(_p: Vector2) -> void:
		pass

	func _snap(p: Vector2) -> Vector2:
		var m := canvas.map
		return m.grid.snap_to_center(p) if m != null else p

	func draw_overlay(c: Node2D) -> void:
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
