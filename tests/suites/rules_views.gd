extends TestCase
## Phase 4: the projection of the rules for an audience, and the whole
## thing over the wire — a Player's sheet from the plugin, intents, a
## prompt answered from the phone, a helped roll, a display that sees the
## table but may do nothing, a v1 client refused.


func _state() -> EncounterState:
	var st := EncounterState.new(Encounter.create("Views"))
	st.encounter.doc.rng = {"seed": 4242, "index": 0}
	return st


func test_projection_audience() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _state()
	var k := RulesKernel.new(st)
	var host := PluginHost.new(k)
	check(host.load_dir("res://tests/plugins/sample.focus") == "", "sample.focus loads")
	st.apply({"t": "player.add", "player": {"id": "pl_1", "name": "Ana", "color": "#4f9cf6"}})
	st.apply({"t": "player.add", "player": {"id": "pl_2", "name": "Ben", "color": "#5bc86a"}})
	st.apply({"t": "scene.add", "scene": {"id": "s_1", "name": "G", "map": "", "map_path": "", "level": "ground", "overrides": {}, "fog": {"enabled": false, "explored": []}, "tokens": []}})
	check(k.commit([
		{"t": "actor.add", "actor": {"id": "a_ana", "kind": "pc", "name": "Ana's rogue", "owner": "pl_1", "ext": {"sample.focus": {"traits": {"nerve": 1, "grace": 2, "wit": 0}, "hand": ["dash"], "vault": ["rally"], "secret": "likes Ben"}},
			"audience": {"fields": {"ext/sample.focus/secret": "owner"}}}},
		{"t": "actor.add", "actor": {"id": "a_ben", "kind": "pc", "name": "Ben's bard", "owner": "pl_2", "ext": {"sample.focus": {"traits": {"nerve": 0, "grace": 0, "wit": 3}}}}},
		{"t": "actor.add", "actor": {"id": "a_gob", "kind": "npc", "name": "Goblin", "ext": {"sample.focus": {"traits": {"nerve": 1}, "adversary": true}}, "audience": {"fields": {"derived/sample.focus/evade": "all"}}}},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Rogue", Vector2(1, 1), {"id": "t_ana", "actor": "a_ana", "owner": "pl_1"})},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Gob", Vector2(3, 1), {"id": "t_gob", "actor": "a_gob", "hidden": true})},
		Resources.set_event("actor:a_ana", "sample.focus", "hp", Resources.track(6, 1)),
		{"t": "log.add", "entry": {"id": "n_all", "kind": "note", "text": "for all", "audience": "all"}},
		{"t": "log.add", "entry": {"id": "n_gm", "kind": "note", "text": "for the gm", "audience": "gm"}},
		{"t": "log.add", "entry": {"id": "n_ben", "kind": "note", "text": "for ben", "audience": "owner:pl_2"}},
		{"t": "track.add", "track": {"id": "k_all", "plugin": "sample.focus", "name": "Doom", "kind": "countdown", "value": 2, "max": 3, "direction": "down", "advance": {"on": "manual"}, "audience": "all", "done": false}},
		{"t": "track.add", "track": {"id": "k_gm", "plugin": "sample.focus", "name": "Secret plan", "kind": "countdown", "value": 2, "max": 3, "direction": "down", "advance": {"on": "manual"}, "audience": "gm", "done": false}},
		{"t": "pending.open", "kind": "prompts", "record": {"id": "p_ana", "to": "pl_1", "form": {"title": "?"}, "default": {}, "deadline": 30}},
		{"t": "pending.open", "kind": "rolls", "record": {"id": "q_ben", "spec": {"expr": "1d20"}, "open_to": ["pl_2"], "contributions": []}},
	], "Setup") == "", "setup")
	# Ana's projection
	var ana := Views.project(k, host, "pl_1", Views.ROLE_PLAYER)
	check(ana.player == "pl_1" and ana.role == "player" and ana.seq == k.log.seq, "who and where")
	check(ana.actors.has("a_ana") and ana.actors.a_ana.mine and ana.actors.a_ana.ext["sample.focus"].secret == "likes Ben", "Ana sees her own actor whole")
	check(ana.actors.a_ana.sheets.size() == 1 and ana.actors.a_ana.sheets[0].plugin == "sample.focus" and ana.actors.a_ana.sheets[0].schema.type == "column", "with the plugin's sheet schema")
	var sd: Dictionary = ana.actors.a_ana.sheets[0].data
	check(sd.me == "pl_1" and sd.actor.id == "a_ana" and sd.derived.evade.total == 10 and sd.resources.hp.marked == 1 and sd.derived.hand == ["dash"], "and its data: me, actor, derived, resources: %s" % [sd.keys()])
	check(ana.actors.has("a_ben") and not ana.actors.a_ben.mine and ana.actors.a_ben.sheets.is_empty() and ana.actors.a_ben.derived["sample.focus"].evade.total == 8, "another PC: public numbers, no sheet")
	check(not ana.actors.has("a_gob"), "an NPC is not hers to see")
	check(ana.actors.a_ana.tokens.size() == 1, "her token is listed")
	check(ana.prompts.size() == 1 and ana.prompts[0].id == "p_ana", "her prompt, not others'")
	check(ana.rolls.is_empty(), "a roll open to Ben only is not hers to help")
	var texts: Array = ana.log.map(func(e): return e.text)
	check(texts == ["for all"], "log entries by audience: %s" % [texts])
	check(ana.tracks.size() == 1 and ana.tracks[0].id == "k_all", "tracks by audience")
	check(ana.status.size() == 1 and ana.status[0].plugin == "sample.focus" and ana.status[0].data.actors.size() == 2, "the status view with the actors she sees")
	check(ana.status[0].data.scene == "s_1", "and the scene the table shows")
	check(ana.actions.has("sample.focus") and ana.actions["sample.focus"].has("act") and not ana.actions["sample.focus"].act.has("run"), "public action specs")
	# Ben's
	var ben := Views.project(k, host, "pl_2", Views.ROLE_PLAYER)
	check(ben.actors.a_ana.ext["sample.focus"].has("traits") and not ben.actors.a_ana.ext["sample.focus"].has("secret"), "Ben sees Ana's public data but not her owner-only field")
	check(ben.prompts.is_empty() and ben.rolls.size() == 1 and ben.log.map(func(e): return e.text) == ["for all", "for ben"], "Ben's prompts, rolls and log")
	# a display
	var disp := Views.project(k, host, "", Views.ROLE_DISPLAY)
	check(disp.actors.has("a_ana") and disp.actors.has("a_ben") and not disp.actors.has("a_gob") and disp.actors.a_ana.sheets.is_empty() and disp.prompts.is_empty() and disp.tracks.size() == 1 and disp.log.size() == 1, "a display sees what everyone sees and nothing more")
	# the gm
	var gm := Views.project(k, host, "", Views.ROLE_GM)
	check(gm.actors.has("a_gob") and gm.actors.a_gob.sheets.size() == 1 and gm.prompts.size() == 1 and gm.tracks.size() == 2 and gm.log.size() == 3 and gm.actors.a_gob.tokens.size() == 1, "the GM sees everything, hidden tokens included")
	# an NPC field opened to all
	st.apply({"t": "actor.set", "id": "a_gob", "changes": {"audience/visible": "all"}})
	ana = Views.project(k, host, "pl_1", Views.ROLE_PLAYER)
	check(ana.actors.has("a_gob") and ana.actors.a_gob.derived["sample.focus"] == {"evade": gm.actors.a_gob.derived["sample.focus"].evade} and ana.actors.a_gob.ext.is_empty() and ana.actors.a_gob.tokens.is_empty(), "a visible NPC shows only the fields opened to all, and not its hidden token: %s" % [ana.actors.a_gob.derived])
	check(Views.can_see("gm", "pl_1", "player") == false and Views.can_see("owner:pl_1", "pl_1", "player") and not Views.can_see("owner:pl_1", "pl_2", "player") and Views.can_see("", "", "display") and Views.can_see("gm", "", "gm"), "can_see")


