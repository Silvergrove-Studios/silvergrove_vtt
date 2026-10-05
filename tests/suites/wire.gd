extends TestCase
## How a screen's view, its scene and the DM's state travel (Wire, protocol
## 4): each view schema once per connection, by an id made from its contents
## and sent again when a ruleset registers it anew; after the first of each,
## only what changed. Patches made and read back (and fuzzed); the schemas'
## ids; a phone, a display and the DM's screen over a real socket, through
## rules changes, a ruleset loaded again and reconnects; a Godot player's
## schemas kept for the next connection.

const WebSuite := preload("res://tests/suites/web.gd")
const ANA := "pl_fe0170c1"
const BEN := "pl_393eb25a"
const PLUGIN := {"id": "t.views", "version": "1", "api": 1, "name": "Views", "capabilities": ["state"]}


## `old` then `new` through a sender and a reader, as a screen gets them: the
## value the reader makes of the patch, and the patch as it went.
func _through(old: Variant, new: Variant) -> Array:
	var peer := Wire.Peer.new()
	var reader := Wire.Reader.new()
	var first: Variant = JSON.parse_string(JSON.stringify(peer.pack("scene", {"x": JsonDoc.deep(old)})))
	reader.read(first)
	var msg: Dictionary = JSON.parse_string(JSON.stringify(peer.pack("scene", {"x": JsonDoc.deep(new)})))
	var got := reader.read(msg)
	var node: Variant = msg.patch.get("d", {}).get("x", {}) if msg.get("patch") is Dictionary else null
	if bool(got.get("same", false)):
		# (nothing changed: what the screen had, which was the first)
		return [first.get("x"), node]
	return [got.get("msg", {}).get("x") if got.get("msg") is Dictionary else "<unread>", node]


func _same(a: Variant, b: Variant) -> bool:
	return JsonDoc.same(a, b)


func test_wire_patches() -> void:
	check(Wire.diff({"a": 1, "b": [1, 2]}, {"a": 1, "b": [1, 2]}).is_empty(), "nothing changed: an empty patch")
	var old := {"a": 1, "b": {"c": 2, "d": 3}, "gone": true}
	var new := {"a": 1, "b": {"c": 4, "d": 3}, "e": 5}
	var p := Wire.diff(old, new)
	check(p == {"d": {"b": {"d": {"c": {"v": 4}}}, "e": {"v": 5}}, "x": ["gone"]}, "a dictionary: what changed in it, what's new, what's gone: %s" % [p])
	var r := _through(old, new)
	check(_same(r[0], new), "read back: %s" % [r[0]])
	# the log: the lines after those the screen has
	var log := [{"id": "l1", "text": "one"}, {"id": "l2", "text": "two"}]
	var longer := log.duplicate(true)
	longer.append_array([{"id": "l3", "text": "three"}, {"id": "l4", "text": "four"}])
	r = _through(log, longer)
	check(_same(r[0], longer) and _same(r[1], {"k": 2, "a": [{"id": "l3", "text": "three"}, {"id": "l4", "text": "four"}]}), "the log: the new lines after the old (%s)" % [r[1]])
	# a line changed where it is (the DM's ruling on a roll)
	var ruled := log.duplicate(true)
	ruled[1].ruled = "a miss"
	r = _through(log, ruled)
	check(_same(r[0], ruled) and _same(r[1], {"k": 2, "i": {"1": {"d": {"ruled": {"v": "a miss"}}}}}), "a line changed in place: that line's change (%s)" % [r[1]])
	# taken out of the middle, put into the middle, cut short, emptied
	var abcd := ["a", "b", "c", "d"]
	r = _through(abcd, ["a", "c", "d"])
	check(_same(r[0], ["a", "c", "d"]) and _same(r[1], {"k": 1, "s": 2}), "one taken out of the middle: the ends kept (%s)" % [r[1]])
	r = _through(["a", "c"], ["a", "b", "c"])
	check(_same(r[0], ["a", "b", "c"]) and _same(r[1], {"k": 1, "a": ["b"], "s": 1}), "one put into the middle (%s)" % [r[1]])
	r = _through(abcd, ["a", "b"])
	check(_same(r[0], ["a", "b"]), "cut short")
	r = _through(abcd, [])
	check(_same(r[0], []) and _same(r[1], {"k": 0}), "emptied (%s)" % [r[1]])
	r = _through([], abcd)
	check(_same(r[0], abcd), "filled")
	# what something is changes; nulls; numbers
	check(_same(_through({"y": [1]}, {"y": {"z": 1}})[0], {"y": {"z": 1}}), "an array that becomes a dictionary")
	check(_same(_through({"y": null}, {"y": 1})[0], {"y": 1}) and _same(_through({"y": 1}, {"y": null})[0], {"y": null}), "null and back")
	check(_same(_through({"n": 1}, {"n": 1.5})[0], {"n": 1.5}) and _same(_through(3, "three")[0], "three"), "a number changed; a number that becomes a string")
	# a sight polygon whose every point moved: sent whole, shorter than point by point
	var poly := []
	var moved := []
	for i in 60:
		poly.append([float(i) * 0.37, float(i) * 0.91])
		moved.append([float(i) * 0.37 + 0.11, float(i) * 0.91 - 0.07])
	r = _through({"visible": [poly]}, {"visible": [moved]})
	check(_same(r[0], {"visible": [moved]}) and (r[1] as Dictionary).has("d") and (r[1].d.visible as Dictionary).has("v"), "a polygon whose points all moved goes whole: %s" % [JSON.stringify(r[1]).left(60)])
	# random documents, randomly changed: always read back as they are
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var bad := 0
	for i in 300:
		var a: Variant = _random_tree(rng, 0)
		var b: Variant = _mutate(rng, JsonDoc.deep(a), 0)
		var got: Array = _through(a, b)
		if not _same(got[0], b):
			bad += 1
			if bad == 1:
				say.call("  first mismatch: %s → %s, read %s (patch %s)" % [JSON.stringify(a), JSON.stringify(b), JSON.stringify(got[0]), JSON.stringify(got[1])])
	check(bad == 0, "300 random documents changed at random: every one read back as it is (%d wrong)" % bad)


