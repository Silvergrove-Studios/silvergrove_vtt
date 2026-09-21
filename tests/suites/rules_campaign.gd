extends TestCase
## Phase 7: the campaign document and sessions, checkpoints in the
## document, the recap, prep triggers, bulk operations, improvisation,
## the rulings journal, plugin layering and the co-GM role.


func _chapel_kernel() -> Array:
	var m := _chapel()
	var st := EncounterState.new(Encounter.create("Campaign test"))
	st.encounter.doc.rng = {"seed": 91, "index": 0}
	st.encounter.doc.meta.created = "2026-09-21T00:00:00"
	st.attach_map(m)
	var k := RulesKernel.new(st)
	var rules := SampleRules.new()
	rules.install(k)
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	var g := m.grid
	k.commit([{"t": "scene.add", "scene": sc},
		{"t": "player.add", "player": {"id": "pl_1", "name": "Ana", "color": "#4f9cf6"}},
		{"t": "actor.add", "actor": {"id": "a_h", "kind": "pc", "name": "Hero", "owner": "pl_1", "ext": {"sample": {"level": 1, "stats": {"agi": 2, "str": 1, "wit": 0}}}}},
		{"t": "actor.add", "actor": {"id": "a_g", "kind": "npc", "name": "Goblin", "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Hero", g.cell_center(g.offset_to_axial(3, 7)), {"id": "t_h", "actor": "a_h", "owner": "pl_1", "vision": {"radius": 6}})},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Goblin", g.cell_center(g.offset_to_axial(9, 7)), {"id": "t_g", "actor": "a_g"})},
		Resources.set_event("actor:a_h", "sample", "hp", Resources.pool(10, 10, "rest")),
		Resources.set_event("actor:a_g", "sample", "hp", Resources.pool(6, 6, "rest"))], "Setup")
	return [k, str(sc.id), rules]


# ------------------------------------------------------------ checkpoints --

func test_checkpoints_in_the_document() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var st := k.state
	var start := JsonDoc.sans_modified(st.encounter.to_json())
	var start_seq := k.log.seq
	var cp := k.checkpoint("Before the fight")
	check(cp != "" and st.encounter.checkpoints.size() == 1 and st.encounter.checkpoint(cp).name == "Before the fight", "a checkpoint is a record in the document")
	check(st.encounter.checkpoint(cp).snapshot.actors.has("a_h") and not st.encounter.checkpoint(cp).snapshot.has("checkpoints"), "its snapshot is the document without the checkpoints")
	# things happen
	check(k.commit([Resources.spend(st, "actor:a_h", "sample", "hp", 7), {"t": "actor.remove", "id": "a_g"}, {"t": "token.remove", "scene": parts[1], "id": "t_g"},
		{"t": "log.add", "entry": {"id": "n_1", "kind": "note", "text": "ouch", "audience": "all"}}], "Fight") == "", "the fight")
	check(Resources.get_record(st, "actor:a_h", "sample", "hp").current == 3 and not st.encounter.actors.has("a_g"), "hurt, goblin gone")
	var mid := JsonDoc.sans_modified(st.encounter.to_json())
	# the diff says what happened since
	var d := Recap.diff(st.encounter.checkpoint(cp).snapshot, st.encounter.snapshot())
	check(d.actors_removed == ["Goblin"] and d.resources.size() == 1 and d.resources[0].from == 10.0 and d.resources[0].to == 3.0 and d.tokens_removed.size() == 1, "the diff against the checkpoint: %s" % [d])
	# restore: one undoable step, derived rebuilt, the checkpoint kept
	check(k.restore_checkpoint(cp) == "", "restore")
	check(Resources.get_record(st, "actor:a_h", "sample", "hp").current == 10 and st.encounter.actors.has("a_g") and not st.token(parts[1], "t_g").is_empty() and st.encounter.log.is_empty(), "the document is back")
	check(st.encounter.checkpoints.size() == 1 and st.encounter.actor("a_g").derived.sample.defence.total == 11, "the checkpoint list survives a restore and derived is current")
	check(k.log.undo_label().begins_with("Restore"), "as one undo step")
	k.log.undo()
	check(JsonDoc.sans_modified(st.encounter.to_json()) == mid, "undoing the restore brings the fight back, byte for byte")
	k.log.redo()
	check(Resources.get_record(st, "actor:a_h", "sample", "hp").current == 10, "redo restores again")
	# a checkpoint after a reload, from the saved file
	var reloaded := EncounterState.new(Encounter.from_json(st.encounter.to_json()))
	var k2 := RulesKernel.new(reloaded)
	SampleRules.new().install(k2)
	check(k2.commit([Resources.spend(reloaded, "actor:a_h", "sample", "hp", 5)], "Hurt again") == "" and k2.restore_checkpoint(cp) == "", "a restore works from the file alone")
	check(Resources.get_record(reloaded, "actor:a_h", "sample", "hp").current == 10, "…and is exact")
	check(k.drop_checkpoint(cp) == "" and st.encounter.checkpoints.is_empty(), "dropped")
	k.log.undo()
	check(st.encounter.checkpoints.size() == 1 and st.encounter.checkpoint(cp).snapshot.actors.has("a_g"), "undoing a drop brings the checkpoint back with its snapshot")
	# replay reproduces the document, checkpoints included
	var fresh := EncounterState.new(Encounter.from_json(JsonDoc.stringify(JsonDoc.parse(start.replace('"modified": ""', '"modified": "x"')))))
	var fk := RulesKernel.new(fresh)
	SampleRules.new().install(fk)
	var rw := EventLog.replay(fresh, k.log.since(start_seq - 1))
	check(rw == "", "the log replays: " + rw)
	fk.rederive_all()
	check(JsonDoc.sans_modified(fresh.encounter.to_json()) == JsonDoc.sans_modified(st.encounter.to_json()), "replay reproduces the document with its checkpoints")
	check(st.validate({"t": "checkpoint.restore", "id": "nope"}) != "" and st.validate({"t": "encounter.set", "changes": {"checkpoints": []}}) != "", "bad checkpoint events are refused")


