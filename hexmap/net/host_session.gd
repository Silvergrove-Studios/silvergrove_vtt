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
## The table as it happens, for a run to be read back from (tools/web_host.gd
## --log): each message a screen sends (who, what), each refusal the table
## answers with, each change it applies. Nothing is built unless a log listens.
signal traced(entry: Dictionary)

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
## What the campaign has shared before this session (its journal's
## handouts): each client's view carries the entries it may see, so a
## player's Journal keeps what the DM has shown them. Set by the Table.
var journal_source: Callable = Callable()
## The players' own notes (PlayerNotes), kept by the campaign: the live
## array, which a player's note intent changes. Set by the Table, with
## `notes_changed`, called after a change so the campaign is saved.
var notes_source: Callable = Callable()
var notes_changed: Callable = Callable()
## The web clients' HTTP side (WebServer): their files, art and map files.
var web: WebServer
## What the DM's own web screen gives to join as the DM: made by the Table,
## put in the address it opens on this machine. "" refuses it.
var dm_token := ""
## (event: Dictionary) -> String: add a player who joined by name (the
## Table runs it as a command). Without it the event is applied as is.
var add_player: Callable = Callable()
## (intent: Dictionary) -> String: a DM operation from the web DM screen.
var dm_handler: Callable = Callable()
## () -> Dictionary: what the web DM screen shows of the campaign.
var dm_state_source: Callable = Callable()
## () -> Array: the chat banked from sessions before (the campaign's).
var chat_source: Callable = Callable()
## () -> Dictionary: how the table runs, as the players are told it (the
## level in plain words, where fights happen, the answers they notice, the
## house rules: TableSettings.player_summary). Every view carries it.
var table_source: Callable = Callable()
## (map_id: String) -> String: what the campaign has a map as, "battle" or
## "regional" ("" when it doesn't say): a web scene says it as `role`, and
## on the region a player's spell is cast with no target to tap.
var map_role: Callable = Callable()
## Where the campaign keeps the pictures the table uploads ("" for none).
var uploads_dir := ""
## (player_id: String, gm: bool, msg: Dictionary) -> {ok, ref, why}: a
## picture a screen sent (a token's, a journal's), kept and put to use.
var upload_handler: Callable = Callable()
## The least time between one screen's uploads.
const UPLOAD_GAP_MS := 1500
## The least time between one screen's "typing"s that are passed on (the
## web screens say it at most every three seconds).
const TYPING_GAP_MS := 1000
## The table's shared marks — rulers, templates, previews, pings (Marks):
## the Table hands in its own before hosting; never the encounter's.
var marks := Marks.new()
## A mark changed is sent on at most this often (a ruler being dragged: the
## screens send it ten times a second); what came between goes with the next.
const MARK_GAP_MS := 66
## One screen's marks are taken at most this often; one sent sooner waits
## (the newest of each), so a screen can't flood the Table with rulers.
const MARK_IN_GAP_MS := 40
## The DM's marks' colour.
const DM_COLOR := "#ffffff"
var _mark_sent_ms: Dictionary = {}   # id -> when last sent
var _mark_pending: Dictionary = {}   # id -> true: changed since, waiting its turn
var _marks_recheck := false          # the scene changed: who sees which mark, again
var _sight: Dictionary = {}          # "player|scene" -> what their characters see (cleared on change)
## How much of the sessions before a view carries (the newest).
const CHAT_HISTORY_SENT := 400
var _server := TCPServer.new()
var _clients: Array = []   # [{peer: WebSocketPeer, player: "", role: "", hello: false, joined: false, wire: Wire.Peer}]
var _listening := false
var _views_dirty := false
var _scenes_dirty := false
var _dm_dirty := false
var _last_dm_ms := 0
var _last_scene_ms := 0
## What the rules said the players know of a creature (its health, its name,
## its conditions) when the views were last refreshed (Knowledge's
## policies): another answer sends the scenes again.
var _known_was: Array = []
## A Godot player's document is to be sent again (a creature's name revealed,
## the creatures the players don't know numbered afresh): at the next poll.
var _docs_dirty := false

## Colours given to players who join by name, in turn. None is red: red is
## the creatures' (a playtest's player in red read as a goblin).
const PLAYER_COLORS := ["#4f9cf6", "#e67e22", "#2ecc71", "#a4d65e", "#9b59b6", "#f1c40f", "#1abc9c", "#ec87c0"]


func _init(p_state: EncounterState, p_packs: PackLibrary) -> void:
	state = p_state
	packs = p_packs


## Listen on `p_port` (0 for any free port) and start announcing; serve
## the web clients on `web_port` (-1: not at all).
func start(p_port := Protocol.DEFAULT_PORT, announce := true, web_port := WebServer.DEFAULT_PORT) -> Error:
	var err := _server.listen(p_port)
	if err != OK and p_port != 0:
		# Busy: the OS may hand us another.
		err = _server.listen(0)
	if err != OK:
		return err
	port = _server.get_local_port()
	_listening = true
	_known_was = _known()
	cogm_code = "%04d" % (randi() % 10000)
	state.applied.connect(_on_applied)
	if marks.state != state:
		marks.bind(state, kernel.map if kernel != null else null)
	marks.changed.connect(_on_mark_changed)
	marks.removed.connect(_on_mark_removed)
	if web_port >= 0:
		web = WebServer.new()
		web.art_source = func(pack: String, file: String) -> PackedByteArray:
			if packs == null or packs.pack_dir(pack) == "" or not packs.pack_files(pack).has(file):
				return PackedByteArray()
			return FileAccess.get_file_as_bytes(packs.pack_dir(pack).path_join(file))
		web.map_file_source = func(mid: String, file: String) -> PackedByteArray:
			var m: HexMap = state.maps.get(mid)
			return m.asset_bytes(file) if m != null and m.asset_refs().has(file) else PackedByteArray()
		web.config_source = func() -> Dictionary:
			return {"ws_port": port, "name": announcer.name, "protocol": Protocol.VERSION}
		web.upload_source = func(id: String) -> PackedByteArray:
			return Uploads.read(uploads_dir, id)
		if web.start(web_port) != OK:
			web = null
	if announce:
		announcer.web_port = web.port if web != null else 0
		announcer.start(state.encounter.name, port)
	log.emit("Hosting on port %d" % port + (", web on %d" % web.port if web != null else ""))
	return OK