func _random_tree(rng: RandomNumberGenerator, depth: int) -> Variant:
	var pick := rng.randi_range(0, 9 if depth < 4 else 4)
	match pick:
		0: return rng.randi_range(-5, 50)
		1: return rng.randf_range(-10.0, 10.0)
		2: return ["fire", "cold", "", "Goblin 2", "a ruling"][rng.randi_range(0, 4)]
		3: return null
		4: return rng.randf() < 0.5
		5, 6, 7:
			var d := {}
			for j in rng.randi_range(0, 5):
				d["k%d" % rng.randi_range(0, 7)] = _random_tree(rng, depth + 1)
			return d
	var arr := []
	for j in rng.randi_range(0, 6):
		arr.append(_random_tree(rng, depth + 1))
	return arr


func _mutate(rng: RandomNumberGenerator, v: Variant, depth: int) -> Variant:
	if rng.randf() < 0.15 or depth > 5:
		return _random_tree(rng, depth)
	if v is Dictionary:
		var d: Dictionary = v
		for k in d.keys():
			var roll := rng.randf()
			if roll < 0.15:
				d.erase(k)
			elif roll < 0.5:
				d[k] = _mutate(rng, d[k], depth + 1)
		if rng.randf() < 0.3:
			d["n%d" % rng.randi_range(0, 3)] = _random_tree(rng, depth + 1)
		return d
	if v is Array:
		var arr: Array = v
		match rng.randi_range(0, 4):
			0:
				arr.append(_random_tree(rng, depth + 1))
			1:
				if not arr.is_empty():
					arr.remove_at(rng.randi_range(0, arr.size() - 1))
			2:
				arr.insert(rng.randi_range(0, arr.size()), _random_tree(rng, depth + 1))
			_:
				for j in arr.size():
					if rng.randf() < 0.4:
						arr[j] = _mutate(rng, arr[j], depth + 1)
		return arr
	return _random_tree(rng, depth)


