extends TestCase
## The Player client.

const ANA := "pl_fe0170c1"
const BEN := "pl_393eb25a"


## A Godot client's session that notes each intent it sends, then sends it.
class Spy extends NetSession:
	var sent: Array = []

	func _init(p_address: String, p_port: int, p_packs: PackLibrary, p_name := "") -> void:
		super(p_address, p_port, p_packs, p_name)

	func intent(payload: Dictionary) -> String:
		sent.append(payload.duplicate(true))
		return super(payload)

	## The rules actions it asked for (not a card's answers).
	func asked() -> Array:
		return sent.filter(func(i: Dictionary) -> bool: return str(i.get("kind", "")) == "action")


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
	check(s.request(mv) == "The fight hasn't started: wait for initiative" and s.turn_summary() == "Waiting to begin", "ordered, not running: refused with a reason")
	s.state.apply({"t": "turns.set", "changes": {"running": true, "turn": 2}})
	# (the goblin whose turn it is is hidden: its name isn't said)
	check(s.request(mv) == "It's not your turn" and s.turn_summary().begins_with("Goblin's turn"), "someone else's turn")
	s.state.apply({"t": "token.set", "scene": sid, "id": gob.id, "changes": {"hidden": false}})
	check(s.request(mv) == "It's not your turn: Goblin's turn", "a creature in sight's turn, said by name")
	s.state.apply({"t": "token.set", "scene": sid, "id": gob.id, "changes": {"hidden": true}})
	s.state.apply({"t": "turns.set", "changes": {"turn": 0}})
	check(s.turn_summary().begins_with("Your turn: Ana's fighter") and s.request(mv) == "", "her turn: the move goes through")
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == Vector2(1, 1), "applied to the local copy")
	s.state.apply({"t": "turns.set", "changes": {"mode": "dm", "active": []}})
	check(s.request(mv) == "The DM hasn't given you the move yet" and s.turn_summary() == "Waiting for the DM", "dm mode, not ticked")
	s.state.apply({"t": "turns.set", "changes": {"active": [fighter.id]}})
	check(s.request(mv) == "" and s.turn_summary() == "You may move: Ana's fighter", "dm mode, ticked")
	s.state.apply({"t": "turns.set", "changes": {"mode": "free"}})
	check(s.turn_summary() == "Free movement", "free")
	check(s.request({"t": "token.set", "scene": sid, "id": gob.id, "changes": {"pos": [1, 1]}}) == "No such token", "a hidden token is refused even in free mode, and not said to be there")
	check(s.request({"t": "element.set", "scene": sid, "ref": "walls:x", "changes": {"state": "open"}}) == "Only the DM can do that", "non-move events are for the DM")
	check(s.request({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"hidden": true}}) == "A player moves a token; the DM changes the rest", "other fields are refused")
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
	check(Vision.token_pos(s.state.token(sid, fighter.id)) == to and told == ["It's not your turn"], "a refused move stays put and the player is told")
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
	check(win.screen == "join" and win._known.item_count == 0 and win._diag.text.begins_with("This device:") and not win._trouble.visible and not win._known.visible, "starts on the join screen: no tables joined yet, the network's details behind Trouble joining?")
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


# ------------------------------------------------------ what we know, on a tap --

## A ruleset that answers a tap on a creature (its `tap = "creature"`
## action: what the party knows of it, a card of its own), and keeps count.
const TAP_RULES := """
local hm = hexmap
-- (an action first by name that a tap doesn't ask)
hm.actions.register('aim', { label = 'Aim', target = 'token', run = function(ctx) return true end })
hm.actions.register('known', { label = 'What we know', target = 'token', tap = 'creature', run = function(ctx)
	local tid = tostring(ctx.target or ''):gsub('^token:', '')
	local st = hm.state.get('encounter') or {}
	hm.commit(hm.state.set('encounter', '', { asked = (tonumber(st.asked) or 0) + 1, last = tid, by = tostring(ctx.player) }), 'Asked')
	hm.prompt_open(ctx.player, { heading = 'What we know', title = 'The Goblin: bloodied; Frightened; its Armor Class not known; and what the party has seen it shrug off, a sentence longer than a phone is wide.',
		fields = {}, choices = { { id = 'close', label = 'Close' } } }, { default = { choice = 'close' }, deadline = 0 })
	return true
end })
"""


