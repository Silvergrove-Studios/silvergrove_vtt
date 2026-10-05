extends TestCase
## What the players know of a creature no player owns — its health, its name,
## its conditions — as its ruleset declares (hm.ui.knowledge, Knowledge), and
## the Table filtering what each screen is sent by it: a web screen's scene, a
## Godot client's document and token events, the rules' view, a ruleset's
## words wherever they name a creature (its marks), a refusal, the chat of
## sessions before, the marks on the map, and the DM's See as.

const ANA := "pl_fe0170c1"
const BEN := "pl_393eb25a"
const Web := preload("res://tests/suites/web.gd")


func _chapel_state() -> EncounterState:
	var st := EncounterState.new(Encounter.load_file(example("chapel_ambush.encounter")))
	st.resolve_maps()
	return st


## A ruleset that keeps what it is told from the players, and says what the
## tests need it to: a hit (marked words, a roll at Ana's fighter), a card, a
## refusal naming the goblin.
func _rules(names := "hidden", conditions := "hidden", health := "marks") -> String:
	return """
local hm = hexmap
hm.ui.knowledge({ names = '%s', conditions = '%s',
	health = { tags = { 'bloodied', 'down', 'dead' }, resource = 'hp', effects = { 'dead' }, players = '%s' } })
local function gob(start) return hm.known.name('a_gob', start and 'The Goblin' or 'the Goblin', start and 'A creature' or 'a creature') end
hm.actions.register('hit', { label = 'Hit', target = '', run = function(ctx)
	hm.log(gob(true) .. ' hits Ana' .. string.char(39) .. 's fighter' .. hm.known.conditions('a_gob', ', and is Frightened') .. '.', 'all')
	hm.dice.roll({ expr = '1d20+4' }, { actor = 'a_gob', target = 'a_fighter' }, 'Scimitar')
	return true
end })
hm.actions.register('ask', { label = 'Ask', target = '', run = function(ctx)
	hm.prompt_open(ctx.to, { title = gob(true) .. ' swings at you: a reaction?', fields = {} },
		{ public = 'a reaction (' .. gob(false) .. ')' })
	return true
end })
hm.actions.register('swing', { label = 'Swing', target = '', run = function(ctx)
	error(gob(true) .. ' is out of reach (30 ft)')
end })
""" % [names, conditions, health]


func _load(plugins: PluginHost, src: String) -> String:
	if plugins.plugins.has("t.known"):
		plugins.unload("t.known")
	return plugins.load_source({"id": "t.known", "version": "1", "api": 1, "name": "Known", "capabilities": ["state", "log", "dice", "prompts"]}, [["main.lua", src]])


