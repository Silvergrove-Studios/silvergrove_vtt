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
var _tables: ItemList
var _tables_label: Label
var _known: ItemList
var _diag: Label
var _diag_timer := 0.0
var browser := Discovery.Browser.new()
var _browsing := false
var _players: ItemList
var _pick_title: Label
var _pick_hint: Label
var _cogm_code: LineEdit
var _title: Label
var _turn: Label
var _status: Label
var _token_bar: HBoxContainer
var _pending_path := ""
var _status_timer := 0.0
var _columns: Array = []
var _safe: MarginContainer
## A display: joins as a screen everyone sees — no controls, the "all"
## audience, the map and the table's status. `--display [address]`.
var display_mode := false
## The side pane beside (or, on a phone, instead of) the map: "" (map
## only), "sheet" (my characters) or "table" (turns, prompts, tracks, log).
var pane_mode := ""
var _center: HBoxContainer
var _pane: ScrollContainer
var _pane_box: VBoxContainer
var _sheet_button: Button
var _table_button: Button
var _renderers: Array = []
var _seen_prompts: Dictionary = {}


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
	# Keep the UI out of the notch and the gesture bar.
	_safe = MarginContainer.new()
	bg.add_child(_safe)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 0)
	_safe.add_child(_root)
	_join = _build_join()
	_pick = _build_pick()
	_play = _build_play()
	for s in [_join, _pick, _play]:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_root.add_child(s)
	resized.connect(_fit)
	_fit()
	_restyle()


## Columns are 440 wide when there is room, the window minus a gutter when
## there is not; margins follow the safe area.
func _fit() -> void:
	var insets := App.safe_insets(get_window().content_scale_factor if is_inside_tree() else 1.0)
	if _safe != null:
		_safe.add_theme_constant_override("margin_left", int(insets.left))
		_safe.add_theme_constant_override("margin_top", int(insets.top))
		_safe.add_theme_constant_override("margin_right", int(insets.right))
		_safe.add_theme_constant_override("margin_bottom", int(insets.bottom))
	var avail: float = size.x - float(insets.left) - float(insets.right) - 32.0
	for c in _columns:
		(c as Control).custom_minimum_size.x = minf(440.0, maxf(200.0, avail))
	_layout_pane()


func _big(b: Button, text := "", icon := "") -> Button:
	b.text = text
	if icon != "":
		b.set_meta("icon", icon)
	b.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	return b


## A centred column that scrolls when the screen is shorter than it (a
## phone held sideways).
func _scrolling_column(column: VBoxContainer) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(column)
	scroll.add_child(center)
	return scroll


