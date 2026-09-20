extends TestCase
## Fuzz: random event logs against the invariants.


## Random but valid event sequences on the example encounter. Two things
## must hold whatever happens: undoing every inverse restores the start
## byte for byte, and a second state fed only the applied events (what a
## Player receives) ends up identical to the first.
func test_event_log_fuzz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260919
	var e := Encounter.load_file(example("chapel_ambush.encounter"))
	var st := EncounterState.new(e)
	st.resolve_maps()
	var mirror := EncounterState.new(Encounter.from_json(e.to_json()))
	for id in st.maps:
		mirror.attach_map(st.maps[id])
	var log := []
	st.applied.connect(func(ev: Dictionary, _inv: Dictionary) -> void: log.append(JsonDoc.deep(ev)))
	var start := e.to_json()
	var inverses := []
	var kinds := {}
	var rejected := 0
	for i in 400:
		var ev := _random_event(rng, st)
		if ev.is_empty():
			continue
		var why := st.validate(ev)
		if why != "":
			rejected += 1
			continue
		var inv := st.apply(ev)
		check(not inv.is_empty(), "event %d (%s) applied: %s" % [i, ev.t, ev])
		inverses.append(inv)
		kinds[ev.t] = int(kinds.get(ev.t, 0)) + 1
	check(inverses.size() > 250, "applied %d events (%d rejected by validate)" % [inverses.size(), rejected])
	check(kinds.size() >= 10, "covered %d event kinds: %s" % [kinds.size(), kinds.keys()])
	# Replicate the log.
	for ev in log:
		check(mirror.validate(ev) == "", "a mirror accepts every applied event (%s)" % [ev.t])
		mirror.apply(ev)
	check(JsonDoc.sans_modified(mirror.encounter.to_json()) == JsonDoc.sans_modified(st.encounter.to_json()), "a state fed the applied events matches the original")
	# Undo everything.
	for k in range(inverses.size() - 1, -1, -1):
		st.apply(inverses[k])
	check(JsonDoc.sans_modified(st.encounter.to_json()) == JsonDoc.sans_modified(start), "undoing every inverse restores the start byte for byte (bar the modified stamp)")


func _random_event(rng: RandomNumberGenerator, st: EncounterState) -> Dictionary:
	var e := st.encounter
	if e.scenes.is_empty():
		return {}
	var sc: Dictionary = e.scenes[rng.randi_range(0, e.scenes.size() - 1)]
	var sid := str(sc.id)
	var toks: Array = st.tokens(sid)
	var lvl := st.level_for(sid)
	var pick := func(arr: Array) -> Dictionary:
		return arr[rng.randi_range(0, arr.size() - 1)] if not arr.is_empty() else {}
	match rng.randi_range(0, 13):
		0:
			return {"t": "token.add", "scene": sid, "token": Encounter.new_token("Fuzz %d" % rng.randi_range(1, 99), Vector2(rng.randf_range(0, 20), rng.randf_range(0, 14)), {"hidden": rng.randf() < 0.5})}
		1:
			var tk: Dictionary = pick.call(toks)
			return {"t": "token.remove", "scene": sid, "id": str(tk.id)} if not tk.is_empty() else {}
		2, 3:
			var tk: Dictionary = pick.call(toks)
			if tk.is_empty():
				return {}
			var changes := {}
			match rng.randi_range(0, 4):
				0: changes = {"pos": [snappedf(rng.randf_range(0, 20), 0.001), snappedf(rng.randf_range(0, 14), 0.001)]}
				1: changes = {"hidden": rng.randf() < 0.5}
				2: changes = {"owner": str(e.players[rng.randi_range(0, e.players.size() - 1)].id) if not e.players.is_empty() and rng.randf() < 0.7 else null}
				3: changes = {"tags": ["a", "b"] if rng.randf() < 0.5 else [], "size": rng.randi_range(1, 3)}
				4: changes = {"light": {"bright": 1, "dim": 2, "color": "#fff"} if rng.randf() < 0.5 else null}
			return {"t": "token.set", "scene": sid, "id": str(tk.id), "changes": changes}
		4:
			var w: Dictionary = pick.call(lvl.get("walls", []))
			if w.is_empty():
				return {}
			return {"t": "element.set", "scene": sid, "ref": "walls:" + str(w.id), "changes": {"state": ["open", "closed", "locked"][rng.randi_range(0, 2)] if rng.randf() < 0.8 else null}}
		5:
			var l: Dictionary = pick.call(lvl.get("lights", []))
			if l.is_empty():
				return {}
			return {"t": "element.set", "scene": sid, "ref": "lights:" + str(l.id), "changes": {"on": rng.randf() < 0.5} if rng.randf() < 0.8 else {"on": null}}
		6:
			var p: Dictionary = pick.call(lvl.get("props", []))
			if p.is_empty():
				return {}
			return {"t": "element.set", "scene": sid, "ref": "props:" + str(p.id), "changes": {"hidden": rng.randf() < 0.5}}
		7:
			return {"t": "fog.set", "scene": sid, "enabled": rng.randf() < 0.6}
		8:
			var cells := []
			for i in rng.randi_range(1, 12):
				cells.append("%d,%d" % [rng.randi_range(-5, 20), rng.randi_range(-5, 20)])
			return {"t": "fog.reveal" if rng.randf() < 0.65 else "fog.hide", "scene": sid, "cells": cells}
		9:
			var order := []
			for tk in toks:
				if rng.randf() < 0.7:
					order.append(str(tk.id))
			return {"t": "turns.set", "changes": {"mode": ["free", "dm", "ordered"][rng.randi_range(0, 2)], "order": order, "turn": rng.randi_range(0, 3), "round": rng.randi_range(1, 5), "running": rng.randf() < 0.5, "active": order.slice(0, 1)}}
		10:
			return {"t": "scene.activate", "id": sid}
		11:
			return {"t": "scene.set", "id": sid, "changes": {"name": "Scene %d" % rng.randi_range(1, 9)}}
		12:
			if rng.randf() < 0.5 or e.players.size() < 2:
				return {"t": "player.add", "player": Encounter.new_player("P%d" % rng.randi_range(1, 99))}
			return {"t": "player.remove", "id": str(e.players[rng.randi_range(0, e.players.size() - 1)].id)}
		13:
			return {"t": "encounter.set", "changes": {"name": "Fuzz %d" % rng.randi_range(1, 9), "notes": [] if rng.randf() < 0.5 else [{"id": "n", "title": "t", "text": ""}]}}
	return {}