func _pump(host: HostSession, s: NetSession, done: Callable, max_ms := 4000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		host.poll(0.016)
		s.poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func _label(node: Node, begins: String) -> Label:
	for l in node.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with(begins):
			return l
	return null


func _button(node: Node, text: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _tap(tool: PlayerTools.MoveTool, at: Vector2) -> bool:
	var took := tool.press(at, MOUSE_BUTTON_LEFT, {})
	tool.release(at, MOUSE_BUTTON_LEFT, {})
	return took


## A player's Godot client asks what the party knows of a creature as she taps
## its token, as a web screen does: the ruleset's action registered with `tap
## = "creature"` (the first by plugin, then by name), aimed at the token on
## the scene she's shown. Its card comes back as the table's cards do — its
## heading and its words, which wrap — in front, in the Table pane. The same
## creature tapped again lets it go; her own token, another player's, a thing
## on the map, a creature she doesn't see or a press that wanders ask nothing,
## nor does any tap where no ruleset answers.
func test_what_we_know_on_a_tap() -> void:
	var acts := {"b.rules": {"look": {"label": "Look"}, "known": {"tap": "creature", "target": "token"}, "zzz": {"tap": "creature"}}, "a.rules": {"say": {"label": "Say"}}}
	check(PlayerTools.tap_action(acts) == {"plugin": "b.rules", "action": "known"}, "the action a tap asks: the first plugin, then the first action, with tap = creature")
	check(PlayerTools.tap_action({"a.rules": {"say": {"label": "Say", "tap": "item"}}}).is_empty() and PlayerTools.tap_action(null).is_empty(), "none where no ruleset answers one")
	var gob := {"id": "t_g", "actor": "a_g", "owner": null, "tags": ["humanoid"]}
	check(PlayerTools.asks_about(gob), "a creature no player owns is asked about")
	check(not PlayerTools.asks_about({"id": "t_f", "actor": "a_f", "owner": "pl_1"}) and not PlayerTools.asks_about({"id": "t_l", "actor": "a_g", "owner": null, "tags": ["object"]})
		and not PlayerTools.asks_about({"id": "t_x", "actor": "", "owner": null}) and not PlayerTools.asks_about({"id": "t_y", "actor": null}), "not the party's own, a thing, nor a token with nobody behind it")
	check(PlayerTools.tap_intent(acts, gob, "s_1") == {"kind": "action", "plugin": "b.rules", "action": "known", "ctx": {"target": "token:t_g", "scene": "s_1"}}, "the intent: the action aimed at the token, on the scene shown")
	check(PlayerTools.tap_intent({"a.rules": {"say": {}}}, gob, "s_1").is_empty(), "and none where no ruleset answers")
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := EncounterState.new(Encounter.load_file(example("chapel_ambush.encounter")))
	st.resolve_maps()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(plugins.load_source({"id": "t.tap", "version": "1", "api": 1, "name": "Tap", "capabilities": ["state", "log", "prompts"]}, [["main.lua", TAP_RULES]]) == "", "a ruleset that answers a tap")
	var fighter: Dictionary = st.tokens_owned_by(sid, ANA)[0]
	var ranger: Dictionary = st.tokens_owned_by(sid, BEN)[0]
	var gpos := Vector2(5.0, 7.4)
	var lpos := Vector2(4.0, 5.5)
	check(kernel.commit([
		{"t": "actor.add", "actor": {"id": "a_fighter", "kind": "pc", "name": "Ana's fighter", "owner": ANA}},
		{"t": "token.set", "scene": sid, "id": str(fighter.id), "changes": {"actor": "a_fighter"}},
		{"t": "actor.add", "actor": {"id": "a_gob", "kind": "npc", "name": "Goblin", "audience": {"visible": "all"}}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Goblin", gpos, {"id": "t_gob", "actor": "a_gob", "hidden": false, "tags": ["humanoid"]})},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Floating light", lpos, {"id": "t_obj", "actor": "a_gob", "hidden": false, "tags": ["object"]})},
		{"t": "actor.add", "actor": {"id": "a_lurk", "kind": "npc", "name": "Lurker"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Lurker", Vector2(3.5, 6.0), {"id": "t_lurk", "actor": "a_lurk", "hidden": true})},
	], "setup") == "", "set up: a goblin and a floating light by Ana's fighter, a lurker the DM hides")
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = kernel
	host.plugins = plugins
	host.dm_token = "sesame"
	host.dm_state_source = func() -> Dictionary: return {}
	check(host.start(49750, false, -1) == OK, "hosting")
	var app := App.new("user://test_prefs_player_tap.json")
	var win := PlayerWindow.new()
	win.app = app
	root.add_child(win)
	win._stop_browsing()
	var s := Spy.new("127.0.0.1", host.port, app.packs, "Ana's phone")
	check(s.connect_to_host() == OK and _pump(host, s, func() -> bool: return s.state != null), "her phone reaches the table")
	s.join(ANA)
	check(_pump(host, s, func() -> bool: return s.joined and s.maps_ready() and not s.view.is_empty() and not s.state.token(sid, "t_gob").is_empty()), "joined as Ana: her scene, its map, the rules' view")
	win._bind(s)
	win.show_screen("play")
	await tree.process_frame
	var tool := win.tool
	var in_view := win.view.canvas.tokens_in_view().map(func(t: Dictionary) -> String: return str(t.id))
	check(in_view.has("t_gob") and in_view.has("t_obj") and not in_view.has("t_lurk"), "she sees the goblin and the light, not the lurker: %s" % [in_view])
	# the goblin tapped: picked out, and what we know of it asked
	check(_tap(tool, gpos), "a press on the goblin is the tool's")
	check(s.asked().size() == 1 and s.asked()[0] == {"kind": "action", "plugin": "t.tap", "action": "known", "ctx": {"target": "token:t_gob", "scene": sid}},
		"a tap on the goblin asks the rules what we know of it, as a web screen does: %s" % [s.asked()])
	check(tool.selected == "t_gob", "and picks it out")
	check(_pump(host, s, func() -> bool: return not (s.view.get("prompts", []) as Array).is_empty()), "its card comes back")
	var card: Dictionary = s.view.prompts[0] if not (s.view.get("prompts", []) as Array).is_empty() else {}
	check(str(card.get("form", {}).get("heading", "")) == "What we know" and str(card.get("form", {}).get("title", "")).begins_with("The Goblin:"), "the card, for her: %s" % [card.get("form")])
	var rules := Views.plugin_state(kernel, "t.tap", Views.ROLE_GM)
	check(int(rules.get("asked", 0)) == 1 and str(rules.get("last", "")) == "t_gob" and str(rules.get("by", "")) == ANA, "the rules ran it at the goblin, for Ana: %s" % [rules])
	await tree.process_frame
	check(win.pane_mode == "table", "in front: the Table pane")
	var words := _label(win._pane_box, "The Goblin:")
	check(_label(win._pane_box, "What we know") != null and words != null, "the card there: its heading and its words")
	check(words != null and words.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "its words wrap on a narrow screen")
	# the same one again: let go, nothing asked
	_tap(tool, gpos)
	check(s.asked().size() == 1 and tool.selected == "", "the goblin tapped again: let go, nothing asked")
	# her own token: picked up to move; another player's, a thing, the hidden lurker: nothing
	_tap(tool, Vision.token_pos(fighter))
	check(s.asked().size() == 1 and tool.selected == str(fighter.id), "her own token: hers to move, nothing asked")
	_tap(tool, Vision.token_pos(ranger))
	check(s.asked().size() == 1 and tool.selected == "", "Ben's ranger: nothing asked")
	_tap(tool, lpos)
	check(s.asked().size() == 1 and tool.selected == "", "a thing on the map: nothing asked")
	_tap(tool, Vector2(3.5, 6.0))
	check(s.asked().size() == 1 and tool.selected == "", "where the hidden lurker stands: nothing asked, nothing picked out")
	# a press that wanders off the goblin, and a pinch's release away from it, aren't taps
	tool.press(gpos, MOUSE_BUTTON_LEFT, {})
	tool.drag(gpos + Vector2(0.6, 0.0), MOUSE_BUTTON_LEFT, {})
	tool.release(gpos + Vector2(0.6, 0.0), MOUSE_BUTTON_LEFT, {})
	tool.press(gpos, MOUSE_BUTTON_LEFT, {})
	tool.release(gpos + Vector2(1.5, 0.5), MOUSE_BUTTON_LEFT, {})
	check(s.asked().size() == 1 and tool.selected == "", "a drag from it, or a pinch's release away from it: nothing asked")
	# a pick in flight still takes the tap
	tool.begin_pick({"kind": "action", "plugin": "t.tap", "action": "aim", "pick": "token", "label": "Aim", "ctx": {"actor": "a_fighter"}})
	_tap(tool, gpos)
	check(s.asked().size() == 2 and str(s.asked().back().action) == "aim" and str(s.asked().back().ctx.target) == "token:t_gob" and tool.pick.is_empty(), "a pick in flight takes the tap as before: %s" % [s.asked().back()])
	# Close: the card goes
	var close := _button(win._pane_box, "Close")
	check(close != null, "the card's Close")
	if close != null:
		close.pressed.emit()
		check(_pump(host, s, func() -> bool: return (s.view.get("prompts", []) as Array).is_empty()), "Close: the card goes")
	# where no ruleset answers a tap, nothing is asked
	var plain: Dictionary = JsonDoc.deep(s.view.get("actions", {}))
	(plain["t.tap"]["known"] as Dictionary).erase("tap")
	s.view.actions = plain
	_tap(tool, gpos)
	check(s.asked().size() == 2 and tool.selected == "t_gob", "no ruleset answers a tap: the goblin picked out, nothing asked")
	win._leave()
	win._stop_browsing()   # (the join screen listens for tables: not here)
	host.stop()
	win.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_player_tap.json"))