## A view as Views.project makes one, with a sheet for each actor named, the
## status view and a card: the schemas the very objects given.
func _view(sheet: Dictionary, status: Dictionary, card: Dictionary, actors: Array, hp := 10) -> Dictionary:
	var out := {"actors": {}, "status": [{"plugin": "t.views", "schema": status, "data": {"round": hp}}], "cards": {"spells": {"plugin": "t.views", "schema": card}}, "log": []}
	for aid in actors:
		out.actors[aid] = {"id": aid, "name": aid, "sheets": [{"plugin": "t.views", "schema": sheet, "data": {"hp": hp}}]}
	return out


func test_wire_schemas() -> void:
	var sheet := {"type": "column", "children": [{"type": "text", "text": "Hit points"}, {"type": "number", "bind": "/hp"}]}
	var status := {"type": "text", "expr": "'Round ' .. @round"}
	var card := {"type": "text", "bind": "/entry/name"}
	# an id is the contents': the same tree is the same id, another is another
	var id := Wire.schema_id("t.views", "sheet", sheet)
	check(id.begins_with("t.views/sheet@") and id.length() == "t.views/sheet@".length() + 16, "an id says whose and what, and its contents' hash: %s" % id)
	check(Wire.schema_id("t.views", "sheet", sheet.duplicate(true)) == id, "the same tree registered again (a ruleset loaded again): the same id")
	var other: Dictionary = sheet.duplicate(true)
	other.children.append({"type": "text", "text": "By hand"})
	check(Wire.schema_id("t.views", "sheet", other) != id, "a sheet built otherwise (a table setting): another id")
	var changed: Dictionary = sheet.duplicate(true)
	check(Wire.schema_id("t.views", "sheet", changed) == id, "(a copy, the same id)")
	changed.children[0].text = "HP"
	check(Wire.schema_id("t.views", "sheet", changed) != id, "a tree changed in place since its id was worked out: another id")
	# a DM's view: two actors with the same sheet — it goes once
	var peer := Wire.Peer.new()
	var reader := Wire.Reader.new()
	var wire := func(msg: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(msg))
	var v1 := _view(sheet, status, card, ["a_ana", "a_ben"])
	var expect1: Dictionary = JsonDoc.deep(v1)
	var m1: Dictionary = wire.call(peer.pack("view", v1))
	check(m1.has("view") and int(m1.n) == 1 and not m1.has("patch"), "the first view goes whole")
	check((m1.schemas as Dictionary).size() == 3 and peer.schemas_sent == 3, "with its three schemas, the sheet once for both actors: %s" % [m1.schemas.keys()])
	check(str(m1.view.actors.a_ana.sheets[0].schema_ref) == id and not (m1.view.actors.a_ana.sheets[0] as Dictionary).has("schema"), "each record carries the sheet's id in its place")
	var got := reader.read(m1)
	check(_same(got.get("msg", {}).get("view"), expect1), "read back, the view is as it was made, its schemas in place")
	check(got.msg.view.actors.a_ana.sheets[0].schema is Dictionary and _same(got.msg.view.actors.a_ana.sheets[0].schema, sheet), "the sheet's schema, whole")
	# the next: what changed, no schema
	var v2 := _view(sheet, status, card, ["a_ana", "a_ben"], 7)
	var expect2: Dictionary = JsonDoc.deep(v2)
	var m2: Dictionary = wire.call(peer.pack("view", v2))
	check(m2.has("patch") and int(m2.base) == 1 and int(m2.n) == 2 and not m2.has("schemas") and not m2.has("view"), "the next view: a patch on the first, no schemas")
	check(JSON.stringify(m2).length() < 400, "and small: %d bytes" % JSON.stringify(m2).length())
	got = reader.read(m2)
	check(_same(got.get("msg", {}).get("view"), expect2), "read back as it was made")
	# nothing changed for this screen: a patch of nothing, and nothing to draw again
	var m2b: Dictionary = wire.call(peer.pack("view", _view(sheet, status, card, ["a_ana", "a_ben"], 7)))
	check(m2b.has("patch") and (m2b.patch as Dictionary).is_empty() and int(m2b.base) == 2, "the same view again: an empty patch")
	check(reader.read(m2b) == {"same": true}, "read as nothing to draw again")
	# the sheet built again otherwise: that schema once more, the others not
	var v3 := _view(other, status, card, ["a_ana", "a_ben"], 7)
	var expect3: Dictionary = JsonDoc.deep(v3)
	var m3: Dictionary = wire.call(peer.pack("view", v3))
	check(m3.has("patch") and (m3.get("schemas", {}) as Dictionary).keys() == [Wire.schema_id("t.views", "sheet", other)], "a sheet built otherwise: that one schema, once: %s" % [m3.get("schemas", {}).keys()])
	got = reader.read(m3)
	check(_same(got.get("msg", {}).get("view"), expect3), "read back with the new sheet")
	# a patch on a base the screen doesn't hold: it asks once, and is sent the whole
	var m4: Dictionary = wire.call(peer.pack("view", _view(other, status, card, ["a_ana", "a_ben"], 5)))
	var m5: Dictionary = wire.call(peer.pack("view", _view(other, status, card, ["a_ana", "a_ben"], 4)))
	check(reader.read(m5) == {"need": true}, "a patch on a base it hasn't read (one went missing): ask for it whole")
	check(reader.read(m4).is_empty(), "and nothing more said while it waits (asked once)")
	peer.forget("view")
	var m6: Dictionary = wire.call(peer.pack("view", _view(other, status, card, ["a_ana", "a_ben"], 3)))
	check(m6.has("view") and (m6.schemas as Dictionary).size() == 3, "asked: the whole, with every schema again")
	check(_same(reader.read(m6).get("msg", {}).get("view"), _view(other, status, card, ["a_ana", "a_ben"], 3)), "read again")
	# a screen joining again with what it holds: none of those again
	var again := Wire.Peer.new()
	again.joined(reader.schemas.keys())
	var m7: Dictionary = wire.call(again.pack("view", _view(other, status, card, ["a_ana"], 3)))
	check(m7.has("view") and not m7.has("schemas") and again.schemas_sent == 0, "a reconnect saying what it holds: the whole view, none of its schemas")
	check(_same(reader.read(m7).get("msg", {}).get("view"), _view(other, status, card, ["a_ana"], 3)), "read from the schemas it held")
	# a reader without the schema a view needs asks for it whole
	var fresh := Wire.Reader.new()
	check(fresh.read(m7) == {"need": true}, "a screen that lacks a schema it is told it holds: asks for the whole")
	again.joined(["x".repeat(300), 5, "ok"])
	check(again.held.keys() == ["ok"], "what a screen says it holds is taken only as ids")
	# the DM's state: its party view's schema once, its cards by the ids its view brought them by
	var dmpeer := Wire.Peer.new()
	var dmreader := Wire.Reader.new()
	var party := {"type": "column", "children": [{"type": "text", "text": "The party"}]}
	dmreader.read(wire.call(dmpeer.pack("view", _view(sheet, status, card, ["a_ana"]))))
	var dm_state := {"party_views": [{"plugin": "t.views", "schema": party, "data": {"n": 1}}], "cards": {"spells": {"plugin": "t.views", "schema": card}}, "campaign": {"name": "x"}}
	var dm_expect: Dictionary = JsonDoc.deep(dm_state)
	var dm1: Dictionary = wire.call(dmpeer.pack("dm", dm_state))
	check(dm1.has("state") and (dm1.get("schemas", {}) as Dictionary).keys() == [Wire.schema_id("t.views", "party", party)], "the DM's state: its party view's schema; its card not again (%s)" % [dm1.get("schemas", {}).keys()])
	check(str(dm1.state.cards.spells.schema_ref) == Wire.schema_id("t.views", "entry:spells", card), "its card by the id the view brought it by")
	check(_same(dmreader.read(dm1).get("msg", {}).get("state"), dm_expect), "read back whole, its schemas in place")