func test_mdns() -> void:
	# Names, with and without compression pointers.
	var n := Mdns.encode_name("_hexmap._tcp.local")
	check(n[0] == 7 and n[n.size() - 1] == 0 and n.size() == 1 + 7 + 1 + 4 + 1 + 5 + 1, "name encoding")
	check(Mdns.read_name(n, 0)[0] == "_hexmap._tcp.local" and Mdns.read_name(n, 0)[1] == n.size(), "name decoding")
	var packed := Mdns.encode_name("local") + PackedByteArray([5, 116, 97, 98, 108, 101, 0xC0, 0])   # "table" + pointer to offset 0 ("local")
	check(Mdns.read_name(packed, 7)[0] == "table.local" and Mdns.read_name(packed, 7)[1] == packed.size(), "compression pointer followed, position after the pointer")
	# A query parses as a query for the service.
	var q := Mdns.parse(Mdns.query())
	check(q.query and q.questions.size() == 1 and q.questions[0].name == Mdns.SERVICE and q.questions[0].type == Mdns.TYPE_PTR, "query round trip")
	# A response carries PTR, SRV, TXT and A records that tables_in() reassembles.
	var r := Mdns.parse(Mdns.response("Chapel Ambush", 47777, "macbook", PackedStringArray(["10.5.91.189", "192.168.1.5"]), {"extra": "x"}))
	check(not r.query and r.records.size() == 5, "response has PTR, SRV, TXT and two A records (%d)" % r.records.size())
	var tables := Mdns.tables_in(r)
	check(tables.size() == 1 and tables[0].name == "Chapel Ambush" and tables[0].port == 47777 and tables[0].host == "macbook.local", "tables_in: %s" % [tables])
	check(tables[0].addresses == PackedStringArray(["10.5.91.189", "192.168.1.5"]), "addresses gathered from A records")
	check(Mdns.tables_in(Mdns.parse(Mdns.response("Dots. In. Name", 1, "h", PackedStringArray())))[0].name == "Dots. In. Name", "dots in an instance name survive")
	check(Mdns.parse(PackedByteArray([1, 2, 3])).is_empty() and Mdns.tables_in(Mdns.parse(Mdns.query())).is_empty(), "junk and queries yield no tables")
	# Truncated data does not crash.
	var full := Mdns.response("T", 1, "h", PackedStringArray(["1.2.3.4"]))
	for cut in [13, 20, 40, full.size() - 3]:
		var part := Mdns.parse(full.slice(0, cut))
		check(part is Dictionary, "truncated at %d parses without error" % cut)
	# Responder and browser over loopback, if the mDNS port can be shared
	# with the OS's own responder here.
	var resp := Mdns.Responder.new()
	resp.start("Loopback mdns", 47777)
	var br := Mdns.Browser.new()
	br.start()
	if not resp.listening():
		skip("cannot bind the mDNS port beside the system responder here")
		resp.stop()
		br.stop()
		return
	var got := []
	br.found.connect(func(p_name: String, address: String, port: int) -> void: got.append([p_name, address, port]))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500 and got.is_empty():
		br.ask()
		OS.delay_msec(40)
		resp.poll(0.04)
		OS.delay_msec(40)
		br.poll(0.04)
	if got.is_empty():
		skip("no mDNS traffic over loopback here (asked %d)" % br.asked)
	else:
		check(got[0][0] == "Loopback mdns" and got[0][2] == 47777, "the browser found the responder: %s" % [got[0]])
	resp.stop()
	br.stop()


