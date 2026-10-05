class_name Marks
extends RefCounted
## Shared marks: what someone at the table puts on the map for everyone to
## see — a ruler, a template, a spell's preview, a ping (docs/plugin-
## authoring.md, "Table tools"). Each is one person's (`owner`: "gm" or a
## player's id), drawn in their colour with their name, kept here on the
## Table and sent by the host to everyone allowed to see it (HostSession).
## Never the encounter's: no event, no undo step, nothing in the saved game.
##
## A mark held (its owner still dragging it: `live`) stays while they hold
## it, and goes HELD_MS after the last word from them (a dropped
## connection); let go, it lingers for its kind's while — a ruler a few
## seconds, a template or a preview a minute, a ping a moment — and goes,
## unless pinned: a pinned mark stays until its owner or the DM takes it off.
##
## A mark on a token (`token`: a preview that goes out from its caster)
## stands where the token stands, and goes with it. A ruler's `measure` is
## worked out here (Measure.ruler), by the map's own rules and the ground's
## price as the rules have it.
##
##   {id, owner, kind: ruler | template | preview | ping, scene,
##    points: [[x, y], …] (hex units: a ruler's waypoints, one place for the rest),
##    shape: {type: circle | cone | line | square, size, width, angle, origin, include_self} (hex units),
##    direction (degrees), token, label, pinned, live, private (the DM's own)}
## and from the Table: name, color, measure.

signal changed(id: String)
signal removed(id: String, mark: Dictionary)

const KINDS := ["ruler", "template", "preview", "ping"]
const SHAPES := ["circle", "cone", "line", "square"]
## How many one person may have at once, pinned or not: one more takes the
## place of their oldest unpinned one.
const MAX_PER_OWNER := 8
## A ruler's points, waypoints and both ends.
const MAX_POINTS := 16
const MAX_LABEL := 80
## The biggest a template may be, in hex units (a mile of 5-foot cells).
const MAX_SIZE := 1056.0
## How long a mark lingers once let go, by kind (ms).
const LINGER_MS := {"ruler": 5000, "template": 60000, "preview": 60000, "ping": 4000}
## A mark held with no word from its owner for this long goes (ms).
const HELD_MS := 30000

## id -> mark. Keys starting with "_" are the Table's own and never sent.
var marks: Dictionary = {}
## The time now, in ms (a test sets its own).
var clock: Callable = func() -> int: return Time.get_ticks_msec()
## The encounter and the map's questions, for a ruler's measure and for a
## mark on a token (bind).
var state: EncounterState
var map_query: MapQuery
var _order := 0
## A ruler's legs walked, by scene, cells and what was known: kept until the
## encounter changes.
var _legs: Dictionary = {}
static var _ID := RegEx.create_from_string("^[A-Za-z0-9_-]{4,40}$")


## Follow an encounter: a mark on a token moves with it and goes with it, a
## mark on a scene that goes goes too, and a ruler is measured again when
## its walls change. Marks of the encounter before are dropped.
func bind(p_state: EncounterState, p_map_query: MapQuery) -> void:
	if state != null and state.applied.is_connected(_on_applied):
		state.applied.disconnect(_on_applied)
	clear_all()
	state = p_state
	map_query = p_map_query
	if state != null:
		state.applied.connect(_on_applied)


