class_name PlayerWindow
extends Control
## The Player: joins a table and shows the scene through the player's own
## tokens — fog, vision, nothing the DM has hidden. Runs on every platform,
## so it is laid out for a finger (big targets, one column, no hover, no
## right-click, no menu bar) and talks to the table only through a Session.
## Today's session is local (an encounter file on this device, reloaded
## when the DM saves); the networked one arrives behind the same interface.

signal go_home

const BAR_HEIGHT := 48.0

var app: App
var session: Session
var view: CanvasView
var tool: PlayerTools.MoveTool
## Screens: "join", "pick", "play".
var screen := ""
var _root: VBoxContainer
var _join: Control
var _pick: Control
var _play: Control
var _address: LineEdit
var _files: ItemList
var _tables: ItemList
var _tables_label: Label
var browser := Discovery.Browser.new()
var _browsing := false
var _players: ItemList
var _pick_title: Label
var _title: Label
var _turn: Label
var _status: Label
var _token_bar: HBoxContainer
var _pending_path := ""
var _status_timer := 0.0


func _ready() -> void:
	if app == null:
		app = App.new()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = app.build_theme()
	app.theme_changed.connect(_on_theme)
	_build()
	show_screen("join")


## From the shell: an encounter file to open here, or (later) a table
## address to join.
func open_argument(arg: String) -> void:
	if arg.ends_with(".encounter") or DirAccess.dir_exists_absolute(arg):
		_choose_file(App.resolve_path(arg))
	else:
		_address.text = arg
		_join_address()


func prepare_shot() -> void:
	if view != null and screen == "play":
		view.zoom_to_fit()


func request_quit() -> void:
	if session != null:
		session.leave()
	get_tree().quit()


func _on_theme(_n: String) -> void:
	theme = app.build_theme()
	_restyle()


func _restyle() -> void:
	var t := ThemeBuilder.tokens(app.theme_name)
	var text := ThemeBuilder.c(t, "text")
	for b in find_children("*", "Button", true, false):
		if b.has_meta("icon"):
			(b as Button).icon = UiIcons.get_icon(str(b.get_meta("icon")), int(t.icon) + 4, text, t.stroke)
	if view != null:
		view.set_surround(ThemeBuilder.c(t, "canvas"), Color(0, 0, 0, 0))


# ===================================================================== build ==

func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 0)
	bg.add_child(_root)
	_join = _build_join()
	_pick = _build_pick()
	_play = _build_play()
	for s in [_join, _pick, _play]:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_root.add_child(s)
	_restyle()


func _big(b: Button, text := "", icon := "") -> Button:
	b.text = text
	if icon != "":
		b.set_meta("icon", icon)
	b.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_join() -> Control:
	var center := CenterContainer.new()
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 440
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var title := Label.new()
	title.text = "Player"
	title.theme_type_variation = "HeaderLabel"
	column.add_child(title)
	var h := Label.new()
	h.text = "Join a table"
	h.theme_type_variation = "DimLabel"
	column.add_child(h)
	_tables_label = Label.new()
	_tables_label.text = "Listening for tables on this network…"
	_tables_label.theme_type_variation = "DimLabel"
	column.add_child(_tables_label)
	_tables = ItemList.new()
	_tables.custom_minimum_size = Vector2(0, 120)
	_tables.item_selected.connect(func(i: int) -> void:
		var t: Dictionary = _tables.get_item_metadata(i)
		_connect_to(str(t.address), int(t.port)))
	column.add_child(_tables)
	browser.updated.connect(_refresh_tables)
	var row := HBoxContainer.new()
	_address = LineEdit.new()
	_address.placeholder_text = "Table address or code"
	_address.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _join_address())
	row.add_child(_address)
	var join := _big(Button.new(), "Join")
	join.theme_type_variation = "AccentButton"
	join.pressed.connect(_join_address)
	row.add_child(join)
	column.add_child(row)
	var h2 := Label.new()
	h2.text = "Or open an encounter on this device"
	h2.theme_type_variation = "DimLabel"
	column.add_child(h2)
	_files = ItemList.new()
	_files.custom_minimum_size = Vector2(0, 220)
	_files.fixed_icon_size = Vector2i(0, 0)
	_files.item_selected.connect(func(i: int) -> void: _choose_file(str(_files.get_item_metadata(i))))
	column.add_child(_files)
	var home := _big(Button.new(), "Home")
	home.pressed.connect(func() -> void: go_home.emit())
	column.add_child(home)
	var status := Label.new()
	status.name = "JoinStatus"
	status.theme_type_variation = "DimLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	return center