func _build_join() -> Control:
	var column := VBoxContainer.new()
	_columns.append(column)
	column.add_theme_constant_override("separation", 12)
	var center := _scrolling_column(column)
	var title := Label.new()
	title.text = "Player"
	title.theme_type_variation = "HeaderLabel"
	column.add_child(title)
	var stamp := Label.new()
	stamp.text = App.build_stamp()
	stamp.theme_type_variation = "DimLabel"
	column.add_child(stamp)
	var h := Label.new()
	h.text = "Join a table"
	h.theme_type_variation = "DimLabel"
	column.add_child(h)
	_tables_label = Label.new()
	_tables_label.text = "Listening for tables on this network…"
	_tables_label.theme_type_variation = "DimLabel"
	column.add_child(_tables_label)
	_tables = ItemList.new()
	_tables.custom_minimum_size = Vector2(0, 100)
	# A tap picks (fills the address, Join connects); a double tap connects.
	_tables.item_selected.connect(func(i: int) -> void: _pick_table(_tables.get_item_metadata(i)))
	_tables.item_activated.connect(func(i: int) -> void:
		_pick_table(_tables.get_item_metadata(i))
		_join_address())
	column.add_child(_tables)
	browser.updated.connect(_refresh_tables)
	var row := HBoxContainer.new()
	_address = LineEdit.new()
	_address.placeholder_text = "Table address"
	_address.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _join_address())
	row.add_child(_address)
	# Godot's text field has no touch paste; the clipboard is one tap away.
	var paste := _big(Button.new(), "Paste")
	paste.tooltip_text = "Paste an address from the clipboard"
	paste.pressed.connect(func() -> void:
		var t := DisplayServer.clipboard_get().strip_edges()
		if t != "":
			_address.text = t
			_join_status("Pasted %s — tap Join" % t)
		else:
			_join_status("The clipboard is empty"))
	row.add_child(paste)
	var join := _big(Button.new(), "Join")
	join.theme_type_variation = "AccentButton"
	join.pressed.connect(_join_address)
	row.add_child(join)
	column.add_child(row)
	var h2 := Label.new()
	h2.text = "Tables you have joined before"
	h2.theme_type_variation = "DimLabel"
	column.add_child(h2)
	_known = ItemList.new()
	_known.custom_minimum_size = Vector2(0, 100)
	_known.item_selected.connect(func(i: int) -> void: _pick_table(_known.get_item_metadata(i)))
	_known.item_activated.connect(func(i: int) -> void:
		_pick_table(_known.get_item_metadata(i))
		_join_address())
	column.add_child(_known)
	_diag = Label.new()
	_diag.theme_type_variation = "DimLabel"
	_diag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_diag)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var home := _big(Button.new(), "Home")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.pressed.connect(func() -> void: go_home.emit())
	row2.add_child(home)
	var smaller := _big(Button.new(), "A−")
	smaller.tooltip_text = "Smaller text and buttons"
	smaller.custom_minimum_size.x = BAR_HEIGHT * 1.2
	smaller.pressed.connect(func() -> void: app.step_ui_scale(false))
	row2.add_child(smaller)
	var bigger := _big(Button.new(), "A+")
	bigger.tooltip_text = "Bigger text and buttons"
	bigger.custom_minimum_size.x = BAR_HEIGHT * 1.2
	bigger.pressed.connect(func() -> void: app.step_ui_scale(true))
	row2.add_child(bigger)
	column.add_child(row2)
	var status := Label.new()
	status.name = "JoinStatus"
	status.theme_type_variation = "DimLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	return center


# ================================================================ characters ==

## Send one of the characters kept on this device to the table, to play
## as mine. "" or why not (the table's refusal arrives through status).
func bring_character(doc: Dictionary) -> String:
	if session == null:
		return "not at a table"
	var why := CharacterFile.check(doc)
	if why != "":
		return why
	return session.intent({"kind": "character", "character": doc})


## Keep one of my characters, as the table has it now, on this device.
func keep_character(actor_id: String) -> String:
	if session == null:
		return "not at a table"
	for a in session.my_actors():
		if str(a.get("id", "")) == actor_id:
			var doc := CharacterFile.from_view(a, session.view.get("plugins", []))
			var why := CharacterFile.save(doc)
			_say("Kept %s on this device" % str(a.get("name", "")) if why == "" else why)
			return why
	return "no such character of mine"


## The characters on this device that are not already at the table.
func characters_to_bring() -> Array:
	var here := {}
	if session != null:
		for a in session.my_actors():
			here[str(a.get("id", ""))] = true
	var out := []
	for c in CharacterFile.list():
		if not here.has(str(c.doc.actor.id)):
			out.append(c)
	return out


func _build_pick() -> Control:
	var column := VBoxContainer.new()
	_columns.append(column)
	column.add_theme_constant_override("separation", 12)
	var center := _scrolling_column(column)
	_pick_title = Label.new()
	_pick_title.theme_type_variation = "HeaderLabel"
	column.add_child(_pick_title)
	_pick_hint = Label.new()
	_pick_hint.text = "Who are you?"
	_pick_hint.theme_type_variation = "DimLabel"
	_pick_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_pick_hint)
	_players = ItemList.new()
	_players.custom_minimum_size = Vector2(0, 200)
	_players.item_selected.connect(func(i: int) -> void: _start(str(_players.get_item_metadata(i))))
	column.add_child(_players)
	# a second GM: the table shows a code; this device gets the GM's view
	var cogm := HBoxContainer.new()
	_cogm_code = LineEdit.new()
	_cogm_code.placeholder_text = "Co-GM code"
	_cogm_code.max_length = 4
	_cogm_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cogm_code.text_submitted.connect(func(_t: String) -> void: _join_as_cogm())
	cogm.add_child(_cogm_code)
	var cb := _big(Button.new(), "Join as co-GM")
	cb.tooltip_text = "The whole table on this device, with the code shown on the Table's Players panel"
	cb.pressed.connect(_join_as_cogm)
	cogm.add_child(cb)
	column.add_child(cogm)
	var back := _big(Button.new(), "Back")
	back.pressed.connect(func() -> void: show_screen("join"))
	column.add_child(back)
	return center