func test_remembered_tables() -> void:
	var path := "user://test_prefs_tables.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var app := App.new(path)
	check(app.tables().is_empty(), "none at first")
	app.note_table("10.5.91.189", 47777, "Chapel")
	app.note_table("192.168.1.9", 47777, "Other")
	app.note_table("10.5.91.189", 47777, "Chapel again")
	var t := app.tables()
	check(t.size() == 2 and t[0].name == "Chapel again" and t[1].name == "Other", "newest first, same address:port replaces")
	check(App.new(path).tables().size() == 2, "persists")
	var b := Discovery.Browser.new()
	b.remember("10.5.91.189")
	b.remember("10.5.91.189")
	b.remember("")
	check(b.known == PackedStringArray(["10.5.91.189"]), "known addresses deduplicated, blanks ignored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_player_join_flow() -> void:
	var app := App.new("user://test_prefs_join.json")
	var win := PlayerWindow.new()
	win.app = app
	root.add_child(win)
	# Picking a listed table fills the address; Join uses it.
	win.browser.heard({"name": "Chapel", "port": 47777}, "10.5.91.189")
	win._refresh_tables()
	check(win._tables.item_count == 1, "a heard table is listed")
	win._tables.item_selected.emit(0)
	check(win._address.text == "10.5.91.189:47777" and win.session == null, "a tap fills the address and does not connect yet")
	check((win._join.find_child("JoinStatus", true, false) as Label).text.begins_with("Chapel"), "status says which table")
	app.note_table("192.168.1.9", 5000, "Other")
	win._refresh_known()
	win._known.item_selected.emit(0)
	check(win._address.text == "192.168.1.9:5000", "a remembered table fills the address too")
	# Join with an address connects (to nothing here, but a session exists).
	win._address.text = "127.0.0.1:1"
	win._join_address()
	check(win.session is NetSession and (win._join.find_child("JoinStatus", true, false) as Label).text.begins_with("Connecting"), "Join starts a session and says so")
	check(win.browser.known.has("127.0.0.1"), "the typed address is asked directly from now on")
	# A table heard at several addresses: Join tries the first, then the rest.
	win._leave()
	win.browser.tables.clear()
	win.browser.heard({"name": "Multi", "port": 1, "addresses": ["127.0.0.1", "127.0.0.2"]}, "127.0.0.1")
	win._refresh_tables()
	win._tables.item_selected.emit(0)
	check(win._address.text == "127.0.0.1:1" and win._alternatives == ["127.0.0.2"], "the pick keeps the other addresses as fallbacks")
	win._join_address()
	var first := win.session
	check(first is NetSession and first.address == "127.0.0.1", "tries the first address")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000 and win.session == first:
		win._process(0.05)
		OS.delay_msec(20)
	check(win.session != first and win.session != null and (win.session as NetSession).address == "127.0.0.2", "when it cannot reach it, moves on to the next address (%s)" % [(win._join.find_child("JoinStatus", true, false) as Label).text])
	win._leave()
	win._stop_browsing()
	win.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_join.json"))