func _build_pick() -> Control:
	var center := CenterContainer.new()
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 440
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	_pick_title = Label.new()
	_pick_title.theme_type_variation = "HeaderLabel"
	column.add_child(_pick_title)
	var h := Label.new()
	h.text = "Who are you?"
	h.theme_type_variation = "DimLabel"
	column.add_child(h)
	_players = ItemList.new()
	_players.custom_minimum_size = Vector2(0, 200)
	_players.item_selected.connect(func(i: int) -> void: _start(str(_players.get_item_metadata(i))))
	column.add_child(_players)
	var back := _big(Button.new(), "Back")
	back.pressed.connect(func() -> void: show_screen("join"))
	column.add_child(back)
	return center


func _build_play() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	var leave := _big(Button.new(), "", "x")
	leave.tooltip_text = "Leave the table"
	leave.theme_type_variation = "ToolButton"
	leave.pressed.connect(_leave)
	top.add_child(leave)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.theme_type_variation = "HeaderLabel"
	_title.clip_text = true
	top.add_child(_title)
	_token_bar = HBoxContainer.new()
	top.add_child(_token_bar)
	var fit := _big(Button.new(), "", "maximize")
	fit.tooltip_text = "Fit the map"
	fit.theme_type_variation = "ToolButton"
	fit.pressed.connect(func() -> void: view.zoom_to_fit())
	top.add_child(fit)
	box.add_child(top)
	view = CanvasView.new()
	view.canvas.packs = app.packs
	view.canvas.show_hidden = false
	view.zoom_changed.connect(func(z: float) -> void:
		if tool != null:
			tool.zoom = z)
	box.add_child(view)
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, BAR_HEIGHT * 0.8)
	_turn = Label.new()
	_turn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_turn)
	_status = Label.new()
	_status.theme_type_variation = "DimLabel"
	bottom.add_child(_status)
	box.add_child(bottom)
	return box


func show_screen(name: String) -> void:
	screen = name
	_join.visible = name == "join"
	_pick.visible = name == "pick"
	_play.visible = name == "play"
	if name == "join":
		_refresh_files()
		_start_browsing()
	else:
		_stop_browsing()
	get_window().title = "Player — " + App.NAME


func _start_browsing() -> void:
	if _browsing:
		return
	_browsing = browser.start() == OK
	if not _browsing:
		_tables_label.text = "Cannot listen for tables here; type the address the DM sees."
	_refresh_tables()


func _stop_browsing() -> void:
	if _browsing:
		browser.stop()
		_browsing = false


func _refresh_tables() -> void:
	_tables.clear()
	for t in browser.list():
		var i := _tables.add_item("%s  —  %s:%d" % [str(t.name), str(t.address), int(t.port)])
		_tables.set_item_metadata(i, t)
	if _browsing:
		_tables_label.text = "Tables on this network" if _tables.item_count > 0 else "Listening for tables on this network…"


# ====================================================================== join ==

## Encounters this device knows: recent ones and the examples.
func encounter_files() -> Array:
	var out := []
	for p in app.recent():
		if str(p).ends_with(".encounter") and not out.has(p):
			out.append(p)
	for p in App.bundled(".encounter"):
		if not out.has(p):
			out.append(p)
	return out


func _refresh_files() -> void:
	_files.clear()
	for p in encounter_files():
		var i := _files.add_item(str(p).get_file().get_basename().capitalize())
		_files.set_item_metadata(i, p)
		_files.set_item_tooltip(i, p)


func _join_address() -> void:
	var text := _address.text.strip_edges()
	if text == "":
		_join_status("Type the address the DM's table shows, or pick a table above.")
		return
	var hp := Protocol.parse_address(text)
	_connect_to(str(hp[0]), int(hp[1]))


## Connect to a table; the welcome brings the players to pick from.
func _connect_to(address: String, port: int) -> void:
	if session != null:
		session.leave()
		session = null
	var s := NetSession.new(address, port, app.packs, OS.get_environment("USER"))
	var err := s.connect_to_host()
	if err != OK:
		_join_status("Could not connect to %s:%d: %s" % [address, port, error_string(err)])
		return
	session = s
	_join_status("Connecting to %s:%d…" % [address, port])
	s.connected.connect(func() -> void:
		_pending_path = ""
		_pick_title.text = s.state.encounter.name
		_players.clear()
		for p in s.state.encounter.players:
			var i := _players.add_item(str(p.get("name", "")))
			_players.set_item_metadata(i, str(p.get("id", "")))
			_players.set_item_custom_fg_color(i, Color(str(p.get("color", "#ffffff"))))
		if s.state.encounter.players.is_empty():
			s.leave()
			session = null
			_join_status("'%s' has no players yet. Ask the DM to add them." % s.state.encounter.name)
			return
		show_screen("pick"))
	s.joined_as.connect(func(_pid: String) -> void:
		_bind(s)
		show_screen("play"))
	s.closed.connect(func(reason: String) -> void:
		if session == s:
			_leave()
			_join_status(reason))
	s.status.connect(func(t: String) -> void:
		if screen != "play":
			_join_status(t))


