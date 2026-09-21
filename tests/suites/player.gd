extends TestCase
## The Player client.


func test_local_session() -> void:
	var src := example("chapel_ambush.encounter")
	var path := ProjectSettings.globalize_path("user://test_session.encounter")
	# Copy beside the map so map_path resolves: point at the examples dir instead.
	var s := LocalSession.new(src, "nobody")
	var told := []
	s.status.connect(func(t: String) -> void: told.append(t))
	check(s.open() == "" and s.state != null and s.warnings.is_empty(), "opens the example and finds its map")
	check(told.size() == 1 and told[0].contains("no player"), "an unknown player id is reported")
	var ana: Dictionary = s.state.encounter.players[0]
	s.player_id = str(ana.id)
	check(s.player_name() == "Ana" and s.my_tokens().size() == 1 and s.scene_id() == s.state.encounter.active_scene_id, "player, tokens, scene")
	var sid := s.scene_id()
	var fighter: Dictionary = s.my_tokens()[0]
	var gob: Dictionary = s.state.tokens(sid)[2]
	var mv := {"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [1, 1]}}
	check(s.request(mv) == "Turns have not begun" and s.turn_summary() == "Waiting to begin", "ordered, not running: refused with a reason")
	s.state.apply({"t": "turns.set", "changes": {"running": true, "turn": 2}})
	check(s.request(mv) == "Not your turn" and s.turn_summary().begins_with("Goblin's turn"), "someone else's turn")
	s.state.apply({"t": "turns.set", "changes": {"turn": 0}})
	check(s.turn_summary().begins_with("Your turn: Ana's fighter") and s.request(mv) == "", "her turn: the move goes through")
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == Vector2(1, 1), "applied to the local copy")
	s.state.apply({"t": "turns.set", "changes": {"mode": "dm", "active": []}})
	check(s.request(mv) == "The DM has not given you the move" and s.turn_summary() == "Waiting for the DM", "dm mode, not ticked")
	s.state.apply({"t": "turns.set", "changes": {"active": [fighter.id]}})
	check(s.request(mv) == "" and s.turn_summary() == "You may move: Ana's fighter", "dm mode, ticked")
	s.state.apply({"t": "turns.set", "changes": {"mode": "free"}})
	check(s.turn_summary() == "Free movement", "free")
	check(s.request({"t": "token.set", "scene": sid, "id": gob.id, "changes": {"pos": [1, 1]}}) == "You cannot move that", "a hidden token is refused even in free mode")
	check(s.request({"t": "element.set", "scene": sid, "ref": "walls:x", "changes": {"state": "open"}}) == "Only the DM can do that", "non-move events are for the DM")
	check(s.request({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"hidden": true}}) == "You cannot move that", "other fields are refused")
	check(s.request({"t": "token.set", "scene": sid, "id": "zz", "changes": {"pos": [0, 0]}}) == "No such token", "unknown token")
	# The file changing on disk reloads the state; a missing file closes.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src).replace('"name": "Chapel Ambush"', '"name": "Copy"'))
	f.close()
	var s2 := LocalSession.new(path, str(ana.id))
	check(s2.open() == "" and s2.state.encounter.name == "Copy", "opens a copy (its map warning is fine: %s)" % [s2.warnings])
	var changes := []
	s2.changed.connect(func(w: String, _sc: String) -> void: changes.append(w))
	s2.poll()
	check(changes.is_empty(), "unchanged file: no reload")
	OS.delay_msec(1100)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src).replace('"name": "Chapel Ambush"', '"name": "Saved again"'))
	f.close()
	s2.tick(0.5)
	check(changes.is_empty(), "tick below the poll interval does nothing")
	s2.tick(0.6)
	check(changes == [""] and s2.state.encounter.name == "Saved again", "a newer file is reloaded")
	var closed := []
	s2.closed.connect(func(r: String) -> void: closed.append(r))
	DirAccess.remove_absolute(path)
	s2.poll()
	check(closed.size() == 1 and s2.path == "", "a vanished file closes the session")
	check(Session.new().request({}) == "no session" and Session.new().turn_summary() == "" and Session.new().player_name() == "the DM", "the base session is inert")


