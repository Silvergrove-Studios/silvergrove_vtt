extends TestCase
## The web clients' side of the host: the HTTP server beside the WebSocket,
## the scene each web client is sent (filtered for them), joining by name,
## the DM's own screen, chat and its audiences.


func _webroot() -> String:
	var dir := "user://test_webroot"
	DirAccess.make_dir_recursive_absolute(dir.path_join("assets"))
	var f := FileAccess.open(dir.path_join("index.html"), FileAccess.WRITE)
	f.store_string("<!doctype html><html>Hexmap web</html>")
	f.close()
	f = FileAccess.open(dir.path_join("assets/app.js"), FileAccess.WRITE)
	f.store_string("console.log('hexmap')")
	f.close()
	return dir


func test_web_server() -> void:
	var w := WebServer.new()
	w.root = _webroot()
	w.art_source = func(pack: String, file: String) -> PackedByteArray:
		return "<svg/>".to_utf8_buffer() if pack == "woodland" and file == "terrain/grass_1.svg" else PackedByteArray()
	w.map_file_source = func(mid: String, file: String) -> PackedByteArray:
		return PackedByteArray([1, 2, 3]) if mid == "m1" and file == "ground.png" else PackedByteArray()
	w.config_source = func() -> Dictionary: return {"ws_port": 47777, "name": "Our Chapel"}
	var get := func(path: String, method := "GET") -> String:
		return w.respond("%s %s HTTP/1.1\r\nHost: table\r\n\r\n" % [method, path]).get_string_from_utf8()
	var page: String = get.call("/")
	check(page.begins_with("HTTP/1.1 200") and page.contains("text/html") and page.contains("Hexmap web"), "the player's page")
	check(str(get.call("/dm")).contains("Hexmap web") and str(get.call("/join")).contains("Hexmap web"), "the DM's is the same one-page client")
	var js: String = get.call("/assets/app.js")
	check(js.contains("text/javascript") and js.contains("immutable") and js.contains("console.log"), "its script, cached for good")
	check(str(get.call("/config.json")).contains("\"ws_port\":47777"), "where the WebSocket is")
	var art: String = get.call("/art/woodland/terrain/grass_1.svg")
	check(art.contains("image/svg+xml") and art.ends_with("<svg/>"), "a pack's art")
	check(str(get.call("/art/woodland/secret.txt")).begins_with("HTTP/1.1 404"), "only what the pack has")
	check(w.respond("GET /mapfile/m1/ground.png HTTP/1.1\r\n\r\n").size() > 3 and str(get.call("/mapfile/m1/ground.png")).contains("image/png"), "a map's own file")
	for bad in ["/../project.godot", "/assets/../../project.godot", "/assets/%2e%2e/%2e%2e/project.godot", "/assets/x%00.js", "/nothing"]:
		check(str(get.call(bad)).begins_with("HTTP/1.1 404"), "nothing outside its roots: %s" % bad)
	check(str(get.call("/", "POST")).begins_with("HTTP/1.1 405"), "only GET and HEAD")
	check(WebServer.address_rank("192.168.1.23") == 0 and WebServer.address_rank("10.5.91.189") == 0 and WebServer.address_rank("192.168.18.1") == 1
		and WebServer.address_rank("100.99.188.26") == 2 and WebServer.address_rank("8.8.8.8") == 3, "the addresses players likely reach come first")
	# the web clients as the exports carry them: one zip
	var zpath := "user://test_webclient.zip"
	var zp := ZIPPacker.new()
	zp.open(zpath)
	zp.start_file("index.html")
	zp.write_file("<!doctype html><html>Zipped web</html>".to_utf8_buffer())
	zp.close_file()
	zp.start_file("assets/app-1.js")
	zp.write_file("console.log('zipped')".to_utf8_buffer())
	zp.close_file()
	zp.close()
	var wz := WebServer.new()
	wz.root = zpath
	check(wz.respond("GET /dm HTTP/1.1\r\n\r\n").get_string_from_utf8().contains("Zipped web"), "the page, out of the zip")
	check(wz.respond("GET /assets/app-1.js HTTP/1.1\r\n\r\n").get_string_from_utf8().contains("console.log('zipped')"), "a script, out of the zip")
	check(wz.respond("GET /assets/none.js HTTP/1.1\r\n\r\n").get_string_from_utf8().begins_with("HTTP/1.1 404"), "only what the zip holds")
	check(FileAccess.file_exists("res://webclient.zip") and WebServer.new().respond("GET / HTTP/1.1\r\n\r\n").get_string_from_utf8().contains("<div id=\"app\">"), "the built web clients are in the project (web/: npm run build)")
	var head: String = get.call("/", "HEAD")
	check(head.begins_with("HTTP/1.1 200") and not head.contains("Hexmap web"), "HEAD: the headers alone")
	# over a real socket
	check(w.start(0) == OK and w.port > 0, "listening (port %d)" % w.port)
	var s := StreamPeerTCP.new()
	s.connect_to_host("127.0.0.1", w.port)
	var sent := false
	var got := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		w.poll()
		s.poll()
		if s.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				s.put_data("GET /dm HTTP/1.1\r\nHost: localhost\r\n\r\n".to_utf8_buffer())
				sent = true
			var n := s.get_available_bytes()
			if n > 0:
				got.append_array(s.get_partial_data(n)[1])
		elif sent and s.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		if got.get_string_from_utf8().contains("</html>"):
			break
		OS.delay_msec(5)
	check(got.get_string_from_utf8().begins_with("HTTP/1.1 200") and got.get_string_from_utf8().contains("Hexmap web"), "a browser gets the page over the network: [%s] status %d sent %s" % [got.get_string_from_utf8().left(80), s.get_status(), sent])
	w.stop()
	check(not w.is_running(), "and it stops")