func stop() -> void:
	if not _listening:
		return
	for c in _clients:
		(c.peer as WebSocketPeer).close()
	_clients.clear()
	_server.stop()
	if web != null:
		web.stop()
		web = null
	announcer.stop()
	if state.applied.is_connected(_on_applied):
		state.applied.disconnect(_on_applied)
	if marks.changed.is_connected(_on_mark_changed):
		marks.changed.disconnect(_on_mark_changed)
		marks.removed.disconnect(_on_mark_removed)
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
		# (the Table binds its own marks to the encounter it opens; a host on its own, its own)
		if marks.state != state:
			marks.bind(state, kernel.map if kernel != null else null)
		_sight.clear()
		for c in _clients:
			_send(c, _welcome(c))
			if c.joined:
				_send_marks(c)
		_scenes_dirty = true
		_dm_dirty = true


func _is_gm(c: Dictionary) -> bool:
	return c.role == Views.ROLE_COGM or c.role == Views.ROLE_DM


## What the rulesets loaded now say the players know of a creature no player
## owns — its health, its name, its conditions (Knowledge): each player's
## snapshot, document, token events, view and every message follow it.
func _known() -> Array:
	return kernel.knowledge_policies() if kernel != null else []


## What a screen knows, for the marks in what it is sent (Knowledge.knower).
func _knows_for(c: Dictionary) -> Callable:
	return Knowledge.knower(state.encounter.actors, _known(), _is_gm(c))


## The document a screen is sent as it says hello, joins, or the encounter
## changes under it: a Godot client's to hold, as it may (Protocol.welcome); a
## web screen's only the table's name and its players — it draws from its
## snapshots, never a document (it was sent every token, the hidden too).
func _welcome(c: Dictionary) -> Dictionary:
	if bool(c.get("web", false)):
		return Protocol.welcome_web(state.encounter)
	return Protocol.welcome(state.encounter, _is_gm(c), _known())


## What each screen holds of the scene, sent again as the rules loaded now
## would have it — a web screen's snapshot, a Godot player's document (a
## monster's marks and name, shown or kept from the players: Knowledge). The
## rules loaded again saying otherwise of what the players know do it
## (refresh_views); so does a creature's name revealed.
func refresh_scenes() -> void:
	_scenes_dirty = true
	_known_was = _known()
	_send_docs()


## A Godot player's document again, as they may hold it now (Knowledge).
func _send_docs() -> void:
	_docs_dirty = false
	for c in _clients:
		if c.hello and not _is_gm(c) and not bool(c.web):
			_send(c, Protocol.welcome(state.encounter, false, _known()))


## Is the client on this machine (the DM's own browser)?
static func is_local_address(ip: String) -> bool:
	var a := ip.strip_edges().to_lower()
	if a.begins_with("127."):
		return true
	if not a.contains(":"):
		return false
	# IPv6, however it is written: "::1", "0:0:0:0:0:0:0:1", "::ffff:127.0.0.1",
	# "0:0:0:0:0:ffff:7f00:1" (a browser on this computer asking for localhost)
	var tail := ""
	if a.get_slice(":", a.get_slice_count(":") - 1).contains("."):
		tail = a.get_slice(":", a.get_slice_count(":") - 1)
		a = a.left(a.length() - tail.length()) + "0:0"
	var parts := a.split("::")
	if parts.size() > 2:
		return false
	var head := parts[0].split(":", false)
	var rest := parts[1].split(":", false) if parts.size() == 2 else PackedStringArray()
	var groups := []
	for g in head:
		groups.append(g.hex_to_int())
	for i in 8 - head.size() - rest.size():
		groups.append(0)
	for g in rest:
		groups.append(g.hex_to_int())
	if groups.size() != 8:
		return false
	var zeros := func(n: int) -> bool:
		for i in n:
			if int(groups[i]) != 0:
				return false
		return true
	if zeros.call(7) and int(groups[7]) == 1:
		return true
	if zeros.call(5) and int(groups[5]) == 0xffff:
		return tail.begins_with("127.") if tail != "" else (int(groups[6]) >> 8) == 127
	return false


## The web address players open: one per network this machine is on.
func join_urls() -> PackedStringArray:
	return WebServer.urls(web.port) if web != null else PackedStringArray()


## The DM's web screen changed what it shows: send it again (soon).
func refresh_dm() -> void:
	_dm_dirty = true


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
	if web != null:
		web.poll()
	while _server.is_connection_available():
		var peer := WebSocketPeer.new()
		peer.inbound_buffer_size = Protocol.BUFFER_SIZE
		peer.outbound_buffer_size = Protocol.BUFFER_SIZE
		peer.max_queued_packets = 4096
		if peer.accept_stream(_server.take_connection()) == OK:
			# (wire: the schemas this connection holds, and the view, scene and DM
			# state it was sent last, so the next goes as what changed: Wire)
			_clients.append({"peer": peer, "player": "", "role": "", "hello": false, "joined": false, "web": false, "scene": "", "see_as": "", "wire": Wire.Peer.new()})
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
		# what they held, let go (a screen that went: the ruler they were dragging)
		var owner := _mark_owner(c)
		if owner != "" and not _clients.any(func(o: Dictionary) -> bool: return o.joined and _mark_owner(o) == owner):
			marks.let_go(owner)
	_poll_marks()
	_flush_views()
	# a Godot player's document again (a creature's name revealed, the creatures
	# the players don't know numbered afresh), once however many changes did it
	if _docs_dirty:
		_send_docs()
	# web clients get the scene whole, a few times a second at most
	if _scenes_dirty and Time.get_ticks_msec() - _last_scene_ms >= 50:
		_scenes_dirty = false
		_last_scene_ms = Time.get_ticks_msec()
		for c in _clients:
			if c.joined and bool(c.web):
				_send_scene(c)
	# (and the DM's screen its campaign state, as often)
	if _dm_dirty and Time.get_ticks_msec() - _last_dm_ms >= 150:
		_dm_dirty = false
		_last_dm_ms = Time.get_ticks_msec()
		for c in _clients:
			if c.joined and c.role == Views.ROLE_DM:
				_send_dm(c)


## Every joined client's view again, now, if the rules changed since the last.
func _flush_views() -> void:
	if not _views_dirty:
		return
	_views_dirty = false
	for c in _clients:
		if c.joined:
			_send_view(c)


func _player_name(pid: String) -> String:
	return str(state.encounter.player(pid).get("name", pid))


## Everything a screen is sent goes through here, as JSON text: the rulesets'
## marked words in it — a creature's name, its conditions — put right for that
## screen (Knowledge), whatever the message (a view, a refusal's why, the
## chat of sessions before, a card), so none reaches a screen that may not
## read them.
func _send(c: Dictionary, msg: Dictionary) -> void:
	var text := Protocol.encode(msg)
	if text.contains(Knowledge.ANCHOR) or text.contains(Knowledge.SEP) or text.contains(Knowledge.END):
		text = Knowledge.render_json(text, _knows_for(c), _is_gm(c))
	(c.peer as WebSocketPeer).send_text(text)
	if str(msg.get("t", "")) in ["refused", "error", "upload_failed"] and not traced.get_connections().is_empty():
		traced.emit({"dir": "out", "player": str(c.get("player", "")), "msg": msg})


