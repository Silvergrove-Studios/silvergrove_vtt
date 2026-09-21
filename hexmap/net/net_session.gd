class_name NetSession
extends Session
## A Player's session over the network: connects to a Table, receives the
## encounter and every applied event, sends requests, and fetches the maps
## and pack files it lacks into user://packs so a device with nothing
## installed still draws the scene. The Table decides everything; this
## side only pre-checks a request to give the reason at once.

## The welcome arrived: `state` is usable and the players can be listed.
signal connected
## Every pack file has arrived; textures were reloaded.
signal assets_ready
## The table accepted the join.
signal joined_as(player_id: String)

var address := ""
var port := Protocol.DEFAULT_PORT
var packs: PackLibrary
## Where fetched packs go; PackLibrary already searches user://packs.
var cache_dir := "user://packs"
var joined := false
var _peer := WebSocketPeer.new()
var _was_open := false
var _closed := false
## Seconds a connection may spend connecting before it counts as unreachable.
## Some stacks (Windows) take much longer than others to report a refusal.
var connect_timeout := 5.0
var _started_ms := 0
var _pending_files := {}   # "pack/file" -> true
var _maps_wanted := {}
var _hello_name := ""


func _init(p_address: String, p_port: int, p_packs: PackLibrary, p_name := "") -> void:
	address = p_address
	port = p_port
	packs = p_packs
	_hello_name = p_name


func connect_to_host() -> Error:
	_started_ms = Time.get_ticks_msec()
	_peer.inbound_buffer_size = Protocol.BUFFER_SIZE
	_peer.outbound_buffer_size = Protocol.BUFFER_SIZE
	_peer.max_queued_packets = 4096
	return _peer.connect_to_url("ws://%s:%d" % [address, port])


func is_connected_to_host() -> bool:
	return _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func _send(msg: Dictionary) -> void:
	if is_connected_to_host():
		_peer.send_text(Protocol.encode(msg))


## Become this player at the table (or a display: no player, everyone's
## audience, no controls).
## `code` is what a co-GM gives (the table shows it).
func join(p_player_id: String, p_role := "player", code := "") -> void:
	player_id = p_player_id
	role = p_role
	var msg := {"t": "join", "player": p_player_id, "role": p_role}
	if code != "":
		msg.code = code
	_send(msg)


func is_gm() -> bool:
	return role == Views.ROLE_COGM


## req id -> callback, for compendium requests in flight
var _comp_waiting: Dictionary = {}
var _comp_seq := 0


func comp(collection: String, req: Dictionary, on_reply: Callable) -> void:
	if not is_connected_to_host():
		super(collection, req, on_reply)
		return
	_comp_seq += 1
	var id := "c%d" % _comp_seq
	_comp_waiting[id] = on_reply
	var msg := {"t": "need", "kind": "comp", "req": id, "collection": collection}
	if req.has("id"):
		msg.id = str(req.id)
	else:
		msg.query = req.get("query", {}) if req.get("query") is Dictionary else {}
	_send(msg)


func request(ev: Dictionary) -> String:
	if state == null or not is_connected_to_host():
		return "Not connected"
	if not joined:
		return "Not joined yet"
	if not is_gm() and not state.allowed(ev, player_id):
		return LocalSession.why_not(state, ev)
	var why := state.validate(ev)
	if why != "":
		return why
	_send({"t": "request", "ev": ev})
	return ""


func intent(payload: Dictionary) -> String:
	if not is_connected_to_host():
		return "not connected"
	if not joined:
		return "join first"
	_send({"t": "intent", "intent": payload})
	return ""


func leave() -> void:
	if not _closed:
		_peer.close()
	_closed = true


func poll() -> void:
	if _closed:
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_send(Protocol.hello(_hello_name))
			while _peer.get_available_packet_count() > 0:
				var msg := Protocol.decode(_peer.get_packet().get_string_from_utf8())
				if not msg.is_empty():
					_handle(msg)
		WebSocketPeer.STATE_CONNECTING:
			if Time.get_ticks_msec() - _started_ms > connect_timeout * 1000.0:
				_closed = true
				_peer.close()
				closed.emit("No answer from the table")
		WebSocketPeer.STATE_CLOSED:
			_closed = true
			var why := "The table closed the connection" if _was_open else "Could not reach the table"
			var reason := _peer.get_close_reason()
			closed.emit(why if reason == "" else reason)


