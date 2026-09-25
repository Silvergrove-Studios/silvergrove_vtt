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
	dm.send({"t": "intent", "intent": {"kind": "dm", "op": "launch", "encounter": "e1"}})
	check(_pump(host, [dm], func() -> bool: return ops.has("launch")), "the DM's operations reach the Table")
	var crypt := str(st.encounter.scenes[1].id)
	dm.send({"t": "intent", "intent": {"kind": "dm", "op": "view_scene", "scene": crypt}})
	check(_pump(host, [dm], func() -> bool: return str(dm.last("scene").scene.id) == crypt), "the DM looks at another scene; the players' stays")
	ana.send({"t": "intent", "intent": {"kind": "dm", "op": "launch"}})
	check(_pump(host, [ana], func() -> bool: return not ana.last("refused").is_empty()), "a player's DM operation is refused")
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
	check((texts.call(ben_view) as Array).has("Hello all"), "what is said to everyone, everyone reads")
	host.stop()
	check(not host.is_running() and host.web == null, "stopped, the web side too")