## A screen saying its chat box holds something being written (_typing).
static func _is_typing(msg: Dictionary) -> bool:
	return str(msg.get("t", "")) == "intent" and msg.get("intent") is Dictionary and str(msg.intent.get("kind", "")) == "typing"


## A mark still held by its owner (a ruler being dragged).
static func _is_held_mark(msg: Dictionary) -> bool:
	return str(msg.get("t", "")) == "mark" and msg.get("mark") is Dictionary and bool(msg.mark.get("live", false))


## A message as the trace keeps it: an upload's picture by its size.
static func _traced_copy(msg: Dictionary) -> Dictionary:
	var out := msg.duplicate(true)
	if out.has("data") and out.data is String:
		out.data = "<%d characters>" % (out.data as String).length()
	return out


func _broadcast(msg: Dictionary, gm_only := false) -> void:
	for c in _clients:
		# (web clients hold no document: they get snapshots, not events)
		if bool(c.web) and str(msg.get("t", "")) == "event":
			continue
		if c.hello and (not gm_only or _is_gm(c)):
			_send(c, msg)


## Scene events go to every client as they are; anything about the rules
## changes what each client is shown, so their views are resent (once per
## poll, however many events a step applied).
func _on_applied(ev: Dictionary, inv: Dictionary) -> void:
	if not traced.get_connections().is_empty():
		traced.emit({"dir": "event", "ev": ev})
	# who sees what may have changed: the DM's marks are sent again where they now may be
	_sight.clear()
	_marks_recheck = true
	var t := str(ev.get("t", ""))
	if t == "checkpoint.restore":
		# the whole document changed under everyone: start them over
		for c in _clients:
			if c.hello:
				_send(c, _welcome(c))
		_views_dirty = true
		return
	var known := _known()
	if Protocol.SCENE_EVENTS.has(t):
		if (t == "token.add" or t == "token.set") and Knowledge.hides(known):
			# a monster as each may see it (Knowledge): the DM's whole, a player's
			# without what the players don't know — its health's marks, its
			# conditions' tags, its name (and the label they know it by)
			var sid := str(ev.get("scene", ""))
			var tid := str(ev.token.get("id", "")) if t == "token.add" and ev.get("token") is Dictionary else str(ev.get("id", ""))
			var now := state.token(sid, tid)
			var labels := Knowledge.player_labels(state.tokens(sid), state.encounter.actors, known)
			var mine := Protocol.event(Knowledge.player_event(ev, now, state.encounter.doc, known, str(labels.get(tid, ""))))
			for c in _clients:
				if c.hello and not bool(c.web):
					_send(c, Protocol.event(ev) if _is_gm(c) else mine)
			# one come, hidden or shown: the others the players don't know are numbered afresh
			var ch: Variant = ev.get("changes")
			if Knowledge.names_hidden(known) and (t == "token.add" or (ch is Dictionary and ((ch as Dictionary).has("hidden") or (ch as Dictionary).has("actor") or (ch as Dictionary).has("owner")))):
				_docs_dirty = true
		else:
			_broadcast(Protocol.event(ev))
		if t == "token.remove" and Knowledge.names_hidden(known):
			_docs_dirty = true
		# a note on the map shown to the players (or hidden again): their
		# devices get the map again, with it (or without it)
		if t == "element.set" and str(ev.get("ref", "")).begins_with("notes:"):
			var mid := str(state.encounter.scene(str(ev.get("scene", ""))).get("map", ""))
			for c in _clients:
				if c.hello and not _is_gm(c) and not bool(c.web) and state.maps.has(mid):
					_send(c, _map_msg(c, mid))
	elif Protocol.AUDIENCE_EVENTS.has(t):
		# co-GMs hold the scene whole: every region and cell event as it is
		_broadcast(Protocol.event(ev), true)
		for msg in _audience_events(ev, inv):
			for c in _clients:
				if c.hello and not _is_gm(c) and not bool(c.web):
					_send(c, Protocol.event(msg))
	if Protocol.SCENE_EVENTS.has(t) or Protocol.AUDIENCE_EVENTS.has(t) or t.begins_with("token.") or t == "checkpoint.restore":
		_scenes_dirty = true
	# a creature's hit points, on its token where the players see them exactly
	if t == "resource.set" and Knowledge.exact(known):
		_scenes_dirty = true
	# a creature's name revealed (or kept again), or who it is or whose: every
	# screen's scene and a Godot player's document follow (its name, the labels);
	# an effect on a creature whose conditions the players don't know: its tags
	if Knowledge.hides(known) and (t in ["actor.add", "actor.remove"] or (t == "actor.set" and _names_whom(ev)) or (t.begins_with("effect.") and Knowledge.conditions_hidden(known))):
		_scenes_dirty = true
		_docs_dirty = true
	if t == "turns.set" or not Protocol.SCENE_EVENTS.has(t):
		_views_dirty = true
		# the DM's screen draws the party (hit points, conditions) from its state too
		_dm_dirty = true
	# a picture shown: phones that lack its pack (one added since they joined) fetch it
	if t == "log.add" and str(ev.get("entry", {}).get("image", "")) != "":
		var listing := pack_listing()
		for c in _clients:
			if c.hello:
				_send(c, {"t": "packs", "packs": listing})


## Whether an actor's change touches who it is to the players: its name, its
## owner, its kind, its audience (a name revealed).
static func _names_whom(ev: Dictionary) -> bool:
	var ch: Variant = ev.get("changes")
	if not (ch is Dictionary):
		return false
	for k in ch:
		var root := str(k).get_slice("/", 0)
		if root in ["name", "owner", "kind", "audience"]:
			return true
	return false


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
	var pid := "" if _is_gm(c) else str(c.player)
	var role := Views.ROLE_GM if _is_gm(c) else (str(c.role) if c.role != "" else Views.ROLE_PLAYER)
	var out := Views.project(kernel, plugins, pid, role)
	out.notes = PlayerNotes.for_viewer(notes_source.call(), pid, role) if notes_source.is_valid() else []
	# what can be looked up (the web screens search across these)
	out.collections = kernel.comp.collections()
	out.chat_history = _chat_history(func(aud: String) -> bool: return Views.can_see(aud, pid, role))
	var known := _known()
	Knowledge.for_viewer({"chat_history": out.chat_history}, state.encounter.actors, known, _is_gm(c))
	# the DM seeing as a player: that player's chat too (the DM's See as), as
	# they read it — a creature they don't know is "a creature" there too
	var who := str(c.get("see_as", ""))
	if _is_gm(c) and who != "" and not state.encounter.player(who).is_empty():
		out.preview_chat = Knowledge.for_viewer(preview_chat(who), state.encounter.actors, known, false)
	if table_source.is_valid():
		out.table = table_source.call()
	out.journal = []
	if journal_source.is_valid():
		for entry in journal_source.call():
			if entry is Dictionary and str(entry.get("kind", "")) == "handout" and Views.can_see(str(entry.get("audience", "gm")), pid, role):
				out.journal.append(JsonDoc.deep(entry))
	return out