func _handle(msg: Dictionary) -> void:
	match str(msg.t):
		"welcome":
			_receive_encounter(msg.get("encounter", {}))
		"joined":
			joined = true
			player_id = str(msg.player)
			role = str(msg.get("role", "player"))
			joined_as.emit(player_id)
			status.emit("Joined as " + (player_name() if role == "player" else ("a co-GM" if is_gm() else "a display")))
		"view":
			if msg.get("view") is Dictionary:
				view = msg.view
				view_changed.emit()
		"event":
			if state != null and msg.get("ev") is Dictionary:
				var why := state.validate(msg.ev)
				if why == "":
					state.apply(msg.ev)
				else:
					push_warning("event from the table rejected: " + why)
		"refused":
			status.emit(str(msg.get("why", "Refused")))
		"map":
			if state != null and msg.get("doc") is Dictionary:
				var m := HexMap.from_json(JSON.stringify(msg.doc))
				if m != null:
					state.attach_map(m)
					_maps_wanted.erase(str(msg.id))
					changed.emit("", "")
		"packs":
			_receive_packs(msg.get("packs", []))
		"file":
			_receive_file(str(msg.pack), str(msg.file), str(msg.data))
		"comp":
			var cb: Variant = _comp_waiting.get(str(msg.get("req", "")))
			_comp_waiting.erase(str(msg.get("req", "")))
			if cb is Callable and (cb as Callable).is_valid():
				var reply := {"collection": str(msg.get("collection", ""))}
				for k in ["page", "entry", "error"]:
					if msg.has(k):
						reply[k] = msg[k]
				(cb as Callable).call(reply)
		"error":
			status.emit(str(msg.get("why", "error")))


func _receive_encounter(doc: Dictionary) -> void:
	var e := Encounter.from_json(JSON.stringify(doc))
	if e == null:
		status.emit("The table sent an encounter this build cannot read")
		return
	if state != null and state.encounter.changed.is_connected(_relay):
		state.encounter.changed.disconnect(_relay)
	var old_maps := state.maps if state != null else {}
	state = EncounterState.new(e)
	state.encounter.changed.connect(_relay)
	for id in old_maps:
		state.attach_map(old_maps[id])
	for id in e.map_ids():
		if not state.maps.has(id):
			_maps_wanted[id] = true
			_send({"t": "need", "kind": "map", "id": id})
	_send({"t": "need", "kind": "packs"})
	connected.emit()
	changed.emit("", "")


func _relay(what: String, p_scene: String) -> void:
	changed.emit(what, p_scene)


func maps_ready() -> bool:
	return _maps_wanted.is_empty()


func assets_pending() -> int:
	return _pending_files.size()


## The host's pack listing: keep what we have, ask for what we lack.
func _receive_packs(listing: Array) -> void:
	_pending_files.clear()
	for p in listing:
		var id := str(p.get("id", ""))
		var version := str(p.get("version", ""))
		if packs.pack_dir(id) != "" and packs.pack_version(id) == version:
			continue   # already installed, same version
		var dir := cache_dir.path_join(id)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var f := FileAccess.open(dir.path_join("pack.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(p.get("manifest", {}), "  "))
			f.close()
		for file in p.get("files", []):
			var rel := str(file)
			if rel == "pack.json" or rel.contains(".."):
				continue
			if FileAccess.file_exists(dir.path_join(rel)):
				continue
			_pending_files["%s/%s" % [id, rel]] = true
			_send({"t": "need", "kind": "file", "pack": id, "file": rel})
	if _pending_files.is_empty():
		_assets_done()


func _receive_file(pack: String, file: String, data: String) -> void:
	if file.contains(".."):
		return
	var path := cache_dir.path_join(pack).path_join(file)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(Marshalls.base64_to_raw(data))
		f.close()
	_pending_files.erase("%s/%s" % [pack, file])
	if _pending_files.is_empty():
		_assets_done()


func _assets_done() -> void:
	packs.reload()
	assets_ready.emit()
	changed.emit("", "")