## Put a mark, or change one of one's own: "" or why not. `extra` is what
## the Table says of it (name, color); `gm` may keep it to the DMs
## (`private`).
func put(owner: String, raw: Variant, extra: Dictionary = {}, gm := false) -> String:
	if owner == "":
		return "join the table first"
	if not (raw is Dictionary):
		return "not a mark"
	var r: Dictionary = raw
	var id := str(r.get("id", ""))
	if _ID.search(id) == null:
		return "a mark's id is 4 to 40 letters, digits, - or _"
	var had: Dictionary = marks.get(id, {})
	if not had.is_empty() and str(had.owner) != owner:
		return "that mark is someone else's"
	var kind := str(r.get("kind", ""))
	if not KINDS.has(kind):
		return "a mark is a ruler, a template, a preview or a ping"
	var scene := str(r.get("scene", ""))
	if scene == "" or (state != null and state.encounter.scene(scene).is_empty()):
		return "no such scene"
	var pts := _points(r.get("points"), scene)
	if pts.is_empty():
		return "where is it?"
	if pts.size() > (MAX_POINTS if kind == "ruler" else 1):
		return "a ruler has %d points at most" % MAX_POINTS if kind == "ruler" else "a %s is at one place" % kind
	var m := {"id": id, "owner": owner, "kind": kind, "scene": scene, "points": pts,
		"pinned": bool(r.get("pinned", false)) if r.get("pinned") is bool else false,
		"live": kind != "ping" and r.get("live") is bool and bool(r.live)}
	var dir: Variant = r.get("direction", 0.0)
	m.direction = wrapf(float(dir), -180.0, 180.0) if (dir is float or dir is int) and is_finite(float(dir)) else 0.0
	if kind == "template" or kind == "preview":
		var sh := _shape(r.get("shape"))
		if sh.is_empty():
			return "a template is a circle, a cone, a line or a square, of a size"
		m.shape = sh
		var tk := str(r.get("token", "")) if r.get("token") is String else ""
		if tk != "":
			if state != null and state.token(scene, tk).is_empty():
				return "no such token on this scene"
			m.token = tk
	var label := str(r.get("label", "")) if r.get("label") is String else ""
	label = label.replace("\n", " ").replace("\t", " ").strip_edges().left(MAX_LABEL)
	if label != "":
		m.label = label
	if gm and r.get("private") is bool and bool(r.private):
		m.private = true
	for k in extra:
		m[k] = extra[k]
	if had.is_empty():
		var why := _room_for(owner)
		if why != "":
			return why
		_order += 1
		m._order = _order
	else:
		m._order = had._order
	_anchor(m)
	if kind == "ruler":
		_measure(m, had)
	var now := int(clock.call())
	m._at = now
	m._until = INF if bool(m.pinned) and not bool(m.live) else now + (HELD_MS if bool(m.live) else int(LINGER_MS[kind]))
	marks[id] = m
	changed.emit(id)
	return ""


## Take a mark off: its owner may, and the DM may take anyone's. "" or why not.
func remove(by: String, id: String, gm := false) -> String:
	var m: Dictionary = marks.get(id, {})
	if m.is_empty():
		return ""
	if str(m.owner) != by and not gm:
		return "that mark is someone else's"
	_drop(id)
	return ""


## Take marks off: one's own (`whose` "" or one's own id), or — the DM —
## one person's ("gm" or a player's id) or everyone's ("all"). The ids gone.
func clear(by: String, whose := "", gm := false) -> Array:
	var who := by if whose == "" else whose
	if who != by and not gm:
		return []
	var gone := []
	for id in marks.keys():
		if who == "all" or str(marks[id].owner) == who:
			gone.append(str(id))
	for id in gone:
		_drop(id)
	return gone


## Everything goes (another encounter, hosting stopped).
func clear_all() -> void:
	for id in marks.keys():
		_drop(str(id))
	_legs.clear()


## Someone let go of everything they held (their screen went): it lingers
## and goes, as when they let go of it.
func let_go(owner: String) -> void:
	var now := int(clock.call())
	for id in marks.keys():
		var m: Dictionary = marks[id]
		if str(m.owner) == owner and bool(m.live):
			m.live = false
			m._until = INF if bool(m.pinned) else now + int(LINGER_MS[str(m.kind)])
			changed.emit(str(id))


## Marks whose time is up go. Call every frame or so.
func tick() -> void:
	var now := int(clock.call())
	var gone := []
	for id in marks:
		if float(marks[id]._until) <= now:
			gone.append(str(id))
	for id in gone:
		_drop(id)


## A mark as it goes over the wire (and to a drawing): without the Table's own keys.
static func wire(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		if not str(k).begins_with("_"):
			out[k] = JsonDoc.deep(m[k])
	return out


## The marks on a scene, oldest first.
func of_scene(scene_id: String) -> Array:
	var out := []
	for id in marks:
		if str(marks[id].scene) == scene_id:
			out.append(marks[id])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a._order) < int(b._order))
	return out


## A mark's place as a point: its first (a ruler's start, a template's place).
static func point(m: Dictionary, i := 0) -> Vector2:
	var pts: Array = m.get("points", [])
	if pts.is_empty():
		return Vector2.ZERO
	var p: Array = pts[clampi(i, -pts.size(), pts.size() - 1)]
	return Vector2(float(p[0]), float(p[1]))


# --------------------------------------------------------------- inside --

func _drop(id: String) -> void:
	var m: Dictionary = marks.get(id, {})
	if m.is_empty():
		return
	marks.erase(id)
	removed.emit(id, m)


## Room for one more of `owner`'s: their oldest unpinned goes when they have
## all they may; with every one pinned, no.
func _room_for(owner: String) -> String:
	var mine := []
	for id in marks:
		if str(marks[id].owner) == owner:
			mine.append(marks[id])
	if mine.size() < MAX_PER_OWNER:
		return ""
	mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a._order) < int(b._order))
	for m in mine:
		if not bool(m.pinned):
			_drop(str(m.id))
			return ""
	return "%d marks at most, all pinned: take one off first" % MAX_PER_OWNER


