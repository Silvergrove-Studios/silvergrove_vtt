extends TestCase
## Networking: protocol, discovery, sessions.


## Pump host and client until `done` says so, or give up.
func _pump(host: HostSession, clients: Array, done: Callable, max_ms := 4000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		host.poll(0.016)
		for c in clients:
			(c as NetSession).poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func test_protocol() -> void:
	check(Protocol.decode(Protocol.encode({"t": "ping"})) == {"t": "ping"}, "encode/decode")
	check(Protocol.decode("[1]").is_empty() and Protocol.decode("{}").is_empty() and Protocol.decode("nope").is_empty(), "not messages")
	check(Protocol.parse_address("192.168.1.4") == ["192.168.1.4", Protocol.DEFAULT_PORT], "bare host")
	check(Protocol.parse_address(" ws://table.local:5000/ ") == ["table.local", 5000], "url with port")
	check(Protocol.parse_address("10.0.0.2:abc") == ["10.0.0.2:abc", Protocol.DEFAULT_PORT], "a non-number is part of the host")
	var a := Protocol.parse_announcement(Protocol.encode(Protocol.announcement("Chapel", 47777, "mac")))
	check(a.name == "Chapel" and int(a.port) == 47777 and a.host == "mac", "announcement round trip")
	check(Protocol.parse_announcement('{"hexmap": 99, "name": "x", "port": 1}').is_empty() and Protocol.parse_announcement("junk").is_empty(), "other versions and junk ignored")
	var b := Discovery.Browser.new()
	var updates := []
	b.updated.connect(func() -> void: updates.append(1))
	check(b.heard({"name": "A", "port": 1}, "10.0.0.1") and not b.heard({"name": "A", "port": 1}, "10.0.0.1"), "heard: new then repeat")
	check(not b.heard({"name": "A", "port": 1}, "10.0.0.2") and b.list().size() == 1 and b.list()[0].addresses == ["10.0.0.1", "10.0.0.2"], "same name and port from another address: the same table, heard at two addresses")
	check(b.heard({"name": "B", "port": 1}, "10.0.0.1") and b.list()[0].name == "A" and b.list()[1].name == "B", "another name is another table; list sorted by name")
	# Which address to connect to: one that answered a direct query, then a
	# known one, then the packet's source, then the rest.
	var m := Discovery.Browser.new()
	var multi := {"name": "M", "port": 7, "addresses": ["192.168.18.1", "10.5.91.189", "10.211.55.2"]}
	m.heard(multi, "192.168.18.1", "mdns")
	check(m.list()[0].address == "192.168.18.1" and m.list()[0].via == "mdns", "with no better evidence, the source address")
	m.remember("10.5.91.189")
	m.heard(multi, "192.168.18.1", "mdns")
	check(m.list()[0].address == "10.5.91.189", "a known address beats the source")
	m.confirmed["10.211.55.2"] = true
	m.heard(multi, "192.168.18.1", "mdns")
	check(m.list()[0].address == "10.211.55.2" and m.list()[0].addresses[0] == "10.211.55.2", "one that answered a direct query beats everything")
	check(m.last_heard.begins_with("M via mdns from 192.168.18.1"), "the diagnostics remember what was heard: %s" % m.last_heard)


func test_discovery_loopback() -> void:
	check(Discovery.is_query(Protocol.encode(Discovery.query())) and not Discovery.is_query("{}") and not Discovery.is_query(Protocol.encode(Protocol.announcement("x", 1, ""))), "queries are told from announcements")
	var targets := Discovery.shout_targets()
	check(targets.has(Protocol.DISCOVERY_GROUP) and targets.has("255.255.255.255"), "shouting to the group and the broadcast")
	for t in targets:
		check(str(t).is_valid_ip_address(), "target %s is an address" % t)
	# The ask-and-answer path: a browser asks from an ephemeral socket, the
	# announcer answers it by unicast. This is what phones rely on.
	var ann := Discovery.Announcer.new()
	check(ann.start("Loopback table", 47777) == OK, "announcer starts")
	if not ann._listening:
		skip("announcer cannot bind the discovery port here (%s)" % error_string(ann.listen_error))
		ann.stop()
		return
	var browser := Discovery.Browser.new()
	check(browser.start() == OK, "browser starts")
	var heard := false
	var answered := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000 and not heard:
		browser.ask()
		OS.delay_msec(30)
		answered += ann.answer_queries()
		OS.delay_msec(30)
		browser.poll(0.06)
		for t in browser.list():
			if str(t.name) == "Loopback table":
				heard = true
	check(answered > 0, "the announcer answered %d queries" % answered)
	check(heard and int(browser.list()[0].port) == 47777, "the browser lists the table from the unicast answer")
	ann.stop()
	browser.stop()


func test_host_and_net_session() -> void:
	var packs := PackLibrary.new()
	packs.reload()
	var e := Encounter.load_file(example("chapel_ambush.encounter"))
	var st := EncounterState.new(e)
	st.resolve_maps()
	var history := EventLog.new(st)
	var cmds := EncounterCommands.new(st, history)
	var host := HostSession.new(st, packs)
	var applied := []
	host.apply_request = func(ev: Dictionary, pid: String) -> String:
		applied.append(pid)
		return cmds.run(ev, "Player move")
	var joined := []
	host.client_joined.connect(func(p: String) -> void: joined.append(p))
	check(host.start(0, false) == OK and host.port > 0 and host.is_running(), "host listens on a free port (%d)" % host.port)
	# A client with its own pack library pointed at a scratch cache.
	var cache := "user://packs_test"
	var cpacks := PackLibrary.new()
	cpacks.reload()
	var client := NetSession.new("127.0.0.1", host.port, cpacks, "test client")
	client.cache_dir = cache
	var told := []
	client.status.connect(func(t: String) -> void: told.append(t))
	var closed := []
	client.closed.connect(func(r: String) -> void: closed.append(r))
	check(client.connect_to_host() == OK, "client connects")
	check(_pump(host, [client], func() -> bool: return client.state != null and client.maps_ready()), "welcome and maps arrive")
	check(client.state.encounter.name == "Chapel Ambush" and client.state.maps.size() == 1 and client.state.map_for(client.scene_id()).name == "Ruined Chapel", "the client has the encounter and its map")
	check(host.client_count() == 1 and host.connected_players().is_empty(), "connected, not yet joined")
	var ana: Dictionary = e.players[0]
	var sid := e.active_scene_id
	var fighter: Dictionary = st.tokens_owned_by(sid, str(ana.id))[0]
	var mv := {"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [1.5, 1.5]}}
	check(client.request(mv) == "Not joined yet", "requests need a join")
	client.join("pl_nobody")
	check(_pump(host, [client], func() -> bool: return told.has("no such player")), "an unknown player is refused")
	client.join(str(ana.id))
	check(_pump(host, [client], func() -> bool: return client.joined), "joined as Ana")
	check(joined == [str(ana.id)] and host.connected_players() == [str(ana.id)], "the host says so too")
	# The example is ordered-not-running: the client refuses locally with the reason, nothing is sent.
	check(client.request(mv) == "Turns have not begun" and applied.is_empty(), "pre-checked locally")
	cmds.set_turn_mode("free")
	check(_pump(host, [client], func() -> bool: return client.state.encounter.turns.mode == "free"), "the host's change reached the client as an event")
	check(client.request(mv) == "", "in free mode the request goes out")
	check(_pump(host, [client], func() -> bool: return Vision.token_pos(client.state.token(sid, fighter.id)) == Vector2(1.5, 1.5)), "applied at the host and echoed back")
	check(applied == [str(ana.id)] and history.undo_label() == "Player move" and Vision.token_pos(st.token(sid, fighter.id)) == Vector2(1.5, 1.5), "the host applied it through the table's commands, undoably")
	check(JsonDoc.sans_modified(client.state.encounter.to_json()) == JsonDoc.sans_modified(JsonDoc.stringify(Protocol.client_document(st.encounter.doc))), "the client holds the host's document minus its rules blocks")
	history.undo()
	check(_pump(host, [client], func() -> bool: return Vision.token_pos(client.state.token(sid, fighter.id)) != Vector2(1.5, 1.5)), "the DM's undo reaches the client")
	check(JsonDoc.sans_modified(client.state.encounter.to_json()) == JsonDoc.sans_modified(JsonDoc.stringify(Protocol.client_document(st.encounter.doc))), "still the same after undo")
	# a scene over a map the client has never seen, added mid-session: the map is fetched
	var road := HexMap.load_file("res://examples/forest_road.hexmap")
	st.attach_map(road)
	var road_scene := Encounter.new_scene(road, str(road.levels[0].get("id", "ground")), "The road", "res://examples/forest_road.hexmap")
	check(cmds.add_scene(road_scene, true) == "", "the table adds a scene over the forest road")
	check(_pump(host, [client], func() -> bool: return client.maps_ready() and client.state.maps.has(str(road.doc.id))), "the client asked for the new map and got it (%d maps)" % client.state.maps.size())
	check(client.scene_id() == str(road_scene.id) and client.state.map_for(client.scene_id()) != null, "and shows the road")
	cmds.activate_scene(sid)
	check(_pump(host, [client], func() -> bool: return client.scene_id() == sid), "back to the chapel")
	# A second client, as Ben, sees Ana's next move.
	var client2 := NetSession.new("127.0.0.1", host.port, cpacks, "second")
	client2.cache_dir = cache
	client2.connect_to_host()
	check(_pump(host, [client, client2], func() -> bool: return client2.state != null and client2.maps_ready()), "second client welcomed")
	client2.join(str(e.players[1].id))
	check(_pump(host, [client, client2], func() -> bool: return client2.joined), "Ben joined")
	client.request({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [2.5, 2.5]}})
	check(_pump(host, [client, client2], func() -> bool: return Vision.token_pos(client2.state.token(sid, fighter.id)) == Vector2(2.5, 2.5)), "Ben sees Ana's move")
	# A tampered request: the host refuses what allowed() forbids.
	client2._send({"t": "request", "ev": {"t": "element.set", "scene": sid, "ref": "walls:x", "changes": {"state": "open"}}})
	var told2 := []
	client2.status.connect(func(t: String) -> void: told2.append(t))
	check(_pump(host, [client, client2], func() -> bool: return told2.has("not allowed")), "the host refuses a forged request")
	# Packs: the client pretends it lacks the swamp pack and gets it streamed.
	cpacks.packs.erase("swamp")
	(st.maps.values()[0] as HexMap).doc.packs["swamp"] = "0.1.0"
	var ready := []
	client.assets_ready.connect(func() -> void: ready.append(1))
	client._send({"t": "need", "kind": "packs"})
	check(_pump(host, [client, client2], func() -> bool: return not ready.is_empty(), 8000), "pack files streamed")
	var cdir := ProjectSettings.globalize_path(cache.path_join("swamp"))
	check(FileAccess.file_exists(cdir.path_join("pack.json")) and FileAccess.file_exists(cdir.path_join("props/witch_hut.svg")), "files landed in the cache")
	check(FileAccess.get_file_as_bytes(cdir.path_join("props/witch_hut.svg")) == FileAccess.get_file_as_bytes(packs.pack_dir("swamp").path_join("props/witch_hut.svg")), "byte-identical")
	check(client.assets_pending() == 0, "nothing pending")
	# Path traversal is refused.
	client._send({"t": "need", "kind": "file", "pack": "swamp", "file": "../../project.godot"})
	check(_pump(host, [client, client2], func() -> bool: return told.any(func(t: String) -> bool: return t.begins_with("no file"))), "traversal refused")
	# Leaving and stopping.
	client2.leave()
	check(_pump(host, [client], func() -> bool: return host.client_count() == 1), "a client that leaves is dropped")
	host.stop()
	check(_pump(host, [client], func() -> bool: return not closed.is_empty()), "stopping the host closes the client (%s)" % [closed])
	check(not host.is_running(), "host stopped")
	# Clean the cache.
	for f in ["props/witch_hut.svg", "pack.json"]:
		DirAccess.remove_absolute(cdir.path_join(f))
	_rm_tree(cdir)
	history.clear()


func _rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in d.get_directories():
		_rm_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func test_table_hosts_player_joins() -> void:
	var app := App.new("user://test_prefs_net.json")
	var table := TableWindow.new()
	table.app = app
	root.add_child(table)
	table._open_path(_example("chapel_ambush.encounter"))
	table.ctx.commands.set_turn_mode("free")
	# the chapel gets a backdrop on the table, in memory: the phone must fetch the image
	var chapel: HexMap = table.ctx.map()
	var bimg := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	bimg.fill(Color.DARK_GREEN)
	chapel.add_asset("ground.png", bimg.save_png_to_buffer())
	chapel.level(0)["backdrop"] = {"image": "local:ground.png", "pos": [0, 0], "size": [22, 16], "opacity": 1.0, "hidden": false}
	table._set_hosting(true)
	check(table.host != null and table.host.is_running() and table.host_button.button_pressed, "the table hosts")
	check(table.host_address().ends_with(":%d" % table.host.port), "and shows an address: %s" % table.host_address())
	var player := PlayerWindow.new()
	player.app = app
	root.add_child(player)
	check(player.screen == "join", "player on the join screen")
	var pump := func(done: Callable, max_ms := 4000) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < max_ms:
			table._process(0.05)
			player._process(0.05)
			if done.call():
				return true
			OS.delay_msec(10)
		return false
	# Discovery, or the typed address. Other tables may be on the network
	# (someone's real one), so look for ours by name and port.
	var ours := func() -> int:
		for i in player._tables.item_count:
			var t: Dictionary = player._tables.get_item_metadata(i)
			if int(t.port) == table.host.port and str(t.name) == "Chapel Ambush":
				return i
		return -1
	var found: bool = player._browsing and pump.call(func() -> bool: return ours.call() >= 0, 2500)
	if found:
		say.call("  found the table by discovery: %s" % player._tables.get_item_text(ours.call()))
		player._tables.item_selected.emit(ours.call())   # a tap joins…
		check(player._address.text.ends_with(":%d" % table.host.port), "…the table's address")
	else:
		say.call("  (no discovery on loopback here; using the address)")
		player._address.text = "127.0.0.1:%d" % table.host.port
		player._join_address()
	check(player.session is NetSession, "connecting")
	check(pump.call(func() -> bool: return player.screen == "pick"), "welcomed: the player picker shows")
	check(player._players.item_count == 2 and player._pick_title.text == "Chapel Ambush", "players listed from the table's document")
	player._start(str(player._players.get_item_metadata(0)))
	check(pump.call(func() -> bool: return player.screen == "play" and player.view.canvas.map != null), "joined as Ana and the map arrived")
	# a player with no character of her own is taken to where one is made
	check(pump.call(func() -> bool: return not player.session.view.is_empty()), "the table's view arrived")
	var no_character: bool = player.session.my_actors().is_empty()
	check(player.pane_mode == ("table" if no_character else ""), "no character of her own: the pane where one is made (%s, %d of hers)" % [player.pane_mode, player.session.my_actors().size()])
	if no_character:
		check(player._pane_box.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "You have no character yet"), "and told so")
		player.set_pane("")
	# the DM shows the players something: on the phone at once, kept in the
	# Journal; what is shown to another player never reaches this one
	check(Sharing.share(table.ctx, "note:runes", "The runes", "Runes glow faintly.", "", "all") == "", "shown to everyone")
	check(pump.call(func() -> bool: return player.is_showing_handout()), "on Ana's phone at once, on the whole screen")
	check(player._shown_box.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "The runes"), "the runes")
	player._close_shown()
	var ana_id: String = player.session.player_id
	var ben_id := ""
	for pl in table.ctx.encounter().players:
		if str(pl.id) != ana_id:
			ben_id = str(pl.id)
	check(Sharing.share(table.ctx, "note:ben", "Ben's secret", "Only Ben.", "", "players:" + ben_id) == "", "shown to Ben alone")
	check(Sharing.share(table.ctx, "note:ana", "For Ana", "Only Ana.", "", "players:" + ana_id) == "", "and something to Ana alone")
	check(pump.call(func() -> bool: return player.handouts().size() == 2), "Ana's phone has what was shown to everyone and to her: %s" % [player.handouts().map(func(h: Dictionary) -> String: return str(h.title))])
	check(not player.handouts().any(func(h: Dictionary) -> bool: return str(h.title) == "Ben's secret"), "never what was shown to Ben")
	player._close_shown()
	player.set_pane("journal")
	check(player._pane_box.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "For Ana"), "her Journal keeps them")
	player.set_pane("")
	check(Sharing.unshare(table.ctx, "note:ana") == "" and pump.call(func() -> bool: return player.handouts().size() == 1), "taken back: gone from her Journal")
	check(table.players.online.size() == 1 and table.players.list.get_item_text(0).begins_with("●"), "the table shows Ana online")
	check(player.view.canvas.tokens_in_view().size() == 2, "Ana sees the party")
	var pmap: HexMap = player.view.canvas.map
	check(pmap.level(0).get("backdrop", {}).get("image") == "local:ground.png", "the map came with its backdrop record")
	check(pump.call(func() -> bool: return pmap.asset_texture("local:ground.png") != null), "and the image followed over the wire")
	check(pmap.asset_texture("local:ground.png").get_width() == 8, "as sent")
	# Ana moves her fighter; the table applies it as an undoable step and the DM sees it.
	var sid := player.session.scene_id()
	var fighter: Dictionary = player.session.my_tokens()[0]
	var from := Vision.token_pos(fighter)
	var g := player.view.canvas.map.grid
	var to := g.cell_center(g.world_to_axial(from) + Vector2i(1, 0))
	var mods := {"shift": false, "ctrl": false, "alt": false}
	player.tool.press(from, MOUSE_BUTTON_LEFT, mods)
	player.tool.drag(to, MOUSE_BUTTON_LEFT, mods)
	player.tool.release(to, MOUSE_BUTTON_LEFT, mods)
	check(pump.call(func() -> bool: return Vision.token_pos(table.ctx.state.token(sid, fighter.id)) == to), "the table got the move")
	check(table.ctx.history.undo_label().begins_with("Ana moves"), "as one labelled undo step: %s" % table.ctx.history.undo_label())
	check(pump.call(func() -> bool: return Vision.token_pos(player.session.state.token(sid, fighter.id)) == to), "echoed to the player")
	check(table.ctx.state.explored(sid).size() >= 88, "the move explored fog at the table")
	# The DM opens the door and switches turn mode; the player is told.
	var door := _door_of(table.ctx)
	table.ctx.commands.set_door(sid, door.id, "open")
	table.ctx.commands.set_turn_mode("ordered")
	table.ctx.commands.start_turns(sid)
	check(pump.call(func() -> bool: return player.session.state.effective(sid, "walls", door).state == "open" and player.session.state.encounter.turns.running), "door and turns reached the player")
	check(player._turn.text.begins_with("Your turn: Ana's fighter"), "the player's bar says it is her turn")
	check(JsonDoc.sans_modified(player.session.state.encounter.to_json()) == JsonDoc.sans_modified(JsonDoc.stringify(Protocol.client_document(table.ctx.state.encounter.doc))), "the scene is identical across the wire")
	# Leaving and stopping.
	player._leave()
	check(pump.call(func() -> bool: return table.players.online.is_empty()), "the table sees her leave")
	table._set_hosting(false)
	check(table.host == null and not table.host_button.button_pressed, "hosting stopped")
	player._stop_browsing()
	player.queue_free()
	table.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_net.json"))