func test_player_tool() -> void:
	var s := LocalSession.new(example("chapel_ambush.encounter"), "")
	s.open()
	s.player_id = str(s.state.encounter.players[0].id)
	s.state.apply({"t": "turns.set", "changes": {"mode": "free"}})
	var canvas := MapCanvas.new()
	canvas.packs = PackLibrary.new()
	canvas.set_scene(s.state, s.scene_id())
	var tool := PlayerTools.MoveTool.new(s, canvas)
	var sid := s.scene_id()
	var fighter: Dictionary = s.my_tokens()[0]
	var ranger: Dictionary = s.state.tokens(sid)[1]
	var from := Vision.token_pos(fighter)
	var mods := {}
	check(tool.token_at(from).id == fighter.id and tool.token_at(Vision.token_pos(ranger)).is_empty(), "only my own tokens can be picked up")
	check(not tool.press(Vision.token_pos(ranger), MOUSE_BUTTON_LEFT, mods) and tool.selected == "", "pressing another's token does nothing")
	check(tool.press(from, MOUSE_BUTTON_LEFT, mods) and tool.selected == fighter.id, "press picks mine")
	tool.drag(from + Vector2(0.03, 0.02), MOUSE_BUTTON_LEFT, mods)
	tool.release(from + Vector2(0.03, 0.02), MOUSE_BUTTON_LEFT, mods)
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == from and tool.selected == fighter.id, "a wobble is a tap: no move, still selected")
	var g := canvas.map.grid
	var to := g.cell_center(g.world_to_axial(from) + Vector2i(1, 0))
	tool.press(from, MOUSE_BUTTON_LEFT, mods)
	tool.drag(to + Vector2(0.1, 0.05), MOUSE_BUTTON_LEFT, mods)
	check(tool._moved, "a real drag")
	tool.release(to + Vector2(0.1, 0.05), MOUSE_BUTTON_LEFT, mods)
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == to, "released on the snapped centre")
	var told := []
	s.status.connect(func(t: String) -> void: told.append(t))
	s.state.apply({"t": "turns.set", "changes": {"mode": "ordered", "running": true, "turn": 2}})
	tool.press(to, MOUSE_BUTTON_LEFT, mods)
	tool.drag(from, MOUSE_BUTTON_LEFT, mods)
	tool.release(from, MOUSE_BUTTON_LEFT, mods)
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == to and told == ["Not your turn"], "a refused move stays put and the player is told")
	check(not tool.press(Vector2(0.1, 0.1), MOUSE_BUTTON_LEFT, mods) and tool.selected == "", "tapping empty ground deselects")
	canvas.free()


func test_player_tool_on_a_square_map() -> void:
	var s := LocalSession.new(example("chapel_ambush.encounter"), "")
	s.open()
	s.player_id = str(s.state.encounter.players[0].id)
	var cellar := HexMap.load_file(example("cellar.hexmap"))
	s.state.attach_map(cellar)
	var sc := Encounter.new_scene(cellar, "ground", "The cellar", "cellar.hexmap")
	s.state.apply({"t": "scene.add", "scene": sc})
	s.state.apply({"t": "scene.activate", "id": sc.id})
	s.state.apply({"t": "turns.set", "changes": {"mode": "free"}})
	var sid := s.scene_id()
	check(sid == str(sc.id), "the player is on the cellar")
	s.state.apply({"t": "token.add", "scene": sid, "token": Encounter.new_token("Fighter", cellar.grid.cell_center(Vector2i(7, 3)), {"id": "t_sq", "owner": s.player_id})})
	var canvas := MapCanvas.new()
	canvas.packs = PackLibrary.new()
	canvas.set_scene(s.state, sid)
	var tool := PlayerTools.MoveTool.new(s, canvas)
	var from := Vector2(7.5, 3.5)
	check(tool.token_at(from).id == "t_sq", "my token on the square")
	tool.press(from, MOUSE_BUTTON_LEFT, {})
	tool.drag(Vector2(8.8, 4.7), MOUSE_BUTTON_LEFT, {})
	tool.release(Vector2(8.8, 4.7), MOUSE_BUTTON_LEFT, {})
	check(Vision.token_pos(s.state.token(sid, "t_sq")) == Vector2(8.5, 4.5), "a diagonal drag lands on the square's centre")
	canvas.free()