func _join_status(text: String) -> void:
	(_join.find_child("JoinStatus", true, false) as Label).text = text


## An encounter file was picked: load it and ask who the player is.
func _choose_file(path: String) -> void:
	var err: Array = []
	var e := Encounter.load_file(path, err)
	if e == null:
		show_screen("join")
		_join_status("Could not open %s: %s" % [path.get_file(), "; ".join(PackedStringArray(err))])
		return
	_pending_path = path
	_pick_title.text = e.name
	_players.clear()
	for p in e.players:
		var i := _players.add_item(str(p.get("name", "")))
		_players.set_item_metadata(i, str(p.get("id", "")))
		_players.set_item_custom_fg_color(i, Color(str(p.get("color", "#ffffff"))))
	if e.players.is_empty():
		show_screen("join")
		_join_status("'%s' has no players yet. Add them at the table." % e.name)
		return
	show_screen("pick")


## Start playing as this player.
func _start(player_id: String) -> void:
	if session is NetSession:
		(session as NetSession).join(player_id)
		return
	var s := LocalSession.new(_pending_path, player_id)
	var err := s.open()
	if err != "":
		show_screen("join")
		_join_status(err)
		return
	_bind(s)
	app.note_recent(_pending_path)
	show_screen("play")
	view.zoom_to_fit.call_deferred()


func _bind(s: Session) -> void:
	if session != null and session != s:
		session.leave()
	session = s
	session.changed.connect(_on_changed)
	session.status.connect(_say)
	if not (s is NetSession):
		session.closed.connect(func(reason: String) -> void:
			_leave()
			_join_status(reason))
	tool = PlayerTools.MoveTool.new(session, view.canvas)
	tool.zoom = view.zoom()
	view.set_handler(tool)
	view.canvas.viewpoint = session.player_id
	_show_scene()
	if not session.warnings.is_empty():
		_say("; ".join(session.warnings))


func _leave() -> void:
	if session != null:
		session.leave()
		session = null
	view.set_handler(null)
	tool = null
	view.canvas.state = null
	view.canvas.map = null
	show_screen("join")


# ====================================================================== play ==

func _show_scene() -> void:
	view.canvas.viewpoint = session.player_id
	view.canvas.set_scene(session.state, session.scene_id())
	view.zoom_to_fit.call_deferred()
	_refresh_bars()


func _on_changed(what: String, _scene: String) -> void:
	if session == null:
		return
	if what == "" or what == "active_scene" or what == "scenes" or view.canvas.scene_id != session.scene_id():
		# A reload, a scene switch, or a map that just arrived.
		var had_map := view.canvas.map != null
		view.canvas.viewpoint = session.player_id
		view.canvas.set_scene(session.state, session.scene_id())
		if what == "active_scene" or (not had_map and view.canvas.map != null):
			view.zoom_to_fit.call_deferred()
	else:
		view.canvas.refresh()
	_refresh_bars()


func _refresh_bars() -> void:
	if session == null or session.state == null:
		return
	var sc := session.state.encounter.scene(session.scene_id())
	_title.text = "%s — %s" % [session.state.encounter.name, str(sc.get("name", ""))] if not sc.is_empty() else session.state.encounter.name
	_turn.text = session.turn_summary()
	for c in _token_bar.get_children():
		_token_bar.remove_child(c)
		c.queue_free()
	var up := session.state.highlighted_token_ids()
	for tk in session.my_tokens():
		var b := _big(Button.new(), str(tk.get("label", "")))
		b.tooltip_text = str(tk.get("name", ""))
		b.custom_minimum_size.x = BAR_HEIGHT
		b.add_theme_color_override("font_color", Color(str(tk.get("color", "#ffffff"))))
		if up.has(str(tk.id)):
			b.theme_type_variation = "AccentButton"
		var id := str(tk.id)
		b.pressed.connect(func() -> void: _focus_token(id))
		_token_bar.add_child(b)


func _focus_token(id: String) -> void:
	var tk := session.state.token(session.scene_id(), id)
	if tk.is_empty():
		return
	view.camera.position = Vision.token_pos(tk) * view.canvas.ppx
	if view.zoom() < 0.3:
		view.set_zoom(0.5)
	tool.selected = id
	view.canvas.overlay.queue_redraw()


func _say(text: String) -> void:
	_status.text = text
	_status_timer = 4.0


func _process(delta: float) -> void:
	if _browsing:
		browser.poll(delta)
	if session == null:
		return
	if session is LocalSession:
		(session as LocalSession).tick(delta)
	else:
		session.poll()
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_status.text = ""


func _exit_tree() -> void:
	_stop_browsing()
	if app != null and app.theme_changed.is_connected(_on_theme):
		app.theme_changed.disconnect(_on_theme)
	if session != null:
		session.leave()
	if view != null:
		view.set_handler(null)