func _join_as_cogm() -> void:
	if not (session is NetSession):
		_say("Co-GMs join a hosted table")
		return
	var code := _cogm_code.text.strip_edges()
	if code == "":
		_say("Type the code the Table shows")
		return
	(session as NetSession).join("", Views.ROLE_COGM, code)


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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.6
	_token_bar = HBoxContainer.new()
	scroll.add_child(_token_bar)
	top.add_child(scroll)
	var fit := _big(Button.new(), "", "maximize")
	fit.tooltip_text = "Fit the map"
	fit.theme_type_variation = "ToolButton"
	fit.pressed.connect(func() -> void: view.zoom_to_fit())
	top.add_child(fit)
	box.add_child(top)
	_sheet_button = _big(Button.new(), "Sheet")
	_sheet_button.theme_type_variation = "ToolButton"
	_sheet_button.toggle_mode = true
	_sheet_button.pressed.connect(func() -> void: set_pane("sheet" if pane_mode != "sheet" else ""))
	top.add_child(_sheet_button)
	_table_button = _big(Button.new(), "Table")
	_table_button.theme_type_variation = "ToolButton"
	_table_button.toggle_mode = true
	_table_button.pressed.connect(func() -> void: set_pane("table" if pane_mode != "table" else ""))
	top.add_child(_table_button)
	_center = HBoxContainer.new()
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.add_theme_constant_override("separation", 0)
	view = CanvasView.new()
	view.canvas.packs = app.packs
	view.canvas.show_hidden = false
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.zoom_changed.connect(func(z: float) -> void:
		if tool != null:
			tool.zoom = z)
	_center.add_child(view)
	_pane = ScrollContainer.new()
	_pane.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pane.custom_minimum_size.x = 360
	_pane.visible = false
	_pane_box = VBoxContainer.new()
	_pane_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pane_box.add_theme_constant_override("separation", 10)
	_pane.add_child(_pane_box)
	_center.add_child(_pane)
	box.add_child(_center)
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
		_refresh_known()
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
	for t in app.tables():
		browser.remember(str(t.get("address", "")))
	_refresh_tables()
	_refresh_diag()


func _stop_browsing() -> void:
	if _browsing:
		browser.stop()
		_browsing = false


func _refresh_tables() -> void:
	_tables.clear()
	for t in browser.list():
		var extra: int = (t.get("addresses", []) as Array).size() - 1
		var i := _tables.add_item("%s  —  %s:%d%s" % [str(t.name), str(t.address), int(t.port), ("  (+%d)" % extra) if extra > 0 else ""])
		_tables.set_item_metadata(i, t)
		_tables.set_item_tooltip(i, "heard via %s; addresses: %s" % [str(t.get("via", "")), ", ".join(PackedStringArray(t.get("addresses", [])))])
	if _browsing:
		_tables_label.text = "Tables on this network" if _tables.item_count > 0 else "Listening for tables on this network…"


# ====================================================================== join ==

func _refresh_known() -> void:
	_known.clear()
	for t in app.tables():
		var i := _known.add_item("%s  —  %s:%d" % [str(t.get("name", "")), str(t.get("address", "")), int(t.get("port", 0))])
		_known.set_item_metadata(i, t)


