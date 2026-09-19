class_name HostSession
extends RefCounted
## The Table's side of the network: a WebSocket server that hands every
## client the encounter, tells them each applied event, answers their
## requests through the Table's own commands (so a player's move is undoable
## and explores fog like any other), and streams maps and pack files to
## clients that lack them. Announces itself on the LAN. Authority lives
## here: a request is applied only if allowed() and validate() say so.

signal client_joined(player_id: String)
signal client_left(player_id: String)
signal log(text: String)

var state: EncounterState
var packs: PackLibrary
## Called with (event, player_id) to apply an allowed request; returns ""
## or why not. The Table hands in its commands so history sees it.
var apply_request: Callable
var port := 0
var announcer := Discovery.Announcer.new()
var _server := TCPServer.new()
var _clients: Array = []   # [{peer: WebSocketPeer, player: "", hello: false}]
var _listening := false


func _init(p_state: EncounterState, p_packs: PackLibrary) -> void:
	state = p_state
	packs = p_packs


## Listen on `p_port` (0 for any free port) and start announcing.
func start(p_port := Protocol.DEFAULT_PORT, announce := true) -> Error:
	var err := _server.listen(p_port)
	if err != OK and p_port != 0:
		# Busy: the OS may hand us another.
		err = _server.listen(0)
	if err != OK:
		return err
	port = _server.get_local_port()
	_listening = true
	state.applied.connect(_on_applied)
	if announce:
		announcer.start(state.encounter.name, port)
	log.emit("Hosting on port %d" % port)
	return OK


func stop() -> void:
	if not _listening:
		return
	for c in _clients:
		(c.peer as WebSocketPeer).close()
	_clients.clear()
	_server.stop()
	announcer.stop()
	if state.applied.is_connected(_on_applied):
		state.applied.disconnect(_on_applied)
	_listening = false
	log.emit("Stopped hosting")


func is_running() -> bool:
	return _listening


## The encounter's name changed, or another one was opened: tell the LAN.
func set_state(p_state: EncounterState) -> void:
	if state != null and state.applied.is_connected(_on_applied):
		state.applied.disconnect(_on_applied)
	state = p_state
	if _listening:
		state.applied.connect(_on_applied)
		announcer.name = state.encounter.name
		for c in _clients:
			_send(c, Protocol.welcome(state.encounter))


## Player ids of clients that have joined.
func connected_players() -> Array:
	var out := []
	for c in _clients:
		if c.player != "":
			out.append(c.player)
	return out


func client_count() -> int:
	return _clients.size()


## Pump the server and every client. Call every frame.
func poll(delta := 0.0) -> void:
	if not _listening:
		return
	announcer.poll(delta)
	while _server.is_connection_available():
		var peer := WebSocketPeer.new()
		peer.inbound_buffer_size = Protocol.BUFFER_SIZE
		peer.outbound_buffer_size = Protocol.BUFFER_SIZE
		peer.max_queued_packets = 4096
		if peer.accept_stream(_server.take_connection()) == OK:
			_clients.append({"peer": peer, "player": "", "hello": false})
	var gone := []
	for c in _clients:
		var peer: WebSocketPeer = c.peer
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					var msg := Protocol.decode(peer.get_packet().get_string_from_utf8())
					if not msg.is_empty():
						_handle(c, msg)
			WebSocketPeer.STATE_CLOSED:
				gone.append(c)
	for c in gone:
		_clients.erase(c)
		if c.player != "":
			log.emit("%s left" % _player_name(c.player))
			client_left.emit(c.player)


func _player_name(pid: String) -> String:
	return str(state.encounter.player(pid).get("name", pid))


func _send(c: Dictionary, msg: Dictionary) -> void:
	(c.peer as WebSocketPeer).send_text(Protocol.encode(msg))


func _broadcast(msg: Dictionary) -> void:
	for c in _clients:
		if c.hello:
			_send(c, msg)


func _on_applied(ev: Dictionary, _inv: Dictionary) -> void:
	_broadcast(Protocol.event(ev))


func _handle(c: Dictionary, msg: Dictionary) -> void:
	var t := str(msg.t)
	if not c.hello and t != "hello":
		_send(c, Protocol.error("say hello first"))
		return
	match t:
		"hello":
			if int(msg.get("version", 0)) != Protocol.VERSION:
				_send(c, Protocol.error("this table speaks protocol %d, you speak %d" % [Protocol.VERSION, int(msg.get("version", 0))]))
				(c.peer as WebSocketPeer).close()
				return
			c.hello = true
			c.name = str(msg.get("name", ""))
			_send(c, Protocol.welcome(state.encounter))
		"join":
			var pid := str(msg.get("player", ""))
			if state.encounter.player(pid).is_empty():
				_send(c, Protocol.error("no such player"))
				return
			if c.player != "":
				client_left.emit(c.player)
			c.player = pid
			_send(c, {"t": "joined", "player": pid})
			log.emit("%s joined" % _player_name(pid))
			client_joined.emit(pid)
		"request":
			var ev = msg.get("ev", {})
			if not (ev is Dictionary):
				_send(c, Protocol.refused({}, "not an event"))
				return
			if c.player == "":
				_send(c, Protocol.refused(ev, "join first"))
				return
			if not state.allowed(ev, c.player):
				_send(c, Protocol.refused(ev, "not allowed"))
				return
			var why := state.validate(ev)
			if why == "":
				why = str(apply_request.call(ev, c.player)) if apply_request.is_valid() else _apply_plain(ev)
			if why != "":
				_send(c, Protocol.refused(ev, why))
		"need":
			_serve(c, msg)
		"ping":
			_send(c, {"t": "pong"})


func _apply_plain(ev: Dictionary) -> String:
	state.apply(ev)
	return ""


## Maps and pack files a client asks for.
func _serve(c: Dictionary, msg: Dictionary) -> void:
	match str(msg.get("kind", "")):
		"map":
			var id := str(msg.get("id", ""))
			var m: HexMap = state.maps.get(id)
			if m == null:
				_send(c, Protocol.error("no map " + id))
				return
			_send(c, {"t": "map", "id": id, "doc": m.doc})
		"packs":
			_send(c, {"t": "packs", "packs": pack_listing()})
		"file":
			var pack := str(msg.get("pack", ""))
			var file := str(msg.get("file", ""))
			var dir := packs.pack_dir(pack)
			if dir == "" or file.contains("..") or file.begins_with("/") or not packs.pack_files(pack).has(file):
				_send(c, Protocol.error("no file %s in pack %s" % [file, pack]))
				return
			var bytes := FileAccess.get_file_as_bytes(dir.path_join(file))
			_send(c, {"t": "file", "pack": pack, "file": file, "data": Marshalls.raw_to_base64(bytes)})


## The packs the encounter's maps use, with their file lists.
func pack_listing() -> Array:
	var ids := {}
	for id in state.maps:
		for p in (state.maps[id] as HexMap).doc.get("packs", {}):
			ids[str(p)] = true
	var out := []
	for id in ids:
		if packs.pack_dir(id) == "":
			continue
		out.append({"id": id, "version": packs.pack_version(id), "manifest": packs.manifest(id), "files": Array(packs.pack_files(id))})
	return out