## The Bonjour helper (dns-sd, avahi-publish) outlives a Table that is
## killed unless something stops it: a watchdog does.
func test_bonjour_helper_dies_with_the_table() -> void:
	if OS.has_feature("windows") or OS.has_feature("mobile") or not FileAccess.file_exists("/bin/sleep"):
		skip("no /bin/sh helpers here")
		return
	var parent := OS.create_process("/bin/sleep", ["30"])
	var child := OS.create_process("/bin/sleep", ["60"])
	var dog := Bonjour.watchdog(parent, child)
	check(parent > 0 and child > 0 and dog > 0, "a stand-in table, a helper, and the watchdog")
	OS.delay_msec(300)
	check(OS.is_process_running(child), "the helper runs while the table does")
	OS.kill(parent)
	var t0 := Time.get_ticks_msec()
	# (is_process_running reaps the stand-in, as its real parent would the Table)
	while Time.get_ticks_msec() - t0 < 8000 and (OS.is_process_running(child) or OS.is_process_running(parent)):
		OS.delay_msec(100)
	check(not OS.is_process_running(child), "and stops when the table is gone (%d ms)" % (Time.get_ticks_msec() - t0))
	if OS.is_process_running(child):
		OS.kill(child)
	OS.kill(dog)


func test_responsive_layout() -> void:
	# UI scale: points on a phone, but never fewer than 360 points across.
	check(App.density_scale(160, Vector2(1920, 1080)) == 1.0, "desktop density: no scaling")
	check(near(App.density_scale(440, Vector2(1080, 2400)), 2.75, 0.01), "a 440 dpi phone scales 2.75× (1080 px → 393 pt)")
	check(near(App.density_scale(640, Vector2(720, 1600)), 2.0, 0.01), "a small dense screen is capped so 360 pt fit (720 / 2)")
	check(App.density_scale(1000, Vector2(1440, 3200)) == 4.0, "scale is capped at 4")
	check(App.safe_insets(2.0) == {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0} or OS.has_feature("mobile"), "no insets on a desktop")
	# The Player's columns fit a narrow window.
	var app := App.new("user://test_prefs_resp.json")
	var win := PlayerWindow.new()
	win.app = app
	root.add_child(win)
	check((win._columns[0] as Control).custom_minimum_size.x > 0, "columns are fitted once built, without waiting for a resize")
	win.size = Vector2(360, 640)
	win._fit()
	for c in win._columns:
		check((c as Control).custom_minimum_size.x <= 360 - 32, "player column fits a 360 pt window (%d)" % int((c as Control).custom_minimum_size.x))
	win.size = Vector2(1200, 800)
	win._fit()
	check((win._columns[0] as Control).custom_minimum_size.x == 440, "and is 440 when there is room")
	win._stop_browsing()
	win.queue_free()
	var home := HomeScreen.new()
	home.app = app
	root.add_child(home)
	home.size = Vector2(320, 600)
	home._fit()
	check(home._column.custom_minimum_size.x <= 320 - 32, "home column fits a 320 pt window")
	home.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_resp.json"))