## Where this device is and what discovery has done, so a player and a
## DM on the phone together can tell a subnet problem from a dead table.
func _refresh_diag() -> void:
	if _diag == null:
		return
	var ips := App.local_ipv4()
	var text := "This device: %s · %s" % [", ".join(ips) if not ips.is_empty() else "no network", browser.summary()]
	if text != _diag.text:
		_diag.text = text
		print("discovery: " + text)   # logcat / stdout, for a device one cannot read


## A table from either list: put its address in the box so Join takes it;
## the other addresses it was heard at are kept as fallbacks for Join.
var _alternatives: Array = []

func _pick_table(t: Dictionary) -> void:
	_address.text = "%s:%d" % [str(t.get("address", "")), int(t.get("port", Protocol.DEFAULT_PORT))]
	_alternatives = []
	for a in t.get("addresses", []):
		if str(a) != str(t.get("address", "")):
			_alternatives.append(str(a))
	_join_status("%s — tap Join" % str(t.get("name", "")))


func _join_address() -> void:
	var text := _address.text.strip_edges()
	if text == "":
		_join_status("Type the address the DM's table shows, or pick a table above.")
		return
	var hp := Protocol.parse_address(text)
	browser.remember(str(hp[0]))
	var alts := _alternatives.duplicate()
	_alternatives = []
	_connect_to(str(hp[0]), int(hp[1]), alts)