## [[x, y], …] of finite numbers on (or by) the scene's map, or [] for anything else.
func _points(v: Variant, scene: String) -> Array:
	if not (v is Array):
		return []
	var lim := Vector2(1e6, 1e6)
	if state != null and state.map_for(scene) != null:
		lim = state.map_for(scene).grid.map_size() + Vector2(4, 4)
	var out := []
	for p in v:
		if not (p is Array) or (p as Array).size() != 2 or not (p[0] is float or p[0] is int) or not (p[1] is float or p[1] is int):
			return []
		var x := float(p[0])
		var y := float(p[1])
		if not is_finite(x) or not is_finite(y) or x < -4.0 or y < -4.0 or x > lim.x or y > lim.y:
			return []
		out.append([snappedf(x, 0.001), snappedf(y, 0.001)])
	return out


## A template's shape, checked: {} when it isn't one.
static func _shape(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var s: Dictionary = v
	var type := str(s.get("type", ""))
	if not SHAPES.has(type):
		return {}
	var num := func(k: String, fallback: float) -> float:
		var x: Variant = s.get(k, fallback)
		return float(x) if (x is float or x is int) and is_finite(float(x)) else -1.0
	var size: float = num.call("size", -1.0)
	if size <= 0.0 or size > MAX_SIZE:
		return {}
	var out := {"type": type, "size": snappedf(size, 0.0001)}
	if type == "line":
		var w: float = num.call("width", 1.0)
		if w <= 0.0 or w > MAX_SIZE:
			return {}
		out.width = snappedf(w, 0.0001)
	if type == "cone":
		var a: float = num.call("angle", 53.0)
		if a <= 0.0 or a > 360.0:
			return {}
		out.angle = a
	out.origin = "edge" if str(s.get("origin", "")) == "edge" else "center"
	out.include_self = not (s.get("include_self") is bool) or bool(s.include_self)
	return out


## A mark on a token stands where the token does.
func _anchor(m: Dictionary) -> void:
	if state == null or str(m.get("token", "")) == "":
		return
	var tk := state.token(str(m.scene), str(m.token))
	if not tk.is_empty():
		var p := Vision.token_pos(tk)
		m.points = [[snappedf(p.x, 0.001), snappedf(p.y, 0.001)]]


## A ruler's measure, by the map's rules: again only when its points moved
## (or its walls changed: `had` empty).
func _measure(m: Dictionary, had: Dictionary) -> void:
	if not had.is_empty() and had.get("points") == m.points and had.has("measure"):
		m.measure = had.measure
		for k in ["_walk_cells", "_walk_secret"]:
			if had.has(k):
				m[k] = had[k]
		return
	if state == null or map_query == null or (m.points as Array).size() < 2:
		m.erase("measure")
		return
	var pts := []
	for p in m.points:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var me := Measure.ruler(map_query, state, str(m.scene), pts, str(m.owner), _legs)
	if me.has("cells"):
		m._walk_cells = me.cells
		me.erase("cells")
	else:
		m.erase("_walk_cells")
	# (the DM's walk priced by ground the players aren't shown: theirs is the distance alone)
	if bool(me.get("secret", false)):
		m._walk_secret = true
	else:
		m.erase("_walk_secret")
	me.erase("secret")
	m.measure = me


func _on_applied(ev: Dictionary, _inv: Dictionary) -> void:
	var t := str(ev.get("t", ""))
	match t:
		"token.set":
			var ch: Variant = ev.get("changes", {})
			if ch is Dictionary and (ch as Dictionary).has("pos"):
				for id in marks:
					var m: Dictionary = marks[id]
					if str(m.get("token", "")) == str(ev.get("id", "")) and str(m.scene) == str(ev.get("scene", "")):
						_anchor(m)
						changed.emit(str(id))
		"token.remove":
			for id in marks.keys():
				if str(marks[id].get("token", "")) == str(ev.get("id", "")) and str(marks[id].scene) == str(ev.get("scene", "")):
					_drop(str(id))
		"scene.remove":
			for id in marks.keys():
				if str(marks[id].scene) == str(ev.get("id", "")):
					_drop(str(id))
		"element.set", "fog.set", "fog.reveal", "fog.hide", "scene.set", "region.add", "region.remove", "region.set":
			# the walls, the ground's price or what is known changed: the rulers there are measured again
			_legs.clear()
			var sid := str(ev.get("scene", ev.get("id", "")))
			for id in marks:
				var m: Dictionary = marks[id]
				if str(m.kind) == "ruler" and str(m.scene) == sid:
					var before: Variant = m.get("measure")
					_measure(m, {})
					if m.get("measure") != before:
						changed.emit(str(id))
