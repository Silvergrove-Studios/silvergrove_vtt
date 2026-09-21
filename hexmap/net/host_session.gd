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
## What a co-GM must give to join: shown on the Table, four digits, new
## for every hosting. "" refuses co-GMs.
var cogm_code := ""
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
	cogm_code = "%04d" % (randi() % 10000)
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
			_send(c, Protocol.welcome(state.encounter, c.role == Views.ROLE_COGM))


func _is_gm(c: Dictionary) -> bool:
	return c.role == Views.ROLE_COGM


## The co-GMs joined right now.
func cogm_count() -> int:
	var n := 0
	for c in _clients:
		if c.joined and _is_gm(c):
			n += 1
	return n


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


func _broadcast(msg: Dictionary, gm_only := false) -> void:
	for c in _clients:
		if c.hello and (not gm_only or _is_gm(c)):
			_send(c, msg)


## Scene events go to every client as they are; anything about the rules
## changes what each client is shown, so their views are resent (once per
## poll, however many events a step applied).
func _on_applied(ev: Dictionary, inv: Dictionary) -> void:
	var t := str(ev.get("t", ""))
	if t == "checkpoint.restore":
		# the whole document changed under everyone: start them over
		for c in _clients:
			if c.hello:
				_send(c, Protocol.welcome(state.encounter, _is_gm(c)))
		_views_dirty = true
		return
	if Protocol.SCENE_EVENTS.has(t):
		_broadcast(Protocol.event(ev))
	elif Protocol.AUDIENCE_EVENTS.has(t):
		# co-GMs hold the scene whole: every region and cell event as it is
		_broadcast(Protocol.event(ev), true)
		for msg in _audience_events(ev, inv):
			for c in _clients:
				if c.hello and not _is_gm(c):
					_send(c, Protocol.event(msg))
	if t == "turns.set" or not Protocol.SCENE_EVENTS.has(t):
		_views_dirty = true


## Regions and cells reach players only as far as their audience allows:
## a GM-only region is never sent, one opened later arrives whole, one
## closed is removed; a cell's record and plugin state follow its
## `revealed` flag.
func _audience_events(ev: Dictionary, inv: Dictionary) -> Array:
	var t := str(ev.get("t", ""))
	var scene_id := str(ev.get("scene", ""))
	match t:
		"region.add":
			return [ev] if str(ev.region.get("audience", "all")) != "gm" else []
		"region.remove":
			return [ev] if str(inv.get("region", {}).get("audience", "all")) != "gm" else []
		"region.set":
			var now: Dictionary = state.encounter.scene(scene_id).regions.get(str(ev.id), {})
			var was_gm := str(inv.get("changes", {}).get("audience", now.get("audience", "all"))) == "gm"
			var is_gm := str(now.get("audience", "all")) == "gm"
			if is_gm:
				return [{"t": "region.remove", "scene": scene_id, "id": str(ev.id)}] if not was_gm else []
			if was_gm:
				return [{"t": "region.add", "scene": scene_id, "region": JsonDoc.deep(now)}]
			return [ev]
		"cell.set", "ext.set":
			if t == "ext.set" and str(ev.get("scope", "")) != "cell":
				return []
			var cell: Dictionary = state.encounter.scene(scene_id).get("cells", {}).get(str(ev.id), {})
			if not bool(cell.get("revealed", false)):
				return []
			# the whole cell as it is now, so a cell just revealed arrives complete
			var out := []
			var plain: Dictionary = JsonDoc.deep(cell)
			plain.erase("ext")
			if not plain.is_empty():
				out.append({"t": "cell.set", "scene": scene_id, "id": str(ev.id), "changes": plain})
			for pid in cell.get("ext", {}):
				out.append({"t": "ext.set", "scope": "cell", "scene": scene_id, "id": str(ev.id), "plugin": str(pid), "changes": JsonDoc.deep(cell.ext[pid])})
			return out
	return []


