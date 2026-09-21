class_name HostSession
extends RefCounted
## The Table's side of the network: a WebSocket server that hands every
## client the scene, tells them each scene event, sends each its own
## projection of the rules (a view) whenever those change, resolves their
## intents through the kernel and the plugins, answers their scene requests
## through the Table's own commands (so a player's move is undoable and
## explores fog like any other), and streams maps and pack files to
## clients that lack them. Announces itself on the LAN. Authority lives
## here: nothing a client sends is applied unless the rules say so.

signal client_joined(player_id: String)
signal client_left(player_id: String)
signal log(text: String)

var state: EncounterState
var packs: PackLibrary
## The rules engine and plugins behind the views and intents (optional:
## without them clients get scene events only and every intent is refused).
var kernel: RulesKernel
var plugins: PluginHost
## Called with (event, player_id) to apply an allowed request; returns ""
## or why not. The Table hands in its commands so history sees it.
var apply_request: Callable
var port := 0
var announcer := Discovery.Announcer.new()
var _server := TCPServer.new()
var _clients: Array = []   # [{peer: WebSocketPeer, player: "", role: "", hello: false, joined: false}]
var _listening := false
var _views_dirty := false


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
			_clients.append({"peer": peer, "player": "", "role": "", "hello": false, "joined": false})
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
	if _views_dirty:
		_views_dirty = false
		for c in _clients:
			if c.joined:
				_send_view(c)


func _player_name(pid: String) -> String:
	return str(state.encounter.player(pid).get("name", pid))


func _send(c: Dictionary, msg: Dictionary) -> void:
	(c.peer as WebSocketPeer).send_text(Protocol.encode(msg))


func _broadcast(msg: Dictionary) -> void:
	for c in _clients:
		if c.hello:
			_send(c, msg)


## Scene events go to every client as they are; anything about the rules
## changes what each client is shown, so their views are resent (once per
## poll, however many events a step applied).
func _on_applied(ev: Dictionary, _inv: Dictionary) -> void:
	var t := str(ev.get("t", ""))
	if Protocol.SCENE_EVENTS.has(t):
		_broadcast(Protocol.event(ev))
	if t == "turns.set" or not Protocol.SCENE_EVENTS.has(t):
		_views_dirty = true


## A client's projection of the rules, if there is a kernel to project.
func projection(c: Dictionary) -> Dictionary:
	if kernel == null:
		return {}
	return Views.project(kernel, plugins, str(c.player), str(c.role) if c.role != "" else Views.ROLE_PLAYER)


func _send_view(c: Dictionary) -> void:
	if kernel != null:
		_send(c, Protocol.view(projection(c)))


func _handle(c: Dictionary, msg: Dictionary) -> void:
	var t := str(msg.t)
	if not c.hello and t != "hello":
		_send(c, Protocol.error("say hello first"))
		return
	match t:
		"hello":
			if int(msg.get("version", 0)) != Protocol.VERSION:
				var why := "this table speaks protocol %d, you speak %d" % [Protocol.VERSION, int(msg.get("version", 0))]
				_send(c, Protocol.error(why))
				# the close reason carries it too: a client may see the close before the packet
				(c.peer as WebSocketPeer).close(1002, why.left(120))
				return
			c.hello = true
			c.name = str(msg.get("name", ""))
			_send(c, Protocol.welcome(state.encounter))
		"join":
			var pid := str(msg.get("player", ""))
			var role := str(msg.get("role", Views.ROLE_PLAYER))
			if not Protocol.ROLES.has(role):
				_send(c, Protocol.error("unknown role '%s'" % role))
				return
			if role == Views.ROLE_PLAYER and state.encounter.player(pid).is_empty():
				_send(c, Protocol.error("no such player"))
				return
			if role == Views.ROLE_DISPLAY:
				pid = ""
			if c.player != "":
				client_left.emit(c.player)
			c.player = pid
			c.role = role
			c.joined = true
			_send(c, {"t": "joined", "player": pid, "role": role})
			_send_view(c)
			log.emit("%s joined" % (_player_name(pid) if pid != "" else "a display (%s)" % str(c.get("name", ""))))
			if pid != "":
				client_joined.emit(pid)
		"intent":
			var intent = msg.get("intent", {})
			if not (intent is Dictionary):
				_send(c, Protocol.intent_refused({}, "not an intent"))
				return
			var why := _handle_intent(c, intent)
			if why != "":
				_send(c, Protocol.intent_refused(intent, why))
		"request":
			var ev = msg.get("ev", {})
			if not (ev is Dictionary):
				_send(c, Protocol.refused({}, "not an event"))
				return
			if c.player == "" or c.role != Views.ROLE_PLAYER:
				_send(c, Protocol.refused(ev, "join as a player first"))
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


