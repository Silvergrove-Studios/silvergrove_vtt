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
