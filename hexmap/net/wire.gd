class_name Wire
extends RefCounted
## How a screen's view, its scene and the DM's state travel (protocol 4),
## so that a phone is not sent the same thing again and again.
##
## **Schemas once.** A view schema — a sheet's, the status view's, an entry's
## card, the DM's party view: the trees a ruleset registers, a sheet's some
## 290 KB — reaches each connection once. In its place a record carries
## `schema_ref`, "<plugin>/<kind>@<hash of its contents>", and the message that
## first needs it carries it in `schemas` ({id: schema}). A ruleset that
## registers a schema again with other contents (its sheets built again for a
## table setting) gives it another id, and every screen is sent it once more.
## A screen says which it holds when it joins (`join {have: [ids]}`), so a
## reconnect is sent none of those again.
##
## **Then what changed.** A view, a scene and a DM state are each sent whole
## the first time on a connection (`view`, `state`, a scene's own fields, with
## `n`: its number), and after that as a patch on the one before (`{t, patch,
## base, n}`: `base` the `n` it changes). A screen that can't apply one (a
## base it doesn't hold, a schema it lacks) asks for the whole again: `need
## {kind: view | dm | scene}`.
##
## A patch node:
##   {v: value}                         the value, whole
##   {d: {key: node}, x: [keys]}        a dictionary: those keys changed (or new),
##                                      those gone, every other key as it was
##   {k: n, i: {index: node}, a: [items], s: m}
##                                      an array: its first n items (those under
##                                      i changed), then the items of a, then its
##                                      last m items
## An empty node ({}) is no change. The projection is what it was — what each
## viewer may see is decided before any of this (Views.project) — only less of
## it travels again.

const KINDS := ["view", "dm", "scene"]
## The keys of a message that are the wire's own, not a scene's fields.
const OWN := ["t", "n", "base", "patch", "schemas"]
## The most schema ids a screen may say it holds.
const MAX_HAVE := 512

## Schema ids worked out before: hash(schema) -> [[schema, id], …] (the same
## schema, unchanged since, is not written out and hashed again). A few rule
## loads' worth: the rest let go.
static var _ids: Dictionary = {}
const IDS_KEPT := 32


## The id a schema travels by: whose it is, what it is, and its contents' hash.
static func schema_id(plugin: String, kind: String, schema: Variant) -> String:
	var h := hash(schema)
	var known: Array = _ids.get(h, [])
	for e in known:
		if is_same(e[0], schema):
			return str(e[1])
	var id := "%s/%s@%s" % [plugin, kind, JSON.stringify(schema).sha1_text().left(16)]
	if _ids.size() >= IDS_KEPT:
		_ids.clear()
		known = []
	known.append([schema, id])
	_ids[h] = known
	return id


## The records of a body that hold a schema (`schema`, or `schema_ref` on the
## wire): [[record, kind], …] — a view's sheets, status views and cards, the DM's
## party views and cards.
static func schema_records(kind: String, body: Dictionary) -> Array:
	var out := []
	match kind:
		"view":
			var actors: Variant = body.get("actors")
			if actors is Dictionary:
				for aid in actors:
					var a: Variant = actors[aid]
					if a is Dictionary and a.get("sheets") is Array:
						for sh in a.sheets:
							if sh is Dictionary:
								out.append([sh, "sheet"])
			if body.get("status") is Array:
				for st in body.status:
					if st is Dictionary:
						out.append([st, "status"])
			_cards(body.get("cards"), out)
		"dm":
			if body.get("party_views") is Array:
				for pv in body.party_views:
					if pv is Dictionary:
						out.append([pv, "party"])
			_cards(body.get("cards"), out)
	return out


static func _cards(cards: Variant, out: Array) -> void:
	if cards is Dictionary:
		for coll in cards:
			if cards[coll] is Dictionary:
				out.append([cards[coll], "entry:%s" % coll])


## A message's body: a view's projection, the DM's state, a scene's fields.
static func body_of(msg: Dictionary) -> Dictionary:
	match str(msg.get("t", "")):
		"view":
			return msg.view if msg.get("view") is Dictionary else {}
		"dm":
			return msg.state if msg.get("state") is Dictionary else {}
	var out := msg.duplicate()
	for k in OWN:
		out.erase(k)
	return out


## A body as its whole message reads (the shape protocol 3 sent it in).
static func whole(kind: String, body: Dictionary) -> Dictionary:
	match kind:
		"view":
			return {"t": "view", "view": body}
		"dm":
			return {"t": "dm", "state": body}
	var out := body.duplicate()
	out.t = kind
	return out