## Resolve a client's intent through the kernel. Displays may send none;
## a player may act only with actors they own, answer only prompts
## addressed to them, and ask for the focus only for what they own.
func _handle_intent(c: Dictionary, intent: Dictionary) -> String:
	if kernel == null:
		return "this table runs no rules"
	if c.role != Views.ROLE_PLAYER or c.player == "":
		return "only players may act"
	var pid := str(c.player)
	match str(intent.get("kind", "")):
		"action":
			if plugins == null:
				return "no plugins here"
			var plugin := str(intent.get("plugin", ""))
			var action := str(intent.get("action", ""))
			var ctx: Dictionary = intent.get("ctx", {}) if intent.get("ctx") is Dictionary else {}
			var p := plugins.plugin(plugin)
			if p == null or not p.actions.has(action):
				return "no action %s/%s" % [plugin, action]
			if ctx.has("actor") and not _owns_actor(pid, str(ctx.actor)):
				return "that is not your character"
			if ctx.has("token") and not _owns_token(pid, str(ctx.token)):
				return "that is not your token"
			var pc := plugins.dispatch(plugin, action, ctx)
			if pc.status == PluginHost.PluginCall.ERROR:
				return pc.error
			kernel.pending.drive(pc, plugin)
			return ""
		"answer":
			return kernel.pending.answer(str(intent.get("prompt", "")), intent.get("answer", {}), pid)
		"focus":
			var ref := str(intent.get("ref", ""))
			if ref.begins_with("actor:") and not _owns_actor(pid, ref.substr(6)):
				return "that is not your character"
			if ref.begins_with("token:") and not _owns_token(pid, ref.substr(6)):
				return "that is not your token"
			if not ref.begins_with("actor:") and not ref.begins_with("token:"):
				return "ask for the focus for one of your tokens or characters"
			return kernel.turns.request_focus(pid, ref)
		"contribute":
			return kernel.pending.contribute(str(intent.get("roll", "")), pid, str(intent.get("name", "")), str(intent.get("expr", "")))
		"character":
			# a player brings their own character: adopted as theirs, checked
			# by the rulesets like any actor
			var doc: Variant = intent.get("character")
			var why := CharacterFile.check(doc)
			if why != "":
				return why
			var actor := CharacterFile.to_actor(doc, pid)
			if state.encounter.actors.has(str(actor.id)):
				var have := state.encounter.actor(str(actor.id))
				if str(have.get("owner", "")) != pid:
					return "an actor with that id is already at the table"
				return kernel.commit([{"t": "actor.set", "id": str(actor.id), "changes": {"ext": actor.ext, "name": actor.name, "packs": actor.get("packs", {})}}], "Character updated", {"by": pid})
			if not actor.has("packs") or (actor.packs is Dictionary and (actor.packs as Dictionary).is_empty()):
				actor.packs = kernel.comp.versions()
			why = kernel.commit([{"t": "actor.add", "actor": actor}], "Character brought", {"by": pid})
			if why == "":
				log.emit("%s brought %s" % [_player_name(pid), str(actor.name)])
			return why
	return "unknown intent '%s'" % str(intent.get("kind", ""))


func _owns_actor(pid: String, actor_id: String) -> bool:
	return str(state.encounter.actor(actor_id).get("owner", "")) == pid and pid != ""


func _owns_token(pid: String, token_id: String) -> bool:
	var tk := state.find_token(token_id)
	if tk.is_empty():
		return false
	if tk.get("owner", null) != null and str(tk.owner) == pid:
		return true
	return _owns_actor(pid, str(tk.get("actor", "")))


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