## The chat of sessions before, as far as `may_read` (an audience) lets a
## viewer read it: not what the live log still holds (a session ended but
## still open has its chat in both, and a playtest's list put the whole
## evening above its first hour), the newest CHAT_HISTORY_SENT.
func _chat_history(may_read: Callable) -> Array:
	if not chat_source.is_valid():
		return []
	var live := {}
	for entry in kernel.state.encounter.log:
		live[str(entry.get("id", ""))] = true
	var hist: Array = chat_source.call()
	var kept := []
	for i in range(hist.size() - 1, -1, -1):
		if kept.size() >= CHAT_HISTORY_SENT:
			break
		var m: Variant = hist[i]
		if m is Dictionary and not live.has(str(m.get("id", ""))) and bool(may_read.call(str(m.get("audience", "all")))):
			# (a session's rolls are done with: no rulings on them, nobody's notes)
			kept.append(Views.log_entry_for(m, Views.ROLE_PLAYER))
	kept.reverse()
	return kept


## A player's chat as the DM seeing as them is shown it: what the player
## reads of the talk, the rolls and the notes, this session's and before,
## less what the DM may not read (what players keep from the DM stays
## theirs). A playtest's DM couldn't check whether a hidden creature's
## initiative roll had reached the players' chat.
func preview_chat(pid: String) -> Dictionary:
	var both := func(aud: String) -> bool: return Views.can_see(aud, pid, Views.ROLE_PLAYER) and Views.can_see(aud, "", Views.ROLE_GM)
	var log := []
	for entry in kernel.state.encounter.log:
		if str(entry.get("kind", "")) in ["chat", "roll", "note"] and bool(both.call(str(entry.get("audience", "all")))):
			# (as the player reads it: without the DM's actions and notes on it)
			log.append(Views.log_entry_for(entry, Views.ROLE_PLAYER))
	return {"as": pid, "log": log, "chat_history": _chat_history(both)}


## Something the views draw on changed outside the encounter (the
## campaign's journal, the rules loaded again): every client's view is sent
## again — and when the rules now say otherwise of what the players know of a
## monster (its health, its name, its conditions), every screen's scene too,
## however they were reloaded.
func refresh_views() -> void:
	_views_dirty = true
	if not JsonDoc.same(_known(), _known_was):
		refresh_scenes()


## A client's view: its schemas once, then what changed since the last (Wire).
func _send_view(c: Dictionary) -> void:
	if kernel != null:
		_send(c, (c.wire as Wire.Peer).pack("view", projection(c)))


## A web client's scene: the one the players see (the DM's: the one they
## chose), whole, as they may see it (what the players know of a monster
## too: Knowledge).
func _send_scene(c: Dictionary) -> void:
	var e := state.encounter
	var sid := str(c.get("scene", ""))
	if sid == "" or e.scene(sid).is_empty() or not _is_gm(c):
		sid = e.active_scene_id
	var known := _known()
	var msg := {"t": "scene", "scene": WebScene.build(state, sid, str(c.player), _is_gm(c), known) if sid != "" else {},
		"players": JsonDoc.deep(e.players), "clock": JsonDoc.deep(e.clock), "online": connected_players()}
	if not (msg.scene as Dictionary).is_empty():
		msg.scene.role = str(map_role.call(str(msg.scene.get("map", "")))) if map_role.is_valid() else ""
		# how the table's rulers count (the rules' diagonal rule): a screen counts the
		# straight distance itself as a ruler is dragged; the walk comes from here
		msg.scene.measure = kernel.map.measure_rule() if kernel != null else {"diagonals": "5-5-5"}
	if _is_gm(c):
		msg.scenes = e.scenes.map(func(s: Dictionary) -> Dictionary: return {"id": str(s.id), "name": str(s.get("name", "")), "map": str(s.get("map", "")), "active": str(s.id) == e.active_scene_id})
		# seeing as a player: that player's snapshot of the scene, as their screen has it
		var who := str(c.get("see_as", ""))
		if who != "" and sid != "" and not e.player(who).is_empty():
			msg.preview = WebScene.build(state, sid, who, false, known)
			msg.preview_as = who
			# and why each creature they don't see isn't there: hidden, dark or walls
			msg.preview_why = WebScene.unseen(state, sid, who)
			# and the marks on the map as they are sent them (a ruler or a preview of
			# the DM's over what they can't see left out, a creature's preview unnamed)
			msg.preview_marks = _marks_as(who)
	# (whole the first time, then what changed: Wire)
	_send(c, (c.wire as Wire.Peer).pack("scene", Wire.body_of(msg)))


## Every mark a player's screen is sent now (the DM's See as draws these).
func _marks_as(who: String) -> Array:
	var seat := {"joined": true, "role": Views.ROLE_PLAYER, "player": who}
	var out := []
	for id in marks.marks:
		var m := _mark_for(seat, marks.marks[id])
		if not m.is_empty():
			out.append(m)
	return out


func _send_dm(c: Dictionary) -> void:
	if dm_state_source.is_valid():
		_send(c, (c.wire as Wire.Peer).pack("dm", dm_state_source.call()))


