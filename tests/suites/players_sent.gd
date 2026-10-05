extends TestCase
## What a player's device receives — every byte, not just what a screen
## draws: the dice's stream, the turn order, a Godot client's document and
## its events, the maps, the pictures, the labels, what the table waits on,
## the recap, the Lookup, the marks — and what a client can't get round (a
## co-GM's code, a player's seat, a target it can't see).

const ANA := "pl_fe0170c1"
const BEN := "pl_393eb25a"
const Web := preload("res://tests/suites/web.gd")


func _chapel_state() -> EncounterState:
	var st := EncounterState.new(Encounter.load_file(example("chapel_ambush.encounter")))
	st.resolve_maps()
	return st


func _pump(host: HostSession, clients: Array, done: Callable, max_ms := 3000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		host.poll(0.016)
		for c in clients:
			c.poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


## A web screen joined as a player (by id).
func _web_player(host: HostSession, pid: String, others: Array = []) -> Web.WebClient:
	var c := Web.WebClient.new(host.port)
	_pump(host, others + [c], func() -> bool: return c.open())
	c.send({"t": "hello", "version": Protocol.VERSION, "name": "phone", "web": true})
	c.send({"t": "join", "role": "player", "player": pid, "device": "device-of-" + pid})
	_pump(host, others + [c], func() -> bool: return not c.last("joined").is_empty() or not c.last("error").is_empty())
	return c


func _host(st: EncounterState, kernel: RulesKernel = null, plugins: PluginHost = null) -> HostSession:
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = kernel
	host.plugins = plugins
	check(host.start(0, false, 0) == OK, "hosting")
	return host


func _load(plugins: PluginHost, id: String, src: String, caps := ["state", "log", "dice", "prompts"]) -> String:
	if plugins.plugins.has(id):
		plugins.unload(id)
	return plugins.load_source({"id": id, "version": "1", "api": 1, "name": id, "capabilities": caps}, [["main.lua", src]])


# ------------------------------------------------------------------ dice --

## The dice come from a secret stream: a key of 256 random bits, each face a
## keyed hash of its place, the key never in anything a screen is sent — nor
## where in the stream a roll drew, in this session's log or the chat banked
## before (a log from before had the stream's seed in every roll: one public
## roll told every die before and after). A document read with a known seed
## gets a key; a known seed set on purpose (a test, a `--seed` run) is still
## a stream anyone with it can repeat; an undone roll rolled again comes up
## the same, and the plugins are never handed the draw.
func test_dice_from_a_secret_stream() -> void:
	var e := Encounter.create("Dice")
	check(Dice.is_key(e.doc.rng.get("key")) and not e.doc.rng.has("seed"), "a new encounter's dice: a key of its own, no seed: %s" % [e.doc.rng.keys()])
	check(str(Encounter.create("Other").doc.rng.key) != str(e.doc.rng.key), "every encounter its own")
	# the keyed stream: the same place the same face; another key, other faces
	var key := str(e.doc.rng.key)
	check(Dice.face(key, 5, 20) == Dice.face(key, 5, 20), "a place in the stream is a face: the same every time")
	var other := Dice.new_key()
	var same := 0
	for i in 200:
		if Dice.face(key, i, 20) == Dice.face(other, i, 20):
			same += 1
	check(same < 30, "another key, other faces (%d of 200 alike)" % same)
	var counts := {}
	for i in 6000:
		var f := Dice.face(key, i, 6)
		counts[f] = int(counts.get(f, 0)) + 1
	var even := counts.size() == 6 and counts.values().all(func(n: int) -> bool: return n > 850 and n < 1150)
	check(even, "a d6 6000 times: every face about as often: %s" % [counts])
	var span := {}
	for i in 400:
		span[Dice.face(key, i, 20)] = true
	check(span.size() == 20 and span.keys().min() == 1 and span.keys().max() == 20 and Dice.face(key, 3, 1) == 1, "a d20's faces are 1 to 20")
	# a document from before: its known seed gives way to a key, its place kept
	var old := Encounter.from_json(JsonDoc.stringify({"format": Encounter.FORMAT, "version": Encounter.VERSION, "name": "Old", "rng": {"seed": 425830988, "index": 12}}))
	check(old.doc.rng.get("seed") == 425830988.0, "read from text (a test's own), a known seed stays")
	var path := out_dir().path_join("old_dice.encounter")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JsonDoc.stringify({"format": Encounter.FORMAT, "version": Encounter.VERSION, "name": "Old", "rng": {"seed": 425830988, "index": 12}}))
	f.close()
	var loaded := Encounter.load_file(path)
	check(Dice.is_key(loaded.doc.rng.get("key")) and not loaded.doc.rng.has("seed") and int(loaded.doc.rng.index) == 12, "read from a file to play: a key in its place, where it had got to kept: %s" % [loaded.doc.rng.keys()])
	var guessed := 0
	var st := EncounterState.new(loaded)
	var k := RulesKernel.new(st)
	for i in 10:
		var r := k.roll("1d20", {}, "d20")
		if int(r.result.dice[0].face) == Dice.face(425830988, 12 + i, 20):
			guessed += 1
	check(guessed < 5, "a player who had the old seed guesses no die: %d of 10" % guessed)
	# a roll: where it drew is the entry's, never the key; the result has no draw
	var st2 := EncounterState.new(Encounter.create("Rolls"))
	var k2 := RulesKernel.new(st2)
	var r1 := k2.roll("3d6", {}, "Three")
	check(r1.draw == {"index": 0, "count": 3} and not (r1.result as Dictionary).has("draw"), "the entry says where it drew, {index, count}, and nothing of the stream: %s" % [r1.draw])
	check(not JSON.stringify(st2.encounter.log).contains(str(st2.encounter.doc.rng.key)), "the key is in no log entry")
	# undone and rolled again: the same faces (no fishing for a better roll)
	var faces := Dice.faces_of(r1.result)
	k2.log.undo()
	check(int(st2.encounter.doc.rng.index) == 0, "undone: the stream back where it was")
	var r2 := k2.roll("3d6", {}, "Three again")
	check(Dice.faces_of(r2.result) == faces, "rolled again: the same faces: %s and %s" % [faces, Dice.faces_of(r2.result)])
	# a known seed on purpose (a test's, a `--seed` run's): the same dice every time
	var a := EncounterState.new(Encounter.create("A"))
	var b := EncounterState.new(Encounter.create("B"))
	a.encounter.doc.rng = {"seed": 12, "index": 0}
	b.encounter.doc.rng = {"seed": 12, "index": 0}
	check(Dice.faces_of(RulesKernel.new(a).roll("4d20", {}, "x").result) == Dice.faces_of(RulesKernel.new(b).roll("4d20", {}, "x").result), "a known seed: the same dice for the same seed")
	# a checkpoint from before the key brings no seed back
	var c := EncounterState.new(Encounter.create("C"))
	var ck := RulesKernel.new(c)
	var own := str(c.encounter.doc.rng.key)
	var snap := c.encounter.snapshot()
	snap.rng = {"seed": 5, "index": 0}
	check(ck.commit([{"t": "checkpoint.restore", "snapshot": snap}], "Restore") == "", "an old snapshot put back")
	check(str(c.encounter.doc.rng.get("key", "")) == own and not c.encounter.doc.rng.has("seed"), "the table's key stays, no seed")


