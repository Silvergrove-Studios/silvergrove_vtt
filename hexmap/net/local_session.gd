class_name LocalSession
extends Session
## A session over an encounter file on this device: the Player mode
## without a network. Allowed requests are applied to this copy; when the
## file changes on disk (the DM saved), it is reloaded, so a Table and a
## Player on the same machine make a workable two-screen setup, and it is
## how the DM previews the players' client full-screen.

var path := ""
var _mtime := 0
var _poll_every := 1.0
var _since_poll := 0.0


func _init(p_path: String, p_player_id := "") -> void:
	path = p_path
	player_id = p_player_id


## Load (or reload) the file. Returns "" or an error.
func open() -> String:
	var err: Array = []
	var e := Encounter.load_file(path, err)
	if e == null:
		return "; ".join(PackedStringArray(err))
	if state != null and state.encounter.changed.is_connected(_relay):
		state.encounter.changed.disconnect(_relay)
	state = EncounterState.new(e)
	warnings = state.resolve_maps()
	state.encounter.changed.connect(_relay)
	_mtime = _file_mtime()
	if player_id != "" and player().is_empty():
		status.emit("This encounter has no player '%s'" % player_id)
	changed.emit("", "")
	return ""


func _relay(what: String, p_scene: String) -> void:
	changed.emit(what, p_scene)


func _file_mtime() -> int:
	var real := path
	if DirAccess.dir_exists_absolute(path):
		real = path.path_join("encounter.json")
	return FileAccess.get_modified_time(real) if FileAccess.file_exists(real) else 0


func request(ev: Dictionary) -> String:
	if state == null:
		return "no encounter open"
	if not state.allowed(ev, player_id):
		return _why_not(ev)
	var why := state.validate(ev)
	if why != "":
		return why
	state.apply(ev)
	return ""


## A player-facing reason a request was refused.
func _why_not(ev: Dictionary) -> String:
	if str(ev.get("t", "")) != "token.set":
		return "Only the DM can do that"
	var tk := state.token(str(ev.get("scene", "")), str(ev.get("id", "")))
	if tk.is_empty():
		return "No such token"
	var turns := state.encounter.turns
	match str(turns.get("mode", "free")):
		"dm":
			return "The DM has not given you the move"
		"ordered":
			return "Not your turn" if bool(turns.get("running", false)) else "Turns have not begun"
	return "You cannot move that"


## Reload when the file changed on disk. Call every frame with the delta.
func tick(delta: float) -> void:
	_since_poll += delta
	if _since_poll < _poll_every:
		return
	_since_poll = 0.0
	poll()


func poll() -> void:
	if path == "":
		return
	var m := _file_mtime()
	if m == 0:
		closed.emit("The encounter file is gone")
		path = ""
		return
	if m != _mtime:
		var err := open()
		if err == "":
			status.emit("Updated from the table")
