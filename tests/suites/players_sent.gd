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


static func _tok_in(doc: Dictionary, id: String) -> Dictionary:
	for sc in doc.get("scenes", []):
		for tk in sc.get("tokens", []):
			if str(tk.id) == id:
				return tk
	return {}