## A client's projection of the rules, if there is a kernel to project.
func projection(c: Dictionary) -> Dictionary:
	if kernel == null:
		return {}
	if _is_gm(c):
		return Views.project(kernel, plugins, "", Views.ROLE_GM)
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
			if role == Views.ROLE_COGM and (cogm_code == "" or str(msg.get("code", "")) != cogm_code):
				_send(c, Protocol.error("co-GMs join with the code shown on the table"))
				return
			if role != Views.ROLE_PLAYER:
				pid = ""
			if c.player != "":
				client_left.emit(c.player)
			c.player = pid
			c.role = role
			c.joined = true
			if role == Views.ROLE_COGM:
				# the whole scene, now that they may see it
				_send(c, Protocol.welcome(state.encounter, true))
			_send(c, {"t": "joined", "player": pid, "role": role})
			_send_view(c)
			var who := _player_name(pid) if pid != "" else ("a co-GM (%s)" if role == Views.ROLE_COGM else "a display (%s)") % str(c.get("name", ""))
			log.emit("%s joined" % who)
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
			if not _is_gm(c) and (c.player == "" or c.role != Views.ROLE_PLAYER):
				_send(c, Protocol.refused(ev, "join as a player first"))
				return
			# a co-GM may ask for any scene event the Table itself could apply
			if not _is_gm(c) and not state.allowed(ev, c.player):
				_send(c, Protocol.refused(ev, "not allowed"))
				return
			var why := state.validate(ev)
			if why == "":
				why = str(apply_request.call(ev, "" if _is_gm(c) else c.player)) if apply_request.is_valid() else _apply_plain(ev)
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
	if not _is_gm(c) and (c.role != Views.ROLE_PLAYER or c.player == ""):
		return "only players may act"
	var pid := str(c.player)
	var gm := _is_gm(c)
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
			if not gm and ctx.has("actor") and not _owns_actor(pid, str(ctx.actor)):
				return "that is not your character"
			if not gm and ctx.has("token") and not _owns_token(pid, str(ctx.token)):
				return "that is not your token"
			# a target picked on the map must be one this viewer may pick
			var kind := str(p.actions[action].get("target", ""))
			if kind in ["token", "cell", "area"]:
				var sc := str(ctx.get("scene", state.encounter.active_scene_id))
				var why_t := PluginHost.check_target(state, sc, kind, ctx.get("target"), gm)
				if why_t != "":
					return why_t
				ctx = ctx.duplicate()
				ctx.scene = sc
			# who sent it, from the connection — never from the wire
			ctx = ctx.duplicate()
			ctx.player = "" if gm else pid
			ctx.gm = gm
			var pc := plugins.dispatch(plugin, action, ctx)
			if pc.status == PluginHost.PluginCall.ERROR:
				return pc.error
			kernel.pending.drive(pc, plugin)
			return ""
		"answer":
			# a co-GM answers on anyone's behalf, as the Table would
			return kernel.pending.answer(str(intent.get("prompt", "")), intent.get("answer", {}), "" if gm else pid)
		"focus":
			var ref := str(intent.get("ref", ""))
			if gm:
				return kernel.turns.set_focus(ref, "gm")
			if ref.begins_with("actor:") and not _owns_actor(pid, ref.substr(6)):
				return "that is not your character"
			if ref.begins_with("token:") and not _owns_token(pid, ref.substr(6)):
				return "that is not your token"
			if not ref.begins_with("actor:") and not ref.begins_with("token:"):
				return "ask for the focus for one of your tokens or characters"
			return kernel.turns.request_focus(pid, ref)
		"gm":
			# the GM's own verbs, for a co-GM: next turn, checkpoints, triggers, bulk
			if not gm:
				return "only the GM does that"
			return _gm_intent(intent)
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


## What a co-GM may drive besides actions: {op: next|previous|checkpoint|restore|trigger|bulk, …}.
func _gm_intent(intent: Dictionary) -> String:
	match str(intent.get("op", "")):
		"next": return kernel.turns.next()
		"previous": return kernel.turns.previous()
		"checkpoint": return "" if kernel.checkpoint(str(intent.get("name", "Checkpoint"))) != "" else "could not mark"
		"restore": return kernel.restore_checkpoint(str(intent.get("id", "")))
		"trigger": return kernel.fire_trigger(str(intent.get("scene", state.encounter.active_scene_id)), str(intent.get("trigger", "")))
		"bulk":
			var r := Bulk.run(kernel, Array(intent.get("targets", [])), intent.get("op_spec", {}) if intent.get("op_spec") is Dictionary else {}, str(intent.get("label", "")))
			return r.why
	return "unknown gm op '%s'" % str(intent.get("op", ""))


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
		"asset":
			# a map's own file: only what the document refers to
			var mid := str(msg.get("map", ""))
			var file := str(msg.get("file", ""))
			var m: HexMap = state.maps.get(mid)
			if m == null or not m.asset_refs().has(file):
				_send(c, Protocol.error("no asset %s in map %s" % [file, mid]))
				return
			var bytes := m.asset_bytes(file)
			if bytes.is_empty():
				_send(c, Protocol.error("asset %s is missing on the table" % file))
				return
			_send(c, {"t": "asset", "map": mid, "file": file, "data": Marshalls.raw_to_base64(bytes)})
		"comp":
			# the compendium, as this viewer may see it: a page or an entry
			var coll := str(msg.get("collection", ""))
			var out := {"t": "comp", "req": str(msg.get("req", "")), "collection": coll}
			if kernel == null or coll == "":
				out.error = "no compendium here"
			elif msg.has("id"):
				var e := kernel.comp.entry_for(coll, str(msg.id), _is_gm(c))
				if e.is_empty():
					out.error = "no such entry"
				else:
					out.entry = e
			else:
				var q: Dictionary = msg.get("query", {}) if msg.get("query") is Dictionary else {}
				out.page = kernel.comp.query_for(coll, q, _is_gm(c))
			_send(c, out)
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