func test_player_window() -> void:
	var app := App.new("user://test_prefs_player.json")
	var win := PlayerWindow.new()
	win.app = app
	root.add_child(win)
	check(win.screen == "join" and win._known.item_count == 0 and win._diag.text.begins_with("This device:"), "starts on the join screen: no tables joined yet, diagnostics shown")
	win._join_address()
	check((win._join.find_child("JoinStatus", true, false) as Label).text.begins_with("Type the address"), "joining an empty address asks for one")
	win._choose_file("/nowhere/x.encounter")
	check(win.screen == "join" and (win._join.find_child("JoinStatus", true, false) as Label).text.begins_with("Could not open"), "a bad file is reported")
	var path := example("chapel_ambush.encounter")
	win.open_argument("examples/chapel_ambush.encounter")
	check(win.screen == "pick" and win._players.item_count == 2 and win._pick_title.text == "Chapel Ambush", "a relative path from the shell reaches the player picker")
	win._start(str(win._players.get_item_metadata(1)))
	check(win.screen == "play" and win.session is LocalSession and win.session.player_name() == "Ben", "playing as Ben")
	check(win.view.canvas.viewpoint == win.session.player_id and win.view.canvas.scene_id == win.session.scene_id() and win.view.canvas.map != null, "the canvas shows the scene through Ben")
	check(win.view.canvas.tokens_in_view().size() == 2 and not win.view.canvas.show_hidden, "party visible, goblins not")
	check(win._token_bar.get_child_count() == 1 and (win._token_bar.get_child(0) as Button).text == "BR", "one token button, his ranger")
	check(win._turn.text == "Waiting to begin" and win._title.text.contains("Chapel at dusk"), "bars filled")
	check(app.recent().any(func(r) -> bool: return str(r).ends_with("chapel_ambush.encounter")), "noted as recent (wherever resolve_path found it): %s" % [app.recent()])
	# The DM switches the shown scene: the player follows.
	var st: EncounterState = win.session.state
	var crypt := str(st.encounter.scenes[1].id)
	st.apply({"t": "scene.activate", "id": crypt})
	check(win.view.canvas.scene_id == crypt and win.view.canvas.level().id == "crypt" and win._token_bar.get_child_count() == 0, "follows the active scene; no tokens of his there")
	st.apply({"t": "scene.activate", "id": str(st.encounter.scenes[0].id)})
	# Turn changes update the bar; his token lights up when it is his turn.
	st.apply({"t": "turns.set", "changes": {"mode": "ordered", "running": true, "turn": 1}})
	check(win._turn.text.begins_with("Your turn: Ben's ranger") and (win._token_bar.get_child(0) as Button).theme_type_variation == "AccentButton", "his turn shows on the bar and the button")
	# Focus a token, status messages fade, leave.
	var ranger: Dictionary = win.session.my_tokens()[0]
	win._focus_token(ranger.id)
	check(win.tool.selected == ranger.id and win.view.camera.position == Vision.token_pos(ranger) * win.view.canvas.ppx, "focus centres and selects")
	win._say("hello")
	check(win._status.text == "hello", "status shown")
	win._process(5.0)
	check(win._status.text == "", "and fades")
	win._leave()
	check(win.screen == "join" and win.session == null and win.view.canvas.state == null, "leave returns to join")
	win._stop_browsing()   # free the discovery port now; queue_free waits for the frame
	win.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_player.json"))