## Nothing a screen is sent carries the dice's key or where a roll drew: a
## roll in the log (the DM's and a player's view), one from a log from
## before with its seed, the chat banked from sessions before; a ruleset is
## handed none of it either.
func test_no_screen_hears_the_dice_stream() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var key := str(st.encounter.doc.rng.key)
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, "t.dice", """
local hm = hexmap
hm.actions.register('roll', { label = 'Roll', target = '', run = function(ctx)
	local r = hm.dice.roll({ expr = '1d20+2' }, {}, 'Luck')
	hm.log('drawn: ' .. tostring(r.draw) .. ', ' .. tostring(r.result.draw), 'all')
	return true
end })
""") == "", "a ruleset that rolls")
	# a roll from a log saved before: its draw (and its result's) with the seed in it
	check(kernel.commit([{"t": "log.add", "entry": {"id": "r_old", "kind": "roll", "label": "Old", "audience": "all", "draw": {"seed": 424242, "index": 0, "count": 1},
		"result": {"total": 7, "dice": [{"face": 7, "sides": 20}], "draw": {"seed": 424242, "index": 0, "count": 1}}}}], "an old roll") == "", "an old roll in the log")
	var host := _host(st, kernel, plugins)
	host.dm_token = "sesame"
	host.dm_state_source = func() -> Dictionary: return {}
	host.chat_source = func() -> Array: return [{"id": "r_banked", "kind": "roll", "label": "Banked", "audience": "all", "draw": {"seed": 31337, "index": 4, "count": 1},
		"result": {"total": 3, "draw": {"seed": 31337, "index": 4, "count": 1}}}]
	var ana := _web_player(host, ANA)
	check(not ana.last("joined").is_empty(), "Ana joined")
	ana.send({"t": "intent", "intent": {"kind": "action", "plugin": "t.dice", "action": "roll", "ctx": {}}, "req": "r1"})
	check(_pump(host, [ana], func() -> bool: return not ana.last("done").is_empty()), "she rolled")
	_pump(host, [ana], func() -> bool: return false, 200)
	var view: Dictionary = ana.last("view").get("view", {})
	var mine: Array = view.get("log", []).filter(func(x: Dictionary) -> bool: return str(x.get("label", "")) == "Luck")
	check(mine.size() == 1 and not (mine[0] as Dictionary).has("draw") and not (mine[0].result as Dictionary).has("draw"), "her roll in her view: no draw")
	var note: Array = view.get("log", []).filter(func(x: Dictionary) -> bool: return str(x.get("text", "")).begins_with("drawn"))
	check(note.size() == 1 and str(note[0].text) == "drawn: nil, nil", "the ruleset was handed no draw: %s" % [note])
	var raw := JSON.stringify(ana.raw)
	check(not raw.contains(key), "the key: in nothing she was sent")
	check(not raw.contains("\"draw\"") and not raw.contains("424242") and not raw.contains("31337"), "no draw, no old seed, this session's or the chat banked")
	check(view.get("chat_history", []).size() == 1, "the banked chat came (without its draw)")
	host.stop()


# ----------------------------------------------------------------- order --