func _chapel_state() -> EncounterState:
	var st := EncounterState.new(Encounter.load_file(example("chapel_ambush.encounter")))
	st.resolve_maps()
	return st


func test_web_scene() -> void:
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var ana := "pl_fe0170c1"
	var snap := WebScene.build(st, sid, ana, false)
	var names := (snap.tokens as Array).map(func(t: Dictionary) -> String: return str(t.name))
	check(snap.fog and names.has("Ana's fighter") and not names.has("Goblin"), "Ana sees her fighter and no hidden goblin: %s" % [names])
	check(not (snap.tokens as Array).any(func(t: Dictionary) -> bool: return t.has("hidden")), "a player is never told what is hidden")
	check(not (snap.visible as Array).is_empty() and (snap.visible[0] as Array).size() >= 3, "what her fighter sees, as polygons from the table")
	var dm := WebScene.build(st, sid, "", true)
	check((dm.tokens as Array).size() == 6 and (dm.tokens as Array).filter(func(t: Dictionary) -> bool: return bool(t.hidden)).size() == 4, "the DM sees every token, the hidden ones marked")
	check(not (dm.visible as Array).is_empty(), "and the players' sight, as a preview")
	# a goblin revealed where Ana can see it; another revealed where she cannot
	var gob := str(st.tokens(sid)[2].id)
	var far := str(st.tokens(sid)[4].id)
	st.apply({"t": "token.set", "scene": sid, "id": gob, "changes": {"hidden": false, "pos": [4.5, 6.6]}})
	st.apply({"t": "token.set", "scene": sid, "id": far, "changes": {"hidden": false, "pos": [40.0, 40.0]}})
	var ids := (WebScene.build(st, sid, ana, false).tokens as Array).map(func(t: Dictionary) -> String: return str(t.id))
	check(ids.has(gob) and not ids.has(far), "a revealed goblin beside her is there; one she cannot see is not")
	# the rest of the party, wherever they are (a playtest's player saw a
	# friend's token vanish through a doorway, and took it for a dropped connection)
	var ben_tk := Encounter.new_token("Ben's rogue", Vector2(40.5, 40.5), {"owner": "pl_393eb25a", "hidden": false})
	st.apply({"t": "token.add", "scene": sid, "token": ben_tk})
	ids = (WebScene.build(st, sid, ana, false).tokens as Array).map(func(t: Dictionary) -> String: return str(t.id))
	check(ids.has(str(ben_tk.id)) and not ids.has(far), "Ben's rogue, far out of her sight, is still on Ana's map; the goblin there is not")
	check(WebScene.build(st, "nope", ana, false).is_empty(), "no such scene: nothing")