## Connect to a table; the welcome brings the players to pick from. A table
## heard at several addresses is tried at each in turn until one answers.
func _connect_to(address: String, port: int, alternatives: Array = []) -> void:
	if session != null:
		session.leave()
		session = null
	var s := NetSession.new(address, port, app.packs, OS.get_environment("USER"))
	var err := s.connect_to_host()
	if err != OK:
		_join_status("Could not connect to %s:%d: %s" % [address, port, error_string(err)])
		return
	session = s
	_join_status("Connecting to %s:%d…" % [address, port] + (" (then %d more to try)" % alternatives.size() if not alternatives.is_empty() else ""))
	s.connected.connect(func() -> void:
		_pending_path = ""
		_pick_title.text = s.state.encounter.name
		_players.clear()
		for p in s.state.encounter.players:
			var i := _players.add_item(str(p.get("name", "")))
			_players.set_item_metadata(i, str(p.get("id", "")))
			_players.set_item_custom_fg_color(i, Color(str(p.get("color", "#ffffff"))))
		if display_mode:
			s.join("", "display")
			return
		_pick_hint.text = "Who are you?" if not s.state.encounter.players.is_empty() else "'%s' has no players yet. Ask the DM to add them — or join as a co-GM." % s.state.encounter.name
		show_screen("pick"))
	s.joined_as.connect(func(_pid: String) -> void:
		app.note_table(address, port, s.state.encounter.name)
		_bind(s)
		show_screen("play")
		if display_mode:
			set_pane("table" if size.x > 900 else "")
		view.zoom_to_fit.call_deferred())
	s.closed.connect(func(reason: String) -> void:
		if session != s:
			return
		if s.state == null and not alternatives.is_empty():
			# Never welcomed: this address does not reach it; try the next.
			var rest := alternatives.duplicate()
			var next := str(rest.pop_front())
			session = null
			_join_status("%s at %s; trying %s" % [reason, address, next])
			_connect_to(next, port, rest)
			return
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
	session.view_changed.connect(_on_view)
	if display_mode:
		tool = null
		view.set_handler(null)
	else:
		tool = PlayerTools.MoveTool.new(session, view.canvas)
		tool.zoom = view.zoom()
		view.set_handler(tool)
	view.canvas.viewpoint = session.player_id
	_show_scene()
	_on_view()
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
	_clear_pane()
	show_screen("join")


# ====================================================================== pane ==

## Show a pane beside the map (wide screens) or instead of it (phones).
func set_pane(mode: String) -> void:
	pane_mode = mode
	_layout_pane()
	_render_pane()


## Wide: the map and a 360-wide pane side by side. Narrow: one or the other.
func _layout_pane() -> void:
	if _pane == null:
		return
	var wide := size.x > 900
	_pane.visible = pane_mode != ""
	view.visible = wide or pane_mode == ""
	_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not wide else Control.SIZE_FILL
	_pane.custom_minimum_size.x = 360 if wide else 0
	_sheet_button.button_pressed = pane_mode == "sheet"
	_table_button.button_pressed = pane_mode == "table"
	_sheet_button.visible = not display_mode


func _clear_pane() -> void:
	_renderers.clear()
	for c in _pane_box.get_children():
		_pane_box.remove_child(c)
		c.queue_free()


## The table sent a new projection: redraw the pane, badge the buttons,
## and bring a prompt for me to the front.
func _on_view() -> void:
	if session == null:
		return
	var v := session.view
	var prompts: Array = v.get("prompts", [])
	_table_button.text = "Table" + (" (%d)" % prompts.size() if not prompts.is_empty() else "")
	_sheet_button.text = "Sheet" if session.my_actors().is_empty() else "Sheet (%d)" % session.my_actors().size()
	var fresh := false
	for p in prompts:
		if not _seen_prompts.has(str(p.get("id", ""))):
			fresh = true
			_seen_prompts[str(p.get("id", ""))] = true
	if fresh and pane_mode != "table" and not display_mode:
		set_pane("table")
		return
	_render_pane()
	_refresh_bars()


func _render_pane() -> void:
	_clear_pane()
	if session == null or pane_mode == "":
		return
	var v := session.view
	match pane_mode:
		"sheet":
			var mine := session.my_actors()
			if mine.is_empty():
				_pane_text("No character of yours here. Ask the DM to give you one, or bring one below." if not v.is_empty() else "Waiting for the table…", "dim")
			for a in mine:
				_pane_text(str(a.get("name", "")), "header")
				var sheets: Array = a.get("sheets", [])
				if sheets.is_empty():
					_pane_render(_default_sheet(), {"actor": a, "ext": a.get("ext", {}), "derived": a.get("derived", {}), "resources": a.get("resources", {}), "effects": a.get("effects", [])})
				for sh in sheets:
					_pane_render(sh.get("schema", {}), sh.get("data", {}))
				if not (a.get("outdated", {}) as Dictionary).is_empty():
					_pane_text("Built against older content: %s" % [a.outdated.keys()], "dim")
				var keep := Button.new()
				keep.text = "Keep %s on this device" % str(a.get("name", ""))
				var aid := str(a.get("id", ""))
				keep.pressed.connect(func() -> void: keep_character(aid))
				_pane_box.add_child(keep)
			if not display_mode:
				for c in characters_to_bring():
					var b := Button.new()
					b.text = "Bring %s" % str(c.doc.actor.name)
					b.tooltip_text = str(c.path)
					var doc: Dictionary = c.doc
					b.pressed.connect(func() -> void:
						var why := bring_character(doc)
						if why != "":
							_say(why))
					_pane_box.add_child(b)
		"table":
			_pane_render(_table_schema(v), v)
			# a plugin's status view binds to its own data (me, role, actors as a
			# list, state…), not to the raw projection
			for stv in v.get("status", []):
				_pane_text(str(stv.get("plugin", "")), "header")
				_pane_render(stv.get("schema", {}), stv.get("data", {}))


func _pane_text(text: String, style := "") -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if style == "header":
		l.theme_type_variation = "HeaderLabel"
	elif style == "dim":
		l.theme_type_variation = "DimLabel"
	_pane_box.add_child(l)


func _pane_render(schema: Dictionary, data: Dictionary) -> void:
	var r := ViewRenderer.new()
	r.intent.connect(_send_intent)
	r.pick_requested.connect(_begin_pick)
	if session != null:
		r.comp_source = session.comp
	r.packs = app.packs if app != null else null
	_pane_box.add_child(r)
	r.render(schema, data)
	_renderers.append(r)


## An intent that wants a target on the map: show the map and let the
## tool take the next tap.
func _begin_pick(payload: Dictionary) -> void:
	if session == null or tool == null:
		_say("This screen cannot pick a target")
		return
	if pane_mode != "" and size.x <= 900:
		set_pane("")
	tool.begin_pick(payload)


func _send_intent(payload: Dictionary) -> void:
	if session == null:
		return
	var why := session.intent(payload)
	if why != "":
		_say(why)


## What a character looks like when its ruleset registered no sheet: the
## derived numbers, the resources and the effects, plainly.
func _default_sheet() -> Dictionary:
	return {"type": "column", "children": [
		{"type": "section", "title": "Numbers", "children": [
			{"type": "list", "expr": "@derived", "item": {"type": "text", "expr": "str(@item)"}, "empty": "nothing derived"}]},
		{"type": "section", "title": "Resources", "children": [
			{"type": "list", "expr": "@resources", "item": {"type": "text", "expr": "str(@item)"}, "empty": "none"}]},
		{"type": "section", "title": "Effects", "children": [{"type": "effects", "bind": "/effects"}]},
	]}


## The table pane: turns or focus (with a request button for my tokens),
## prompts for me, rolls I may help with, the plugins' status views,
## tracks, and the log.
func _table_schema(v: Dictionary) -> Dictionary:
	var children := []
	var turns: Dictionary = v.get("turns", {})
	var focus_shape := str(turns.get("strategy", "ordered")) == "focus" and bool(turns.get("running", false))
	children.append({"type": "text", "text": session.turn_summary() if not focus_shape else "Focus: " + _holder_name(str(turns.get("focus", ""))), "style": "header"})
	if focus_shape and not display_mode:
		var acts := []
		for tk in session.my_tokens():
			acts.append({"type": "button", "label": "Ask for the focus: " + str(tk.get("name", "")), "intent": {"kind": "focus", "ref": "token:" + str(tk.id)}})
		if not acts.is_empty():
			children.append({"type": "action_bar", "actions": acts})
	if not (v.get("prompts", []) as Array).is_empty():
		var items := []
		for i in (v.prompts as Array).size():
			items.append({"type": "prompt", "bind": "/prompts/%d" % i})
		children.append({"type": "section", "title": "For you", "children": items})
	if not (v.get("rolls", []) as Array).is_empty() and not display_mode:
		var items := []
		for i in (v.rolls as Array).size():
			var r: Dictionary = v.rolls[i]
			items.append({"type": "row", "children": [
				{"type": "text", "text": "%s (%s)" % [str(r.get("label", "A roll")), str(r.get("by", ""))]},
				{"type": "button", "label": "Help (1d6)", "intent": {"kind": "contribute", "roll": str(r.get("id", "")), "name": "help_" + session.player_id, "expr": "1d6"}}]})
		children.append({"type": "section", "title": "Open rolls", "children": items})
	if not (v.get("tracks", []) as Array).is_empty():
		var items := []
		for i in (v.tracks as Array).size():
			items.append({"type": "tracker", "bind": "/tracks/%d" % i})
		children.append({"type": "section", "title": "Tracks", "children": items})
	children.append({"type": "section", "title": "Log", "children": [{"type": "log", "bind": "/log", "limit": 12}]})
	# status views bind to their own data, so they are rendered on the spot
	var schema := {"type": "column", "children": []}
	for c in children:
		if c.get("type") == "section" and (c.children as Array).size() == 1 and (c.children[0] as Dictionary).has("type") and v.get("status", []).any(func(st: Dictionary) -> bool: return st.schema == c.children[0]):
			continue
		schema.children.append(c)
	return schema


func _holder_name(ref: String) -> String:
	if ref == "gm":
		return "the GM"
	if ref.begins_with("token:") and session.state != null:
		var tk := session.state.find_token(ref.substr(6))
		return str(tk.get("name", ref)) if not tk.is_empty() else ref
	if ref.begins_with("actor:"):
		return str(session.view.get("actors", {}).get(ref.substr(6), {}).get("name", ref))
	return "nobody"


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
		_diag_timer += delta
		if _diag_timer > 1.0:
			_diag_timer = 0.0
			_refresh_diag()
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