# --------------------------------------------------------------- campaign --

func test_campaign_two_sessions_with_a_recap() -> void:
	var dir := "user://campaign_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var c := Campaign.create("The Sunken Reach")
	c.players.append({"id": "pl_1", "name": "Ana", "color": "#4f9cf6"})
	c.players.append({"id": "pl_2", "name": "Ben", "color": "#f6a54f"})
	c.actors["a_h"] = {"id": "a_h", "kind": "pc", "name": "Hero", "owner": "pl_1", "ext": {"sample": {"level": 1, "stats": {"agi": 2, "str": 1, "wit": 0}}}}
	c.tracks["k_doom"] = Tracks.make("sample", "Doom", 6, "countdown", {"on": "session", "amount": 1}, "gm")
	c.tracks["k_doom"].id = "k_doom"
	c.doc.state.ext = {"sample": {"luck": 1}}
	c.resources["actor:a_h"] = {"sample": {"hp": Resources.pool(10, 10, "rest")}}
	c.plugins.append({"id": "sample", "version": "0.1.0", "settings": {"critical_on": 19}})
	check(c.save(dir.path_join("reach.campaign")) == OK, "saved")
	var loaded := Campaign.load_file(dir.path_join("reach.campaign"))
	check(loaded != null and loaded.name == "The Sunken Reach" and loaded.players.size() == 2 and loaded.actors.has("a_h") and loaded.plugin_order() == ["sample"] and loaded.plugin_settings("sample").critical_on == 19, "loads back")
	check(JsonDoc.sans_modified(Campaign.from_json(loaded.to_json()).to_json()) == JsonDoc.sans_modified(loaded.to_json()), "byte for byte")
	# session one: a fresh encounter takes the campaign in
	var m := _chapel()
	var e := Encounter.create("Session one")
	e.doc.rng = {"seed": 5, "index": 0}
	var st := EncounterState.new(e)
	st.attach_map(m)
	var k := RulesKernel.new(st)
	SampleRules.new().install(k)
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	k.commit([{"t": "scene.add", "scene": sc}], "Scene")
	var hooked := []
	k.hooks.on("session_start", func(p: Dictionary) -> Variant:
		hooked.append(int(p.session))
		p.events.append({"t": "ext.set", "scope": "campaign", "plugin": "sample", "changes": {"luck": int(st.encounter.campaign.ext.get("sample", {}).get("luck", 0)) + 1}})
		return p, "test")
	check(k.start_session(loaded, "reach.campaign") == "", "session one starts")
	check(e.players.size() == 2 and e.actors.has("a_h") and e.tracks.has("k_doom") and e.tracks.k_doom.campaign == true and Resources.get_record(st, "actor:a_h", "sample", "hp").max == 10, "players, actors, resources and tracks came in")
	check(e.clock.session == 1 and e.campaign.id == loaded.id and e.campaign.path == "reach.campaign", "the clock and the campaign reference are set")
	check(hooked == [1] and e.campaign.ext.sample.luck == 2, "the session_start hook ran and changed campaign-scoped state")
	check(e.checkpoints.size() == 1 and e.checkpoints[0].name == "Session 1 start", "the session start is a checkpoint")
	check(e.actor("a_h").derived.sample.defence.total == 12, "the campaign's actor derives under the rules")
	# play: a goblin, a fight, a ruling, a handout, a note for the journal
	var g := m.grid
	k.commit([{"t": "actor.add", "actor": {"id": "a_g", "kind": "npc", "name": "Goblin", "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Hero", g.cell_center(g.offset_to_axial(3, 7)), {"id": "t_h", "actor": "a_h", "owner": "pl_1"})},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Goblin", g.cell_center(g.offset_to_axial(9, 7)), {"id": "t_g", "actor": "a_g"})},
		Resources.set_event("actor:a_g", "sample", "hp", Resources.pool(6, 6, "rest"))], "Goblin")
	var r := k.roll("1d20", {"actor": "a_h", "kind": "attack", "dc": 11}, "Strike")
	check(not r.is_empty(), "a roll")
	k.commit([Resources.spend(st, "actor:a_h", "sample", "hp", 4), {"t": "actor.remove", "id": "a_g"}, {"t": "token.remove", "scene": sc.id, "id": "t_g"},
		{"t": "log.add", "entry": {"id": "j_1", "kind": "ruling", "text": "A table gives partial cover", "rule": "cover", "tags": ["cover"], "audience": "gm"}},
		{"t": "log.add", "entry": {"id": "h_1", "kind": "handout", "title": "The stone", "text": "Runes glow faintly.", "audience": "all"}},
		{"t": "log.add", "entry": {"id": "n_1", "kind": "note", "text": "Ben owes Ana a favour", "audience": "all", "journal": true}},
		{"t": "log.add", "entry": {"id": "n_2", "kind": "note", "text": "not for the journal", "audience": "gm"}},
		{"t": "actor.add", "actor": {"id": "a_dog", "kind": "companion", "name": "Dog", "owner": "pl_2", "ext": {"sample": {"level": 1, "stats": {"agi": 3, "str": 0, "wit": 0}}}}},
		{"t": "clock.set", "changes": {"day": 3, "minute": 600}}], "The fight")
	# the recap
	var md := Recap.markdown(e, "gm")
	check(md.begins_with("# Session one — session 1") and md.contains("**Ana** — Hero") and md.contains("Hero: hp 10 → 6") and not md.contains("actor:a_g") and md.contains("Runes glow faintly") and md.contains("## Rulings") and md.contains("partial cover") and md.contains("## Dice") and md.contains("Dog joined"), "the GM recap has it all:\n" + md)
	var pmd := Recap.markdown(e, "all")
	check(not pmd.contains("Rulings") and not pmd.contains("not for the journal") and pmd.contains("Runes glow faintly") and pmd.contains("Ben owes Ana"), "the players' recap leaves GM matter out")
	var summ := Recap.summary(e)
	check(summ.rolls.has("Hero") and summ.rolls.Hero.count == 1 and summ.changes.clock.has("day"), "the summary is structured data")
	# banking the session into the campaign
	check(e.save(dir.path_join("one.encounter")) == OK, "the session is saved")
	var banked := loaded.bank(e, "one.encounter")
	check(banked.actors == 2 and banked.journal == 3 and banked.tracks == 1 and banked.players == 0, "banked: %s" % [banked])
	check(loaded.actors.has("a_dog") and not loaded.actors.has("a_g") and not loaded.actors.a_h.has("derived"), "the companion came along, the goblin did not, derived is left behind")
	check(loaded.clock.session == 1 and loaded.clock.day == 3 and loaded.clock.minute == 600 and loaded.doc.state.ext.sample.luck == 2 and loaded.resources["actor:a_h"].sample.hp.current == 6, "the clock, campaign state and the hero's pool carried")
	check(loaded.journal.size() == 3 and loaded.journal[0].session == 1 and loaded.search_journal("cover").size() == 1 and loaded.search_journal("favour").size() == 1 and loaded.search_journal("nothing here").is_empty(), "the journal has the ruling, the handout and the marked note, searchable")
	check(loaded.encounters == ["one.encounter"], "the session is listed")
	check(loaded.save() == OK, "campaign saved again")
	# session two: a new encounter, the luck and the dog come back, the recap of the second session stands alone
	var again := Campaign.load_file(dir.path_join("reach.campaign"))
	var e2 := Encounter.create("Session two")
	e2.doc.rng = {"seed": 6, "index": 0}
	var st2 := EncounterState.new(e2)
	st2.attach_map(m)
	var k2 := RulesKernel.new(st2)
	SampleRules.new().install(k2)
	k2.commit([{"t": "scene.add", "scene": Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")}], "Scene")
	check(k2.start_session(again, "reach.campaign") == "", "session two starts")
	check(e2.clock.session == 2 and e2.clock.day == 3 and e2.actors.has("a_dog") and e2.campaign.ext.sample.luck == 2 and e2.tracks.k_doom.value == 4 and Resources.get_record(st2, "actor:a_h", "sample", "hp").current == 6, "session two picks up where one left off (doom ticked twice: once per session; the hero still hurt)")
	check(e2.actor("a_h").derived.sample.defence.total == 12, "derived again in the new session")
	check(Recap.markdown(e2).contains("session 2"), "a recap for session two")
	e2.path = dir.path_join("two.encounter")
	check(Campaign.for_encounter(e2) != null and Campaign.for_encounter(e2).id == again.id, "an encounter finds its campaign beside it")
	# an encounter file round-trips its campaign block
	var back := Encounter.from_json(e2.to_json())
	check(back.campaign.ext.sample.luck == 2 and back.checkpoints.size() == 1, "campaign state and checkpoints are in the file")
	for f in ["reach.campaign", "one.encounter"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# --------------------------------------------------------------- triggers --

func test_prep_triggers() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var m := st.map_for(sid)
	var g := m.grid
	var door := {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	# validation
	check(st.validate({"t": "scene.set", "id": sid, "changes": {"triggers": [{"id": "x", "on": "sometime", "do": []}]}}) != "" and st.validate({"t": "scene.set", "id": sid, "changes": {"triggers": [{"id": "x", "on": "manual", "do": [{"text": "no kind"}]}]}}) != "", "malformed triggers are refused")
	# a region with an enter trigger: read-aloud, a light on, a countdown
	var zone := MapQuery.region("r_altar", HexGrid.spiral(g.offset_to_axial(9, 7), 1), ["altar"], {"label": "Altar"})
	var light_id := str(m.level_by_id("ground").lights[0].id) if not m.level_by_id("ground").lights.is_empty() else ""
	var steps := [
		{"kind": "read", "title": "The altar", "text": "Something stirs.", "audience": "all"},
		{"kind": "track", "name": "Awakening", "max": 3, "plugin": "sample", "audience": "gm"},
		{"kind": "note", "text": "the altar woke", "audience": "gm"}]
	if light_id != "":
		steps.append({"kind": "light", "ref": "lights:" + light_id, "on": false})
	zone.triggers = [Triggers.make("enter", steps, {"id": "tr_altar", "label": "Altar wakes"})]
	check(k.commit([{"t": "region.add", "scene": sid, "region": zone}], "Zone") == "", "a region with a trigger")
	var fired := []
	k.trigger_failed.connect(func(id: String, why: String) -> void: fired.append(id + ": " + why))
	# the hero walks in
	var here := g.cell_center(g.offset_to_axial(8, 7))
	check(k.move_token(sid, "t_h", here) == "", "the hero moves next to the altar")
	var handouts := st.encounter.log.filter(func(x: Dictionary) -> bool: return x.kind == "handout")
	check(handouts.size() == 1 and handouts[0].title == "The altar" and st.encounter.tracks.size() == 1 and st.encounter.log.any(func(x: Dictionary) -> bool: return x.kind == "note" and x.text == "the altar woke"), "the trigger fired: handout, track, note")
	if light_id != "":
		check(st.effective_level(sid).lights.any(func(l: Dictionary) -> bool: return str(l.id) == light_id and l.get("on", true) == false), "the light went out")
	check(st.encounter.scene(sid).regions.r_altar.triggers[0].fired == true and fired.is_empty(), "marked fired")
	check(k.log.undo_label().begins_with("Trigger"), "the trigger is its own undo step after the move")
	k.move_token(sid, "t_h", g.cell_center(g.offset_to_axial(3, 7)))
	k.move_token(sid, "t_h", here)
	check(st.encounter.log.filter(func(x: Dictionary) -> bool: return x.kind == "handout").size() == 1, "once means once")
	# undo the trigger and the move: the region's fired flag returns
	k.log.undo()
	k.log.undo()
	k.log.undo()
	k.log.undo()
	check(st.encounter.log.filter(func(x: Dictionary) -> bool: return x.kind == "handout").is_empty() and st.encounter.scene(sid).regions.r_altar.triggers[0].fired == false, "undone back to before the first entry")
	# a door trigger and a reveal trigger on the scene, plus a manual one
	var spawn_at := g.offset_to_axial(6, 5)
	check(k.commit([{"t": "scene.set", "id": sid, "changes": {"triggers": [
		Triggers.make("door", [{"kind": "spawn", "tokens": [{"name": "Ghoul", "at": HexMap.cell_key(spawn_at), "actor": {"kind": "npc", "name": "Ghoul", "ext": {"sample": {"level": 2, "stats": {"agi": 0, "str": 2, "wit": 0}}}}}]}], {"id": "tr_door", "ref": "walls:" + str(door.id), "state": "open"}),
		Triggers.make("reveal", [{"kind": "effect", "effect": {"on": "actor:a_h", "plugin": "sample", "key": "shaken", "label": "Shaken", "changes": [{"path": "defence", "mode": "add", "value": -2, "type": "status"}]}}], {"id": "tr_reveal", "cells": [HexMap.cell_key(g.offset_to_axial(5, 5))]}),
		Triggers.make("manual", [{"kind": "event", "ev": {"t": "clock.set", "changes": {"minute": 30}}}], {"id": "tr_manual", "once": false}),
		Triggers.make("scene", [{"kind": "reveal", "cells": [HexMap.cell_key(g.offset_to_axial(4, 4)), HexMap.cell_key(g.offset_to_axial(4, 5))]}], {"id": "tr_scene"})]}}], "Prep") == "", "scene triggers laid down")
	check(k.commit([{"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}}], "Open") == "", "the door opens")
	var ghoul := st.tokens(sid).filter(func(t: Dictionary) -> bool: return t.name == "Ghoul")
	check(ghoul.size() == 1 and st.encounter.actors.has(str(ghoul[0].actor)) and st.encounter.actor(str(ghoul[0].actor)).derived.sample.defence.total == 10, "the door spawned a ghoul with an actor, derived")
	check(k.commit([{"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "closed"}}, {"t": "element.set", "scene": sid, "ref": "walls:" + str(door.id), "changes": {"state": "open"}}], "Again") == "" and st.tokens(sid).filter(func(t: Dictionary) -> bool: return t.name == "Ghoul").size() == 1, "opening it again spawns nothing more")
	k.commit([{"t": "fog.set", "scene": sid, "enabled": true}, {"t": "fog.reveal", "scene": sid, "cells": [HexMap.cell_key(g.offset_to_axial(5, 5))]}], "Reveal")
	check(Effects.on(st, "actor:a_h").size() == 1 and st.encounter.actor("a_h").derived.sample.defence.total == 10, "revealing the cell shook the hero")
	check(k.fire_trigger(sid, "tr_manual") == "" and st.encounter.clock.minute == 30 and k.fire_trigger(sid, "tr_manual") == "", "a manual trigger fires on demand, again and again")
	check(k.fire_trigger(sid, "nope") != "", "an unknown trigger is refused")
	var sc2 := Encounter.new_scene(m, "ground", "Elsewhere", "ruined_chapel.hexmap")
	k.commit([{"t": "scene.add", "scene": sc2}, {"t": "scene.activate", "id": sc2.id}], "Elsewhere")
	check(k.commit([{"t": "scene.activate", "id": sid}], "Back") == "" and st.explored(sid).has(HexMap.cell_key(g.offset_to_axial(4, 4))), "showing the scene to the players revealed its cells")
	# a trigger whose step fails undoes the whole trigger
	var all: Array = JsonDoc.deep(st.encounter.scene(sid).triggers)
	all.append(Triggers.make("manual", [{"kind": "note", "text": "half"}, {"kind": "event", "ev": {"t": "actor.remove", "id": "nobody"}}], {"id": "tr_bad"}))
	k.commit([{"t": "scene.set", "id": sid, "changes": {"triggers": all}}], "Bad")
	var notes := st.encounter.log.filter(func(x: Dictionary) -> bool: return x.kind == "note").size()
	check(k.fire_trigger(sid, "tr_bad") != "" and st.encounter.log.filter(func(x: Dictionary) -> bool: return x.kind == "note").size() == notes and st.encounter.scene(sid).triggers[4].fired == false, "a failing step leaves nothing behind")


# ------------------------------------------------------------------- bulk --

func test_bulk_operations() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var g := st.map_for(sid).grid
	var events := []
	for i in 4:
		events.append({"t": "actor.add", "actor": {"id": "a_%d" % i, "kind": "npc", "name": "Rat %d" % i, "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}})
		events.append({"t": "token.add", "scene": sid, "token": Encounter.new_token("Rat %d" % i, g.cell_center(g.offset_to_axial(9 + i % 2, 6 + i / 2)), {"id": "t_%d" % i, "actor": "a_%d" % i})})
		events.append(Resources.set_event("actor:a_%d" % i, "sample", "hp", Resources.pool(5, 5, "rest")))
	k.commit(events, "Rats")
	var rats := Bulk.refs_for_tokens(["t_0", "t_1", "t_2", "t_3"])
	var depth := k.log.undo_depth()
	# a condition on all of them
	var r := Bulk.run(k, rats, {"kind": "effect", "effect": {"plugin": "sample", "key": "shaken", "label": "Shaken", "changes": [{"path": "defence", "mode": "add", "value": -2, "type": "status"}]}}, "Shake")
	check(r.ok and st.encounter.effects.size() == 4 and st.encounter.actor("a_2").derived.sample.defence.total == 9, "an effect on every rat, derived: %s" % r.why)
	check(k.log.undo_depth() == depth + 1 and k.log.undo_label() == "Shake", "one undo step")
	# damage to all: a pool floor at zero
	r = Bulk.run(k, rats, {"kind": "resource", "plugin": "sample", "name": "hp", "delta": -3})
	check(r.ok and Resources.get_record(st, "actor:a_0", "sample", "hp").current == 2, "3 damage each")
	r = Bulk.run(k, rats, {"kind": "resource", "plugin": "sample", "name": "hp", "delta": -3})
	check(r.ok and Resources.get_record(st, "actor:a_0", "sample", "hp").current == 0, "overkill floors at zero")
	r = Bulk.run(k, rats, {"kind": "resource", "plugin": "sample", "name": "hp", "delta": 5})
	check(r.ok and Resources.get_record(st, "actor:a_0", "sample", "hp").current == 5, "healed to full, capped")
	# a save for the group, applied per outcome, one step
	depth = k.log.undo_depth()
	r = Bulk.run(k, rats, {"kind": "roll", "spec": "1d20", "ctx": {"kind": "save", "dc": 11}, "label": "Save",
		"per": {"failure": [{"kind": "resource", "plugin": "sample", "name": "hp", "delta": -4}], "success": [{"kind": "resource", "plugin": "sample", "name": "hp", "delta": -2}], "critical": []}}, "Fireball")
	check(r.ok and r.results.size() == 4 and st.encounter.log.filter(func(x: Dictionary) -> bool: return x.kind == "roll").size() == 4, "four saves rolled")
	var consistent := true
	for res in r.results:
		var hp: float = Resources.get_record(st, str(res.ref).replace("token:t_", "actor:a_"), "sample", "hp").current
		var want := 1.0 if res.outcome == "failure" else (3.0 if res.outcome == "success" else 5.0)
		if hp != want:
			consistent = false
	check(consistent and k.log.undo_depth() == depth + 1, "each took what its outcome said, in one step: %s" % [r.results.map(func(x: Dictionary) -> String: return str(x.outcome))])
	k.log.undo()
	check(st.encounter.log.filter(func(x: Dictionary) -> bool: return x.kind == "roll").is_empty() and Resources.get_record(st, "actor:a_0", "sample", "hp").current == 5, "undone as one")
	# the horde moves together, through the kernel's move (hooks and regions)
	var before := Vision.token_pos(st.token(sid, "t_0"))
	r = Bulk.run(k, rats, {"kind": "move", "delta": [-1.0, 0.0]})
	check(r.ok and Vision.token_pos(st.token(sid, "t_0")) == before + Vector2(-1, 0), "moved as one")
	# a refusal undoes everything
	r = Bulk.run(k, rats + ["token:t_missing"], {"kind": "remove"})
	check(not r.ok and st.tokens(sid).size() == 6, "a bad target refuses the whole batch and nothing was removed: " + r.why)
	r = Bulk.run(k, rats, {"kind": "each", "ops": [{"kind": "set", "changes": {"hidden": true}}, {"kind": "remove"}]})
	check(r.ok and st.tokens(sid).size() == 2, "several ops per target; the rats are gone")
	check(not Bulk.run(k, rats, {"kind": "nonsense"}).ok, "an unknown op is refused")


# ----------------------------------------------------------------- improv --

func test_improvisation_without_plugins() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	check(Improv.generate_name(42) == Improv.generate_name(42) and Improv.generate_name(42) != Improv.generate_name(43) and Improv.generate_name(42).length() >= 2, "names are deterministic per seed: %s, %s" % [Improv.generate_name(42), Improv.generate_name(43)])
	var r := Improv.quick(k, "", {"hp": 12, "ac": 15}, sid, Vector2(4, 4), {"color": "#123456"})
	check(not r.has("error") and st.encounter.actors.has(r.actor) and not st.token(sid, r.token).is_empty(), "a number-only token with an actor behind it")
	var a := st.encounter.actor(r.actor)
	check(a.name != "" and a.ext.table.numbers.hp == 12 and Resources.get_record(st, "actor:" + r.actor, "table", "hp").max == 12, "its numbers are pools under the table pseudo-plugin")
	check(k.log.undo_label().begins_with("Improvise"), "one step")
	check(Bulk.run(k, ["token:" + r.token], {"kind": "resource", "plugin": "table", "name": "hp", "delta": -5}).ok and Resources.get_record(st, "actor:" + r.actor, "table", "hp").current == 7, "so bulk damage works on it")
	check(Improv.spawn(k, "sample", "x", {}, sid, Vector2.ZERO).has("error"), "no plugins: spawn says so")
	check(Improv.quick(k, "x", {"hp": 1}, "nope", Vector2.ZERO).has("error"), "no scene: refused")


# ---------------------------------------------------------- co-GM (wire) --

func _pump(host: HostSession, clients: Array, done: Callable, max_ms := 4000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		host.poll(0.016)
		for c in clients:
			(c as NetSession).poll()
		if done.call():
			return true
		OS.delay_msec(5)
	return false


func test_cogm_role() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var g := st.map_for(sid).grid
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_gm", [g.offset_to_axial(1, 1)], ["secret"], {"audience": "gm"})},
		{"t": "scene.set", "id": sid, "changes": {"triggers": [Triggers.make("manual", [{"kind": "note", "text": "fired by the co-GM", "audience": "gm"}], {"id": "tr_1"})]}}], "GM things")
	var packs := PackLibrary.new()
	packs.reload()
	var host := HostSession.new(st, packs)
	host.kernel = k
	var cmds := EncounterCommands.new(st, k.log)
	cmds.kernel = k
	host.apply_request = func(ev: Dictionary, pid: String) -> String: return cmds.run(ev, "request by " + (pid if pid != "" else "co-GM"))
	check(host.start(0, false) == OK, "hosting")
	check(host.cogm_code.length() == 4, "a code for co-GMs: " + host.cogm_code)
	var cpacks := PackLibrary.new()
	cpacks.reload()
	var c := NetSession.new("127.0.0.1", host.port, cpacks, "second screen")
	c.cache_dir = "user://packs_test_cogm"
	var told := []
	c.status.connect(func(t: String) -> void: told.append(t))
	c.connect_to_host()
	check(_pump(host, [c], func() -> bool: return c.state != null), "welcomed as anyone")
	check(not c.state.encounter.scene(sid).regions.has("r_gm") and not c.state.encounter.scene(sid).has("triggers"), "…without GM regions or triggers")
	c.join("", "cogm", "0000" if host.cogm_code != "0000" else "0001")
	check(_pump(host, [c], func() -> bool: return told.any(func(t: String) -> bool: return t.contains("code"))), "the wrong code is refused")
	c.join("", "cogm", host.cogm_code)
	check(_pump(host, [c], func() -> bool: return c.joined and c.is_gm() and not c.view.is_empty()), "joined as co-GM with the code")
	check(host.cogm_count() == 1 and host.connected_players().is_empty(), "the host counts a co-GM, not a player")
	check(c.state.encounter.scene(sid).regions.has("r_gm") and c.state.encounter.scene(sid).triggers.size() == 1, "the co-GM holds the whole scene")
	check(c.view.role == "gm" and c.view.actors.has("a_g") and c.view.actors.a_g.ext.has("sample"), "and the GM projection: every actor, every field")
	# a move of a token no player owns, a GM verb, an action for any actor
	var to := g.cell_center(g.offset_to_axial(8, 7))
	check(c.request({"t": "token.set", "scene": sid, "id": "t_g", "changes": {"pos": [to.x, to.y]}}) == "", "may ask to move the goblin")
	check(_pump(host, [c], func() -> bool: return Vision.token_pos(st.token(sid, "t_g")) == to), "the goblin moved on the table, through the table's commands")
	check(k.log.undo_label().contains("co-GM"), "undoably, named")
	c.intent({"kind": "gm", "op": "trigger", "scene": sid, "trigger": "tr_1"})
	check(_pump(host, [c], func() -> bool: return st.encounter.log.any(func(x: Dictionary) -> bool: return x.get("text", "") == "fired by the co-GM")), "a co-GM fires a trigger")
	c.intent({"kind": "gm", "op": "checkpoint", "name": "By the co-GM"})
	check(_pump(host, [c], func() -> bool: return st.encounter.checkpoints.size() == 1), "and marks a checkpoint")
	c.intent({"kind": "gm", "op": "bulk", "targets": ["token:t_g"], "op_spec": {"kind": "resource", "plugin": "sample", "name": "hp", "delta": -2}})
	check(_pump(host, [c], func() -> bool: return Resources.get_record(st, "actor:a_g", "sample", "hp").current == 4), "and runs a bulk op")
	# a restore re-welcomes everyone with the restored document
	c.intent({"kind": "gm", "op": "restore", "id": str(st.encounter.checkpoints[0].id)})
	check(_pump(host, [c], func() -> bool: return Resources.get_record(st, "actor:a_g", "sample", "hp").current == 6 and c.state.encounter.scene(sid).regions.has("r_gm")), "restored on the table and the client re-welcomed")
	check(JsonDoc.sans_modified(c.state.encounter.to_json()) == JsonDoc.sans_modified(JsonDoc.stringify(Protocol.client_document(st.encounter.doc, true))), "the co-GM's document matches the table's, GM view")
	# a player client gets none of the GM verbs
	var p := NetSession.new("127.0.0.1", host.port, cpacks, "phone")
	p.cache_dir = "user://packs_test_cogm"
	var ptold := []
	p.status.connect(func(t: String) -> void: ptold.append(t))
	p.connect_to_host()
	check(_pump(host, [c, p], func() -> bool: return p.state != null), "a player connects")
	p.join("pl_1")
	check(_pump(host, [c, p], func() -> bool: return p.joined), "joins")
	p.intent({"kind": "gm", "op": "checkpoint", "name": "sneaky"})
	check(_pump(host, [c, p], func() -> bool: return ptold.any(func(t: String) -> bool: return t.contains("only the GM"))), "a player is refused the GM verbs")
	check(not p.state.encounter.scene(sid).regions.has("r_gm"), "and never sees the GM region")
	host.stop()


# -------------------------------------------------------- plugin layering --

func test_plugin_layering_and_campaign_order() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := EncounterState.new(Encounter.create("Layers"))
	st.encounter.doc.rng = {"seed": 3, "index": 0}
	var k := RulesKernel.new(st)
	var host := PluginHost.new(k)
	# the house rules alone: refused, they need their base
	check(host.load_dir("res://tests/plugins/sample.house").contains("depends"), "a layered plugin needs its base loaded first")
	# a manifest that overrides without depending is refused
	check(host.load_source({"id": "t.over", "version": "1", "api": 1, "name": "x", "overrides": {"sample.ordered": ["after_roll"]}}, [["main.lua", ""]]).contains("without depending"), "overrides need a dependency")
	# load_all: dependencies first whatever the order asked, the campaign's order honoured
	host.settings_overrides = {"sample.house": {"critical_from": 18}, "sample.ordered": {"critical_on": 15}}
	var loaded := host.load_all(["res://tests/plugins"], ["sample.house", "sample.ordered"])
	var ids := loaded.map(func(x: Dictionary) -> String: return str(x.id))
	check(ids.find("sample.ordered") < ids.find("sample.house") and loaded.all(func(x: Dictionary) -> bool: return x.why == ""), "all four load, base before house: %s" % [loaded])
	check(k.ruleset_order("sample.ordered") < k.ruleset_order("sample.house") and k.ruleset_order("sample.house") < k.ruleset_order("sample.degrees"), "the campaign's plugins run first, in its order, the rest after")
	check(host.plugin("sample.house").settings.critical_from == 18 and host.plugin("sample.ordered").settings.critical_on == 15 and host.plugin("sample.ordered").settings.armour_reduces == 2, "campaign settings over the defaults")
	# the override: only the house after_roll runs
	check(k.hooks.handlers("after_roll").filter(func(h: Dictionary) -> bool: return h.owner == "sample.ordered").is_empty() and k.hooks.is_overridden("sample.ordered", "after_roll") and not k.hooks.is_overridden("sample.ordered", "before_roll"), "the base after_roll is overridden, its before_roll is not")
	# only the base and the house rules classify from here on
	host.unload("sample.degrees")
	host.unload("sample.focus")
	k.commit([{"t": "actor.add", "actor": {"id": "a_1", "kind": "pc", "name": "One", "ext": {"sample.ordered": {"level": 1, "stats": {"agi": 0, "str": 2, "wit": 0}}}}}], "Actor")
	var r := k.roll({"expr": "1d20", "faces": {"main": [18]}}, {"actor": "a_1", "kind": "attack", "dc": 10}, "Strike")
	check(not r.is_empty() and r.result.outcome == "critical" and r.result.get("house", false) == true and r.result.total == 20, "18 is a critical under the house setting, str +2 from the base's before_roll")
	r = k.roll({"expr": "1d20", "faces": {"main": [1]}}, {"actor": "a_1", "kind": "attack", "dc": 1}, "Strike")
	check(r.result.outcome == "fumble", "a fumble")
	# unloading the house rules lifts the override
	host.unload("sample.house")
	check(not k.hooks.is_overridden("sample.ordered", "after_roll"), "unload lifts the override")
	r = k.roll({"expr": "1d20", "faces": {"main": [18]}}, {"actor": "a_1", "kind": "attack", "dc": 10}, "Strike")
	check(r.result.outcome == "critical" and not r.result.has("house"), "the base classifies again, with the campaign's critical_on 15")


func test_every_reference_plugin_passes_its_own_tests() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := EncounterState.new(Encounter.create("All plugins"))
	var host := PluginHost.new(RulesKernel.new(st))
	var loaded := host.load_all(["res://tests/plugins"])
	check(loaded.size() == 4 and loaded.all(func(x: Dictionary) -> bool: return x.why == ""), "the reference plugins load together: %s" % [loaded])
	for entry in loaded:
		var r := host.run_tests(str(entry.id))
		say.call("  %s: %d checks, %d failed" % [str(entry.id), r.count, r.fails])
		check(r.count > 0 and r.fails == 0, "%s passes its own tests: %s" % [str(entry.id), r.failures])
	check(st.encounter.actors.is_empty() and st.encounter.checkpoints.is_empty(), "the real state is untouched")


# ------------------------------------------------------------------ table --

func test_table_campaign_panel_and_dialogs() -> void:
	var app := App.new("user://test_prefs_campaign.json")
	var table := TableWindow.new()
	table.app = app
	root.add_child(table)
	table.ctx.plugin_dirs = ["res://tests/plugins"]
	table._open_path(_example("chapel_ambush.encounter"))
	await tree.process_frame
	var panel := table.campaign_panel
	check(panel != null and panel._campaign.text.begins_with("No campaign"), "the Campaign pane says no campaign is open")
	# a campaign made from the table's players, a session started, banked
	var dir := "user://campaign_panel_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var c := Campaign.create("Panel test")
	for pl in table.ctx.encounter().players:
		c.players.append(JsonDoc.deep(pl))
	c.plugins.append({"id": "sample.house", "settings": {"critical_from": 17}})
	c.plugins.append({"id": "sample.ordered"})
	check(c.save(dir.path_join("panel.campaign")) == OK, "saved")
	table.ctx.campaign = Campaign.load_file(dir.path_join("panel.campaign"))
	panel.refresh()
	check(panel._campaign.text.begins_with("Panel test") and panel._campaign.text.contains("not started"), "the pane names the campaign and says no session has started")
	check(table.ctx.start_session() == "", "a session starts from the pane's verb")
	await tree.process_frame
	check(table.ctx.encounter().checkpoints.size() == 1 and panel._checkpoints.get_child_count() == 1, "the session start is a checkpoint in the list")
	# marks, rulings and the journal through the panel
	panel._checkpoint_name.text = "Before the ambush"
	panel._mark()
	await tree.process_frame
	check(table.ctx.encounter().checkpoints.size() == 2 and panel._checkpoints.get_child_count() == 2, "a checkpoint marked from the pane")
	panel._ruling.text = "Doors take an action to open"
	panel._rule.text = "movement"
	panel._add_ruling()
	await tree.process_frame
	check(table.ctx.encounter().log.any(func(x: Dictionary) -> bool: return x.kind == "ruling" and x.rule == "movement"), "a ruling recorded from the pane")
	panel._search.text = "doors"
	panel._refresh_journal()
	check(panel._journal.get_child_count() == 1 and (panel._journal.get_child(0) as Label).text.begins_with("Ruling"), "the journal search finds it")
	panel._search.text = "nothing like this"
	panel._refresh_journal()
	check(panel._journal.get_child_count() == 1 and (panel._journal.get_child(0) as Label).text == "No match.", "…and says when nothing matches")
	panel._search.text = ""
	# a manual trigger shows with a Fire button
	var sid := table.ctx.scene_id
	table.ctx.kernel.commit([{"t": "scene.set", "id": sid, "changes": {"triggers": [Triggers.make("manual", [{"kind": "note", "text": "the bell tolls", "audience": "gm"}], {"id": "tr_bell", "label": "The bell"})]}}], "Prep")
	await tree.process_frame
	check(panel._triggers.get_child_count() == 1 and (panel._triggers.get_child(0).get_child(0) as Label).text.begins_with("The bell"), "the pane lists the scene's prep")
	(panel._triggers.get_child(0).get_child(1) as Button).pressed.emit()
	check(table.ctx.encounter().log.any(func(x: Dictionary) -> bool: return x.get("text", "") == "the bell tolls"), "Fire runs it")
	# restore from the pane: the ruling and the bell are gone, the checkpoints stay
	var restore: Button = panel._checkpoints.get_child(1).get_child(1)
	restore.pressed.emit()
	await tree.process_frame
	check(not table.ctx.encounter().log.any(func(x: Dictionary) -> bool: return x.kind == "ruling") and table.ctx.encounter().checkpoints.size() == 2, "restored to before the ruling; the checkpoints remain")
	# bank: the campaign gained the session
	var r := table.ctx.bank_session()
	check(not r.has("error") and table.ctx.campaign.clock.session == 1 and table.ctx.campaign.encounters.size() == 1, "banked and saved: %s" % [r])
	# the campaign's plugin order and settings shape the plugins on reload
	table._set_encounter(table.ctx.encounter())
	check(table.ctx.host != null and table.ctx.host.plugin("sample.house") != null and table.ctx.host.plugin("sample.house").settings.critical_from == 17, "the campaign's settings reached the plugin")
	check(table.ctx.kernel.ruleset_order("sample.ordered") < table.ctx.kernel.ruleset_order("sample.house") and table.ctx.kernel.ruleset_order("sample.house") < table.ctx.kernel.ruleset_order("sample.focus"), "the campaign's plugins come first, base before house")
	# the players pane shows the co-GM code while hosting
	table._set_hosting(true)
	check(table.players._cogm.visible and table.players._cogm.text.contains(table.host.cogm_code), "the Players pane shows the co-GM code")
	table._set_hosting(false)
	check(not table.players._cogm.visible, "…only while hosting")
	# the recap of what happened
	var md := Recap.markdown(table.ctx.encounter(), "gm")
	check(md.contains("session 1") and md.contains("## Who was there"), "a recap comes out of the table's encounter")
	root.remove_child(table)
	table.free()
	for f in ["panel.campaign"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