func _handle(c: Dictionary, msg: Dictionary) -> void:
	var t := str(msg.t)
	# (someone typing, every few seconds, is no more the table's story than a ping;
	# nor is a ruler being dragged, ten times a second: where it was let go is)
	if t != "ping" and not _is_typing(msg) and not _is_held_mark(msg) and not traced.get_connections().is_empty():
		traced.emit({"dir": "in", "player": str(c.get("player", "")), "gm": _is_gm(c), "msg": _traced_copy(msg)})
	if not c.hello and t != "hello":
		_send(c, Protocol.error("say hello first"))
		return
	match t:
		"hello":
			c.web = bool(msg.get("web", false))
			if int(msg.get("version", 0)) != Protocol.VERSION:
				var why := "this table speaks protocol %d, you speak %d" % [Protocol.VERSION, int(msg.get("version", 0))]
				_send(c, Protocol.error(why))
				# the close reason carries it too: a client may see the close before the packet
				(c.peer as WebSocketPeer).close(1002, why.left(120))
				return
			c.hello = true
			c.name = str(msg.get("name", ""))
			_send(c, _welcome(c))
		"join":
			var pid := str(msg.get("player", ""))
			var role := str(msg.get("role", Views.ROLE_PLAYER))
			if not Protocol.ROLES.has(role):
				_send(c, Protocol.error("unknown role '%s'" % role))
				return
			# someone new to the table joins by name: found if they were here before, added if not
			if role == Views.ROLE_PLAYER and pid == "" and str(msg.get("name", "")).strip_edges() != "":
				var why := ""
				var r := _player_by_name(str(msg.name))
				pid = str(r.get("id", ""))
				why = str(r.get("why", ""))
				if why != "":
					_send(c, Protocol.error(why))
					return
			if role == Views.ROLE_PLAYER and state.encounter.player(pid).is_empty():
				_send(c, Protocol.error("no such player"))
				return
			if role == Views.ROLE_DM and (dm_token == "" or str(msg.get("token", "")) != dm_token or not is_local_address((c.peer as WebSocketPeer).get_connected_host())):
				_send(c, Protocol.error("the DM's screen opens from the Table on this computer"))
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
			# everything whole once more, less the schemas it says it holds (Wire)
			(c.wire as Wire.Peer).joined(msg.get("have", []))
			if _is_gm(c):
				# the whole scene, now that they may see it
				_send(c, _welcome(c))
				# and the maps whole: a co-GM's device fetched them before joining,
				# without the DM's notes
				if not bool(c.web):
					for mid in state.maps:
						_send(c, _map_msg(c, str(mid)))
			_send(c, {"t": "joined", "player": pid, "role": role, "name": _player_name(pid) if pid != "" else ""})
			_send_view(c)
			if bool(c.web):
				_send_scene(c)
			# the marks on the map now (a ruler someone is dragging, a pinned template)
			_send_marks(c)
			if role == Views.ROLE_DM:
				_send_dm(c)
			_scenes_dirty = true
			var who := _player_name(pid) if pid != "" else ("the DM's screen" if role == Views.ROLE_DM else ("a co-GM (%s)" if role == Views.ROLE_COGM else "a display (%s)") % str(c.get("name", "")))
			log.emit("%s joined" % who)
			if pid != "":
				client_joined.emit(pid)
		"intent":
			# an intent sent with a `req` hears back either way, done or refused
			# with it (a playtest's DM couldn't tell that "Give it" had worked:
			# the form stayed filled in)
			var req := str(msg.req) if msg.get("req") != null else ""
			var intent = msg.get("intent", {})
			if not (intent is Dictionary):
				_send(c, Protocol.intent_refused({}, "not an intent", req))
				return
			var why := _handle_intent(c, intent)
			if why != "":
				_send(c, Protocol.intent_refused(intent, why, req))
			elif req != "":
				# what it did reaches the screens before the word that it's done,
				# so the screen that waited reads its result as it hears (a button
				# says what it did only where no roll of the player's shows it)
				_flush_views()
				_send(c, Protocol.done(req))
		"request":
			var ev = msg.get("ev", {})
			if not (ev is Dictionary):
				_send(c, Protocol.refused({}, "not an event"))
				return
			if not _is_gm(c) and (c.player == "" or c.role != Views.ROLE_PLAYER):
				_send(c, Protocol.refused(ev, "join as a player first"))
				return
			# a co-GM may ask for any scene event the Table itself could apply;
			# a player is told why not (a playtest's, moving her own token before
			# initiative, heard only "not allowed")
			if not _is_gm(c) and not state.allowed(ev, c.player):
				_send(c, Protocol.refused(ev, state.refusal(ev, c.player)))
				return
			var why := state.validate(ev)
			if why == "":
				why = str(apply_request.call(ev, "" if _is_gm(c) else c.player)) if apply_request.is_valid() else _apply_plain(ev)
			if why != "":
				_send(c, Protocol.refused(ev, why))
		"upload":
			# a picture from a screen that joined: one at a time, the Table says what becomes of it
			if not bool(c.joined):
				return
			var now := Time.get_ticks_msec()
			if now - int(c.get("last_upload", -UPLOAD_GAP_MS)) < UPLOAD_GAP_MS:
				_send(c, {"t": "upload_failed", "req": msg.get("req", ""), "why": "one picture at a time: try again in a moment"})
				return
			c["last_upload"] = now
			var out: Dictionary = upload_handler.call(str(c.player), _is_gm(c), msg) if upload_handler.is_valid() else {"ok": false, "why": "this table takes no pictures"}
			if bool(out.get("ok", false)):
				_send(c, {"t": "uploaded", "req": msg.get("req", ""), "ref": str(out.get("ref", ""))})
			else:
				_send(c, {"t": "upload_failed", "req": msg.get("req", ""), "why": str(out.get("why", "refused"))})
		"need":
			match str(msg.get("kind", "")):
				# whole again: a screen that couldn't read what changed (Wire)
				"scene":
					(c.wire as Wire.Peer).forget("scene")
					_send_scene(c)
				"view":
					if c.joined:
						(c.wire as Wire.Peer).forget("view")
						_send_view(c)
				"dm":
					if c.joined and c.role == Views.ROLE_DM:
						(c.wire as Wire.Peer).forget("dm")
						_send_dm(c)
				_:
					_serve(c, msg)
		"ping":
			_send(c, {"t": "pong"})
		"mark":
			_mark(c, msg)


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
			# a pointer that resolved to nothing (a sheetless view's "$/actor/id") is no claim
			if not gm and ctx.get("actor") != null and str(ctx.actor) != "" and not _owns_actor(pid, str(ctx.actor)):
				return "that is not your character"
			if not gm and ctx.get("token") != null and str(ctx.token) != "" and not _owns_token(pid, str(ctx.token)):
				return "that is not your token"
			# a target picked on the map must be one this viewer may pick; an intent
			# sent with no target at all, saying so (ctx.no_target: the theatre of the
			# mind, or a fight with no battle map), is the ruleset's to roll without one
			var kind := str(p.actions[action].get("target", ""))
			var unaimed := bool(ctx.get("no_target", false)) and (ctx.get("target") == null or str(ctx.get("target")) == "")
			if kind in ["token", "cell", "area"] and not unaimed:
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
		"chat":
			return _chat(c, intent)
		"typing":
			return _typing(c, intent)
		# a sheet's Preview is the screen's own doing (a mark on the map, below)
		"preview":
			return "a preview is put on the map by the web screens"
		# a free roll ("/roll 1d20+4 Stealth" in the chat): anyone's dice, the DM's in
		# secret if asked (a playtest's DM had no dice of his own)
		"roll":
			var expr := str(intent.get("expr", "")).strip_edges()
			if expr == "" or expr.length() > 60:
				return "what to roll? e.g. 1d20+4"
			var what := str(intent.get("label", "")).strip_edges().left(80)
			var who := "The DM" if gm else _player_name(pid)
			var spec := {"expr": expr, "kind": "free"}
			if gm and bool(intent.get("secret", false)):
				spec.visibility = "gm"
			var entry := kernel.roll(spec, {"by": pid if not gm else "gm"}, "%s: %s" % [who, what if what != "" else expr])
			if entry.is_empty():
				return kernel.last_veto if kernel.last_veto != "" else "that isn't a roll: %s (try 1d20+4)" % expr
			return ""
		"dm":
			if c.role != Views.ROLE_DM:
				return "only the DM's screen does that"
			if str(intent.get("op", "")) == "view_scene":
				# which scene this DM screen looks at (the players see the active one)
				c.scene = str(intent.get("scene", ""))
				_send_scene(c)
				return ""
			if str(intent.get("op", "")) == "see_as":
				# what one player's screen shows, beside the DM's own (a playtest's DM
				# revealed the goblins and couldn't tell that nobody could see them)
				var who := str(intent.get("player", ""))
				if who != "" and state.encounter.player(who).is_empty():
					return "no such player"
				c.see_as = who
				_send_scene(c)
				# (and their chat, which comes with the view)
				_send_view(c)
				return ""
			if not dm_handler.is_valid():
				return "no DM operations here"
			var why_dm := str(dm_handler.call(intent))
			_dm_dirty = true
			_scenes_dirty = true
			return why_dm
		"prefs":
			# a player's own preferences ({plugin, key, value}), within what the DM
			# allows (PlayerPrefs); the DM changes anyone's in Table settings
			if gm:
				return "a player's preferences are changed in Table settings"
			var why_p := PlayerPrefs.change(state.encounter, plugins, pid, str(intent.get("plugin", "")), str(intent.get("key", "")), intent.get("value"), pid,
				func(events: Array, label: String, reason: Dictionary) -> String: return kernel.commit(events, label, reason))
			if why_p == "":
				# (the DM's Table settings lists each player's choices)
				_dm_dirty = true
			return why_p
		"note":
			# a player's own notes: theirs to write, keep private or share
			if gm:
				return "the DM's notes are kept on the Table"
			if not notes_source.is_valid():
				return "this table keeps no notes (open a campaign)"
			var why := PlayerNotes.apply(notes_source.call(), intent, pid, state.encounter.players)
			if why == "":
				if notes_changed.is_valid():
					notes_changed.call()
				_views_dirty = true
			return why
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