## Two goblins no player owns beside Ana's fighter (an actor of hers), a
## third the DM keeps hidden, a person of the world the players see listed.
func _setup(k: RulesKernel, sid: String) -> void:
	var fighter := str(k.state.tokens(sid).filter(func(t: Dictionary) -> bool: return str(t.name) == "Ana's fighter")[0].id)
	check(k.commit([
		{"t": "actor.add", "actor": {"id": "a_fighter", "kind": "pc", "name": "Ana's fighter", "owner": ANA}},
		{"t": "token.set", "scene": sid, "id": fighter, "changes": {"actor": "a_fighter"}},
		{"t": "actor.add", "actor": {"id": "a_gob", "kind": "npc", "name": "Goblin", "audience": {"visible": "all"}}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Goblin", Vector2(4.5, 6.6), {"id": "t_gob", "actor": "a_gob", "label": "G", "hidden": false, "tags": ["humanoid"]})},
		{"t": "actor.add", "actor": {"id": "a_gob2", "kind": "npc", "name": "Goblin Boss"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Goblin Boss", Vector2(5.0, 7.4), {"id": "t_gob2", "actor": "a_gob2", "label": "GB", "hidden": false, "tags": []})},
		{"t": "actor.add", "actor": {"id": "a_lurk", "kind": "npc", "name": "Lurker"}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Lurker", Vector2(3.5, 6.0), {"id": "t_lurk", "actor": "a_lurk", "hidden": true, "tags": []})},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Floating light", Vector2(4.0, 5.5), {"id": "t_obj", "actor": "a_gob2", "hidden": false, "tags": ["object"]})},
		Resources.set_event("actor:a_gob", "t.known", "hp", Resources.pool(3, 7)),
		{"t": "effect.apply", "effect": {"id": "e_fear", "on": "actor:a_gob", "plugin": "t.known", "key": "frightened", "label": "Frightened", "stack": "none", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "token.set", "scene": sid, "id": "t_gob", "changes": {"tags": ["humanoid", "frightened", "bloodied"]}},
	], "setup") == "", "set up: two goblins by Ana's fighter, a lurker hidden")


func _tok(snap: Dictionary, id: String) -> Dictionary:
	for t in snap.get("tokens", []):
		if str(t.id) == id:
			return t
	return {}


func _doc_tok(doc: Dictionary, id: String) -> Dictionary:
	for sc in doc.get("scenes", []):
		for t in sc.get("tokens", []):
			if str(t.id) == id:
				return t
	return {}


func _note(view: Dictionary, has: String) -> String:
	for e in view.get("log", []):
		if str(e.get("kind", "")) == "note" and str(e.get("text", "")).contains(has):
			return str(e.text)
	return ""


func _roll(view: Dictionary) -> Dictionary:
	for e in view.get("log", []):
		if str(e.get("kind", "")) == "roll":
			return e
	return {}


## A ruleset declares what the players know: its parts merged over what it
## said before (hm.ui.health alone keeps names and conditions), bad values
## refused, nothing once it's unloaded.
func test_knowledge_declared() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var k := RulesKernel.new(_chapel_state())
	var plugins := PluginHost.new(k)
	check(k.knowledge_policies().is_empty() and not Knowledge.hides([]), "nothing declared: the players are sent everything, as before")
	check(_load(plugins, _rules("hidden", "shown", "marks")) == "", "declared")
	var p: Dictionary = k.knowledge_policies()[0]
	check(str(p.names) == "hidden" and str(p.conditions) == "shown" and str(p.players) == "marks" and p.tags == ["bloodied", "down", "dead"], "names hidden, conditions shown, health's marks: %s" % [p])
	check(Knowledge.names_hidden(k.knowledge_policies()) and not Knowledge.conditions_hidden(k.knowledge_policies()) and Knowledge.hides(k.knowledge_policies()), "what it keeps")
	check(_load(plugins, "hexmap.ui.knowledge({ names = 'hidden' })\nhexmap.ui.health({ players = 'none', tags = { 'down' } })") == "", "health declared after names")
	p = k.knowledge_policies()[0]
	check(str(p.names) == "hidden" and str(p.players) == "none" and p.tags == ["down"], "hm.ui.health keeps what was declared of names: %s" % [p])
	check(plugins.load_source({"id": "t.bad", "version": "1", "api": 1, "name": "Bad"}, [["main.lua", "hexmap.ui.knowledge({ names = 'secret' })"]]) != "", "a value it doesn't know is refused")
	check(plugins.load_source({"id": "t.bad2", "version": "1", "api": 1, "name": "Bad"}, [["main.lua", "hexmap.ui.health({ players = 'some' })"]]) != "", "so is a health mode")
	plugins.unload("t.known")
	check(k.knowledge_policies().is_empty(), "unloaded, nothing is declared")


## The marks a ruleset's words carry: the DM's words for the DM, "a creature"
## for a screen that doesn't know, conditions' words gone; a mark cut short is
## nothing to a player; the wire's JSON stays JSON.
func test_marks_in_words() -> void:
	var name := Knowledge.mark("name", "a_gob", "The Goblin", "A creature")
	var cond := Knowledge.mark("cond", "a_gob", ", and is Frightened")
	var line := name + " hits Wren" + cond + "."
	check(Knowledge.plain(line) == "The Goblin hits Wren, and is Frightened.", "the DM's words: %s" % Knowledge.plain(line))
	var nobody := func(_aspect: String, _aid: String) -> bool: return false
	var names_only := func(aspect: String, _aid: String) -> bool: return aspect == "name"
	check(Knowledge.render(line, nobody) == "A creature hits Wren.", "a player who knows neither: %s" % Knowledge.render(line, nobody))
	check(Knowledge.render(line, names_only) == "The Goblin hits Wren.", "its name revealed, its conditions kept")
	# a name said with no capital ("a creature") starts a sentence with one
	var bare := Knowledge.mark("name", "a_gob", "Goblin", "a creature")
	check(Knowledge.render(bare + " drops prone. Wren laughs at " + bare + ".", nobody) == "A creature drops prone. Wren laughs at a creature.", "capitalised where a sentence starts: %s" % Knowledge.render(bare + " drops prone. Wren laughs at " + bare + ".", nobody))
	check(Knowledge.render("a reaction (" + bare + ")", nobody) == "a reaction (a creature)", "not mid-sentence")
	var wire: Variant = JSON.parse_string(Knowledge.render_json(JSON.stringify({"text": bare + " flees", "b": "Then: " + bare}), nobody))
	check(str(wire.text) == "A creature flees" and str(wire.b) == "Then: a creature", "and on the wire: %s" % [wire])
	# words about its conditions read as nothing take their list's separator with them
	var held := Knowledge.mark("cond", "a_gob", "Paralyzed")
	check(Knowledge.render("Hold Person → " + bare + ": fails the save, " + held + ".", nobody) == "Hold Person → a creature: fails the save.", "a list's comma goes with them: %s" % Knowledge.render("Hold Person → " + bare + ": fails the save, " + held + ".", nobody))
	var gone := Knowledge.mark("cond", "a_gob", "the Goblin is no longer Paralyzed")
	check(Knowledge.render(gone + "; Wren is no longer Frightened", nobody) == "Wren is no longer Frightened", "a list's first: the separator after it")
	check(Knowledge.render("the Goblin: " + held, nobody) == "the Goblin", "a clause's colon, at its end")
	check(Knowledge.render("fails the save, " + held + ".", names_only) == "fails the save.", "names known, conditions not")
	check(Knowledge.plain("fails the save, " + held + ".") == "fails the save, Paralyzed.", "the DM's: whole")
	wire = JSON.parse_string(Knowledge.render_json(JSON.stringify({"text": "fails the save, " + held, "b": held + ", and 5 fire damage"}), nobody))
	check(str(wire.text) == "fails the save" and str(wire.b) == "and 5 fire damage", "and on the wire: %s" % [wire])
	# nested words keep the outer mark whole
	check(Knowledge.plain(Knowledge.mark("name", "a_gob", name + "'s", "a creature's")) == "The Goblin's", "a mark inside a mark: one mark")
	# cut short: the DM reads the words, a player nothing of them
	var half := name.left(name.find(Knowledge.SEP) + 3) + " hits"
	check(Knowledge.render(half, nobody) == "", "a mark cut short reads as nothing to a player: '%s'" % Knowledge.render(half, nobody))
	check(Knowledge.render(Knowledge.ANCHOR + "The Gob", nobody, false) == "" and Knowledge.render(Knowledge.ANCHOR + "The Gob", nobody, true) == "The Gob", "an anchor alone: nothing to a player, the words to the DM")
	check(Knowledge.cut("a reaction (" + name + ")", 12) == "a reaction (", "cut to 12: the name doesn't fit, so it goes whole")
	check(Knowledge.plain(Knowledge.cut("a reaction (" + name + ")", 40)) == "a reaction (The Goblin)", "it fits: kept whole")
	# the wire
	var msg := {"t": "view", "view": {"log": [{"kind": "note", "text": line}], "why": "\"quoted\" " + name}}
	var text := Knowledge.render_json(JSON.stringify(msg), nobody)
	var back: Variant = JSON.parse_string(text)
	check(back is Dictionary and str(back.view.log[0].text) == "A creature hits Wren." and str(back.view.why) == "\"quoted\" A creature", "on the wire, JSON still: %s" % text)
	var cut_short := JSON.stringify({"t": "x", "a": half, "b": "fine"})
	back = JSON.parse_string(Knowledge.render_json(cut_short, nobody))
	check(back is Dictionary and str(back.a) == "" and str(back.b) == "fine", "a cut mark on the wire: parsed and put right")
	var v := {"a": [line, {"b": name}], "schema": {"text": name}}
	Knowledge.render_value(v, nobody, false, {"schema": true})
	check(str(v.a[0]) == "A creature hits Wren." and str(v.a[1].b) == "A creature" and str(v.schema.text) == name, "a value walked, a schema passed by")


## Names hidden: a creature no player owns is "a creature" on a player's
## screens, "?" alone or numbered among those they see (the DM's hidden ones
## not counted), until the DM reveals it; the party's and things keep theirs;
## the DM sees every name and the label the players see.
func test_names_kept_from_players() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var k := RulesKernel.new(st)
	var plugins := PluginHost.new(k)
	check(_load(plugins, _rules("hidden", "hidden")) == "", "a ruleset keeping names and conditions")
	_setup(k, sid)
	var known := k.knowledge_policies()
	var snap := WebScene.build(st, sid, ANA, false, known)
	var gob := _tok(snap, "t_gob")
	check(str(gob.name) == "a creature" and bool(gob.get("unknown", false)), "Ana's screen: the goblin is a creature: %s" % [gob.get("name")])
	check(str(gob.label) == "1" and str(_tok(snap, "t_gob2").label) == "2", "two she doesn't know: 1 and 2, the hidden lurker not counted: %s, %s" % [gob.label, _tok(snap, "t_gob2").get("label")])
	check(str(_tok(snap, "t_gob2").name) == "a creature", "the boss too")
	check(str(_tok(snap, "t_obj").name) == "Floating light", "a thing on the map keeps its name")
	check(str(_tok(snap, str(st.tokens(sid)[0].id)).name) == "Ana's fighter", "her fighter is hers")
	check(_tok(snap, "t_lurk").is_empty(), "the hidden lurker isn't sent at all")
	check(not (gob.tags as Array).has("frightened") and (gob.tags as Array).has("bloodied"), "conditions kept: no Frightened tag; health's marks shown: %s" % [gob.tags])
	var dm := WebScene.build(st, sid, "", true, known)
	check(str(_tok(dm, "t_gob").name) == "Goblin" and str(_tok(dm, "t_gob").player_label) == "1" and _tok(dm, "t_gob").name_known == false, "the DM's: its name, and the label the players see")
	check((_tok(dm, "t_gob").tags as Array).has("frightened"), "the DM's: every tag")
	# a Godot player's document, and a token event after it
	var doc := Protocol.client_document(st.encounter.doc, false, known)
	check(str(_doc_tok(doc, "t_gob").name) == "a creature" and str(_doc_tok(doc, "t_gob").label) == "1", "Ben's Godot client: a creature, 1")
	check(str(_doc_tok(doc, "t_lurk").name) == "a creature" and str(_doc_tok(doc, "t_lurk").label) == "?", "the lurker his client holds, hidden: a creature, ? (its name never there)")
	check(str(_doc_tok(Protocol.client_document(st.encounter.doc, true, known), "t_gob").name) == "Goblin", "a co-GM's: its name")
	var ev := {"t": "token.set", "scene": sid, "id": "t_gob", "changes": {"name": "Goblin Warrior", "label": "GW", "tags": ["humanoid", "frightened"]}}
	var theirs := Knowledge.player_event(ev, st.token(sid, "t_gob"), st.encounter.doc, known, "1")
	check(str(theirs.changes.name) == "a creature" and str(theirs.changes.label) == "1" and not (theirs.changes.tags as Array).has("frightened"), "a change of its name and tags, as a player's client is sent it: %s" % [theirs.changes])
	check(str(ev.changes.name) == "Goblin Warrior", "the DM's event untouched")
	# the rules' view: the goblin listed to players is a creature, its Frightened kept
	var view := Views.project(k, plugins, ANA, Views.ROLE_PLAYER)
	check(str(view.actors.a_gob.name) == "a creature" and str(view.actors.a_gob.tokens[0].name) == "a creature", "Ana's view: a creature: %s" % [view.actors.a_gob.name])
	check((view.actors.a_gob.effects as Array).is_empty(), "its Frightened isn't in her view")
	check(str(view.actors.a_fighter.name) == "Ana's fighter", "her own, by name")
	var dm_view := Views.project(k, plugins, "", Views.ROLE_GM)
	check(str(dm_view.actors.a_gob.name) == "Goblin" and (dm_view.actors.a_gob.effects as Array).size() == 1, "the DM's view: Goblin, Frightened")
	# a ruleset's words naming it, and a roll it made at her fighter
	check(plugins.dispatch("t.known", "hit", {"gm": true}).status != PluginHost.PluginCall.ERROR, "the goblin hits")
	view = Views.project(k, plugins, ANA, Views.ROLE_PLAYER)
	check(_note(view, "hits") == "A creature hits Ana's fighter.", "Ana's log: %s" % _note(view, "hits"))
	var r := _roll(view)
	check(str(r.get("who", "")) == "A creature" and str(r.get("whom", "")) == "Ana's fighter", "its roll: a creature at Ana's fighter: %s / %s" % [r.get("who"), r.get("whom")])
	dm_view = Views.project(k, plugins, "", Views.ROLE_GM)
	check(_note(dm_view, "hits") == "The Goblin hits Ana's fighter, and is Frightened.", "the DM's: %s" % _note(dm_view, "hits"))
	check(str(_roll(dm_view).get("who", "")) == "Goblin" and str(_roll(dm_view).get("whom", "")) == "Ana's fighter", "the DM's roll: Goblin at Ana's fighter")
	# the DM reveals its name: everything Ana is sent has it, before and after
	check(k.commit([{"t": "actor.set", "id": "a_gob", "changes": {"audience/name": "all"}}], "Reveal") == "", "revealed")
	known = k.knowledge_policies()
	snap = WebScene.build(st, sid, ANA, false, known)
	check(str(_tok(snap, "t_gob").name) == "Goblin" and str(_tok(snap, "t_gob").label) == "G", "Ana's screen: the Goblin, by its own label: %s %s" % [_tok(snap, "t_gob").name, _tok(snap, "t_gob").label])
	check(str(_tok(snap, "t_gob2").label) == "?" and str(_tok(snap, "t_gob2").name) == "a creature", "the boss alone unknown now: ?")
	view = Views.project(k, plugins, ANA, Views.ROLE_PLAYER)
	check(_note(view, "hits") == "The Goblin hits Ana's fighter.", "the line said before names it now; its Frightened still kept: %s" % _note(view, "hits"))
	check(str(_roll(view).get("who", "")) == "Goblin", "and its roll")
	check((view.actors.a_gob.effects as Array).is_empty(), "its conditions are another thing: still kept")
	check(WebScene.build(st, sid, "", true, known).tokens.filter(func(t: Dictionary) -> bool: return str(t.id) == "t_gob")[0].name_known == true, "the DM's screen: its name known (to keep it again)")
	# names shown: nothing kept
	check(_load(plugins, _rules("shown", "shown")) == "", "names and conditions shown")
	known = k.knowledge_policies()
	snap = WebScene.build(st, sid, ANA, false, known)
	check(str(_tok(snap, "t_gob2").name) == "Goblin Boss" and str(_tok(snap, "t_gob2").label) == "GB" and (_tok(snap, "t_gob").tags as Array).has("frightened"), "everything, as before")
	view = Views.project(k, plugins, ANA, Views.ROLE_PLAYER)
	check(_note(view, "hits") == "The Goblin hits Ana's fighter, and is Frightened.", "a line marked while they were kept reads whole: %s" % _note(view, "hits"))


## Cards, what the table waits on, a refusal: a creature named in them is "a
## creature" to a player; the DM reads its name.
func test_cards_and_refusals() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var k := RulesKernel.new(st)
	var plugins := PluginHost.new(k)
	check(_load(plugins, _rules()) == "", "loaded")
	_setup(k, sid)
	check(plugins.dispatch("t.known", "ask", {"gm": true, "to": ANA}).status != PluginHost.PluginCall.ERROR, "a card for Ana")
	var view := Views.project(k, plugins, ANA, Views.ROLE_PLAYER)
	check(str(view.prompts[0].form.title) == "A creature swings at you: a reaction?", "her card: %s" % view.prompts[0].form.title)
	var ben := Views.project(k, plugins, BEN, Views.ROLE_PLAYER)
	check(str(ben.waiting[0].what) == "a reaction (a creature)", "Ben is told what the table waits on: %s" % ben.waiting[0].what)
	var dm := Views.project(k, plugins, "", Views.ROLE_GM)
	check(str(dm.prompts[0].form.title) == "The Goblin swings at you: a reaction?" and str(dm.waiting[0].what) == "a reaction (the Goblin)", "the DM's: the Goblin")
	var pc := plugins.dispatch("t.known", "swing", {"gm": true})
	check(pc.status == PluginHost.PluginCall.ERROR, "refused")
	var knows := Knowledge.knower(st.encounter.actors, k.knowledge_policies(), false)
	check(Knowledge.render(pc.error, knows).ends_with("A creature is out of reach (30 ft)") and Knowledge.plain(pc.error).ends_with("The Goblin is out of reach (30 ft)"), "a refusal: a player reads a creature, the DM the Goblin: %s" % Knowledge.render(pc.error, knows))


## Over the wire: Ana's web screen, Ben's Godot client, the DM's screen. A
## line naming the goblin reaches each as they may read it; a refusal too;
## the DM's See as shows what Ana is sent (the names, the chat, the marks);
## a name revealed reaches every screen at once, Ben's document sent again.
func test_names_over_the_wire() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var kernel := RulesKernel.new(st)
	var plugins := PluginHost.new(kernel)
	check(_load(plugins, _rules()) == "", "loaded")
	_setup(kernel, sid)
	var host := HostSession.new(st, PackLibrary.new())
	host.kernel = kernel
	host.plugins = plugins
	host.dm_token = "sesame"
	host.dm_state_source = func() -> Dictionary: return {}
	check(host.start(0, false, 0) == OK, "hosting")
	var seat := func(hello: Dictionary, join: Dictionary) -> Web.WebClient:
		var w := Web.WebClient.new(host.port)
		_pump(host, [w], func() -> bool: return w.open())
		w.send(hello)
		w.send(join)
		_pump(host, [w], func() -> bool: return not w.last("joined").is_empty())
		return w
	var ana: Web.WebClient = seat.call({"t": "hello", "version": Protocol.VERSION, "name": "phone", "web": true}, {"t": "join", "role": "player", "player": ANA})
	var ben: Web.WebClient = seat.call({"t": "hello", "version": Protocol.VERSION, "name": "godot"}, {"t": "join", "role": "player", "player": BEN})
	var dm: Web.WebClient = seat.call({"t": "hello", "version": Protocol.VERSION, "name": "dm", "web": true}, {"t": "join", "role": "dm", "token": "sesame"})
	var all := [ana, ben, dm]
	_pump(host, all, func() -> bool: return not ana.last("scene").is_empty() and not dm.last("scene").is_empty())
	check(str(_tok(ana.last("scene").scene, "t_gob").name) == "a creature", "Ana's screen: a creature")
	check(str(_tok(dm.last("scene").scene, "t_gob").name) == "Goblin", "the DM's: the Goblin")
	check(str(_doc_tok(ben.last("welcome").encounter, "t_gob").name) == "a creature", "Ben's document: a creature")
	# the goblin hits: every screen's log as it may read it
	var views := ana.count("view")
	check(plugins.dispatch("t.known", "hit", {"gm": true}).status != PluginHost.PluginCall.ERROR, "the goblin hits")
	host.refresh_views()
	check(_pump(host, all, func() -> bool: return ana.count("view") > views and _note(ben.last("view").view, "hits") != "" and _note(dm.last("view").view, "hits") != ""), "the views go out")
	check(_note(ana.last("view").view, "hits") == "A creature hits Ana's fighter.", "Ana's: %s" % _note(ana.last("view").view, "hits"))
	check(_note(ben.last("view").view, "hits") == "A creature hits Ana's fighter.", "Ben's Godot client's: %s" % _note(ben.last("view").view, "hits"))
	check(_note(dm.last("view").view, "hits") == "The Goblin hits Ana's fighter, and is Frightened.", "the DM's: %s" % _note(dm.last("view").view, "hits"))
	for w in all:
		var raw := JSON.stringify((w as Web.WebClient).inbox)
		check(not raw.contains(Knowledge.ANCHOR) and not raw.contains(Knowledge.SEP), "no mark reaches a screen")
	var sent := JSON.stringify(ana.inbox)
	var at := sent.find("Goblin\"")
	check(at < 0, "nothing Ana was sent names the goblin: %s" % sent.substr(maxi(0, at - 300), 340))
	# a refusal: Ana's action naming the goblin
	var p := plugins.plugins["t.known"] as PluginHost.Plugin
	p.actions["swing"] = {"label": "Swing", "target": ""}
	ana.send({"t": "intent", "intent": {"kind": "action", "plugin": "t.known", "action": "swing", "ctx": {}}, "req": "r1"})
	check(_pump(host, all, func() -> bool: return not ana.last("refused").is_empty()), "refused")
	check(str(ana.last("refused").why).ends_with("A creature is out of reach (30 ft)"), "Ana is told why, as she knows it: %s" % ana.last("refused").why)
	# See as: the DM's preview of Ana's screen, her chat, her marks (fog off: she
	# sees all but the lurker the DM hides)
	kernel.commit([{"t": "fog.set", "scene": sid, "enabled": false}], "No fog")
	check(host.marks.put("gm", {"id": "dm-ruler", "kind": "ruler", "scene": sid, "points": [[4.0, 6.64], [5.0, 7.4]]}, {"name": "DM", "color": "#fff"}, true) == "", "a ruler of the DM's, over what Ana sees")
	check(host.marks.put("gm", {"id": "dm-far", "kind": "ruler", "scene": sid, "points": [[3.5, 6.0], [3.0, 5.0]]}, {"name": "DM", "color": "#fff"}, true) == "", "and one from the lurker she can't see")
	var scenes := dm.count("scene")
	dm.send({"t": "intent", "intent": {"kind": "dm", "op": "see_as", "player": ANA}, "req": "s1"})
	check(_pump(host, all, func() -> bool: return dm.count("scene") > scenes and not dm.last("scene").get("preview", {}).is_empty() and dm.last("view").view.has("preview_chat")), "the DM sees as Ana")
	var seen: Dictionary = dm.last("scene")
	check(str(_tok(seen.preview, "t_gob").name) == "a creature" and str(_tok(seen.preview, "t_gob").label) == "1", "her screen as she has it: a creature, 1")
	check(str(_tok(seen.scene, "t_gob").name) == "Goblin", "the DM's own: the Goblin")
	var pv: Dictionary = dm.last("view").view.preview_chat
	check(_note(pv, "hits") == "A creature hits Ana's fighter.", "her chat as she reads it: %s" % _note(pv, "hits"))
	var preview_marks: Array = seen.get("preview_marks", [])
	check(preview_marks.any(func(m: Dictionary) -> bool: return str(m.id) == "dm-ruler") and not preview_marks.any(func(m: Dictionary) -> bool: return str(m.id) == "dm-far"), "her marks: the ruler she sees, not the one over what she can't: %s" % [preview_marks.map(func(m: Dictionary) -> String: return str(m.id))])
	host.marks.remove("gm", "dm-ruler", true)
	check(_pump(host, all, func() -> bool: return not dm.last("seen_marks").is_empty() and (dm.last("seen_marks").marks as Array).is_empty()), "a mark gone: the See as's marks follow")
	# the DM reveals the goblin's name: Ana's screen and Ben's document at once
	var welcomes := ben.count("welcome")
	check(kernel.commit([{"t": "actor.set", "id": "a_gob", "changes": {"audience/name": "all"}}], "Reveal") == "", "revealed")
	check(_pump(host, all, func() -> bool: return str(_tok(ana.last("scene").scene, "t_gob").name) == "Goblin" and ben.count("welcome") > welcomes), "Ana's screen names it, Ben's client is sent its document again")
	check(str(_doc_tok(ben.last("welcome").encounter, "t_gob").name) == "Goblin" and str(_doc_tok(ben.last("welcome").encounter, "t_gob2").label) == "?", "Ben's: the Goblin, and the boss alone unknown: ?")
	# the lurker shows itself: the creatures the players don't know numbered afresh
	welcomes = ben.count("welcome")
	kernel.commit([{"t": "token.set", "scene": sid, "id": "t_lurk", "changes": {"hidden": false}}], "Show the lurker")
	check(_pump(host, all, func() -> bool: return ben.count("welcome") > welcomes), "Ben's document again")
	check(str(_doc_tok(ben.last("welcome").encounter, "t_gob2").label) == "1" and str(_doc_tok(ben.last("welcome").encounter, "t_lurk").label) == "2", "the boss 1, the lurker 2")
	host.stop()


## Conditions kept: what is on a creature no player owns isn't in a
## player's view of it, nor its tokens' tags that say it; its health still
## follows its health. Shown: everything.
func test_conditions_kept_from_players() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _chapel_state()
	var sid := st.encounter.active_scene_id
	var k := RulesKernel.new(st)
	var plugins := PluginHost.new(k)
	check(_load(plugins, _rules("shown", "hidden", "marks")) == "", "conditions kept, names shown")
	_setup(k, sid)
	k.commit([{"t": "effect.apply", "effect": {"id": "e_dead", "on": "actor:a_gob2", "plugin": "t.known", "key": "dead", "label": "Dead", "stack": "none", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "actor.set", "id": "a_gob2", "changes": {"audience/visible": "all"}}], "the boss falls")
	var view := Views.project(k, plugins, ANA, Views.ROLE_PLAYER)
	check((view.actors.a_gob.effects as Array).is_empty(), "the goblin's Frightened isn't in Ana's view")
	check((view.actors.a_gob2.effects as Array).size() == 1 and str(view.actors.a_gob2.effects[0].key) == "dead", "the boss's death follows its health (marks): told")
	var snap := WebScene.build(st, sid, ANA, false, k.knowledge_policies())
	check(not (_tok(snap, "t_gob").tags as Array).has("frightened") and (_tok(snap, "t_gob").tags as Array).has("humanoid"), "its token: no frightened tag, its others kept: %s" % [_tok(snap, "t_gob").tags])
	check(str(_tok(snap, "t_gob").name) == "Goblin", "names shown: the Goblin")
	check(plugins.dispatch("t.known", "hit", {"gm": true}).status != PluginHost.PluginCall.ERROR, "the goblin hits")
	check(_note(Views.project(k, plugins, ANA, Views.ROLE_PLAYER), "hits") == "The Goblin hits Ana's fighter.", "the line: its name, not its Frightened")
	check(_load(plugins, _rules("shown", "shown", "marks")) == "", "conditions shown")
	view = Views.project(k, plugins, ANA, Views.ROLE_PLAYER)
	check((view.actors.a_gob.effects as Array).size() == 1, "shown: Ana's view has it")
	check((_tok(WebScene.build(st, sid, ANA, false, k.knowledge_policies()), "t_gob").tags as Array).has("frightened"), "and its tag")


## The DM's "Reveal its name" and "Reveal all" (the web DM screen's
## reveal_names): the creatures' actors' audience.name, one step of the
## Table's undo; told again, kept again. The party's and the unknown aren't.
func test_reveal_names_from_the_dm_screen() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var dir := "user://table_reveal_names_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var app := App.new("user://test_prefs_reveal_names.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	win.ctx.plugin_dirs = ["res://tests/plugins"]
	var c := Campaign.create("Names")
	c.players.append({"id": "pl_1", "name": "Ana", "color": "#4f9cf6"})
	c.actors["a_h"] = {"id": "a_h", "kind": "pc", "name": "Hero", "owner": "pl_1", "ext": {"sample.ordered": {"level": 2, "stats": {"agi": 2, "str": 1, "wit": 0}}}}
	c.plugins.append({"id": "sample.ordered"})
	check(c.save(dir.path_join("names.campaign")) == OK, "saved")
	win._open_path(dir.path_join("names.campaign"))
	await tree.process_frame
	var ctx := win.ctx
	check(ctx.commands.run_all([{"t": "actor.add", "actor": {"id": "a_gob", "kind": "npc", "name": "Goblin"}},
		{"t": "actor.add", "actor": {"id": "a_boss", "kind": "npc", "name": "Goblin Boss"}}], "Goblins") == "", "two goblins")
	check(win.web_dm.op({"op": "reveal_names", "actors": ["a_gob"]}) == "", "Reveal its name")
	check(str(ctx.encounter().actor("a_gob").get("audience", {}).get("name", "")) == "all", "the goblin's name is the players' now")
	check(not ctx.encounter().actor("a_boss").get("audience", {}).has("name"), "the boss's isn't")
	check(win.web_dm.op({"op": "reveal_names", "actors": ["a_gob", "a_boss", "a_h"]}) == "", "Reveal all (the party's passed by)")
	check(str(ctx.encounter().actor("a_boss").audience.name) == "all" and not (ctx.encounter().actor("a_h").get("audience", {}) as Dictionary).has("name"), "the boss's too; the hero's untouched")
	check(win.web_dm.op({"op": "reveal_names", "actors": ["a_boss"], "known": false}) == "", "kept from the players again")
	check(not ctx.encounter().actor("a_boss").get("audience", {}).has("name"), "the boss's name is the DM's again")
	check(win.web_dm.op({"op": "reveal_names", "actors": []}) != "", "whose name?")
	win.queue_free()
	await tree.process_frame


func _pump(host: HostSession, clients: Array, done: Callable, max_ms := 3000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		host.poll(0.016)
		for c in clients:
			(c as Web.WebClient).poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false