# ------------------------------------------------------------------ patches --

## What changed from `old` to `new`, as a patch node ({} for nothing).
static func diff(old: Variant, new: Variant) -> Dictionary:
	if typeof(old) == typeof(new) and old == new:
		return {}
	if old is Dictionary and new is Dictionary:
		var d := {}
		var x := []
		for k in new:
			if not (old as Dictionary).has(k):
				d[str(k)] = {"v": new[k]}
				continue
			var sub := diff(old[k], new[k])
			if not sub.is_empty():
				d[str(k)] = sub
		for k in old:
			if not (new as Dictionary).has(k):
				x.append(str(k))
		var out := {}
		if not d.is_empty():
			out.d = d
		if not x.is_empty():
			out.x = x
		return out
	if old is Array and new is Array:
		return _diff_array(old, new)
	return {"v": new}


static func _diff_array(a: Array, b: Array) -> Dictionary:
	var m := mini(a.size(), b.size())
	var p := 0
	while p < m and typeof(a[p]) == typeof(b[p]) and a[p] == b[p]:
		p += 1
	if a.size() == b.size():
		# the same length: the items that changed, each by what changed in it
		var items := {}
		for idx in range(p, m):
			var sub := diff(a[idx], b[idx])
			if not sub.is_empty():
				items[str(idx)] = sub
		if items.is_empty():
			return {}
		var out := {"k": m, "i": items}
		# numbers, or arrays of them (a sight polygon's points, all moved a little):
		# whole when that is shorter
		if not b.all(func(x: Variant) -> bool: return x is Dictionary) and JSON.stringify(out).length() >= JSON.stringify(b).length():
			return {"v": b}
		return out
	# longer or shorter: what both begin with and end with kept, the middle sent
	# (the log: the new lines after the old)
	var s := 0
	while s < m - p and typeof(a[a.size() - 1 - s]) == typeof(b[b.size() - 1 - s]) and a[a.size() - 1 - s] == b[b.size() - 1 - s]:
		s += 1
	var out := {"k": p}
	if b.size() - s > p:
		out.a = b.slice(p, b.size() - s)
	if s > 0:
		out.s = s
	return out


# ------------------------------------------------------------- the sender --

## One connection's side, on the host: the schemas it holds, and the last of
## each view, scene and DM state it was sent, to send the next as a patch.
class Peer:
	var held: Dictionary = {}
	## How many schemas this connection has been sent.
	var schemas_sent := 0
	var _last: Dictionary = {}   # kind -> the body last sent (a copy: nothing changes it after)
	var _n: Dictionary = {}      # kind -> its number

	## The message for `body` of `kind` (view, dm, scene): its schemas by id
	## (those this connection lacks carried along), whole the first time, then
	## what changed. `body` is the caller's own: its records are changed.
	func pack(kind: String, body: Dictionary) -> Dictionary:
		var schemas := {}
		for rec in Wire.schema_records(kind, body):
			var r: Dictionary = rec[0]
			if not (r.get("schema") is Dictionary):
				continue
			var id := Wire.schema_id(str(r.get("plugin", "")), str(rec[1]), r.schema)
			if not held.has(id):
				held[id] = true
				schemas[id] = r.schema
				schemas_sent += 1
			r.erase("schema")
			r.schema_ref = id
		var n := int(_n.get(kind, 0)) + 1
		_n[kind] = n
		var msg: Dictionary
		if _last.has(kind):
			msg = {"t": kind, "patch": Wire.diff(_last[kind], body), "base": n - 1, "n": n}
		else:
			msg = Wire.whole(kind, body)
			msg.n = n
		if not schemas.is_empty():
			msg.schemas = schemas
		_last[kind] = JsonDoc.deep(body)
		return msg

	## The screen joined (again): what it says it holds is all it holds, and
	## everything goes whole once more.
	func joined(have: Variant) -> void:
		_last.clear()
		held.clear()
		if have is Array:
			for id in (have as Array).slice(0, Wire.MAX_HAVE):
				if id is String and (id as String).length() <= 200:
					held[id] = true

	## The screen asked for `kind` whole (it couldn't read a patch, or lacks a
	## schema): the next goes whole, a view's or a DM state's with every schema.
	func forget(kind: String) -> void:
		_last.erase(kind)
		if kind != "scene":
			held.clear()