## A player found by name (as typed, any case), or added: {id} or {why}.
func _player_by_name(p_name: String) -> Dictionary:
	var wanted := p_name.strip_edges().left(40)
	if wanted == "":
		return {"why": "type your name"}
	for p in state.encounter.players:
		if str(p.get("name", "")).strip_edges().to_lower() == wanted.to_lower():
			return {"id": str(p.id)}
	var pid := JsonDoc.new_id("pl")
	var ev := {"t": "player.add", "player": {"id": pid, "name": wanted, "color": PLAYER_COLORS[state.encounter.players.size() % PLAYER_COLORS.size()]}}
	var why := str(add_player.call(ev)) if add_player.is_valid() else _apply_plain(ev)
	if why != "":
		return {"why": why}
	log.emit("%s is new at the table" % wanted)
	return {"id": pid}


## A chat message: {text, to: "all" | ["gm", player ids…], private}. To
## everyone; to some players (the DM reads it too); or, `private`, to some
## players and not the DM. Kept in the log (so in the campaign), and a
## viewer sees what their audience lets them.
func _chat(c: Dictionary, intent: Dictionary) -> String:
	var text := str(intent.get("text", "")).strip_edges().left(2000)
	if text == "":
		return "say something"
	var from := "gm" if _is_gm(c) else str(c.player)
	var to: Variant = intent.get("to", "all")
	var audience := _chat_audience(c, intent)
	var names := []
	if audience != "all":
		names = (to as Array).map(func(x: Variant) -> String: return "the DM" if str(x) == "gm" else _player_name(str(x)))
	var entry := {"id": JsonDoc.new_id("m"), "kind": "chat", "from": from, "text": text, "audience": audience, "to": names, "at": JsonDoc.now()}
	return kernel.commit([{"t": "log.add", "entry": entry}], "Chat", {"by": from}, audience)


## Who reads what a client says to `to` ("all" or [ids, "gm"]), `private`
## or not: "all", "players:<ids>" (with the one who says it, and the DM) or
## "private:<ids>" (players only).
func _chat_audience(c: Dictionary, intent: Dictionary) -> String:
	var gm := _is_gm(c)
	var from := "gm" if gm else str(c.player)
	var to: Variant = intent.get("to", "all")
	if not (to is Array) or (to as Array).is_empty() or (to as Array).has("all"):
		return "all"
	var ids := []
	for x in to:
		var k := str(x)
		if k != "gm" and not state.encounter.player(k).is_empty() and not ids.has(k):
			ids.append(k)
	if not gm and not ids.has(from):
		ids.append(from)
	var private := bool(intent.get("private", false)) and not gm and not (to as Array).has("gm")
	return ("private:" if private else "players:") + ",".join(PackedStringArray(ids))


## Someone writing in the chat ({to, private} as the message will have
## them): said to the web screens that would read the message — never back
## to the one writing, never to a player a private word leaves out — and
## kept nowhere. "Leo is typing…" (a playtest's DM and players crossed
## messages many times, each answering what the other had said before).
func _typing(c: Dictionary, intent: Dictionary) -> String:
	var now := Time.get_ticks_msec()
	if now - int(c.get("last_typing", -TYPING_GAP_MS)) < TYPING_GAP_MS:
		return ""
	c["last_typing"] = now
	var gm := _is_gm(c)
	var from := "gm" if gm else str(c.player)
	var audience := _chat_audience(c, intent)
	var msg := {"t": "typing", "from": from, "name": "the DM" if gm else _player_name(from)}
	for o in _clients:
		if is_same(o, c) or not bool(o.web) or not bool(o.joined):
			continue
		if Views.can_see(audience, "" if _is_gm(o) else str(o.player), Views.ROLE_GM if _is_gm(o) else Views.ROLE_PLAYER):
			_send(o, msg)
	return ""