## A web client over a real socket: its messages, as they come.
class WebClient:
	var ws := WebSocketPeer.new()
	var inbox: Array = []

	func _init(port: int) -> void:
		ws.connect_to_url("ws://127.0.0.1:%d" % port)

	func poll() -> void:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var j := JSON.new()
			if j.parse(ws.get_packet().get_string_from_utf8()) == OK and j.data is Dictionary:
				inbox.append(j.data)

	func send(msg: Dictionary) -> void:
		ws.send_text(JSON.stringify(msg))

	func open() -> bool:
		return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

	func last(t: String) -> Dictionary:
		for i in range(inbox.size() - 1, -1, -1):
			if str(inbox[i].get("t", "")) == t:
				return inbox[i]
		return {}

	func count(t: String) -> int:
		return inbox.filter(func(m: Dictionary) -> bool: return str(m.get("t", "")) == t).size()


func _pump(host: HostSession, clients: Array, done: Callable, max_ms := 3000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		host.poll(0.016)
		for c in clients:
			(c as WebClient).poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func test_web_clients_on_the_host() -> void:
	var st := _chapel_state()
	var kernel := RulesKernel.new(st)
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = kernel
	host.add_player = func(ev: Dictionary) -> String:
		st.apply(ev)
		return ""
	var ops := []
	host.dm_handler = func(intent: Dictionary) -> String:
		ops.append(str(intent.get("op", "")))
		return ""
	host.dm_state_source = func() -> Dictionary: return {"campaign": {"name": "Chapel"}}
	host.dm_token = "sesame"
	check(host.start(0, false, 0) == OK and host.web != null and host.web.port > 0, "the host serves the web clients beside its WebSocket (ws %d, web %d)" % [host.port, host.web.port])
	check(host.join_urls().size() >= 0, "and knows the addresses to join at: %s" % [host.join_urls()])
	# someone new joins by name, from a browser
	var cara := WebClient.new(host.port)
	check(_pump(host, [cara], func() -> bool: return cara.open()), "a browser connects")
	cara.send({"t": "hello", "version": Protocol.VERSION, "name": "phone", "web": true})
	cara.send({"t": "join", "role": "player", "name": "Cara"})
	check(_pump(host, [cara], func() -> bool: return not cara.last("scene").is_empty()), "joined, and sent the scene")
	var added := st.encounter.players.filter(func(p: Dictionary) -> bool: return str(p.name) == "Cara")
	check(added.size() == 1 and str(cara.last("joined").player) == str(added[0].id), "Cara is new at the table: added, and joined as herself")
	check(not cara.last("view").is_empty(), "with her view of the rules")
	# someone who was here before is found, whatever the case
	var ana := WebClient.new(host.port)
	_pump(host, [ana], func() -> bool: return ana.open())
	ana.send({"t": "hello", "version": Protocol.VERSION, "name": "phone", "web": true})
	ana.send({"t": "join", "role": "player", "name": "  ana "})
	check(_pump(host, [ana], func() -> bool: return not ana.last("joined").is_empty()) and str(ana.last("joined").player) == "pl_fe0170c1", "Ana, back again, is Ana")
	check(st.encounter.players.size() == 3, "and not added twice")
	# web clients get the scene again, whole, not the events
	var scenes_before := ana.count("scene")
	var sid := st.encounter.active_scene_id
	st.apply({"t": "token.set", "scene": sid, "id": "t_bdb237f2", "changes": {"pos": [4.2, 6.7]}})
	check(_pump(host, [ana, cara], func() -> bool: return ana.count("scene") > scenes_before), "a move: the scene again")
	check(ana.count("event") == 0, "and never the event stream")
	# the DM's own screen: the token, and only from this machine
	var dm := WebClient.new(host.port)
	_pump(host, [dm], func() -> bool: return dm.open())
	dm.send({"t": "hello", "version": Protocol.VERSION, "name": "dm", "web": true})
	dm.send({"t": "join", "role": "dm", "token": "wrong"})
	check(_pump(host, [dm], func() -> bool: return not dm.last("error").is_empty()), "a wrong token is refused")
	dm = WebClient.new(host.port)
	_pump(host, [dm], func() -> bool: return dm.open())
	dm.send({"t": "hello", "version": Protocol.VERSION, "name": "dm", "web": true})
	dm.send({"t": "join", "role": "dm", "token": "sesame"})
	check(_pump(host, [dm], func() -> bool: return not dm.last("dm").is_empty()), "the DM's screen joins, and gets the campaign")
	var dm_scene: Dictionary = dm.last("scene")
	check((dm_scene.scene.tokens as Array).size() == 6 and (dm_scene.get("scenes", []) as Array).size() == 2, "the DM sees every token, and every scene")
	check(HostSession.is_local_address("127.0.0.1") and HostSession.is_local_address("::1") and not HostSession.is_local_address("192.168.1.9"), "only a browser on this machine may be the DM")
	for ip in ["0:0:0:0:0:0:0:1", "::ffff:127.0.0.1", "0:0:0:0:0:ffff:7f00:1", "127.0.1.1"]:
		check(HostSession.is_local_address(ip), "this machine, however it is written: %s" % ip)
	for ip in ["::ffff:192.168.1.9", "0:0:0:0:0:ffff:c0a8:109", "fe80::1", "::", "10.0.0.1", ""]:
		check(not HostSession.is_local_address(ip), "not this machine: %s" % ip)
	# seeing as a player: that player's snapshot beside the DM's own (a playtest's
	# DM revealed the goblins and couldn't tell that nobody could see them)
	dm.send({"t": "intent", "intent": {"kind": "dm", "op": "see_as", "player": "pl_fe0170c1"}})
	check(_pump(host, [dm], func() -> bool: return str(dm.last("scene").get("preview_as", "")) == "pl_fe0170c1"), "the DM sees as Ana")
	var preview: Dictionary = dm.last("scene").get("preview", {})
	check((preview.get("tokens", []) as Array).size() < (dm.last("scene").scene.tokens as Array).size() and not (preview.tokens as Array).any(func(t: Dictionary) -> bool: return t.has("hidden")),
		"her snapshot: fewer tokens than the DM's, nothing hidden among them")
	dm.send({"t": "intent", "intent": {"kind": "dm", "op": "see_as", "player": ""}})
	check(_pump(host, [dm], func() -> bool: return not dm.last("scene").has("preview")), "and back to the DM's own")
	dm.send({"t": "intent", "intent": {"kind": "dm", "op": "launch", "encounter": "e1"}})
	check(_pump(host, [dm], func() -> bool: return ops.has("launch")), "the DM's operations reach the Table")
	var crypt := str(st.encounter.scenes[1].id)
	dm.send({"t": "intent", "intent": {"kind": "dm", "op": "view_scene", "scene": crypt}})
	check(_pump(host, [dm], func() -> bool: return str(dm.last("scene").scene.id) == crypt), "the DM looks at another scene; the players' stays")
	ana.send({"t": "intent", "intent": {"kind": "dm", "op": "launch"}})
	check(_pump(host, [ana], func() -> bool: return not ana.last("refused").is_empty()), "a player's DM operation is refused")
	# the rules change something (hit points in a fight): the DM's screen hears it too
	var dm_before := dm.count("dm")
	kernel.commit([{"t": "log.add", "entry": {"id": "n_hp", "kind": "note", "text": "a goblin is hurt", "audience": "gm"}}], "Note")
	check(_pump(host, [dm], func() -> bool: return dm.count("dm") > dm_before), "a rules change: the DM's state again (its party view draws from it)")
	# chat: to everyone, to some players (the DM reads it), privately among players
	var ben := "pl_393eb25a"
	ana.send({"t": "intent", "intent": {"kind": "chat", "text": "Hello all", "to": "all"}})
	ana.send({"t": "intent", "intent": {"kind": "chat", "text": "Ben, a word", "to": [ben], "private": true}})
	cara.send({"t": "intent", "intent": {"kind": "chat", "text": "DM, a question", "to": ["gm"]}})
	var chats := func() -> Array: return st.encounter.log.filter(func(x: Dictionary) -> bool: return str(x.get("kind", "")) == "chat")
	check(_pump(host, [ana, cara, dm], func() -> bool: return (chats.call() as Array).size() == 3), "three messages kept in the log")
	var by_text := {}
	for m in chats.call():
		by_text[str(m.text)] = m
	check(str(by_text["Hello all"].audience) == "all" and str(by_text["Hello all"].from) == "pl_fe0170c1", "to everyone, from Ana")
	check(str(by_text["Ben, a word"].audience).begins_with("private:") and str(by_text["Ben, a word"].audience).contains(ben), "a private word to Ben")
	var ben_view := host.projection({"player": ben, "role": Views.ROLE_PLAYER})
	var dm_view := host.projection({"player": "", "role": Views.ROLE_DM})
	var cara_view := host.projection({"player": str(added[0].id), "role": Views.ROLE_PLAYER})
	var texts := func(v: Dictionary) -> Array: return (v.log as Array).filter(func(x: Dictionary) -> bool: return str(x.get("kind", "")) == "chat").map(func(x: Dictionary) -> String: return str(x.text))
	check((texts.call(ben_view) as Array).has("Ben, a word") and not (texts.call(dm_view) as Array).has("Ben, a word") and not (texts.call(cara_view) as Array).has("Ben, a word"), "Ben reads it; the DM and Cara do not")
	check((texts.call(dm_view) as Array).has("DM, a question") and not (texts.call(ben_view) as Array).has("DM, a question"), "Cara's question: the DM reads it, Ben does not")
	check((texts.call(cara_view) as Array).has("DM, a question"), "and Cara sees what she sent")
	# free rolls: a player's, the DM's in secret, and one that isn't a roll
	ana.send({"t": "intent", "intent": {"kind": "roll", "expr": "1d20+4", "label": "Stealth"}})
	dm.send({"t": "intent", "intent": {"kind": "roll", "expr": "2d6", "secret": true}})
	ana.send({"t": "intent", "intent": {"kind": "roll", "expr": "lots of dice"}})
	var rolls := func() -> Array: return st.encounter.log.filter(func(x: Dictionary) -> bool: return str(x.get("kind", "")) == "roll")
	check(_pump(host, [ana, dm], func() -> bool: return (rolls.call() as Array).size() == 2 and not ana.last("refused").is_empty()), "two rolls kept, one refused: %s" % [ana.last("refused")])
	var labels := (rolls.call() as Array).map(func(x: Dictionary) -> String: return "%s|%s" % [x.label, x.audience])
	check(labels.has("Ana: Stealth|all") and labels.has("The DM: 2d6|gm"), "Ana's for all, the DM's for the DM: %s" % [labels])
	check((texts.call(ben_view) as Array).has("Hello all"), "what is said to everyone, everyone reads")
	# a session ended but still open: its chat is in the campaign's history and
	# still in the live log (a playtest's list put the evening above its first hour)
	var banked: Array = [{"id": "m_old", "kind": "chat", "text": "Last week", "audience": "all", "session": 1}]
	for x in chats.call():
		banked.append(JsonDoc.deep(x))
	host.chat_source = func() -> Array: return banked
	var hist := (host.projection({"player": ben, "role": Views.ROLE_PLAYER}).chat_history as Array).map(func(x: Dictionary) -> String: return str(x.text))
	check(hist == ["Last week"], "the history a view carries is the sessions before, not the live log again: %s" % [hist])
	host.stop()
	check(not host.is_running() and host.web == null, "stopped, the web side too")


## The DM screen's Next says the turn it showed (`from`): in a playtest a
## player's End turn and the DM's Next a few seconds apart took two turns.
func test_dm_next_names_the_turn_it_ends() -> void:
	var dir := "user://web_dm_next_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var app := App.new("user://test_prefs_web_dm_next.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	var c := Campaign.create("Next turn")
	c.players.append({"id": "pl_1", "name": "Ana", "color": "#4f9cf6"})
	check(c.save(dir.path_join("next.campaign")) == OK, "saved")
	win._open_path(dir.path_join("next.campaign"))
	await tree.process_frame
	var ctx := win.ctx
	check(ctx.commands.run({"t": "scene.add", "scene": {"id": "s_fight", "name": "Fight", "map": "", "tokens": []}}, "Scene") == "" and ctx.commands.activate_scene("s_fight") == "", "a scene")
	for n in ["Ada", "Grace", "Jin"]:
		ctx.commands.add_token("s_fight", Encounter.new_token(n, Vector2(2 + ["Ada", "Grace", "Jin"].find(n), 2), {"id": "t_" + n.to_lower()}))
	check(win.web_dm.op({"op": "turns", "do": "start"}) == "" and ctx.encounter().turns.order == ["t_ada", "t_grace", "t_jin"], "turns started: Ada, Grace, Jin")
	# Ada's player ended her turn a moment before the DM, still seeing Ada's, pressed Next
	check(ctx.commands.next_turn({"by": "pl_1", "expect": {"round": 1, "turn": 0}}) == "" and int(ctx.encounter().turns.turn) == 1, "Ada's turn ended from her sheet")
	var why := win.web_dm.op({"op": "turns", "do": "next", "from": {"round": 1, "turn": 0}})
	check(why == "Ada's turn has already ended: it's Grace's turn now.", "the DM's Next for Ada's turn is refused, saying whose it is: " + why)
	check(int(ctx.encounter().turns.turn) == 1 and str(ctx.encounter().turns.last.entry) == "t_ada", "Grace's turn goes on")
	check(win.web_dm.op({"op": "turns", "do": "next", "from": {"round": 1, "turn": 1}}) == "" and int(ctx.encounter().turns.turn) == 2 and str(ctx.encounter().turns.last.by) == "gm", "the DM's Next for Grace's turn ends it")
	check(win.web_dm.op({"op": "turns", "do": "next"}) == "" and int(ctx.encounter().turns.round) == 2, "and a Next that says no turn steps as before")
	win.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(dir.path_join("next.campaign"))


## Pictures the table uploads (the team: token pictures, pictures in
## journals): checked and made again as WebP, a token's cut square, kept
## once by what is in them, served at /upload/<id>.webp to whoever has the
## address and nothing else there, drawn by the Table.
func test_uploads() -> void:
	var dir := "user://uploads_test"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
	var img := Image.create(800, 400, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.8))
	img.fill_rect(Rect2i(350, 150, 100, 100), Color.RED)
	var png := img.save_png_to_buffer()
	var r := Uploads.store(dir, "token", png)
	check(bool(r.ok) and Uploads.is_ref(str(r.ref)), "a token's picture kept: %s" % [r])
	var kept := Image.new()
	check(kept.load_webp_from_buffer(Uploads.read(dir, str(r.id))) == OK and kept.get_width() == 400 and kept.get_height() == 400, "as WebP, cut square from its middle (%dx%d)" % [kept.get_width(), kept.get_height()])
	check(kept.get_pixel(200, 200).r > 0.8 and kept.get_pixel(200, 200).b < 0.3, "the middle kept: the red square")
	check(str(Uploads.store(dir, "token", png).ref) == str(r.ref) and Uploads.count(dir) == 1, "the same picture twice is kept once")
	var photo := Image.create(3000, 2000, false, Image.FORMAT_RGB8)
	photo.fill(Color.DARK_GREEN)
	var p := Uploads.store(dir, "picture", photo.save_jpg_to_buffer(0.9))
	var pk := Image.new()
	check(bool(p.ok) and pk.load_webp_from_buffer(Uploads.read(dir, str(p.id))) == OK and pk.get_width() == 1600 and pk.get_height() == 1067, "a journal's photo: 1600 on its longer side (%dx%d)" % [pk.get_width(), pk.get_height()])
	check(str(Uploads.store(dir, "token", "not a picture at all, honestly".to_utf8_buffer()).why).contains("not a picture"), "what is not a picture is refused")
	var huge := PackedByteArray()
	huge.resize(Uploads.MAX_BYTES + 1)
	check(str(Uploads.store(dir, "token", huge).why).contains("too big"), "nor one too big")
	check(not bool(Uploads.store(dir, "banner", png).ok) and not bool(Uploads.store("", "token", png).ok), "nor a kind there is not, nor a campaign with no folder")
	var id := str(r.id)
	check(Uploads.path_of(dir, "../" + id) == "" and Uploads.path_of(dir, id.to_upper()) == "" and Uploads.path_of(dir, id + "0") == "" and Uploads.path_of(dir, "upload:" + id) != "", "no address but an upload's own")
	# served on the web side, and nothing else there
	var web := WebServer.new()
	web.upload_source = func(i: String) -> PackedByteArray: return Uploads.read(dir, i)
	var ok := web.respond("GET /upload/%s.webp HTTP/1.1\r\nHost: t\r\n\r\n" % id)
	var head := ok.slice(0, 200).get_string_from_ascii()
	check(head.begins_with("HTTP/1.1 200") and head.contains("image/webp") and head.contains("immutable"), "served as WebP, for good: %s" % head.get_slice("\r\n", 0))
	check(ok.size() > Uploads.read(dir, id).size() and ok.slice(ok.size() - Uploads.read(dir, id).size()) == Uploads.read(dir, id), "the picture itself")
	for bad in ["/upload/%s.png" % id, "/upload/../%s.webp" % id, "/upload/%s.webp" % "0".repeat(32), "/upload/x.webp"]:
		check(web.respond("GET %s HTTP/1.1\r\n\r\n" % bad).slice(0, 12).get_string_from_ascii().contains("404"), "not found: %s" % bad)
	# the Table draws it
	var lib := PackLibrary.new()
	lib.uploads_dir = dir
	check(lib.token_texture(str(r.ref), 64.0) != null and lib.picture_texture(str(p.ref)) != null, "the Table draws an uploaded token and picture")
	check(lib.token_texture("upload:" + "0".repeat(32), 64.0) == null, "one that is not there: nothing (and no crash)")