# ------------------------------------------------------------- the reader --

## A screen's side: the schemas it holds (by id) and the last of each view,
## scene and DM state, to read the next by. A Godot client's; the web
## clients' is web/src/lib/wire.ts.
class Reader:
	## id -> schema. A NetSession's outlive it (NetSession.schemas_kept), for the next connection.
	var schemas: Dictionary = {}
	var _bodies: Dictionary = {}   # kind -> the last body, its schemas by ref
	var _n: Dictionary = {}
	var _asked: Dictionary = {}    # kind -> asked for it whole, not come yet
	var _bad := false

	func _init(p_schemas: Variant = null) -> void:
		if p_schemas is Dictionary:
			schemas = p_schemas

	## `msg` (a view, dm or scene message) as a whole one reads, in the shape
	## protocol 3 sent it, its schemas in place: {msg} — {same: true} when
	## nothing changed (nothing to draw again), or {need: true} the first time
	## one can't be read (ask for that kind whole: need {kind}), {} until the
	## whole one comes.
	func read(msg: Dictionary) -> Dictionary:
		var kind := str(msg.get("t", ""))
		if msg.get("schemas") is Dictionary:
			for id in msg.schemas:
				if msg.schemas[id] is Dictionary:
					schemas[str(id)] = msg.schemas[id]
		var body: Variant
		if msg.has("patch"):
			if not _bodies.has(kind) or int(msg.get("base", -1)) != int(_n.get(kind, -2)):
				return _stale(kind)
			if msg.patch is Dictionary and (msg.patch as Dictionary).is_empty():
				_n[kind] = int(msg.get("n", 0))
				return {"same": true}
			_bad = false
			body = _apply(_bodies[kind], msg.patch)
			if _bad or not (body is Dictionary):
				return _stale(kind)
		else:
			# (a copy: the patches that follow change it in place)
			body = JsonDoc.deep(Wire.body_of(msg))
		_bodies[kind] = body
		_n[kind] = int(msg.get("n", 0))
		var out := Wire.whole(kind, JsonDoc.deep(body))
		for rec in Wire.schema_records(kind, Wire.body_of(out)):
			var r: Dictionary = rec[0]
			if r.has("schema_ref"):
				var s: Variant = schemas.get(str(r.schema_ref))
				if not (s is Dictionary):
					return _stale(kind)
				r.schema = s
				r.erase("schema_ref")
		_asked.erase(kind)
		return {"msg": out}

	## The schema ids the last view and DM state use (what is worth keeping).
	func in_use() -> Array:
		var out := []
		for kind in _bodies:
			for rec in Wire.schema_records(str(kind), _bodies[kind]):
				var id := str(rec[0].get("schema_ref", ""))
				if id != "" and not out.has(id):
					out.append(id)
		return out

	func _stale(kind: String) -> Dictionary:
		_bodies.erase(kind)
		_n.erase(kind)
		if _asked.has(kind):
			return {}
		_asked[kind] = true
		return {"need": true}

	func _apply(old: Variant, node: Variant) -> Variant:
		if not (node is Dictionary):
			_bad = true
			return old
		if node.has("v"):
			return node.v
		if node.has("k"):
			if not (old is Array) or not _count(node.k) or not _count(node.get("s", 0)):
				_bad = true
				return old
			var src: Array = old
			var k := int(node.k)
			var s := int(node.get("s", 0))
			if k + s > src.size():
				_bad = true
				return old
			var out := src.slice(0, k)
			var items: Variant = node.get("i", {})
			if items is Dictionary:
				for key in items:
					var idx := int(str(key)) if str(key).is_valid_int() else -1
					if idx < 0 or idx >= k:
						_bad = true
						return old
					out[idx] = _apply(out[idx], items[key])
			if node.get("a") is Array:
				out.append_array(node.a)
			if s > 0:
				out.append_array(src.slice(src.size() - s))
			return out
		if not node.has("d") and not node.has("x"):
			return old   # ({}: no change)
		if not (old is Dictionary):
			_bad = true
			return old
		var d: Variant = node.get("d", {})
		if d is Dictionary:
			for key in d:
				old[str(key)] = _apply(old.get(str(key)), d[key])
		var x: Variant = node.get("x", [])
		if x is Array:
			for key in x:
				(old as Dictionary).erase(str(key))
		return old

	static func _count(v: Variant) -> bool:
		return (v is int or v is float) and float(v) >= 0.0 and float(v) == floorf(float(v))