## What a co-GM may drive besides actions: {op: next|previous|checkpoint|restore|trigger|bulk, …}.
## Next may say the turn it means (`from`: {round, turn}), as the DM's own does.
func _gm_intent(intent: Dictionary) -> String:
	match str(intent.get("op", "")):
		"next": return kernel.turns.next({"by": "gm", "expect": intent.get("from")})
		"previous": return kernel.turns.previous()
		"checkpoint": return "" if kernel.checkpoint(str(intent.get("name", "Checkpoint"))) != "" else "could not mark"
		"restore": return kernel.restore_checkpoint(str(intent.get("id", "")))
		"trigger": return kernel.fire_trigger(str(intent.get("scene", state.encounter.active_scene_id)), str(intent.get("trigger", "")))
		"bulk":
			var r := Bulk.run(kernel, Array(intent.get("targets", [])), intent.get("op_spec", {}) if intent.get("op_spec") is Dictionary else {}, str(intent.get("label", "")))
			return r.why
	return "unknown gm op '%s'" % str(intent.get("op", ""))


# ------------------------------------------------------------------ marks --
# The table's shared marks (Marks): {t: "mark", op: "set", mark} puts or
# changes one of one's own; {op: "remove", id} takes one off (the DM: anyone's);
# {op: "clear", whose} one's own ("" or one's id), or — the DM — one person's
# or everyone's ("all"). Each screen hears {t: "marks", marks} on joining,
# then {t: "mark", mark} for one put or changed and {t: "unmark", ids} for
# those gone (or no longer for it), only what it may see: a player's marks
# reach everyone on the scene the players see; the DM's not where they lie
# over what a player can't see, and a private one only the DMs.

## Whose a screen's marks are: "gm" for the DMs, a player's id, "" for none (a display).
func _mark_owner(c: Dictionary) -> String:
	if not bool(c.get("joined", false)):
		return ""
	if _is_gm(c):
		return "gm"
	return str(c.player) if c.role == Views.ROLE_PLAYER else ""


func _mark(c: Dictionary, msg: Dictionary) -> void:
	var owner := _mark_owner(c)
	if owner == "":
		_send(c, {"t": "refused", "why": "join as a player to put marks on the map"})
		return
	var gm := _is_gm(c)
	var why := ""
	match str(msg.get("op", "")):
		"set":
			var raw: Variant = msg.get("mark")
			if not (raw is Dictionary):
				why = "not a mark"
			else:
				# a screen's marks are taken at most every MARK_IN_GAP_MS: the newest of
				# each waits for its turn (poll)
				var now := Time.get_ticks_msec()
				if now - int(c.get("mark_in_ms", -MARK_IN_GAP_MS)) < MARK_IN_GAP_MS:
					if not c.has("mark_queue"):
						c["mark_queue"] = {}
					c.mark_queue[str(raw.get("id", ""))] = raw
					return
				c["mark_in_ms"] = now
				why = _put_mark(owner, raw, gm)
		"remove":
			var id := str(msg.get("id", ""))
			if c.has("mark_queue"):
				(c.mark_queue as Dictionary).erase(id)
			why = marks.remove(owner, id, gm)
		"clear":
			var whose := str(msg.get("whose", ""))
			if whose != "" and whose != owner and not gm:
				why = "only the DM clears someone else's marks"
			else:
				if c.has("mark_queue"):
					(c.mark_queue as Dictionary).clear()
				marks.clear(owner, whose, gm)
		_:
			why = "unknown mark op '%s'" % str(msg.get("op", ""))
	if why != "":
		_send(c, {"t": "refused", "why": why})


## A mark from `owner`, with who they are (their name and colour) and, for a
## creature's preview, the creature's name: "" or why not.
func _put_mark(owner: String, raw: Dictionary, gm: bool) -> String:
	var extra := {"name": "DM", "color": DM_COLOR}
	if owner != "gm":
		var p := state.encounter.player(owner)
		extra = {"name": _mark_name(owner), "color": str(p.get("color", "#ffffff"))}
	# a preview says whose it is: a caster's own (the DM's creature, a player's character)
	var aid := str(raw.get("actor", "")) if raw.get("actor") is String else ""
	if str(raw.get("kind", "")) == "preview" and aid != "":
		var a := state.encounter.actor(aid)
		if not a.is_empty() and (gm or str(a.get("owner", "")) == owner):
			extra._as = str(a.get("name", ""))
			extra._as_actor = aid
	return marks.put(owner, raw, extra, gm)


## What a player's marks are labelled: their character's name when they have
## one character ("Wren: 25 ft"), else their own.
func _mark_name(pid: String) -> String:
	var mine := []
	for aid in state.encounter.actors:
		var a: Dictionary = state.encounter.actors[aid]
		if str(a.get("owner", "")) == pid and str(a.get("kind", "pc")) == "pc":
			mine.append(str(a.get("name", "")))
	return mine[0] if mine.size() == 1 and str(mine[0]) != "" else _player_name(pid)


## Every mark this screen may see, at once (it joined, or the encounter changed).
func _send_marks(c: Dictionary) -> void:
	var list := []
	var sent := {}
	for id in marks.marks:
		var out := _mark_for(c, marks.marks[id])
		if not out.is_empty():
			list.append(out)
			sent[str(id)] = true
	c["marks_sent"] = sent
	_send(c, {"t": "marks", "marks": list})


func _on_mark_changed(id: String) -> void:
	if Time.get_ticks_msec() - int(_mark_sent_ms.get(id, -MARK_GAP_MS)) < MARK_GAP_MS:
		_mark_pending[id] = true
		return
	_relay_mark(id)


func _on_mark_removed(id: String, _m: Dictionary) -> void:
	_mark_pending.erase(id)
	_mark_sent_ms.erase(id)
	for c in _clients:
		if c.get("marks_sent", {}).has(id):
			(c.marks_sent as Dictionary).erase(id)
			_send(c, {"t": "unmark", "ids": [id]})
	_send_seen_marks()


## The DM seeing as a player: the marks as that player is sent them, again
## (a mark put, changed or gone): the See as draws these, not the DM's own.
func _send_seen_marks() -> void:
	for c in _clients:
		var who := str(c.get("see_as", ""))
		if c.joined and _is_gm(c) and bool(c.web) and who != "" and not state.encounter.player(who).is_empty():
			_send(c, {"t": "seen_marks", "as": who, "marks": _marks_as(who)})