## A table hosting a ruleset with a sheet, a status view and a card, two
## players with characters, and the DM's screen's state from the rules.
func _table() -> Dictionary:
	var web := WebSuite.new()
	var st := web._chapel_state()
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	var why := plugins.load_source(PLUGIN, [["main.lua", _source(150)]])
	kernel.commit([{"t": "actor.add", "actor": {"id": "a_ana", "kind": "pc", "name": "Ana's fighter", "owner": ANA, "ext": {"t.views": {"hp": 10}}}},
		{"t": "actor.add", "actor": {"id": "a_ben", "kind": "pc", "name": "Ben's rogue", "owner": BEN, "ext": {"t.views": {"hp": 8}}}}], "Characters")
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = kernel
	host.plugins = plugins
	host.dm_token = "sesame"
	host.dm_state_source = func() -> Dictionary:
		var p: PluginHost.Plugin = host.plugins.plugins["t.views"]
		return {"party_views": [{"plugin": "t.views", "schema": p.views.party, "data": {"n": kernel.log.seq}}], "cards": EntryCard.cards_of(host.plugins), "campaign": {"name": "Chapel"}}
	return {"web": web, "st": st, "kernel": kernel, "plugins": plugins, "host": host, "why": why}


## The ruleset's views: a sheet of `rows` lines (some weight to it), a status
## line, the DM's party view, a card.
func _source(rows: int) -> String:
	return """
		local hm = hexmap
		local rows = {}
		for i = 1, %d do rows[i] = { type = "text", text = "Line " .. i .. " of the sheet, long enough to weigh something on a phone" } end
		hm.ui.register("sheet", { type = "column", children = rows })
		hm.ui.register("status", { type = "text", expr = "'Seq ' .. (@turns.round ?? 0)" })
		hm.ui.register("party", { type = "column", children = { { type = "text", text = "The party" } } })
		hm.ui.register("entry:spells", { type = "column", children = { { type = "text", bind = "/entry/name" } } })
	""" % rows