func test_ui_scale_pref() -> void:
	var path := "user://test_prefs_scale.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var app := App.new(path)
	check(app.ui_scale == 1.0, "default UI scale is 1")
	var got := []
	app.ui_scale_changed.connect(func(s: float) -> void: got.append(s))
	app.step_ui_scale(true)
	check(is_equal_approx(app.ui_scale, 1.15) and got == [1.15], "step up goes to the next size")
	app.step_ui_scale(false)
	app.step_ui_scale(false)
	check(is_equal_approx(app.ui_scale, 0.85), "step down twice")
	app.set_ui_scale(9.0)
	check(app.ui_scale == 2.0, "clamped to the largest")
	app.set_ui_scale(0.1)
	check(app.ui_scale == 0.75, "clamped to the smallest")
	for i in 10:
		app.step_ui_scale(true)
	check(app.ui_scale == 2.0, "stepping past the end stays at the end")
	app.set_ui_scale(1.3)
	check(App.new(path).ui_scale == 1.3, "persists")
	check(App.scale_label(1.3) == "130%" and App.scale_label(0.85) == "85%", "labels")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"ui_scale": "big"}')
	f.close()
	check(App.new(path).ui_scale == 1.0, "garbage falls back to 1")
	check(App.window_scale(1.5) >= 1.5, "the window scale multiplies the user's choice in")
	# The windows' View menus reflect it.
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	var idx := App.UI_SCALES.find(1.3)
	check(win.scale_menu.is_item_checked(idx), "the table's UI size menu shows the current size")
	win._on_menu(win.V_SCALE_BASE + App.UI_SCALES.find(1.0))
	check(app.ui_scale == 1.0 and win.scale_menu.is_item_checked(App.UI_SCALES.find(1.0)) and not win.scale_menu.is_item_checked(idx), "picking a size applies it and moves the check")
	win._on_menu(win.V_SCALE_UP)
	check(is_equal_approx(app.ui_scale, 1.15), "View → Bigger")
	win.queue_free()
	var home := HomeScreen.new()
	home.app = app
	root.add_child(home)
	check((home.find_child("ScaleValue", true, false) as Label).text == "115%", "the home screen shows it")
	app.step_ui_scale(true)
	check((home.find_child("ScaleValue", true, false) as Label).text == "130%", "and follows changes")
	home.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