func test_wire_views_intents_and_roles() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var app := App.new("user://test_prefs_views.json")
	var table := TableWindow.new()
	table.app = app
	root.add_child(table)
	table.ctx.plugin_dirs = ["res://tests/plugins"]
	table._open_path(_example("chapel_ambush.encounter"))
	check(table.ctx.host != null and table.ctx.host.plugins.has("sample.focus"), "the table loaded the plugins: %s" % [table.ctx.plugin_log])
	var st := table.ctx.state
	var sid := table.ctx.scene_id
	var ana_id := str(st.encounter.players[0].id)
	var ben_id := str(st.encounter.players[1].id)
	var ana_token := str(st.tokens_owned_by(sid, ana_id)[0].id)
	check(table.ctx.kernel.commit([
		{"t": "actor.add", "actor": {"id": "a_ana", "kind": "pc", "name": "Ana's fighter", "owner": ana_id, "ext": {"sample.focus": {"traits": {"nerve": 2, "grace": 1, "wit": 0}, "hand": ["dash", "rally"], "vault": ["trick"]}}}},
		{"t": "actor.add", "actor": {"id": "a_ben", "kind": "pc", "name": "Ben's mage", "owner": ben_id, "ext": {"sample.focus": {"traits": {"nerve": 0, "grace": 0, "wit": 2}}}}},
		{"t": "token.set", "scene": sid, "id": ana_token, "changes": {"actor": "a_ana"}}], "Actors") == "", "actors linked")
	table.ctx.host.dispatch("sample.focus", "setup", {"actor": "a_ana", "armour": 1})
	table.ctx.commands.set_turn_mode("ordered")
	table.ctx.commands.run({"t": "turns.set", "changes": {"system": "sample.focus"}})
	check(table.ctx.commands.start_turns(sid) == "" and st.encounter.turns.strategy == "focus", "focus turns are running")
	table._set_hosting(true)
	check(table.host != null and table.host.is_running() and table.host.kernel == table.ctx.kernel, "hosting with the kernel")
	var player := PlayerWindow.new()
	player.app = app
	root.add_child(player)
	var display := PlayerWindow.new()
	display.app = app
	display.display_mode = true
	root.add_child(display)
	var pump := func(done: Callable, max_ms := 4000) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < max_ms:
			table._process(0.05)
			player._process(0.05)
			display._process(0.05)
			if done.call():
				return true
			OS.delay_msec(10)
		return false
	# a v1 client is refused with a message
	var old := WebSocketPeer.new()
	check(old.connect_to_url("ws://127.0.0.1:%d" % table.host.port) == OK, "an old client connects")
	var refused := [""]   # a box: lambdas capture strings by value
	pump.call(func() -> bool:
		old.poll()
		if old.get_ready_state() == WebSocketPeer.STATE_OPEN and refused[0] == "":
			old.send_text(JSON.stringify({"t": "hello", "version": 1, "name": "old"}))
			refused[0] = "sent"
		while old.get_available_packet_count() > 0:
			var m := Protocol.decode(old.get_packet().get_string_from_utf8())
			if m.get("t") == "error":
				refused[0] = str(m.why)
		if old.get_ready_state() == WebSocketPeer.STATE_CLOSED and refused[0] == "sent":
			refused[0] = "closed: " + old.get_close_reason()
		return refused[0] != "" and refused[0] != "sent", 3000)
	check(refused[0].contains("protocol 2"), "…and told which protocol the table speaks: " + refused[0])
	old.close()
	# Ana joins as a player
	player._address.text = "127.0.0.1:%d" % table.host.port
	player._join_address()
	check(pump.call(func() -> bool: return player.screen == "pick"), "welcomed")
	check(player.session.state.encounter.actors.is_empty() and (player.session.state.encounter.doc.rng as Dictionary).is_empty(), "the client holds no rules blocks")
	player._start(ana_id)
	check(pump.call(func() -> bool: return player.screen == "play" and not player.session.view.is_empty()), "joined and a view arrived")
	var v: Dictionary = player.session.view
	check(v.player == ana_id and v.role == "player" and v.actors.has("a_ana") and v.actors.a_ana.mine and v.actors.a_ana.sheets.size() == 1, "the view has Ana's sheet from the plugin")
	check(v.actors.has("a_ben") and not v.actors.a_ben.mine, "and Ben's public actor")
	check(player._sheet_button.text == "Sheet (1)", "the Sheet button counts her characters")
	player.set_pane("sheet")
	await tree.process_frame
	check(player._renderers.size() == 1 and _has_button(player._pane_box, "dash") and _has_button(player._pane_box, "Act (nerve)"), "the sheet renders: her hand and the act buttons")
	# tap a card: play it → an effect appears in the next view
	var pool_before: int = int(st.encounter.doc.state.ext.get("sample.focus", {}).get("pool", 0))
	_button(player._pane_box, "dash").pressed.emit()
	check(pump.call(func() -> bool: return not st.encounter.effects.is_empty()), "the intent played the card on the table")
	check(pump.call(func() -> bool: return not player.session.view.actors.a_ana.effects.is_empty()), "and the new view shows the effect")
	# a display joins and sees the table, not Ana's sheet, and may do nothing
	display._address.text = "127.0.0.1:%d" % table.host.port
	display._join_address()
	check(pump.call(func() -> bool: return display.screen == "play" and not display.session.view.is_empty()), "the display joined straight into play")
	check(display.session.role == "display" and display.session.player_id == "" and display.tool == null, "as a display: no player, no move tool")
	var dv: Dictionary = display.session.view
	check(dv.actors.has("a_ana") and dv.actors.a_ana.sheets.is_empty() and dv.status.size() == 1 and dv.prompts.is_empty(), "it sees the actors and the status view, no sheets, no prompts")
	check(display.session.intent({"kind": "action", "plugin": "sample.focus", "action": "act", "ctx": {"actor": "a_ana"}}) == "", "it may send an intent…")
	var told := []
	display.session.status.connect(func(t: String) -> void: told.append(t))
	check(pump.call(func() -> bool: return told.any(func(t: String) -> bool: return t.contains("only players")), 2000), "…which the table refuses: %s" % [told])
	# Ana acts: the roll and its consequences reach the table
	var log_before := st.encounter.log.size()
	_button(player._pane_box, "Act (nerve)").pressed.emit()
	check(pump.call(func() -> bool: return st.encounter.log.size() > log_before), "her act rolled on the table")
	check(pump.call(func() -> bool: return player.session.view.log.size() > 0), "and the log reached her view")
	# Ana may not act with Ben's character
	told.clear()
	player.session.status.connect(func(t: String) -> void: told.append(t))
	player.session.intent({"kind": "action", "plugin": "sample.focus", "action": "act", "ctx": {"actor": "a_ben"}})
	check(pump.call(func() -> bool: return told.any(func(t: String) -> bool: return t.contains("not your character")), 2000), "acting with someone else's character is refused: %s" % [told])
	# a pointer that resolved to nothing is no claim on a character: an intent
	# from a sheetless view (a "new character" wizard) is dispatched, not refused
	told.clear()
	player.session.intent({"kind": "action", "plugin": "sample.focus", "action": "sign", "ctx": {"actor": null}})
	check(pump.call(func() -> bool: return str(st.encounter.doc.state.ext.get("sample.focus", {}).get("last_sender", "")) == ana_id), "an intent with a null actor pointer goes through")
	# the host stamps who sent an intent; a claim on the wire is overwritten
	player.session.intent({"kind": "action", "plugin": "sample.focus", "action": "sign", "ctx": {"player": ben_id, "gm": true}})
	check(pump.call(func() -> bool: return str(st.encounter.doc.state.ext.get("sample.focus", {}).get("last_sender", "")) == ana_id), "the action saw Ana as the sender, not what her client claimed")
	check(st.encounter.doc.state.ext["sample.focus"].last_gm == false, "and not the GM")
	var signed := table.ctx.host.dispatch("sample.focus", "sign", {})
	check(signed.value.player == "" and signed.value.gm == true, "the Table's own dispatch is the GM's")
	# targets picked on the phone: a hidden token is refused by the table, a
	# visible one goes through, and the tool's pick fills the intent in
	var gob_tk := ""
	for tk in st.tokens(sid):
		if bool(tk.get("hidden", false)):
			gob_tk = str(tk.id)
			break
	var ben_token := str(st.tokens_owned_by(sid, ben_id)[0].id)
	var ana_pos := Vision.token_pos(st.token(sid, ana_token))
	check(table.ctx.kernel.commit([
		{"t": "actor.set", "id": "a_ana", "changes": {"ext/sample.ordered": {"level": 1, "stats": {"agi": 2, "str": 1, "wit": 0}}}},
		{"t": "actor.add", "actor": {"id": "a_ben2", "kind": "pc", "name": "Ben's ranger", "owner": ben_id, "ext": {"sample.ordered": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}},
		{"t": "token.set", "scene": sid, "id": ben_token, "changes": {"actor": "a_ben2", "pos": [ana_pos.x + 1.0, ana_pos.y]}}], "Neighbours") == "", "Ana knows the ordered rules too; Ben's ranger stands beside her")
	told.clear()
	player.session.intent({"kind": "action", "plugin": "sample.ordered", "action": "shove", "ctx": {"actor": "a_ana", "target": "token:" + gob_tk}})
	check(pump.call(func() -> bool: return told.any(func(t: String) -> bool: return t.contains("cannot see")), 2000), "a hidden token is not a target: %s" % [told])
	told.clear()
	player.session.intent({"kind": "action", "plugin": "sample.ordered", "action": "shove", "ctx": {"actor": "a_ana", "target": "actor:a_ben2"}})
	check(pump.call(func() -> bool: return told.any(func(t: String) -> bool: return t.contains("wants a token")), 2000), "the wrong kind of target is refused: %s" % [told])
	check(pump.call(func() -> bool: return player.session.state.token(sid, ben_token).get("actor", "") == "a_ben2"), "the phone caught up with the scene")
	var ben_before := Vision.token_pos(player.session.state.token(sid, ben_token))
	player.tool.begin_pick({"kind": "action", "plugin": "sample.ordered", "action": "shove", "ctx": {"actor": "a_ana"}, "pick": "token", "label": "Shove"})
	check(not player.tool.pick.is_empty() and player.tool.pick_spec().kind == "token" and player.tool.pick_spec().from == ana_token, "the phone's tool is picking a token from Ana's token")
	check(player.tool.press(Vision.token_pos(player.session.state.token(sid, gob_tk)), MOUSE_BUTTON_LEFT, {}) and player.tool.pick.is_empty(), "a tap on the hidden goblin's spot is a tap on nothing: the pick is cancelled")
	player.tool.begin_pick({"kind": "action", "plugin": "sample.ordered", "action": "shove", "ctx": {"actor": "a_ana"}, "pick": "token", "label": "Shove"})
	player.tool.press(ben_before, MOUSE_BUTTON_LEFT, {})
	check(player.tool.pick.is_empty(), "a tap on Ben's ranger resolves the pick and sends the intent")
	check(pump.call(func() -> bool: return Vision.token_pos(st.token(sid, ben_token)).distance_to(ben_before) > 0.9), "…and the table shoved him: %s" % [st.token(sid, ben_token).pos])
	# an area pick from the sheet's button: the renderer asks the window, which asks the tool
	player.set_pane("sheet")
	await tree.process_frame
	var oil := _button(player._pane_box, "Throw oil  [1 actions]")
	check(oil != null, "the ordered sheet's Throw oil button is on the phone")
	oil.pressed.emit()
	check(not player.tool.pick.is_empty() and player.tool.pick_spec().kind == "area", "pressing it started an area pick")
	player.tool.press(Vision.token_pos(st.token(sid, ben_token)), MOUSE_BUTTON_LEFT, {})
	check(pump.call(func() -> bool: return st.encounter.effects.values().any(func(fx: Dictionary) -> bool: return fx.key == "oily" and fx.on == "actor:a_ben2")), "the splash reached the table: Ben's ranger is oily")
	player.set_pane("")
	# one question to every player at once: Ana on her phone, Ben through the Table
	var volley := table.ctx.host.dispatch("sample.ordered", "volley", {})
	table.ctx.kernel.pending.drive(volley, "sample.ordered")
	check(volley.status == PluginHost.PluginCall.PENDING and table.ctx.kernel.pending.prompts().size() == 2, "the volley waits on two prompts")
	check(pump.call(func() -> bool: return player.session.view.prompts.size() == 1), "Ana's phone shows hers, not Ben's")
	var bens := ""
	for pid in table.ctx.kernel.pending.prompts():
		if str(table.ctx.kernel.pending.prompts()[pid].to) == ben_id:
			bens = str(pid)
	check(table.ctx.kernel.pending.answer(bens, {"dodge": true}, "") == "" and volley.status == PluginHost.PluginCall.PENDING, "Ben's answer alone does not finish it")
	check(pump.call(func() -> bool: return player.session.view.prompts.size() == 1), "Ana's is still open")
	player.set_pane("table")
	await tree.process_frame
	check(_find_label(player._pane_box, "GM pool:") != null, "the plugin's status view renders on the phone over its own data (@state)")
	# a handout from the DM reaches the phone's table pane, for its audience
	table.ctx.kernel.commit([{"t": "log.add", "entry": {"id": "h_stone", "kind": "handout", "title": "The stone", "text": "Runes glow.", "audience": "all"}},
		{"t": "log.add", "entry": {"id": "h_ben", "kind": "handout", "title": "Ben's letter", "text": "For Ben.", "audience": "owner:" + ben_id}}], "Handouts")
	check(pump.call(func() -> bool: return player.session.view.log.any(func(e: Dictionary) -> bool: return e.get("id", "") == "h_stone")), "the handout reached Ana's view")
	player.set_pane("table")
	await tree.process_frame
	check(_find_label(player._pane_box, "The stone") != null and _find_label(player._pane_box, "Ben's letter") == null, "her phone shows the handout for everyone, not Ben's")
	_button(player._pane_box, "Answer").pressed.emit()
	check(pump.call(func() -> bool: return volley.status == PluginHost.PluginCall.OK), "Ana's answer (the default: no dodge) finished the volley: %s" % volley.error)
	check(volley.value.dodged == ["a_ben2"] and volley.value.shaken == ["a_ana"], "Ben dodged, Ana is shaken: %s" % [volley.value])
	player.set_pane("")
	# the compendium reaches the phone under Ana's audience: a page, an
	# entry, and nothing of what is the GM's
	var replies := []
	player.session.comp("creatures", {"query": {"filter": {"kind": "humanoid"}, "sort": "name", "fields": ["name", "level"]}}, func(r: Dictionary) -> void: replies.append(r))
	check(pump.call(func() -> bool: return replies.size() == 1), "a page came back")
	check(replies[0].collection == "creatures" and replies[0].page.total == 2 and replies[0].page.entries[0].name == "Goblin chief" and not replies[0].page.entries[0].has("__pack"), "two humanoids from sample.degrees' pack, without the pack key: %s" % [replies[0]])
	player.session.comp("creatures", {"id": "wolf"}, func(r: Dictionary) -> void: replies.append(r))
	check(pump.call(func() -> bool: return replies.size() == 2) and replies[1].entry.name == "Wolf", "an entry by id")
	player.session.comp("creatures", {"id": "nope"}, func(r: Dictionary) -> void: replies.append(r))
	check(pump.call(func() -> bool: return replies.size() == 3) and replies[2].has("error"), "no such entry")
	var hb := table.ctx.kernel.comp.user_pack("secrets", "The GM's notes", "sample.degrees")
	check(table.ctx.kernel.comp.put("creatures", {"id": "boss", "name": "The Boss", "level": 9, "kind": "humanoid", "audience": "gm"}, "secrets") == "" and table.ctx.kernel.comp.put("creatures", {"id": "bandit", "name": "Bandit", "level": 1, "kind": "humanoid"}, "secrets") == "", "the GM adds a secret boss and a plain bandit")
	player.session.comp("creatures", {"query": {"filter": {"kind": "humanoid"}}}, func(r: Dictionary) -> void: replies.append(r))
	check(pump.call(func() -> bool: return replies.size() == 4) and replies[3].page.total == 3 and not replies[3].page.entries.any(func(e: Dictionary) -> bool: return e.id == "boss"), "the bandit is in her page, the boss is not: %d" % replies[3].page.total)
	player.session.comp("creatures", {"id": "boss"}, func(r: Dictionary) -> void: replies.append(r))
	check(pump.call(func() -> bool: return replies.size() == 5) and replies[4].has("error"), "nor can she fetch it by id")
	check(table.ctx.kernel.comp.query_for("creatures", {"filter": {"kind": "humanoid"}}, true).total == 4 and not table.ctx.kernel.comp.entry_for("creatures", "boss", true).is_empty(), "the GM's own query sees it")
	table.ctx.kernel.comp.unload("secrets")
	# the sheet's picker draws on the compendium over the wire and its pick
	# becomes an action on the table: Ana learns a feat from her phone
	check(table.ctx.kernel.commit([{"t": "actor.set", "id": "a_ana", "changes": {"ext/sample.degrees": {"level": 2, "stats": {"might": 1, "agility": 2, "mind": 0}, "feats": []}}}], "Degrees too") == "", "Ana's fighter knows the degrees rules as well")
	check(pump.call(func() -> bool: return player.session.view.actors.a_ana.sheets.size() == 3), "three sheets on her phone: %s" % [player.session.view.actors.a_ana.sheets.map(func(sh): return sh.plugin)])
	player.set_pane("sheet")
	await tree.process_frame
	var pickers := _all_of(player._pane_box, "ItemList")
	check(pump.call(func() -> bool:
		pickers = _all_of(player._pane_box, "ItemList")
		return not pickers.is_empty() and (pickers[0] as ItemList).item_count > 0), "the feat picker filled from the table's compendium: %d options" % [(pickers[0] as ItemList).item_count if not pickers.is_empty() else 0])
	var feat_list := pickers[0] as ItemList
	var keen := -1
	for i in feat_list.item_count:
		if str(feat_list.get_item_metadata(i).get("id", "")) == "keen-eyes":
			keen = i
	check(keen >= 0, "keen eyes is on offer")
	feat_list.select(keen)
	feat_list.item_selected.emit(keen)
	check(pump.call(func() -> bool: return (st.encounter.actor("a_ana").ext["sample.degrees"].feats as Array).has("keen-eyes")), "the pick reached the table as an action: she has keen eyes")
	player.set_pane("")
	# the GM damages Ana: a prompt reaches her phone; she answers from it
	table.ctx.select_token(ana_token)
	var pc := table.ctx.host.dispatch("sample.focus", "damage", {"target": "a_ana", "amount": 5})
	table.ctx.kernel.pending.drive(pc, "sample.focus")
	check(pc.status == PluginHost.PluginCall.PENDING and table.ctx.kernel.pending.prompts().size() == 1, "the damage waits on Ana")
	check(pump.call(func() -> bool: return player.session.view.prompts.size() == 1), "the prompt is in her view")
	check(player.pane_mode == "table", "and the phone switched to the table pane to show it")
	await tree.process_frame
	var answer := _button(player._pane_box, "Answer")
	check(answer != null, "with an Answer button")
	var cb: CheckBox = _find_class(player._pane_box, "CheckBox")
	cb.button_pressed = true
	answer.pressed.emit()
	check(pump.call(func() -> bool: return pc.status == PluginHost.PluginCall.OK), "her answer resumed the action on the table: %s" % pc.error)
	check(pc.value.boxes == 1 and Resources.get_record(st, "actor:a_ana", "sample.focus", "armour").marked == 1, "and it took effect: armour spent, one box")
	check(pump.call(func() -> bool: return player.session.view.prompts.is_empty()), "the prompt is gone from her view")
	# Ben cannot answer Ana's prompt; the table's Rules panel can wave one through
	var pc2 := table.ctx.host.dispatch("sample.focus", "damage", {"target": "a_ana", "amount": 9})
	table.ctx.kernel.pending.drive(pc2, "sample.focus")
	if pc2.status == PluginHost.PluginCall.PENDING:
		var pid := str(table.ctx.kernel.pending.prompts().keys()[0])
		check(table.ctx.kernel.pending.answer(pid, {"spend": true}, ben_id).contains("for " + ana_id), "Ben may not answer Ana's prompt")
		table.rules.refresh()
		await tree.process_frame
		var dflt := _button(table.rules, "Default")
		check(dflt != null, "the Rules panel lists the prompt with a Default button")
		dflt.pressed.emit()
		check(pc2.status == PluginHost.PluginCall.OK, "the default answered it")
	# a helped roll: Ana opens one through act with help; Ben's phone would contribute — here the table opens and Ana helps
	var qid := table.ctx.kernel.pending.open_roll("1d20", {"actor": "a_ben", "kind": "action", "dc": 10}, "sample.focus", "Ben sneaks", "all", 30)
	check(pump.call(func() -> bool: return player.session.view.rolls.size() == 1), "the open roll reaches Ana")
	player.set_pane("table")
	await tree.process_frame
	var help := _button(player._pane_box, "Help (1d6)")
	check(help != null, "with a Help button")
	help.pressed.emit()
	check(pump.call(func() -> bool: return table.ctx.kernel.pending.rolls()[qid].contributions.size() == 1), "her help die joined the roll")
	var entry := table.ctx.kernel.pending.resolve(qid)
	check(entry.result.groups.has("help_" + ana_id), "and counted when it resolved")
	# the focus: Ana asks; the table's panel shows it
	check(player.session.intent({"kind": "focus", "ref": "token:" + ana_token}) == "", "Ana asks for the focus")
	check(pump.call(func() -> bool: return st.encounter.turns.requests.size() == 1), "the request is on the table")
	check(player.session.intent({"kind": "focus", "ref": "token:t_none"}) == "" and pump.call(func() -> bool: return told.any(func(t: String) -> bool: return t.contains("not your token")), 2000), "not for a token that is not hers")
	# the Rules panel on the table
	table.rules.refresh()
	check(_button(table.rules, "Act") != null and _button(table.rules, "Damage") != null, "the Rules panel offers the selected actor's actions")
	player._leave()
	display._leave()
	table._set_hosting(false)
	player.queue_free()
	display.queue_free()
	table.queue_free()
	await tree.process_frame


func _button(root: Node, text: String) -> Button:
	if root is Button and str(root.text).begins_with(text):
		return root
	for c in root.get_children():
		var b := _button(c, text)
		if b != null:
			return b
	return null


func _find_label(root: Node, text: String) -> Label:
	if root is Label and str((root as Label).text).begins_with(text):
		return root
	for c in root.get_children():
		var l := _find_label(c, text)
		if l != null:
			return l
	return null


func _has_button(root: Node, text: String) -> bool:
	return _button(root, text) != null


func _find_class(root: Node, cls: String) -> Node:
	if root.get_class() == cls:
		return root
	for c in root.get_children():
		var f := _find_class(c, cls)
		if f != null:
			return f
	return null


func _all_of(node: Node, cls: String) -> Array:
	var out := []
	if node.get_class() == cls:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_of(c, cls))
	return out