## A web screen joined to the table, holding `schemas` (what a page kept) and saying so.
func _seat(t: Dictionary, join: Dictionary, schemas: Dictionary = {}) -> WebSuite.WebClient:
	var host: HostSession = t.host
	var w := WebSuite.WebClient.new(host.port)
	if not schemas.is_empty():
		w.wire.schemas = schemas
	t.web._pump(host, [w], func() -> bool: return w.open())
	w.send({"t": "hello", "version": Protocol.VERSION, "name": "screen", "web": true})
	if not schemas.is_empty():
		join = join.duplicate()
		join.have = schemas.keys()
	# (a player's page on her phone, again: the same device, whose seat hers is)
	if str(join.get("role", "")) == "player" and not join.has("device"):
		join = join.duplicate()
		join.device = "device-of-" + str(join.get("player", join.get("name", "")))
	w.send(join)
	t.web._pump(host, [w], func() -> bool: return not w.last("view").is_empty() and not w.last("scene").is_empty())
	return w


## The schema ids a screen was sent, each time it was sent one.
func _schemas_sent(w: WebSuite.WebClient) -> Array:
	var out := []
	for r in w.raw:
		out.append_array((r.msg.get("schemas", {}) as Dictionary).keys())
	return out


func _views_raw(w: WebSuite.WebClient) -> Array:
	return w.raw.filter(func(r: Dictionary) -> bool: return str(r.msg.get("t", "")) == "view")