## Ana's fighter and Ben's ranger; two goblins by her fighter, a boss beside
## them, a lurker the DM hides and a second boss hidden with it; the chapel's
## own four goblins revealed, out in the dark beyond the fighters' sight.
func _fight(k: RulesKernel, sid: String) -> Dictionary:
	var st := k.state
	var fighter := str(st.tokens(sid).filter(func(t: Dictionary) -> bool: return str(t.name) == "Ana's fighter")[0].id)
	var ranger := str(st.tokens(sid).filter(func(t: Dictionary) -> bool: return str(t.name) == "Ben's ranger")[0].id)
	var far: Array = st.tokens(sid).filter(func(t: Dictionary) -> bool: return str(t.name) == "Goblin").map(func(t: Dictionary) -> String: return str(t.id))
	var events := [
		{"t": "actor.add", "actor": {"id": "a_fighter", "kind": "pc", "name": "Ana's fighter", "owner": ANA}},
		{"t": "token.set", "scene": sid, "id": fighter, "changes": {"actor": "a_fighter"}},
		{"t": "actor.add", "actor": {"id": "a_gob", "kind": "npc", "name": "Goblin", "audience": {"visible": "all"}}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Goblin", Vector2(4.5, 6.6), {"id": "t_gob", "actor": "a_gob", "hidden": false, "tags": ["humanoid"]})},
		{"t": "actor.add", "actor": {"id": "a_boss", "kind": "npc", "name": "Goblin Boss"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Goblin Boss", Vector2(5.0, 7.4), {"id": "t_boss", "actor": "a_boss", "hidden": false, "tags": ["humanoid"]})},
		{"t": "actor.add", "actor": {"id": "a_lurk", "kind": "npc", "name": "Lurker"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Lurker", Vector2(3.5, 6.0), {"id": "t_lurk", "actor": "a_lurk", "hidden": true, "tags": []})},
		{"t": "actor.add", "actor": {"id": "a_boss2", "kind": "npc", "name": "Goblin Boss"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Goblin Boss", Vector2(5.5, 6.0), {"id": "t_boss2", "actor": "a_boss2", "hidden": true, "tags": ["humanoid"]})},
	]
	for id in far:
		events.append({"t": "token.set", "scene": sid, "id": id, "changes": {"hidden": false}})
	check(k.commit(events, "setup") == "", "set up: the fighters, the goblins by them, a lurker and a boss hidden, the far goblins revealed")
	return {"fighter": fighter, "ranger": ranger, "far": far}


## Every token a screen's order names (a group's members for a group).
func _order_ids(turns: Dictionary) -> Array:
	var out := []
	for e in turns.get("order", []):
		if str(e).begins_with("group:"):
			out.append_array(turns.get("data", {}).get("groups", {}).get(str(e).substr(6), {}).get("tokens", []))
		else:
			out.append(str(e))
	return out


## The turn order a player is sent has no creature they don't see in any part
## of it: not the order, a group's members, the labels, the turn's notes and
## skips, the counters, the turn that ended (nor where tokens stood then);
## the turn of one they don't see is nobody's (-1); a group of creatures they
## know no names of says nothing ("Creatures"); a ruleset's own data stays on
## the Table. The web's scene, the rules' view and a sheet's data agree, and
## a sheet's End turn, sent by its place in her order, is the Table's place
## when the rules read it.
func test_the_order_a_player_is_sent() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, "t.order", """
local hm = hexmap
hm.ui.knowledge({ names = 'hidden', rolls = 'hidden' })
hm.actions.register('end_turn', { label = 'End turn', target = '', run = function(ctx)
	hm.log('ended at ' .. tostring(ctx.round) .. '/' .. tostring(ctx.turn), 'all')
	return true
end })
""") == "", "a ruleset that keeps names and rolls")
	var f := _fight(kernel, sid)
	var fighter := str(f.fighter)
	var ranger := str(f.ranger)
	check(kernel.commit([{"t": "turns.set", "changes": {"mode": "ordered", "running": true, "scene": sid, "round": 2, "turn": 0,
		"order": ["t_lurk", fighter, "t_gob", "group:g1", ranger] + f.far,
		"data": {"labels": {"t_lurk": "19", fighter: "12", "t_gob": "17", "group:g1": "9", ranger: "8"}, "groups": {"g1": {"tokens": ["t_boss", "t_boss2"], "label": "Goblin Bosses"}},
			"notes": {"t_lurk": "Movement 30 of 30 ft", fighter: "Movement 15 of 30 ft"}, "skip": {"t_lurk": true, "t_gob": true}, "rolling": "rq_1", "budget": {"xp": 450}},
		"counters": {"token:t_lurk": {"actions": 1}, "token:" + fighter: {"actions": 0}, "token:t_boss2": {"actions": 1}},
		"last": {"by": "gm", "entry": "t_lurk", "round": 2, "turn": 0, "log": "n_secret", "pos": {"t_lurk": [3.5, 6.0]}}}}], "An order") == "", "a fight: the lurker first, then Ana's fighter")
	var known := kernel.knowledge_policies()
	var view := Views.project(kernel, plugins, ANA, Views.ROLE_PLAYER)
	var t: Dictionary = view.turns
	var snap := WebScene.build(st, sid, ANA, false, known)
	var drawn := {}
	for tk in snap.tokens:
		drawn[str(tk.id)] = true
	check(_order_ids(snap.turns).all(func(id: Variant) -> bool: return drawn.has(str(id))), "every creature in her scene's order is one her screen draws: %s" % [_order_ids(snap.turns)])
	check(not (t.order as Array).has("t_lurk") and not JSON.stringify(t).contains("t_lurk") and not JSON.stringify(t).contains("t_boss2"), "the hidden ones in no part of her order: %s" % [t.order])
	check(int(t.turn) == -1 and int(snap.turns.turn) == -1, "the lurker's turn is nobody's to her: %s" % [t.turn])
	check((t.order as Array).slice(0, 3) == [fighter, "t_gob", "group:g1"], "the rest in their order: %s" % [t.order])
	check(t.data.groups.g1.tokens == ["t_boss"] and str(t.data.groups.g1.label) == "Creatures", "the group: the boss she sees, called Creatures: %s" % [t.data.groups.g1])
	check(t.data.labels == {fighter: "12", ranger: "8"}, "the labels: the party's (no creature's initiative, the group's neither): %s" % [t.data.labels])
	check((t.data.notes as Dictionary).keys() == [fighter] and (t.data.skip as Dictionary).keys() == ["t_gob"], "the turn's notes and skips of what she sees: %s %s" % [t.data.notes, t.data.skip])
	check(not t.data.has("budget") and str(t.data.get("rolling", "")) == "rq_1", "a ruleset's own data stays on the Table")
	check((t.counters as Dictionary).keys() == ["token:" + fighter], "the counters: her fighter's: %s" % [t.counters.keys()])
	check(str(t.last.entry) == "" and int(t.last.turn) == -1 and not t.last.has("pos") and not t.last.has("log"), "the turn that ended: nobody's to her, no places, no log: %s" % [t.last])
	check((f.far as Array).any(func(id: Variant) -> bool: return not drawn.has(str(id))), "a goblin out there her fighter doesn't see (the fog's own case)")
	for far_id in f.far:
		check(drawn.has(str(far_id)) == (t.order as Array).has(str(far_id)), "a far goblin in her order as her screen shows it (%s: %s)" % [far_id, drawn.has(str(far_id))])
	var gm_turns: Dictionary = Views.project(kernel, plugins, "", Views.ROLE_GM).turns
	check((gm_turns.order as Array).has("t_lurk") and int(gm_turns.turn) == 0 and gm_turns.data.has("budget"), "the DM's: whole")
	# her turn: the Table's 1, her 0 — her sheet's End turn says hers
	check(kernel.commit([{"t": "turns.set", "changes": {"turn": 1}}], "Her turn") == "", "her fighter's turn")
	var mine := Views.project(kernel, plugins, ANA, Views.ROLE_PLAYER)
	check(int(mine.turns.turn) == 0, "her view: her own turn, at 0 in her order")
	var host := _host(st, kernel, plugins)
	var ana := _web_player(host, ANA)
	ana.send({"t": "intent", "intent": {"kind": "action", "plugin": "t.order", "action": "end_turn", "ctx": {"actor": "a_fighter", "round": 2, "turn": int(mine.turns.turn)}}, "req": "e1"})
	check(_pump(host, [ana], func() -> bool: return not ana.last("done").is_empty()), "her End turn sent")
	var said: Array = st.encounter.log.filter(func(x: Dictionary) -> bool: return str(x.get("text", "")).begins_with("ended at"))
	check(said.size() == 1 and str(said[0].text) == "ended at 2/1", "the rules read the Table's place: %s" % [said])
	# the web's scene too: the order as hers
	_pump(host, [ana], func() -> bool: return not ana.last("scene").is_empty())
	var scene_turns: Dictionary = ana.last("scene").get("scene", {}).get("turns", {})
	check(not (scene_turns.get("order", []) as Array).has("t_lurk") and int(scene_turns.get("turn", -2)) == 0, "her screen's scene: her order, her place")
	check(not JSON.stringify(ana.raw).contains("t_lurk"), "nothing she was sent names the lurker")
	host.stop()


# --------------------------------------------------------- Godot clients --

## A screen that isn't a web one (a Godot client: hello without `web`),
## joined as a player (or a display, `pid` "").
func _godot(host: HostSession, pid: String, others: Array = []) -> Web.WebClient:
	var c := Web.WebClient.new(host.port)
	_pump(host, others + [c], func() -> bool: return c.open())
	c.send({"t": "hello", "version": Protocol.VERSION, "name": "godot"})
	c.send({"t": "join", "role": "player" if pid != "" else "display", "player": pid, "device": "device-of-" + pid})
	_pump(host, others + [c], func() -> bool: return not c.last("joined").is_empty() and not c.last("welcome").get("encounter", {}).get("scenes", []).is_empty())
	return c


## What a Godot client holds now: the last document it was sent, with every
## event sent after it applied (as NetSession does).
static func _held(w: Web.WebClient) -> Dictionary:
	var at := -1
	for i in w.inbox.size():
		if str(w.inbox[i].get("t", "")) == "welcome":
			at = i
	if at < 0:
		return {}
	var st := EncounterState.new(Encounter.from_json(JSON.stringify(w.inbox[at].encounter)))
	for i in range(at + 1, w.inbox.size()):
		var m: Dictionary = w.inbox[i]
		if str(m.get("t", "")) == "event" and m.get("ev") is Dictionary and st.validate(m.ev) == "":
			st.apply(m.ev)
	return st.encounter.doc


static func _held_ids(w: Web.WebClient) -> Array:
	var out := []
	for sc in _held(w).get("scenes", []):
		for tk in sc.get("tokens", []):
			out.append(str(tk.id))
	return out


## A player's Godot client holds what her screen shows, as a web screen's
## snapshot has it: the scene the players see and no other (not a fight
## staged on another), the tokens she sees and no other (not one the DM
## hides, not one beyond her sight), the order as hers, and nothing a
## ruleset keeps on the encounter or the campaign. It hears of a hidden
## token nothing, of another scene nothing; a creature come into her sight
## arrives, one gone from it goes; the players shown another scene, she is
## sent that one. Before she has said who she is, nothing but the players.
func test_a_godot_player_holds_what_her_screen_shows() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var crypt := str(st.encounter.scenes.filter(func(s: Dictionary) -> bool: return str(s.id) != sid)[0].id)
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, "t.order", "hexmap.ui.knowledge({ names = 'hidden' })") == "", "names kept")
	var f := _fight(kernel, sid)
	check(kernel.commit([{"t": "encounter.set", "changes": {"campaign": {"id": "c_1", "path": "/Users/dm/Campaigns/secret.campaign", "ext": {"t.order": {"plot": "the vicar did it"}}},
		"notes": [{"id": "n1", "text": "the bell is in the tower"}]}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Secret grove", Vector2(9.0, 2.0), {"id": "t_grove", "hidden": true, "tags": ["place"], "vision": null})}], "secrets") == "", "the DM's own: the campaign's plot, a note, a place not yet shown")
	var host := _host(st, kernel, plugins)
	# before she says who she is: who the players are, nothing more
	var ana := Web.WebClient.new(host.port)
	_pump(host, [ana], func() -> bool: return ana.open())
	ana.send({"t": "hello", "version": Protocol.VERSION, "name": "godot"})
	check(_pump(host, [ana], func() -> bool: return not ana.last("welcome").is_empty()), "welcomed")
	var lobby: Dictionary = ana.last("welcome").encounter
	check((lobby.get("scenes", []) as Array).is_empty() and (lobby.players as Array).size() == 2, "before she has joined: the players, no scene")
	ana.send({"t": "join", "role": "player", "player": ANA, "device": "device-of-" + ANA})
	check(_pump(host, [ana], func() -> bool: return not ana.last("welcome").get("encounter", {}).get("scenes", []).is_empty()), "joined: her document")
	var doc: Dictionary = ana.last("welcome").encounter
	check((doc.scenes as Array).size() == 1 and str(doc.scenes[0].id) == sid and str(doc.active_scene) == sid, "one scene: the one the players see")
	var ids := _held_ids(ana)
	var snap := WebScene.build(st, sid, ANA, false, kernel.knowledge_policies())
	var drawn: Array = snap.tokens.map(func(t: Dictionary) -> String: return str(t.id))
	ids.sort()
	drawn.sort()
	check(ids == drawn, "her client holds the tokens her web screen would draw: %s / %s" % [ids, drawn])
	check(not doc.scenes[0].has("triggers") and not doc.scenes[0].has("map_path") and str(doc.get("campaign", {}).get("path", "")) == "", "no triggers, nowhere the DM keeps the map or the campaign")
	var raw := JSON.stringify(ana.raw)
	for secret in ["t_lurk", "Lurker", "t_boss2", "the vicar", "/Users/dm", "the bell is in", "Secret grove", "Goblin chief", crypt]:
		check(not raw.contains(secret), "nothing she was sent says %s" % secret)
	var other_goblin := ""
	for id in f.far:
		if not ids.has(str(id)):
			other_goblin = str(id)
	check(other_goblin != "", "a goblin out beyond her fighter's sight, not held")
	# the hidden lurker moves, a fight is staged elsewhere, the DM's plot changes: nothing
	var n := ana.raw.size()
	check(kernel.commit([{"t": "token.set", "scene": sid, "id": "t_lurk", "changes": {"pos": [4.0, 5.0]}},
		{"t": "token.add", "scene": crypt, "token": Encounter.new_token("Ogre", Vector2(5, 5), {"id": "t_ogre", "hidden": false})},
		{"t": "encounter.set", "changes": {"campaign": {"id": "c_1", "path": "/Users/dm/Campaigns/secret.campaign", "ext": {"t.order": {"plot": "the reeve knew"}}}}}], "the DM's moves") == "", "the lurker creeps, an ogre staged in the crypt")
	var staged := Encounter.new_scene(st.map_for(sid), "ground", "Ambush ahead", "")
	check(kernel.commit([{"t": "scene.add", "scene": staged}], "Stage") == "", "a scene staged")
	_pump(host, [ana], func() -> bool: return false, 250)
	var since := JSON.stringify(ana.raw.slice(n))
	check(not since.contains("t_lurk") and not since.contains("Ogre") and not since.contains("the reeve") and not since.contains(str(staged.id)) and not since.contains("scene.add"), "she heard nothing of any of it: %s" % since.left(300))
	# the DM reveals the lurker, hides it again: it comes, it goes
	kernel.commit([{"t": "token.set", "scene": sid, "id": "t_lurk", "changes": {"hidden": false}}], "Reveal")
	check(_pump(host, [ana], func() -> bool: return _held_ids(ana).has("t_lurk")), "revealed: her client has it")
	check(_tok_in(_held(ana), "t_lurk").get("name", "") == "a creature", "as a creature")
	kernel.commit([{"t": "token.set", "scene": sid, "id": "t_lurk", "changes": {"hidden": true}}], "Hide")
	check(_pump(host, [ana], func() -> bool: return not _held_ids(ana).has("t_lurk")), "hidden again: gone from it")
	# a goblin comes into her fighter's sight, and goes out of it
	kernel.commit([{"t": "token.set", "scene": sid, "id": other_goblin, "changes": {"pos": [4.6, 7.3]}}], "Come closer")
	check(_pump(host, [ana], func() -> bool: return _held_ids(ana).has(other_goblin)), "a goblin come into her sight arrives")
	kernel.commit([{"t": "token.set", "scene": sid, "id": other_goblin, "changes": {"pos": [14.6, 4.9]}}], "Go away")
	check(_pump(host, [ana], func() -> bool: return not _held_ids(ana).has(other_goblin)), "and goes as it leaves it")
	var gone_to := ana.raw.slice(n).filter(func(m: Dictionary) -> bool: return str(m.msg.get("t", "")) == "event" and str(m.msg.ev.get("id", "")) == other_goblin and m.msg.ev.get("changes") is Dictionary and m.msg.ev.changes.has("pos"))
	check(gone_to.all(func(m: Dictionary) -> bool: return Vector2(float(m.msg.ev.changes.pos[0]), float(m.msg.ev.changes.pos[1])).distance_to(Vector2(14.6, 4.9)) > 0.5), "never where it went, out of her sight")
	# the players are shown the crypt: her client is sent it, and only it
	kernel.commit([{"t": "scene.activate", "id": crypt}], "To the crypt")
	check(_pump(host, [ana], func() -> bool: return str(_held(ana).get("active_scene", "")) == crypt), "shown the crypt: her document is the crypt's")
	check((_held(ana).scenes as Array).size() == 1 and not _held_ids(ana).has(str(f.fighter)), "the chapel and its tokens gone from it")
	# a display holds what every player's characters see, and nothing hidden
	kernel.commit([{"t": "scene.activate", "id": sid}], "Back")
	var tv := _godot(host, "", [ana])
	var on_tv := _held_ids(tv)
	check(on_tv.has(str(f.fighter)) and on_tv.has(str(f.ranger)) and not on_tv.has("t_lurk") and not on_tv.has("t_grove"), "a display: the party, nothing hidden: %s" % [on_tv])
	host.stop()


## A region attached to a token (an emanation round its caster) reaches a
## player only while their screen shows that token, whatever audience the
## rules gave it — the DM hiding the caster takes it from them at once, on a
## web screen and a Godot client; what a ruleset keeps of the campaign (its
## `gm` part: the defences the players have learned) reaches no player's
## device, by a campaign's state set or the encounter's.
func test_regions_and_campaign_state_as_players_have_them() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	_fight(kernel, sid)
	var g := st.map_for(sid).grid
	var aura := MapQuery.region("r_aura", [g.offset_to_axial(3, 6), g.offset_to_axial(4, 6)], ["emanation"], {"audience": "all", "attached_to": "t_gob"})
	check(kernel.commit([{"t": "region.add", "scene": sid, "region": aura}], "An aura") == "", "an aura round the goblin, for everyone")
	var host := _host(st, kernel, plugins)
	var ana := _web_player(host, ANA)
	var ben := _godot(host, BEN, [ana])
	_pump(host, [ana, ben], func() -> bool: return not ana.last("scene").is_empty())
	var held_regions := func() -> Dictionary:
		var doc := _held(ben)
		return doc.scenes[0].get("regions", {}) if not (doc.get("scenes", []) as Array).is_empty() else {}
	check((ana.last("scene").scene.regions as Dictionary).has("r_aura") and (held_regions.call() as Dictionary).has("r_aura"), "the goblin seen: its aura on her screen and in his client")
	kernel.commit([{"t": "token.set", "scene": sid, "id": "t_gob", "changes": {"hidden": true}}], "The DM hides it")
	check(_pump(host, [ana, ben], func() -> bool: return not (ana.last("scene").scene.regions as Dictionary).has("r_aura") and not (held_regions.call() as Dictionary).has("r_aura")), "hidden: its aura gone from both, its audience still 'all'")
	kernel.commit([{"t": "token.set", "scene": sid, "id": "t_gob", "changes": {"hidden": false}}], "Shown")
	check(_pump(host, [ana, ben], func() -> bool: return (ana.last("scene").scene.regions as Dictionary).has("r_aura") and (held_regions.call() as Dictionary).has("r_aura")), "shown again: back")
	var n_a := ana.raw.size()
	var n_b := ben.raw.size()
	check(kernel.commit([{"t": "ext.set", "scope": "campaign", "plugin": "t.order", "changes": {"gm/learned/resist/fire": true, "seen": 1}},
		{"t": "encounter.set", "changes": {"campaign": {"id": "c_1", "path": "", "ext": {"t.order": {"gm": {"learned": {"immune/poison": true}}}}}}},
		{"t": "ext.set", "scope": "encounter", "plugin": "t.order", "changes": {"gm/initiative/a_gob": 17}}], "What the rules keep") == "", "the rules keep what the players have learned, and an initiative")
	_pump(host, [ana, ben], func() -> bool: return false, 250)
	var since := JSON.stringify(ana.raw.slice(n_a)) + JSON.stringify(ben.raw.slice(n_b))
	check(not since.contains("learned") and not since.contains("initiative"), "nothing either was sent says it: %s" % since.left(200))
	host.stop()


# ------------------------------------------------- what a client can't do --

## A screen that joins with `join` (a hello first).
func _client(host: HostSession, join: Dictionary, others: Array = []) -> Web.WebClient:
	var c := Web.WebClient.new(host.port)
	_pump(host, others + [c], func() -> bool: return c.open())
	c.send({"t": "hello", "version": Protocol.VERSION, "name": "screen", "web": true})
	c.send(join)
	_pump(host, others + [c], func() -> bool: return not c.last("joined").is_empty() or not c.last("error").is_empty())
	return c


## What a client can't get round: a co-GM's code is ten letters and digits,
## new each hosting, and wrong tries from one place soon wait (a new
## connection too); a player's seat is the device's that took it — another
## device can't join as them, by id or by name, until the DM frees it; and a
## target that isn't there and one a player's screen doesn't show (hidden, or
## beyond their sight) are refused in the same words.
func test_what_a_client_cannot_get_round() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, "t.aim", """
local hm = hexmap
hm.actions.register('aim', { label = 'Aim', target = 'token', run = function(ctx) return true end })
""") == "", "a ruleset with an action that wants a token")
	var f := _fight(kernel, sid)
	var host := _host(st, kernel, plugins)
	host.dm_token = "sesame"
	host.dm_state_source = func() -> Dictionary: return {}
	var code := host.cogm_code
	check(RegEx.create_from_string("^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$").search(code) != null, "a co-GM's code: ten letters and digits no one misreads: %s" % code)
	check(HostSession.new_cogm_code() != code, "new each time")
	# wrong codes: two let by, the third makes the next wait — the right one too, a new connection too
	var wrong := "AAAAA-AAAAA" if code != "AAAAA-AAAAA" else "BBBBB-BBBBB"
	for i in 3:
		var w := _client(host, {"t": "join", "role": "cogm", "code": wrong})
		check(str(w.last("error").get("why", "")).contains("code shown on the table"), "a wrong code refused (%d)" % (i + 1))
	var hurried := _client(host, {"t": "join", "role": "cogm", "code": code})
	check(str(hurried.last("error").get("why", "")).begins_with("too many wrong codes"), "then even the right one waits: %s" % hurried.last("error").get("why", ""))
	_pump(host, [], func() -> bool: return false, 1100)
	var cogm := _client(host, {"t": "join", "role": "cogm", "code": code.to_lower().replace("-", " ")})
	check(not cogm.last("joined").is_empty(), "the wait over, the right one (in any case, any spacing) joins")
	# seats: Ana's phone takes hers; another device can't be her, by id or by name
	var phone := _client(host, {"t": "join", "role": "player", "player": ANA, "device": "ana-phone"})
	check(not phone.last("joined").is_empty() and host.seat_taken(ANA), "Ana's phone joins: her seat is its")
	var other := _client(host, {"t": "join", "role": "player", "player": ANA, "device": "someone-else"})
	check(str(other.last("error").get("why", "")).contains("seat is taken"), "another device as Ana: refused: %s" % other.last("error").get("why", ""))
	var by_name := _client(host, {"t": "join", "role": "player", "name": "ana", "device": "someone-else"})
	check(str(by_name.last("error").get("why", "")).contains("seat is taken"), "by her name: refused too")
	var bare := _client(host, {"t": "join", "role": "player", "player": ANA})
	check(not bare.last("error").is_empty(), "with no device at all: refused")
	var again := _client(host, {"t": "join", "role": "player", "player": ANA, "device": "ana-phone"})
	check(not again.last("joined").is_empty(), "her phone again (a reload): her")
	var dm := _client(host, {"t": "join", "role": "dm", "token": "sesame"})
	_pump(host, [dm], func() -> bool: return not dm.last("scene").is_empty())
	check((dm.last("scene").get("seats", []) as Array).has(ANA), "the DM's screen says her seat is taken")
	dm.send({"t": "intent", "req": "f1", "intent": {"kind": "dm", "op": "free_seat", "player": ANA}})
	check(_pump(host, [dm], func() -> bool: return not dm.last("done").is_empty()) and not host.seat_taken(ANA), "the DM frees it")
	var tablet := _client(host, {"t": "join", "role": "player", "player": ANA, "device": "ana-tablet"})
	check(not tablet.last("joined").is_empty(), "her new tablet takes it")
	var old := _client(host, {"t": "join", "role": "player", "player": ANA, "device": "ana-phone"})
	check(str(old.last("error").get("why", "")).contains("seat is taken"), "and the old phone no longer can")
	# targets: one not there, one hidden, one beyond her sight — the same words
	var far := ""
	for id in f.far:
		if not WebScene.seen(st, sid, ANA).has(str(id)):
			far = str(id)
	var whys := []
	for target in ["token:t_nothing", "token:t_lurk", "token:" + far]:
		tablet.send({"t": "intent", "req": "a" + str(whys.size()), "intent": {"kind": "action", "plugin": "t.aim", "action": "aim", "ctx": {"actor": "a_fighter", "target": target}}})
		var req := "a" + str(whys.size())
		_pump(host, [tablet], func() -> bool: return str(tablet.last("refused").get("req", "")) == req or str(tablet.last("done").get("req", "")) == req)
		whys.append(str(tablet.last("refused").get("why", "")) if str(tablet.last("refused").get("req", "")) == req else "(done)")
	check(far != "" and whys[0] == "you cannot see that" and whys[1] == whys[0] and whys[2] == whys[0], "not there, hidden, beyond her sight: one answer: %s" % [whys])
	check(PluginHost.check_target(st, sid, "token", "token:t_nothing", true) == "no such token on this scene", "the DM is told it isn't there")
	host.stop()


static func _tok_in(doc: Dictionary, id: String) -> Dictionary:
	for sc in doc.get("scenes", []):
		for tk in sc.get("tokens", []):
			if str(tk.id) == id:
				return tk
	return {}


# --------------------------------------------- pictures, names, lookups --

## A pack of pictures and a creature's token art, on disk for a test.
func _picture_pack() -> PackLibrary:
	var root := ProjectSettings.globalize_path(out_dir()).path_join("t5_art")
	for sub in ["pictures", "tokens"]:
		DirAccess.make_dir_recursive_absolute(root.path_join("t_pics").path_join(sub))
	var put := func(rel: String, text: String) -> void:
		var f := FileAccess.open(root.path_join("t_pics").path_join(rel), FileAccess.WRITE)
		f.store_string(text)
		f.close()
	put.call("pack.json", JSON.stringify({"format": "silvergrove.pack", "version": 1, "id": "t_pics", "name": "Pictures", "pack_version": "1", "license": "CC0-1.0",
		"pictures": [{"id": "thornwick", "name": "Thornwick", "texture": "pictures/thornwick.png"}, {"id": "vicar_secret", "name": "The vicar's crime", "texture": "pictures/vicar_secret.png"}],
		"tokens": [{"id": "goblin_boss", "name": "Goblin Boss", "texture": "tokens/goblin_boss.png"}]}))
	put.call("pictures/thornwick.png", "PNG-thornwick")
	put.call("pictures/vicar_secret.png", "PNG-vicar")
	put.call("tokens/goblin_boss.png", "PNG-boss")
	var lib := PackLibrary.new()
	lib.set_extra_dirs(PackedStringArray([root]))
	lib.reload()
	return lib


static func _pack(listing: Array, id: String) -> Dictionary:
	for p in listing:
		if str(p.get("id", "")) == id:
			return p
	return {}


static func _http(host: HostSession, path: String) -> String:
	return host.web.respond("GET %s HTTP/1.1\r\n\r\n" % path).get_string_from_utf8()


## A picture reaches a player only once it is shown to them, at an address
## only they were sent (never by its name, which an unshown one's would
## give away); the art of a creature whose name they don't know by an id
## that names nothing; its kind's tags, and its power's label on a preview
## of the DM's, kept from them; the collections a ruleset says are the DM's
## neither searchable nor openable from a player's screen, as if empty.
func test_pictures_names_and_lookups() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var lib := _picture_pack()
	check(lib.picture_packs().has("t_pics"), "a pack of pictures and token art")
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, "t.names", "hexmap.ui.knowledge({ names = 'hidden', name_tags = { 'humanoid', 'undead' }, dm_collections = { 'creatures' } })") == "", "a ruleset keeping names, its kind tags and its bestiary")
	var known := kernel.knowledge_policies()
	check(Knowledge.kind_tags(known).has("humanoid") and Knowledge.dm_collections(known).has("creatures"), "declared: %s" % [known])
	check(plugins.load_source({"id": "t.bad4", "version": "1", "api": 1, "name": "Bad"}, [["main.lua", "hexmap.ui.knowledge({ name_tags = 'humanoid' })"]]) != "", "a list it must be")
	var f := _fight(kernel, sid)
	kernel.commit([{"t": "token.set", "scene": sid, "id": "t_boss", "changes": {"art": "t_pics:goblin_boss", "tags": ["humanoid", "bloodied"]}}], "The boss's art")
	kernel.comp.load_pack({"id": "t_book", "name": "Book"}, {"creatures": [{"id": "goblin-boss", "name": "Goblin Boss", "type": "humanoid"}], "spells": [{"id": "light", "name": "Light"}]})
	var host := HostSession.new(st, lib)
	host.kernel = kernel
	host.plugins = plugins
	host.dm_token = "sesame"
	host.dm_state_source = func() -> Dictionary: return {}
	check(host.start(0, false, 0) == OK, "hosting")
	var ana := _web_player(host, ANA)
	var ben := _web_player(host, BEN, [ana])
	ana.send({"t": "need", "kind": "packs"})
	check(_pump(host, [ana, ben], func() -> bool: return not ana.last("packs").is_empty()), "her packs")
	var listing: Array = ana.last("packs").packs
	var art := _pack(listing, HostSession.ART_PACK)
	check(_pack(listing, "t_pics").is_empty(), "no picture of the pack's: none shown to her")
	check(not art.is_empty() and (art.manifest.tokens as Array).size() == 1 and str(art.manifest.tokens[0].url).begins_with("/pic/"), "the boss's art in a pack of its own, at an address: %s" % [art])
	_pump(host, [ana, ben], func() -> bool: return not ana.last("scene").is_empty())
	var boss: Dictionary = {}
	for tk in ana.last("scene").scene.tokens:
		if str(tk.id) == "t_boss":
			boss = tk
	check(str(boss.get("art", "")) == HostSession.ART_PACK + ":" + str(art.manifest.tokens[0].id), "her screen's boss: its art by an id that names nothing: %s" % [boss.get("art")])
	check(boss.get("tags", []) == ["bloodied"], "without the tag that says its kind, its mark kept: %s" % [boss.get("tags")])
	check(_http(host, "/art/t_pics/tokens/goblin_boss.png").begins_with("HTTP/1.1 404"), "its art by its name: never")
	check(_http(host, str(art.manifest.tokens[0].url)).ends_with("PNG-boss"), "by its address: served")
	# the DM shows Ana the village: her picture, at an address; not the vicar's, not Ben's
	kernel.commit([{"t": "log.add", "entry": {"id": "h1", "kind": "handout", "title": "Thornwick", "text": "", "audience": "players:" + ANA, "image": "t_pics:thornwick"}}], "Show Ana")
	check(_pump(host, [ana, ben], func() -> bool: return not _pack(ana.last("packs").packs, "t_pics").is_empty()), "shown: her packs again, with it")
	var pics: Array = _pack(ana.last("packs").packs, "t_pics").manifest.pictures
	check(pics.size() == 1 and str(pics[0].id) == "thornwick" and str(pics[0].url).begins_with("/pic/"), "the village alone, at its address: %s" % [pics])
	check(not (_pack(ana.last("packs").packs, "t_pics").files as Array).has("pictures/vicar_secret.png"), "the vicar's file not in what she may fetch")
	check(_http(host, str(pics[0].url)).ends_with("PNG-thornwick"), "served at its address")
	check(_http(host, "/art/t_pics/pictures/thornwick.png").begins_with("HTTP/1.1 404") and _http(host, "/art/t_pics/pictures/vicar_secret.png").begins_with("HTTP/1.1 404"), "and no picture by its name")
	check(_pack(ben.last("packs").get("packs", []), "t_pics").is_empty(), "Ben, not shown it, wasn't sent it")
	var godot := _godot(host, BEN, [ana, ben])
	_pump(host, [ana, ben, godot], func() -> bool: return not godot.last("packs").is_empty())
	godot.send({"t": "need", "kind": "file", "pack": "t_pics", "file": "pictures/thornwick.png"})
	godot.send({"t": "need", "kind": "file", "pack": "t_pics", "file": "pictures/vicar_secret.png"})
	check(_pump(host, [ana, ben, godot], func() -> bool: return godot.count("error") >= 2), "his Godot client asking for either by name: refused")
	check(godot.count("file") == 0, "no file sent")
	var dm := Web.WebClient.new(host.port)
	_pump(host, [ana, ben, godot, dm], func() -> bool: return dm.open())
	dm.send({"t": "hello", "version": Protocol.VERSION, "name": "dm", "web": true})
	dm.send({"t": "join", "role": "dm", "token": "sesame"})
	_pump(host, [ana, ben, godot, dm], func() -> bool: return not dm.last("joined").is_empty())
	dm.send({"t": "need", "kind": "packs"})
	check(_pump(host, [ana, ben, godot, dm], func() -> bool: return not dm.last("packs").is_empty()), "the DM's packs")
	var dmp: Dictionary = _pack(dm.last("packs").packs, "t_pics").manifest
	check((dmp.pictures as Array).size() == 2 and (dmp.tokens as Array).size() == 1 and (dmp.pictures as Array).all(func(p: Dictionary) -> bool: return str(p.get("url", "")).begins_with("/pic/")), "the DM's: every picture, each at its address")
	# a preview of the boss's breath, the DM's: hers without its name or its power's
	# (no fog now: the DM's marks lie on ground she knows)
	kernel.commit([{"t": "fog.set", "scene": sid, "enabled": false}], "No fog")
	check(host._put_mark("gm", {"id": "boss-breath", "kind": "preview", "scene": sid, "points": [[5.0, 7.4]], "shape": {"type": "cone", "size": 3.0}, "label": "Fire Breath, 15-ft cone", "actor": "a_boss", "token": "t_boss"}, true) == "", "the DM previews the boss's breath")
	check(_pump(host, [ana, ben, godot, dm], func() -> bool: return ana.inbox.any(func(m: Dictionary) -> bool: return str(m.get("t", "")) == "mark" and str(m.mark.id) == "boss-breath")), "it reaches her screen")
	var mark: Dictionary = ana.inbox.filter(func(m: Dictionary) -> bool: return str(m.get("t", "")) == "mark" and str(m.mark.id) == "boss-breath").back().mark
	check(str(mark.get("name", "")) == "A creature" and not mark.has("label"), "a creature's, no label naming its power: %s" % [mark])
	# a template of the DM's whose circle takes in the hidden lurker (its middle
	# well away from it): not on her screen, by the area it covers
	check(host._put_mark("gm", {"id": "dm-circle", "kind": "template", "scene": sid, "points": [[1.8, 6.0]], "shape": {"type": "circle", "size": 2.0}}, true) == "", "the DM lays a circle by the lurker")
	check(host._put_mark("gm", {"id": "dm-clear", "kind": "template", "scene": sid, "points": [[9.0, 2.0]], "shape": {"type": "circle", "size": 1.0}}, true) == "", "and one on open ground")
	check(_pump(host, [ana, ben, godot, dm], func() -> bool: return ana.inbox.any(func(m: Dictionary) -> bool: return str(m.get("t", "")) == "mark" and str(m.mark.id) == "dm-clear")), "the open one reaches her")
	check(not ana.inbox.any(func(m: Dictionary) -> bool: return str(m.get("t", "")) == "mark" and str(m.mark.id) == "dm-circle"), "the one over the lurker never")
	# the bestiary is the DM's: not searchable, not openable, from her screen
	ana.send({"t": "need", "kind": "view"})
	_pump(host, [ana, ben, godot, dm], func() -> bool: return false, 200)
	var colls: Array = ana.last("view").view.get("collections", [])
	check(not colls.has("creatures") and colls.has("spells"), "her Lookup: the spells, not the bestiary: %s" % [colls])
	ana.send({"t": "need", "kind": "comp", "req": "q1", "collection": "creatures", "query": {"text": "goblin", "facets": ["type"]}})
	ana.send({"t": "need", "kind": "comp", "req": "q2", "collection": "creatures", "id": "goblin-boss"})
	check(_pump(host, [ana, ben, godot, dm], func() -> bool: return ana.count("comp") >= 2), "her asking anyway")
	var answers := ana.inbox.filter(func(m: Dictionary) -> bool: return str(m.get("t", "")) == "comp")
	check(int(answers[0].page.total) == 0 and (answers[0].page.entries as Array).is_empty() and str(answers[1].get("error", "")) == "no such entry", "an empty page, and no such entry: %s" % [answers])
	dm.send({"t": "need", "kind": "comp", "req": "q3", "collection": "creatures", "id": "goblin-boss"})
	check(_pump(host, [ana, ben, godot, dm], func() -> bool: return not dm.last("comp").is_empty()) and str(dm.last("comp").entry.name) == "Goblin Boss", "the DM's: the stat block")
	for w in [ana, ben]:
		var raw := JSON.stringify((w as Web.WebClient).raw)
		for said in ["goblin_boss", "vicar", "Goblin Boss"]:
			check(not raw.contains(said), "nothing a player was sent says %s" % said)
	host.stop()


# ------------------------------------------------- waiting list, recap --

## What the table waits on, as a player is sent it: never a card of a creature
## they don't see (a hidden one's opportunity attack, "the DM: a reaction"
## counting down, told them it was there); once it is shown, as before.
func test_the_waiting_list_names_no_hidden_reactor() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, "t.react", """
local hm = hexmap
hm.actions.register('react', { label = 'React', target = '', run = function(ctx)
	hm.prompt_open('gm', { title = 'An opportunity attack?', fields = {} }, { public = 'a reaction', actor = ctx.who, urgent = true, deadline = 30 })
	return true
end })
""") == "", "a ruleset that asks the DM for a creature's reaction")
	_fight(kernel, sid)
	check(plugins.dispatch("t.react", "react", {"gm": true, "who": "a_lurk"}).status != PluginHost.PluginCall.ERROR, "the hidden lurker's reaction asked of the DM")
	check(plugins.dispatch("t.react", "react", {"gm": true, "who": "a_gob"}).status != PluginHost.PluginCall.ERROR, "and the goblin's, which she sees")
	var mine: Array = Views.project(kernel, plugins, ANA, Views.ROLE_PLAYER).waiting
	var dms: Array = Views.project(kernel, plugins, "", Views.ROLE_GM).waiting
	check(mine.size() == 1 and dms.size() == 2, "Ana's waiting list: the goblin's alone; the DM's both: %d / %d" % [mine.size(), dms.size()])
	kernel.commit([{"t": "token.set", "scene": sid, "id": "t_lurk", "changes": {"hidden": false}}], "Reveal")
	check(Views.project(kernel, plugins, ANA, Views.ROLE_PLAYER).waiting.size() == 2, "the lurker shown: its card too")


## The players' recap: what every player may know, nothing more — not a
## creature they haven't been shown nor its rolls, not a creature's hit
## points, not an effect only the DM sees nor one on a creature whose
## conditions they don't know, not a scene they weren't shown; a creature's
## name as they know it. The DM's has it all.
func test_the_players_recap() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, "t.recap", "hexmap.ui.knowledge({ names = 'hidden', conditions = 'hidden', health = { tags = { 'bloodied' }, resource = 'hp', players = 'marks' } })") == "", "a ruleset keeping names and conditions")
	var known := kernel.knowledge_policies()
	check(kernel.checkpoint("Session 1 start") != "", "the session starts")
	var staged := Encounter.new_scene(st.map_for(sid), "ground", "Ambush ahead", "")
	staged.tokens.append(Encounter.new_token("Bone Colossus", Vector2(5, 5), {"id": "t_bones", "actor": "a_bones"}))
	check(kernel.commit([
		{"t": "actor.add", "actor": {"id": "a_ghoul", "kind": "npc", "name": "Ghoul Lord"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Ghoul Lord", Vector2(3.5, 6.0), {"id": "t_ghoul", "actor": "a_ghoul", "hidden": true})},
		{"t": "actor.add", "actor": {"id": "a_snarl", "kind": "npc", "name": "Snarlfang"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Snarlfang", Vector2(4.5, 6.6), {"id": "t_snarl", "actor": "a_snarl"})},
		Resources.set_event("actor:a_snarl", "t.recap", "hp", Resources.pool(7, 7)),
		{"t": "actor.add", "actor": {"id": "a_bones", "kind": "npc", "name": "Bone Colossus"}},
		{"t": "scene.add", "scene": staged},
		{"t": "effect.apply", "effect": {"id": "e_doom", "on": "actor:a_snarl", "plugin": "t.recap", "key": "doomed", "label": "Marked for death", "audience": "gm", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "effect.apply", "effect": {"id": "e_fear", "on": "actor:a_snarl", "plugin": "t.recap", "key": "frightened", "label": "Frightened", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "log.add", "entry": {"id": "n_hit", "kind": "note", "text": Knowledge.mark("name", "a_snarl", "Snarlfang", "A creature") + " howls.", "audience": "all"}},
	], "the fight") == "", "a hidden ghoul, Snarlfang (its name kept), a colossus staged elsewhere, a mark the DM keeps, its fear")
	kernel.roll({"expr": "1d20+3", "visibility": "gm"}, {"actor": "a_ghoul"}, "Claw")
	kernel.roll({"expr": "1d20+4"}, {"actor": "a_snarl"}, "Bite")
	kernel.commit([Resources.spend(st, "actor:a_snarl", "t.recap", "hp", 5)], "Hit")
	var theirs := Recap.markdown(st.encounter, "all", known)
	for said in ["Ghoul Lord", "Snarlfang", "Bone Colossus", "Ambush ahead", "Marked for death", "Frightened", "hp → 2"]:
		check(not theirs.contains(said), "the players' recap doesn't say %s" % said)
	check(theirs.contains("- **A creature**: 1 roll") and theirs.contains("A creature howls.") and theirs.count("joined") == 1, "it says a creature rolled once, and howled, and one came:\n" + theirs)
	var summ := Recap.summary(st.encounter, "all", known)
	check(not summ.rolls.has("Ghoul Lord") and summ.rolls.has("A creature") and not summ.rolls["A creature"].labels.has("Claw"), "no roll of the ghoul's: %s" % [summ.rolls])
	var dms := Recap.markdown(st.encounter, "gm", known)
	for said in ["Ghoul Lord", "Snarlfang", "Bone Colossus", "Marked for death", "Frightened", "hp → 2"]:
		check(dms.contains(said), "the DM's says %s" % said)
	check(Recap.summary(st.encounter, "gm", known).rolls.has("Ghoul Lord"), "and the ghoul's roll")


# ------------------------------------------------------------------- maps --

static func _el(lvl: Dictionary, coll: String, id: String) -> Dictionary:
	for o in lvl.get(coll, []):
		if str(o.get("id", "")) == id:
			return o
	return {}


## A map as a player is sent it has nothing on it the players aren't shown:
## no DM's note, no prop or light the DM hides, a secret door the wall it
## looks like (a door once it's found open), a locked door just closed, no
## hidden wall (but where a Godot client's own sight stops: a pillar's, kept
## hidden), and of the map only the scene's level (not the crypt below).
## Only the map of the scene the players see is served to a player, and its
## files only by the key that comes with it; what they may see of it
## changing (a prop revealed, a door found) brings it again.
func test_maps_as_players_may_see_them() -> void:
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var crypt := str(st.encounter.scenes.filter(func(s: Dictionary) -> bool: return str(s.id) != sid)[0].id)
	var m := st.map_for(sid)
	var mid := str(m.doc.id)
	var ground: Dictionary = m.level_by_id("ground")
	var door := "w_2bf8ecbc"
	var pillar := "w_8abf465d"
	var prop := str(ground.props[0].id)
	var light := str(ground.lights[0].id)
	ground.props[0].hidden = true
	ground.lights[0].hidden = true
	ground.walls.append({"id": "w_ghost", "points": [[1.0, 1.0], [2.0, 1.0]], "blocks": {"move": true, "sight": false, "light": false, "sound": false}, "hidden": true})
	m.add_asset("ground.png", PackedByteArray([137, 80, 78, 71]))
	ground.backdrop = {"image": "local:ground.png", "pos": [0.0, 0.0]}
	var gnote := str(ground.notes[0].id)
	var note_text := str(ground.notes[0].text)
	# the DM locks the chapel's door
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:" + door, "changes": {"state": "locked"}})
	var web := Protocol.player_map(m.doc, st.encounter.scene(sid).overrides, false, "ground")
	var wl: Dictionary = web.levels[0]
	check((web.levels as Array).size() == 1 and str(wl.id) == "ground", "the scene's level alone: no crypt")
	check(_el(wl, "props", prop).is_empty() and _el(wl, "lights", light).is_empty() and _el(wl, "notes", gnote).is_empty(), "no hidden prop, no hidden light, no DM's note")
	check(_el(wl, "walls", pillar).is_empty() and _el(wl, "walls", "w_ghost").is_empty(), "a web screen: no hidden wall at all")
	check(str(_el(wl, "walls", door).get("state", "")) != "locked", "the door: not locked to her")
	var ov := Protocol.player_overrides(st.encounter.scene(sid).overrides, ground)
	check(str(ov.get("walls:" + door, {}).get("state", "")) == "closed", "the scene's override: closed, not locked: %s" % [ov])
	var godot := Protocol.player_map(m.doc, st.encounter.scene(sid).overrides, true, "ground")
	var pw := _el(godot.levels[0], "walls", pillar)
	check(not pw.is_empty() and bool(pw.get("hidden", false)) and pw.keys().size() == 4 and _el(godot.levels[0], "walls", "w_ghost").is_empty(), "a Godot client's: the pillar's wall where its sight stops, hidden, no more; not the one that stops no sight")
	# the crypt: its secret door the wall it looks like, a door once found open
	var crypt_lvl: Dictionary = m.level_by_id("crypt")
	var secret := "w_5aaab580"
	var cm := Protocol.player_map(m.doc, {}, false, "crypt")
	check(str(_el(cm.levels[0], "walls", secret).get("door", "")) == "none" and not _el(cm.levels[0], "walls", secret).has("state"), "the crypt's secret door: a wall")
	check(not JSON.stringify(cm).contains("secret"), "nothing in it says secret")
	var found := Protocol.player_overrides({"walls:" + secret: {"state": "open"}}, crypt_lvl)
	check(found == {"walls:" + secret: {"door": "door", "state": "open"}}, "found open: a door: %s" % [found])
	check(Protocol.player_overrides({"walls:" + secret: {"state": "closed"}}, crypt_lvl).is_empty(), "closed again: the wall it looks like")
	# hosted: what is served, and to whom
	var other := HexMap.load_file(example("forest_road.hexmap"))
	st.attach_map(other)
	var road := Encounter.new_scene(other, str(other.levels[0].id), "The road ahead", "")
	st.apply({"t": "scene.add", "scene": road})
	var kernel := RulesKernel.new(st)
	var host := _host(st, kernel)
	var ana := _web_player(host, ANA)
	ana.send({"t": "need", "kind": "map", "id": mid})
	check(_pump(host, [ana], func() -> bool: return not ana.last("map").is_empty()), "her screen asks for the chapel: it comes")
	var key := str(ana.last("map").get("key", ""))
	check(key.length() == 32 and _el(ana.last("map").doc.levels[0], "props", prop).is_empty(), "with its key, and as she may see it")
	ana.send({"t": "need", "kind": "map", "id": str(other.doc.id)})
	check(_pump(host, [ana], func() -> bool: return str(ana.last("error").get("why", "")).contains("no map")), "the road ahead, a scene she isn't shown: no")
	check(not host.web.map_file_source.call(mid, "ground.png", key).is_empty(), "its backdrop by its key")
	check(host.web.map_file_source.call(mid, "ground.png", "0".repeat(32)).is_empty() and str(host.web.respond("GET /mapfile/%s/ground.png HTTP/1.1\r\n\r\n" % mid).get_string_from_utf8()).begins_with("HTTP/1.1 404"), "not without it")
	# the DM reveals the prop: her map again, with it; a Godot client's too
	var ben := _godot(host, BEN, [ana])
	ben.send({"t": "need", "kind": "map", "id": mid})
	check(_pump(host, [ana, ben], func() -> bool: return not ben.last("map").is_empty()), "Ben's Godot client has the map")
	var maps_a := ana.count("map")
	var maps_b := ben.count("map")
	kernel.commit([{"t": "element.set", "scene": sid, "ref": "props:" + prop, "changes": {"hidden": false}}], "Reveal the prop")
	check(_pump(host, [ana, ben], func() -> bool: return ana.count("map") > maps_a and ben.count("map") > maps_b), "the prop revealed: both sent the map again")
	check(not _el(ana.last("map").doc.levels[0], "props", prop).is_empty() and not _el(ben.last("map").doc.levels[0], "props", prop).is_empty(), "with the prop")
	# the DM unlocks and opens the door: an override as hers
	kernel.commit([{"t": "element.set", "scene": sid, "ref": "walls:" + door, "changes": {"state": "open"}}], "Open")
	check(_pump(host, [ana, ben], func() -> bool: return str(ana.last("scene").get("scene", {}).get("overrides", {}).get("walls:" + door, {}).get("state", "")) == "open" and str(_held(ben).scenes[0].overrides.get("walls:" + door, {}).get("state", "")) == "open"), "the door open on her screen and his client")
	# the players are shown the crypt; the DM finds the secret door for them
	kernel.commit([{"t": "scene.activate", "id": crypt}], "The crypt")
	check(_pump(host, [ana, ben], func() -> bool: return str(ana.last("map").get("doc", {}).get("levels", [{}])[0].get("id", "")) == "crypt"), "shown the crypt: her map again, its level")
	kernel.commit([{"t": "element.set", "scene": crypt, "ref": "walls:" + secret, "changes": {"state": "open"}}], "Found")
	check(_pump(host, [ana, ben], func() -> bool: return str(ana.last("scene").get("scene", {}).get("overrides", {}).get("walls:" + secret, {}).get("door", "")) == "door" and str(_held(ben).scenes[0].overrides.get("walls:" + secret, {}).get("door", "")) == "door"), "found: a door on her screen and his client")
	for w in [ana, ben]:
		var raw := JSON.stringify((w as Web.WebClient).raw)
		for said in ["\"secret\"", "\"state\":\"locked\"", note_text.left(30), "w_ghost"]:
			var at := raw.find(said)
			check(at < 0, "nothing sent says %s: %s" % [said, raw.substr(maxi(0, at - 200), 300) if at >= 0 else ""])
	host.stop()