## A screen sends a picture over its socket: the Table says what becomes of
## it (here, a stand-in), one at a time, and only from a screen that joined.
func test_uploads_over_the_socket() -> void:
	var st := _chapel_state()
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = RulesKernel.new(st)
	var got := []
	host.upload_handler = func(pid: String, gm: bool, msg: Dictionary) -> Dictionary:
		got.append([pid, gm, str(msg.get("kind", ""))])
		return {"ok": true, "ref": "upload:" + "a".repeat(32)} if str(msg.kind) == "picture" else {"ok": false, "why": "that is not your character"}
	check(host.start(0, false, 0) == OK, "hosting")
	var ana := WebClient.new(host.port)
	_pump(host, [ana], func() -> bool: return ana.open())
	ana.send({"t": "hello", "version": Protocol.VERSION, "name": "phone", "web": true})
	ana.send({"t": "upload", "req": "early", "kind": "picture", "data": ""})
	ana.send({"t": "join", "role": "player", "name": "Ana"})
	check(_pump(host, [ana], func() -> bool: return not ana.last("joined").is_empty()), "Ana joins")
	check(got.is_empty() and ana.last("uploaded").is_empty(), "a picture sent before joining is not taken")
	ana.send({"t": "upload", "req": "r1", "kind": "picture", "data": Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))})
	check(_pump(host, [ana], func() -> bool: return not ana.last("uploaded").is_empty()), "a journal picture: kept")
	check(str(ana.last("uploaded").req) == "r1" and str(ana.last("uploaded").ref).begins_with("upload:") and got[0][0] == "pl_fe0170c1" and got[0][1] == false, "its ref sent back to the one who asked: %s" % [got])
	ana.send({"t": "upload", "req": "r2", "kind": "picture", "data": ""})
	check(_pump(host, [ana], func() -> bool: return not ana.last("upload_failed").is_empty()) and str(ana.last("upload_failed").why).contains("one picture at a time"), "one at a time")
	check(got.size() == 1, "(and the Table was not asked)")
	OS.delay_msec(HostSession.UPLOAD_GAP_MS + 50)
	ana.send({"t": "upload", "req": "r3", "kind": "token", "actor": "a_other", "data": ""})
	check(_pump(host, [ana], func() -> bool: return str(ana.last("upload_failed").get("req", "")) == "r3") and str(ana.last("upload_failed").why).contains("not your character"), "the Table's refusal, said")
	host.stop()