func test_wire_over_the_host() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var t := _table()
	check(str(t.why) == "", "the ruleset loads: %s" % t.why)
	var host: HostSession = t.host
	var kernel: RulesKernel = t.kernel
	var web: WebSuite = t.web
	check(host.start(0, false, 0) == OK, "hosting")
	var views: Dictionary = (t.plugins as PluginHost).plugins["t.views"].views
	var sheet_id := Wire.schema_id("t.views", "sheet", views.sheet)
	var ana := _seat(t, {"t": "join", "role": "player", "name": "Ana"})
	var tv := _seat(t, {"t": "join", "role": "display"})
	var dm := _seat(t, {"t": "join", "role": "dm", "token": "sesame"})
	var all := [ana, tv, dm]
	web._pump(host, all, func() -> bool: return not dm.last("dm").is_empty())
	# Ana's phone: the schemas with her first view, then never again
	var first: Dictionary = _views_raw(ana)[0]
	check(first.msg.has("view") and (first.msg.get("schemas", {}) as Dictionary).has(sheet_id) and (first.msg.schemas as Dictionary).size() == 3,
		"Ana's first view: whole, with the sheet, status and card schemas (%d KB)" % (int(first.bytes) / 1024))
	var mine := func(w: WebSuite.WebClient, pid: String, role: String) -> bool:
		return _same(w.last("view").view, host.projection({"player": pid, "role": role}))
	check(mine.call(ana, ANA, "player"), "read back, her view is the table's projection for her, as it was")
	check(_same(ana.last("view").view.actors.a_ana.sheets[0].schema, views.sheet), "her sheet's schema in its place, whole")
	for i in 8:
		kernel.commit([{"t": "log.add", "entry": {"id": "n_%d" % i, "kind": "note", "text": "Note %d" % i, "audience": "all"}}], "Note")
		web._pump(host, all, func() -> bool: return _views_raw(ana).size() >= 2 + i and _views_raw(dm).size() >= 2 + i)
	web._pump(host, all, func() -> bool: return false, 200)
	var later := _views_raw(ana).slice(1)
	check(later.size() >= 8 and later.all(func(r: Dictionary) -> bool: return r.msg.has("patch") and not r.msg.has("schemas") and not r.msg.has("view")), "eight changes later: %d views, each a patch with no schema" % later.size())
	var biggest := 0
	for r in later:
		biggest = maxi(biggest, int(r.bytes))
	check(biggest < 1500 and int(first.bytes) > 10000, "each under 1.5 KB (the biggest %d bytes), where the first was %d KB" % [biggest, int(first.bytes) / 1024])
	check(_schemas_sent(ana).count(sheet_id) == 1, "the sheet's schema reached her phone once")
	check(mine.call(ana, ANA, "player"), "and her view is still the table's projection for her")
	# the DM's screen: the sheet once though both characters have it; the party view by the status view's id
	check(_schemas_sent(dm).count(sheet_id) == 1 and dm.last("view").view.actors.a_ben.sheets[0].schema is Dictionary, "the DM's screen: the sheet once for both characters")
	check(mine.call(dm, "", "dm"), "the DM's view read back as the table's")
	var dm_schemas := []
	for r in dm.raw.filter(func(r: Dictionary) -> bool: return str(r.msg.get("t", "")) == "dm"):
		dm_schemas.append_array((r.msg.get("schemas", {}) as Dictionary).keys())
	check(dm_schemas == [Wire.schema_id("t.views", "party", views.party)], "its state: the party view's schema once, its card by the id its view brought it by: %s" % [dm_schemas])
	check(_same(dm.last("dm").state.party_views[0].schema, views.party) and _same(dm.last("dm").state.cards.spells.schema, views["entry:spells"]), "the DM's state read back with its schemas in place")
	# the display: as before, no sheet — the schemas follow what each may see
	check(not _schemas_sent(tv).has(sheet_id) and tv.last("view").view.actors.a_ana.sheets.is_empty(), "the display is never sent the sheet: it has none")
	# the ruleset loaded again with its sheet built otherwise (a table setting): the new sheet once, to those it is for
	var plugins: PluginHost = t.plugins
	plugins.unload("t.views")
	check(plugins.load_source(PLUGIN, [["main.lua", _source(151)]]) == "", "the ruleset loaded again, its sheet a line longer")
	host.refresh_views()
	var new_id := Wire.schema_id("t.views", "sheet", plugins.plugins["t.views"].views.sheet)
	check(new_id != sheet_id, "another sheet, another id")
	check(web._pump(host, all, func() -> bool: return _schemas_sent(ana).has(new_id) and _schemas_sent(dm).has(new_id)), "the new sheet reaches Ana's phone and the DM's screen")
	web._pump(host, all, func() -> bool: return false, 200)
	check(_schemas_sent(ana).count(new_id) == 1 and _schemas_sent(ana).size() == 4 and _schemas_sent(dm).count(new_id) == 1, "once each, and nothing else again (Ana's: %s)" % [_schemas_sent(ana)])
	check(ana.last("view").view.actors.a_ana.sheets[0].schema.children.size() == 151 and mine.call(ana, ANA, "player"), "her sheet is the new one")
	check(not _schemas_sent(tv).has(new_id), "the display: still none")
	# Ana's phone drops and comes back, saying what it holds: none of it again
	var back := _seat(t, {"t": "join", "role": "player", "name": "Ana"}, ana.wire.schemas)
	web._pump(host, [back], func() -> bool: return mine.call(back, ANA, "player"))
	check(_views_raw(back)[0].msg.has("view") and _schemas_sent(back).is_empty(), "a reconnect that says what it holds: the whole view (%d KB), no schema" % (int(_views_raw(back)[0].bytes) / 1024))
	check(mine.call(back, ANA, "player"), "its view read from the schemas it kept")
	# a new page (nothing held): every schema it needs
	var page := _seat(t, {"t": "join", "role": "player", "name": "Ana"})
	check(_schemas_sent(page).size() == 3 and _schemas_sent(page).has(new_id) and mine.call(page, ANA, "player"), "a page with nothing kept: its three schemas")
	# a screen that couldn't read a patch asks for the whole, and has it
	page.wire._n["view"] = -7
	kernel.commit([{"t": "log.add", "entry": {"id": "n_x", "kind": "note", "text": "After", "audience": "all"}}], "Note")
	check(web._pump(host, [page], func() -> bool: return mine.call(page, ANA, "player") and page.last("view").view.log.any(func(e: Dictionary) -> bool: return str(e.get("text", "")) == "After")),
		"a patch it couldn't read: it asked, and the whole came (its view the table's again)")
	check(_views_raw(page).back().msg.has("view") and (_views_raw(page).back().msg.get("schemas", {}) as Dictionary).size() == 3, "whole, with its schemas")
	host.stop()