## A mark to every screen that may see it, and gone from one that no longer may.
func _relay_mark(id: String, only_changes := false) -> void:
	var m: Dictionary = marks.marks.get(id, {})
	if m.is_empty():
		return
	if not only_changes:
		_mark_sent_ms[id] = Time.get_ticks_msec()
		_mark_pending.erase(id)
	for c in _clients:
		if not c.joined:
			continue
		if not c.has("marks_sent"):
			c["marks_sent"] = {}
		var had: bool = (c.marks_sent as Dictionary).has(id)
		var out := _mark_for(c, m)
		if not out.is_empty():
			if only_changes and had:
				continue
			c.marks_sent[id] = true
			_send(c, {"t": "mark", "mark": out})
		elif had:
			(c.marks_sent as Dictionary).erase(id)
			_send(c, {"t": "unmark", "ids": [id]})
	if not only_changes:
		_send_seen_marks()


## The marks' time passes, what waited its turn goes, what screens held back
## is taken, and after a change on the map who sees which mark is checked.
func _poll_marks() -> void:
	for c in _clients:
		if c.has("mark_queue") and not (c.mark_queue as Dictionary).is_empty() and Time.get_ticks_msec() - int(c.get("mark_in_ms", 0)) >= MARK_IN_GAP_MS:
			var queued: Dictionary = c.mark_queue
			c["mark_queue"] = {}
			c["mark_in_ms"] = Time.get_ticks_msec()
			var owner := _mark_owner(c)
			for raw in queued.values():
				var why := _put_mark(owner, raw, _is_gm(c)) if owner != "" else ""
				if why != "":
					_send(c, {"t": "refused", "why": why})
	marks.tick()
	var now := Time.get_ticks_msec()
	for id in _mark_pending.keys():
		if now - int(_mark_sent_ms.get(id, 0)) >= MARK_GAP_MS:
			_relay_mark(str(id))
	if _marks_recheck:
		_marks_recheck = false
		for id in marks.marks.keys():
			_relay_mark(str(id), true)


## A mark as one screen may see it, or {} when it may not: the DMs see every
## one; anyone else none that is private, none off the scene the players see,
## and none of the DM's that lies over what they can't see (unexplored
## ground under fog, a creature they don't see, or starts at one) — and of the
## DM's ruler only the straight distance, unless its walk is all ground they
## know. A creature's preview says whose it is only to a screen that sees it.
func _mark_for(c: Dictionary, m: Dictionary) -> Dictionary:
	var out := Marks.wire(m)
	var as_name := str(m.get("_as", ""))
	if _is_gm(c):
		if as_name != "":
			out.name = as_name
		return out
	# a creature whose name the players don't know casts it: "A creature" (Knowledge)
	if as_name != "" and not Knowledge.name_known(state.encounter.actor(str(m.get("_as_actor", ""))), _known()):
		as_name = Knowledge.UNKNOWN_START
	if bool(m.get("private", false)) or str(m.scene) != state.encounter.active_scene_id:
		return {}
	var pid := str(c.player) if c.role == Views.ROLE_PLAYER else ""
	if str(m.owner) != "gm":
		if as_name != "":
			out.name = as_name
		return out
	var sight := _sight_of(pid, str(m.scene))
	if not _shown_to(sight, m):
		return {}
	if as_name != "" and str(m.get("token", "")) != "" and (sight.seen as Dictionary).has(str(m.token)):
		out.name = as_name
	var me: Variant = out.get("measure")
	if me is Dictionary and (me.has("walk") or me.has("no_way")):
		var known := not bool(sight.fog)
		if not known:
			known = (m.get("_walk_cells", []) as Array).all(func(k: Variant) -> bool: return (sight.explored as Dictionary).has(str(k)))
		if not known or me.has("no_way"):
			me.erase("walk")
			me.erase("no_way")
			me.words = Measure.words(me)
	return out


## Whether a DM's mark lies where a player's screen may show it (`sight`: _sight_of).
func _shown_to(sight: Dictionary, m: Dictionary) -> bool:
	var sid := str(m.scene)
	var map := state.map_for(sid)
	if map == null:
		return false
	if str(m.get("token", "")) != "" and not (sight.seen as Dictionary).has(str(m.token)):
		return false
	for p in m.get("points", []):
		var v := Vector2(float(p[0]), float(p[1]))
		if bool(sight.fog) and not (sight.explored as Dictionary).has(HexMap.cell_key(map.grid.world_to_axial(v))):
			return false
		for tk in state.tokens(sid):
			if (sight.seen as Dictionary).has(str(tk.id)):
				continue
			if Vision.token_pos(tk).distance_to(v) <= maxf(0.5, float(tk.get("size", 1)) * 0.5):
				return false
	return true


## What a player's screen shows of a scene, worked out once until the table
## changes: {fog, explored (cells), seen (token ids)}. "" is a display's: no eyes.
func _sight_of(pid: String, sid: String) -> Dictionary:
	var key := pid + "|" + sid
	if _sight.has(key):
		return _sight[key]
	var fog := state.fog_enabled(sid)
	var polys: Array = Vision.of(state, sid, WebScene._eyes(state, sid, pid, false)).polygons if fog and pid != "" else []
	var seen := {}
	for tk in state.tokens(sid):
		if WebScene.shows(state, tk, pid, fog, polys):
			seen[str(tk.id)] = true
	var out := {"fog": fog, "explored": state.explored(sid) if fog else {}, "seen": seen}
	_sight[key] = out
	return out


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
			_send(c, _map_msg(c, id))
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


## A map as this client may have it: whole for a GM (the DM's screen, a
## co-GM), and for anyone else without the DM's notes on it
## (Protocol.player_map; those a scene has shown stay). A screen asks for
## its maps before it joins, so until then it is anyone else.
func _map_msg(c: Dictionary, map_id: String) -> Dictionary:
	var m: HexMap = state.maps.get(map_id)
	if m == null:
		return Protocol.error("no map " + map_id)
	if _is_gm(c):
		return {"t": "map", "id": map_id, "doc": m.doc}
	var shown := {}
	for sc in state.encounter.scenes:
		if str(sc.get("map", "")) != map_id:
			continue
		var ovs: Dictionary = sc.get("overrides", {})
		for ref in ovs:
			if str(ref).begins_with("notes:") and ovs[ref] is Dictionary and ovs[ref].get("gm_only", true) == false:
				shown[str(ref)] = true
	return {"t": "map", "id": map_id, "doc": Protocol.player_map(m.doc, shown)}


## The packs the encounter's maps use, and the packs holding the pictures
## the DM may show, with their file lists.
func pack_listing() -> Array:
	var ids := {}
	for id in state.maps:
		for p in (state.maps[id] as HexMap).doc.get("packs", {}):
			ids[str(p)] = true
	for p in packs.picture_packs():
		ids[str(p)] = true
	var out := []
	for id in ids:
		if packs.pack_dir(id) == "":
			continue
		out.append({"id": id, "version": packs.pack_version(id), "manifest": packs.manifest(id), "files": Array(packs.pack_files(id))})
	return out