func test_wire_godot_player_keeps_schemas() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var t := _table()
	var host: HostSession = t.host
	check(host.start(0, false, 0) == OK, "hosting")
	NetSession.schemas_kept.clear()
	var pump := func(clients: Array, done: Callable) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 4000:
			host.poll(0.016)
			for c in clients:
				(c as NetSession).poll()
			if done.call():
				return true
			OS.delay_msec(5)
		return false
	var views: Dictionary = (t.plugins as PluginHost).plugins["t.views"].views
	var packs := PackLibrary.new()
	packs.reload()
	var phone := NetSession.new("127.0.0.1", host.port, packs, "phone")
	phone.cache_dir = "user://packs_wire_test"
	phone.connect_to_host()
	check(pump.call([phone], func() -> bool: return phone.state != null), "welcomed")
	phone.join(ANA)
	check(pump.call([phone], func() -> bool: return not phone.view.is_empty()), "joined; a view came")
	check(phone.view.actors.a_ana.sheets[0].schema is Dictionary and _same(phone.view.actors.a_ana.sheets[0].schema, views.sheet), "the Godot client's view has her sheet's schema in its place")
	check(_same(phone.view, host.projection({"player": ANA, "role": "player"})), "its view is the table's projection for her")
	check(NetSession.schemas_kept.size() == 3, "the app keeps the three schemas: %s" % [NetSession.schemas_kept.keys()])
	(t.kernel as RulesKernel).commit([{"t": "log.add", "entry": {"id": "n_1", "kind": "note", "text": "On the phone", "audience": "all"}}], "Note")
	check(pump.call([phone], func() -> bool: return phone.view.log.any(func(e: Dictionary) -> bool: return str(e.get("text", "")) == "On the phone")), "a change reaches it as a patch, read")
	check(_same(phone.view, host.projection({"player": ANA, "role": "player"})), "and its view is the table's still")
	var sent_first := 0
	for c in host._clients:
		sent_first += (c.wire as Wire.Peer).schemas_sent
	check(sent_first == 3, "the table sent it three schemas in all: %d" % sent_first)
	# the app joins again (a new connection): it says what it kept, and is sent none of it
	phone.leave()
	var again := NetSession.new("127.0.0.1", host.port, packs, "phone again")
	again.cache_dir = "user://packs_wire_test"
	again.connect_to_host()
	check(pump.call([again], func() -> bool: return again.state != null), "welcomed again")
	again.join(ANA)
	check(pump.call([again], func() -> bool: return not again.view.is_empty()), "a view came")
	var peer: Wire.Peer = host._clients.back().wire
	check(peer.schemas_sent == 0 and peer.held.size() == 3, "the table sent the new connection no schema: it said it held all three")
	check(_same(again.view.actors.a_ana.sheets[0].schema, views.sheet) and _same(again.view, host.projection({"player": ANA, "role": "player"})), "its sheet read from what the app kept")
	again.leave()
	host.stop()
	NetSession.schemas_kept.clear()
	PluginHost._rm_rf("user://packs_wire_test")
