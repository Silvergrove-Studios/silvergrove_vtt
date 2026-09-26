extends TestCase
## Encounter documents, events, vision and commands.


func test_json_doc() -> void:
	var d := {"b": 2.0, "a": {"z": [3.0, 1.5, {"y": 1}], "x": 1}}
	var text := JsonDoc.stringify(d)
	check(text.begins_with('{\n  "a": {\n    "x": 1,'), "keys sorted at every level")
	check(text.contains('"b": 2\n'), "whole floats written as ints")
	check(JsonDoc.same(d, JsonDoc.parse(text)), "parse(stringify) is the same document")
	var err: Array = []
	check(JsonDoc.parse("[1,2]", err).is_empty() and err.size() == 1, "an array is not a document")
	err.clear()
	check(JsonDoc.parse("{ nope", err).is_empty() and err[0].begins_with("line "), "parse error names the line")
	var target := {"keep": 1, "drop": 2, "change": 3}
	var before := JsonDoc.merge(target, {"drop": null, "change": 4, "add": 5})
	check(target == {"keep": 1, "change": 4, "add": 5}, "merge sets, adds and removes")
	check(before == {"drop": 2, "change": 3, "add": null}, "merge returns the inverse change set")
	JsonDoc.merge(target, before)
	check(target == {"keep": 1, "drop": 2, "change": 3}, "applying the inverse restores")
	check(JsonDoc.uuid().length() == 36 and JsonDoc.uuid() != JsonDoc.uuid(), "uuids")
	check(JsonDoc.new_id("t").begins_with("t_") and JsonDoc.new_id("t").length() == 10, "short ids")


## The players' own notes: private unless shared, only their writer changes
## them, and the DM never reads a private one.
func test_player_notes() -> void:
	var players := [{"id": "pl_a", "name": "Ana"}, {"id": "pl_b", "name": "Ben"}, {"id": "pl_c", "name": "Cal"}]
	var notes := []
	check(PlayerNotes.apply(notes, {"op": "save", "note": {"id": "pn_1", "title": "Suspects", "text": "The reeve?", "folder": "Mystery"}}, "pl_a", players) == "", "Ana writes a note")
	var n: Dictionary = notes[0]
	check(n.owner == "pl_a" and n.share == [] and n.folder == "Mystery" and str(n.created) != "", "hers, private, in her folder")
	check(PlayerNotes.can_see(n, "pl_a", Views.ROLE_PLAYER) and not PlayerNotes.can_see(n, "pl_b", Views.ROLE_PLAYER) and not PlayerNotes.can_see(n, "", Views.ROLE_GM) and not PlayerNotes.can_see(n, "", Views.ROLE_DISPLAY),
		"a private note: Ana alone reads it — not Ben, not the DM, not a display")
	check(PlayerNotes.apply(notes, {"op": "save", "note": {"id": "pn_1", "title": "Mine now"}}, "pl_b", players) != "" and n.title == "Suspects", "Ben cannot change it")
	check(PlayerNotes.apply(notes, {"op": "delete", "id": "pn_1"}, "pl_b", players) != "" and notes.size() == 1, "nor delete it")
	check(PlayerNotes.apply(notes, {"op": "save", "note": {"id": "pn_1", "title": "Suspects", "text": "The reeve!", "folder": "Mystery", "share": ["gm", "pl_b", "pl_a", "nobody"]}}, "pl_a", players) == "", "she shares it")
	check(n.share == ["gm", "pl_b"] and n.text == "The reeve!", "with the DM and Ben (not herself, not strangers)")
	check(PlayerNotes.can_see(n, "", Views.ROLE_GM) and PlayerNotes.can_see(n, "pl_b", Views.ROLE_PLAYER) and not PlayerNotes.can_see(n, "pl_c", Views.ROLE_PLAYER), "the DM and Ben read it; Cal does not")
	check(PlayerNotes.share_list(["pl_b", "all"], players, "pl_a") == ["all"] and PlayerNotes.can_see({"owner": "pl_a", "share": ["all"]}, "pl_c", Views.ROLE_PLAYER), "shared with everyone: everyone")
	check(PlayerNotes.for_viewer(notes, "pl_c", Views.ROLE_PLAYER).is_empty() and PlayerNotes.for_viewer(notes, "pl_b", Views.ROLE_PLAYER).size() == 1, "each viewer gets what they may read")
	check(PlayerNotes.apply(notes, {"op": "save", "note": {"id": "bad", "title": "x"}}, "pl_a", players) != "" and PlayerNotes.apply(notes, {"op": "save", "note": {"id": "pn_2"}}, "", players) != "", "a note needs an id and a writer")
	check(PlayerNotes.apply(notes, {"op": "save", "note": {"id": "pn_3", "text": "x".repeat(30000)}}, "pl_b", players) == "" and str(PlayerNotes.find(notes, "pn_3").text).length() == PlayerNotes.MAX_TEXT, "a note is kept to a sane size")
	check(PlayerNotes.apply(notes, {"op": "delete", "id": "pn_1"}, "pl_a", players) == "" and PlayerNotes.find(notes, "pn_1").is_empty(), "Ana deletes hers")
	check(PlayerNotes.new_id().begins_with("pn_") and PlayerNotes.new_id() != PlayerNotes.new_id(), "note ids")
	var c := Campaign.create("Notes")
	check(c.player_notes.is_empty() and c.doc.has("player_notes"), "a campaign keeps them")
	c.doc.erase("player_notes")
	check(c.player_notes.is_empty(), "and one from before them gets an empty list")


func test_encounter_document() -> void:
	var m := _chapel()
	var e := Encounter.create("Chapel Ambush")
	check(e.doc.format == Encounter.FORMAT and e.doc.version == Encounter.VERSION, "created with format and version")
	check(e.scenes.is_empty() and e.active_scene().is_empty(), "empty encounter has no active scene")
	var sc := Encounter.new_scene(m, "crypt")
	check(sc.map == m.doc.id and sc.level == "crypt" and sc.name.contains("Crypt") and sc.map_path == "ruined_chapel.hexmap", "new_scene records the map, level and file")
	e.doc.scenes.append(sc)
	e.doc.active_scene = sc.id
	var tk := Encounter.new_token("Goblin", Vector2(1.5, 2.25), {"hidden": true})
	check(tk.label == "GO" and tk.pos == [1.5, 2.25] and tk.hidden == true and tk.vision.radius == 6 and not tk.has("owner"), "new_token defaults and extras")
	check(not Encounter.new_token("x", Vector2.ZERO, {"owner": null}).has("owner"), "a null extra is left out")
	sc.tokens.append(tk)
	var text := e.to_json()
	var back := Encounter.from_json(text)
	check(back != null and back.to_json() == text, "serialisation is stable through a round trip")
	check(back.scene(sc.id).tokens[0].name == "Goblin" and back.active_scene().id == sc.id, "scenes and tokens survive")
	check(back.map_ids() == PackedStringArray([m.doc.id]), "map_ids lists each map once")
	var err: Array = []
	check(Encounter.from_json('{"format": "silvergrove.hexmap"}', err) == null and err[0].contains("not a"), "a map is not an encounter")
	err.clear()
	check(Encounter.from_json('{"format": "silvergrove.encounter", "version": 99}', err) == null and err[0].contains("newer"), "newer version refused")
	# A hand-written minimal file is filled in.
	var thin := Encounter.from_json('{"format": "silvergrove.encounter", "version": 1, "scenes": [{"id": "s1", "map": "x", "level": "ground", "tokens": [{"id": "t1", "name": "Orc"}]}]}')
	check(thin.active_scene_id == "s1" and thin.scene("s1").fog.explored == [] and thin.scene("s1").overrides == {}, "missing fields filled in")
	check(thin.scene("s1").tokens[0].vision.radius == 6 and thin.scene("s1").tokens[0].label == "OR", "partial tokens filled in")
	var nulls := Encounter.from_json('{"format": "silvergrove.encounter", "version": 1, "scenes": [{"id": "s1", "map": "x", "level": "ground", "tokens": [{"id": "t1", "name": "Orc", "owner": null, "light": null}]}]}')
	check(not nulls.scene("s1").tokens[0].has("owner") and not nulls.scene("s1").tokens[0].has("light"), "stored nulls read as absent")
	check(thin.turns.round == 1 and thin.turns.mode == "free" and thin.players == [], "turns and players default")
	var old := Encounter.from_json('{"format": "silvergrove.encounter", "version": 1, "initiative": {"order": ["a"], "turn": 0, "round": 2, "running": true}}')
	check(not old.doc.has("initiative") and old.turns.mode == "ordered" and old.turns.order == ["a"] and old.turns.round == 2, "pre-release initiative block migrates to ordered turns")
	# Save/load through a file, and a bundle directory.
	var path := ProjectSettings.globalize_path("user://test.encounter")
	check(e.save(path) == OK and not e.dirty, "saves")
	var loaded := Encounter.load_file(path)
	check(loaded != null and loaded.path == path and loaded.name == "Chapel Ambush" and loaded.base_dir() == path.get_base_dir(), "loads with path and base_dir")
	DirAccess.remove_absolute(path)
	var bundle := ProjectSettings.globalize_path("user://test_bundle.encounter")
	DirAccess.make_dir_recursive_absolute(bundle)
	check(e.save(bundle) == OK and FileAccess.file_exists(bundle.path_join("encounter.json")), "a bundle directory gets encounter.json")
	check(Encounter.load_file(bundle) != null, "bundle loads")
	DirAccess.remove_absolute(bundle.path_join("encounter.json"))
	DirAccess.remove_absolute(bundle)
	err.clear()
	check(Encounter.load_file("/nowhere/x.encounter", err) == null and err[0].begins_with("no such file"), "missing file reported")


func test_encounter_resolve_maps() -> void:
	var path := example("chapel_ambush.encounter")
	var e := Encounter.load_file(path)
	check(e != null, "example encounter loads")
	var st := EncounterState.new(e)
	var warn := st.resolve_maps()
	check(warn.is_empty(), "example resolves its map without warnings: %s" % [warn])
	check(st.maps.size() == 1 and st.map_for(e.active_scene_id).name == "Ruined Chapel", "map found by path relative to the encounter")
	check(st.level_for(e.scenes[1].id).id == "crypt", "each scene finds its level")
	# Wrong id, missing file.
	var e2 := Encounter.create("x")
	e2.path = path
	e2.doc.scenes.append({"id": "s", "map": "not-the-chapel", "map_path": "ruined_chapel.hexmap", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	e2.doc.scenes.append({"id": "s2", "map": "m", "map_path": "gone.hexmap", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	e2.doc.scenes.append({"id": "s3", "map": "m", "map_path": "", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	var st2 := EncounterState.new(e2)
	warn = st2.resolve_maps()
	check(warn.size() == 3, "mismatch, missing and unnamed maps each warn: %s" % [warn])
	check(st2.map_for("s") != null and e2.scene("s").map == st2.map_for("s").doc.id, "a mismatched id is adopted, not fatal")
	check(st2.level_for("s2").is_empty() and st2.effective_level("s2").is_empty(), "a scene without a map has no level")


func test_encounter_events_roundtrip() -> void:
	# Every event's inverse restores the document exactly.
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var gob: String = parts[3]
	var m := st.map_for(sid)
	var door: Dictionary = {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	var light: Dictionary = m.level_by_id("ground").lights[0]
	var second := Encounter.new_scene(m, "crypt")
	st.apply({"t": "scene.add", "scene": second})
	var third := Encounter.new_scene(m, "crypt", "Third")
	var events := [
		{"t": "encounter.set", "changes": {"name": "Renamed", "notes": [{"id": "n", "title": "x", "text": ""}]}},
		{"t": "scene.add", "scene": third},
		{"t": "scene.add", "scene": third, "index": 0},
		{"t": "scene.remove", "id": sid},
		{"t": "scene.set", "id": sid, "changes": {"name": "Other", "extra": 1}},
		{"t": "scene.activate", "id": second.id},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Orc", Vector2(1, 1))},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Orc", Vector2(1, 1)), "index": 0},
		{"t": "token.remove", "scene": sid, "id": hero},
		{"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [4.5, 4.5], "hidden": true, "note": "new key", "light": {"bright": 1, "dim": 2, "color": "#fff"}}},
		{"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}},
		{"t": "element.set", "scene": sid, "ref": "lights:" + light.id, "changes": {"on": false, "hidden": true}},
		{"t": "fog.set", "scene": sid, "enabled": true},
		{"t": "fog.reveal", "scene": sid, "cells": ["0,0", "1,0", "0,0"]},
		{"t": "turns.set", "changes": {"mode": "ordered", "order": [hero, gob], "running": true, "turn": 1, "round": 3, "active": [hero]}},
		{"t": "player.add", "player": Encounter.new_player("Ana")},
		{"t": "player.add", "player": {"id": "pl_1", "name": "Ben", "color": "#fff"}},
	]
	for ev in events:
		var before := JsonDoc.sans_modified(st.encounter.to_json())
		var why := st.validate(ev)
		check(why == "", "%s validates (%s)" % [ev.t, why])
		var got := []
		st.applied.connect(func(e: Dictionary, i: Dictionary) -> void: got.append([e, i]), CONNECT_ONE_SHOT)
		var inv := st.apply(ev)
		check(not inv.is_empty() and got.size() == 1 and got[0][0] == ev and got[0][1] == inv, "%s applied and announced" % ev.t)
		check(JsonDoc.sans_modified(st.encounter.to_json()) != before, "%s changed something" % ev.t)
		check(st.validate(inv) == "", "inverse of %s validates (%s)" % [ev.t, st.validate(inv)])
		var inv2 := st.apply(inv)
		check(JsonDoc.sans_modified(st.encounter.to_json()) == before, "inverse of %s restores the document" % ev.t)
		st.apply(inv2)
		check(JsonDoc.sans_modified(st.encounter.to_json()) != before, "inverse of the inverse re-applies %s" % ev.t)
		st.apply(inv)
		check(JsonDoc.sans_modified(st.encounter.to_json()) == before, "and undoes again")
	# fog.hide on top of revealed cells, then remove the player that owns a token.
	st.apply({"t": "fog.reveal", "scene": sid, "cells": ["0,0", "1,0"]})
	var before := st.encounter.to_json()
	var inv := st.apply({"t": "fog.hide", "scene": sid, "cells": ["1,0", "9,9"]})
	check(inv.cells == ["1,0"] and st.explored(sid).keys() == ["0,0"], "fog.hide drops only explored cells and inverts to exactly those")
	st.apply(inv)
	check(JsonDoc.sans_modified(st.encounter.to_json()) == JsonDoc.sans_modified(before), "fog.hide inverse restores")
	st.apply({"t": "player.add", "player": {"id": "pl_1", "name": "Ben", "color": "#fff"}})
	st.apply({"t": "player.set", "id": "pl_1", "changes": {"name": "Benjamin"}})
	before = st.encounter.to_json()
	inv = st.apply({"t": "player.remove", "id": "pl_1"})
	st.apply(inv)
	check(JsonDoc.sans_modified(st.encounter.to_json()) == JsonDoc.sans_modified(before), "player.remove inverse restores at the same index")
	check(st.encounter.dirty, "events mark the encounter dirty")


func test_encounter_validate() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var bad := [
		[{}, "unknown event"],
		[{"t": "nope"}, "unknown event"],
		[{"t": "encounter.set"}, "needs 'changes'"],
		[{"t": "encounter.set", "changes": {"scenes": []}}, "cannot change 'scenes'"],
		[{"t": "scene.add", "scene": {}}, "needs a scene with an id"],
		[{"t": "scene.add", "scene": {"id": sid}}, "already exists"],
		[{"t": "scene.remove", "id": "zz"}, "no scene"],
		[{"t": "scene.set", "id": sid, "changes": {"tokens": []}}, "cannot change 'tokens'"],
		[{"t": "token.add", "scene": "zz", "token": {"id": "t"}}, "no scene"],
		[{"t": "token.add", "scene": sid, "token": {"name": "no id"}}, "needs a token with an id"],
		[{"t": "token.add", "scene": sid, "token": {"id": hero}}, "already exists"],
		[{"t": "token.remove", "scene": sid, "id": "zz"}, "no token"],
		[{"t": "token.set", "scene": sid, "id": hero, "changes": {"id": "x"}}, "cannot change 'id'"],
		[{"t": "token.set", "scene": sid, "id": hero}, "needs 'changes'"],
		[{"t": "element.set", "scene": sid, "ref": "walls", "changes": {}}, "needs a ref"],
		[{"t": "element.set", "scene": sid, "ref": "terrain:0,0", "changes": {}}, "needs a ref"],
		[{"t": "element.set", "scene": sid, "ref": "walls:w_nope", "changes": {"state": "open"}}, "no walls:w_nope on the map"],
		[{"t": "fog.set", "scene": sid}, "needs 'enabled'"],
		[{"t": "fog.reveal", "scene": sid}, "needs 'cells'"],
		[{"t": "turns.set", "changes": {"mode": "chaos"}}, "mode must be one of"],
		[{"t": "turns.set", "changes": {"order": "t_1"}}, "must be a list"],
		[{"t": "player.add", "player": {}}, "needs a player with an id"],
		[{"t": "player.remove", "id": "zz"}, "no player"],
		[{"t": "player.set", "id": "zz", "changes": {}}, "no player"],
	]
	for b in bad:
		var why := st.validate(b[0])
		check(why.contains(b[1]), "rejects %s: '%s' should mention '%s'" % [b[0], why, b[1]])
	var before := st.encounter.to_json()
	check(st.apply({"t": "token.remove", "scene": sid, "id": "zz"}).is_empty() and st.encounter.to_json() == before, "apply of an invalid event is a no-op")
	# A scene without a map cannot check element refs, so it accepts them.
	var e := Encounter.create("x")
	e.doc.scenes.append({"id": "s", "map": "m", "map_path": "", "level": "ground", "tokens": [], "overrides": {}, "fog": {"enabled": false, "explored": []}})
	check(EncounterState.new(e).validate({"t": "element.set", "scene": "s", "ref": "walls:w_1", "changes": {"state": "open"}}) == "", "without the map, element refs are trusted")


func test_encounter_permissions() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var gob: String = parts[3]
	var move := {"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [1, 1], "rot": 90}}
	# Ownership matters in dm mode with the hero ticked; free mode is tested below.
	st.apply({"t": "turns.set", "changes": {"mode": "dm", "active": [hero, gob]}})
	check(st.allowed(move, ""), "the table may do anything")
	check(st.allowed({"t": "scene.remove", "id": sid}, ""), "the table may do anything (2)")
	check(st.allowed(move, "pl_1"), "a player may move their own token")
	check(not st.allowed(move, "pl_2"), "another player may not")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_1"), "may not move an unowned token")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": hero, "changes": {"hidden": false}}, "pl_1"), "may not change other fields")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [1, 1], "name": "x"}}, "pl_1"), "one bad field rejects the whole request")
	check(not st.allowed({"t": "element.set", "scene": sid, "ref": "walls:x", "changes": {"state": "open"}}, "pl_1"), "players may not open doors")
	check(not st.allowed({"t": "token.remove", "scene": sid, "id": hero}, "pl_1"), "players may not remove tokens")
	# Turn modes. Free: any visible token, even someone else's.
	st.apply({"t": "turns.set", "changes": {"mode": "free", "active": []}})
	check(Encounter.create("x").turns.mode == "free", "encounters start in free mode")
	check(st.allowed({"t": "token.set", "scene": sid, "id": hero, "changes": {"pos": [1, 1]}}, "pl_2"), "free: another player may move it")
	check(not st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_2"), "free: but never a hidden one")
	st.apply({"t": "token.set", "scene": sid, "id": gob, "changes": {"hidden": false}})
	check(st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_2"), "free: a revealed unowned token is fair game")
	check(st.highlighted_token_ids().is_empty(), "free: nobody is 'up'")
	# DM picks: owned and ticked.
	st.apply({"t": "turns.set", "changes": {"mode": "dm"}})
	check(not st.allowed(move, "pl_1"), "dm: not until the DM ticks it")
	st.apply({"t": "turns.set", "changes": {"active": [hero]}})
	check(st.allowed(move, "pl_1") and not st.allowed(move, "pl_2"), "dm: ticked, the owner may move it and nobody else")
	check(st.highlighted_token_ids() == [hero], "dm: ticked tokens are up")
	st.apply({"t": "turns.set", "changes": {"active": [gob]}})
	check(not st.allowed({"t": "token.set", "scene": sid, "id": gob, "changes": {"pos": [1, 1]}}, "pl_2"), "dm: an unowned token ticked still needs an owner")
	# Ordered: only the owner of the current turn's token.
	st.apply({"t": "turns.set", "changes": {"mode": "ordered", "order": [gob, hero], "turn": 0, "round": 1, "running": false}})
	check(not st.allowed(move, "pl_1") and st.current_turn_token() == "", "ordered but not running: nobody moves")
	st.apply({"t": "turns.set", "changes": {"running": true}})
	check(st.current_turn_token() == gob and not st.allowed(move, "pl_1"), "ordered: goblin's turn, the hero waits")
	st.apply({"t": "turns.set", "changes": {"turn": 1}})
	check(st.current_turn_token() == hero and st.allowed(move, "pl_1") and not st.allowed(move, "pl_2") and st.highlighted_token_ids() == [hero], "ordered: hero's turn, only its owner")
	check(st.allowed({"t": "turns.set", "changes": {"turn": 0}}, ""), "the table may always step turns")
	check(not st.allowed({"t": "turns.set", "changes": {"turn": 0}}, "pl_1"), "a player may not")
	st.apply({"t": "turns.set", "changes": {"mode": "free", "running": false}})
	st.apply({"t": "token.set", "scene": sid, "id": gob, "changes": {"hidden": true}})
	check(st.tokens_owned_by(sid, "pl_1").size() == 1 and st.tokens_owned_by(sid, "pl_2").is_empty(), "tokens_owned_by")
	check(st.tokens_visible_to_players(sid).size() == 1 and st.tokens_visible_to_players(sid)[0].id == hero, "hidden tokens are not for players")


func test_encounter_effective() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var m := st.map_for(sid)
	var lvl := m.level_by_id("ground")
	var door: Dictionary = {}
	for w in lvl.walls:
		if w.get("door", "none") == "door":
			door = w
	check(st.effective(sid, "walls", door).state == "closed", "no override → as stored")
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}})
	var eff := st.effective(sid, "walls", door)
	check(eff.state == "open" and door.state == "closed", "override merged; the map untouched")
	check(eff.points == door.points and eff.id == door.id, "other fields come through")
	eff.points.append([0, 0])
	check(door.points.size() == eff.points.size() - 1, "effective() is a copy: editing it cannot reach the map")
	var el := st.effective_level(sid)
	var found := false
	for w in el.walls:
		if w.id == door.id:
			found = w.state == "open"
	check(found, "effective_level carries the override")
	check(el.terrain == lvl.terrain and el.tree == lvl.tree and el.id == lvl.id, "effective_level shares terrain and tree")
	check(lvl.walls[0].state != "open" or lvl.walls[0].id == door.id, "map walls unchanged")
	var light: Dictionary = lvl.lights[0]
	st.apply({"t": "element.set", "scene": sid, "ref": "lights:" + light.id, "changes": {"on": false}})
	check(st.effective(sid, "lights", light).on == false and not light.has("on"), "overlay-only field")
	st.apply({"t": "element.set", "scene": sid, "ref": "lights:" + light.id, "changes": {"on": null}})
	check(st.override_of(sid, "lights:" + light.id).is_empty() and not st.encounter.scene(sid).overrides.has("lights:" + light.id), "clearing the last key removes the override")
	check(st.effective(sid, "lights", light) == light, "back to as stored")
	check(m.to_json() == _chapel().to_json(), "after all that, the map document is byte-identical")


func test_vision() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var m := st.map_for(sid)
	var g := m.grid
	var door: Dictionary = {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	# At night, the lights out and six hexes of darkvision: what the hero
	# sees is what that reaches (in daylight it would be the whole map in
	# its line of sight — layers_lighting.gd tests the light)
	st.apply({"t": "scene.set", "id": sid, "changes": {"light": "dark"}})
	for l in m.level_by_id("ground").lights:
		st.apply({"t": "element.set", "scene": sid, "ref": "lights:" + str(l.id), "changes": {"on": false}})
	st.apply({"t": "token.set", "scene": sid, "id": hero, "changes": {"vision": {"radius": 6, "dark_radius": 6}}})
	# The hero stands outside the west door; the goblin is inside the nave.
	var inside := g.cell_center(g.offset_to_axial(7, 7))
	var closed := Vision.of(st, sid, [st.token(sid, hero)])
	check(closed.polygons.size() == 1 and closed.cells.size() > 10, "one polygon, some cells seen (%d)" % closed.cells.size())
	check(closed.cells.has(g.world_to_axial(Vision.token_pos(st.token(sid, hero)))), "a token sees its own cell")
	check(not Vision.sees(closed.polygons, inside), "closed door: cannot see into the nave")
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}})
	var opened := Vision.of(st, sid, [st.token(sid, hero)])
	check(Vision.sees(opened.polygons, inside), "open door: sees into the nave")
	check(opened.cells.size() > closed.cells.size(), "open door reveals more cells (%d > %d)" % [opened.cells.size(), closed.cells.size()])
	# In the dark, sight is bounded by the darkvision.
	var far_seen := 0
	for c in opened.cells:
		if g.cell_center(c).distance_to(Vision.token_pos(st.token(sid, hero))) > 6.0 + 0.6:
			far_seen += 1
	check(far_seen == 0, "every seen cell within the darkvision (%d beyond)" % far_seen)
	# No vision, no polygon; two tokens, two polygons; sight vs light walls.
	st.apply({"t": "token.set", "scene": sid, "id": hero, "changes": {"vision": {"radius": 0, "dark_radius": 6}}})
	check(Vision.of(st, sid, [st.token(sid, hero)]).cells.is_empty(), "radius 0 sees nothing, darkvision or not")
	st.apply({"t": "scene.set", "id": sid, "changes": {"light": "daylight"}})
	st.apply({"t": "token.set", "scene": sid, "id": hero, "changes": {"vision": {"radius": 3}}})
	check(Vision.of(st, sid, st.tokens(sid)).polygons.size() == 2, "each seeing token gets a polygon")
	var lvl := {"walls": [{"id": "w", "points": [[0, 0], [0, 2]], "blocks": {"sight": false, "light": true}, "door": "none", "state": "closed"}]}
	check(Vision.segments(lvl).is_empty() and Lighting.blocking_segments(lvl).size() == 1, "a window blocks light but not sight")
	check(Vision.of(st, "no-such-scene", []).cells.is_empty(), "unknown scene sees nothing")


func test_encounter_commands() -> void:
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var hero: String = parts[2]
	var gob: String = parts[3]
	var h := EventLog.new(st)
	var c := EncounterCommands.new(st, h)
	var m := st.map_for(sid)
	var g := m.grid
	var door: Dictionary = {}
	for w in m.level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			door = w
	var start := st.encounter.to_json()
	check(c.run({"t": "token.remove", "scene": sid, "id": "zz"}) != "" and not h.can_undo(), "a refused event is not recorded")
	var applied := []
	st.applied.connect(func(e: Dictionary, _i: Dictionary) -> void: applied.append(e.t))
	var wolf := Encounter.new_token("Wolf", Vector2(2, 2))
	check(c.add_token(sid, wolf) == "" and applied == ["token.add"] and st.tokens(sid).size() == 3, "a command applies its event exactly once")
	h.undo()
	check(applied == ["token.add", "token.remove"] and st.tokens(sid).size() == 2, "undo applies the inverse once")
	h.redo()
	check(applied.size() == 3 and st.tokens(sid).size() == 3 and st.tokens(sid)[2].id == wolf.id, "redo re-adds it")
	h.undo()
	h.clear()
	applied.clear()
	check(c.set_door(sid, door.id, "open") == "" and h.undo_label() == "Open door", "set_door records a labelled step")
	check(st.effective(sid, "walls", door).state == "open", "door open")
	h.undo()
	check(st.effective(sid, "walls", door).state == "closed" and JsonDoc.sans_modified(st.encounter.to_json()) == JsonDoc.sans_modified(start), "undo closes it and restores the document")
	h.redo()
	check(st.effective(sid, "walls", door).state == "open", "redo opens it again")
	c.set_light(sid, m.level_by_id("ground").lights[0].id, false)
	c.set_revealed(sid, "walls", door.id, false)
	c.reset_element(sid, "walls:" + door.id)
	check(st.override_of(sid, "walls:" + door.id).is_empty() and h.undo_label() == "Reset", "reset_element clears both keys in one step")
	h.undo()
	check(st.override_of(sid, "walls:" + door.id) == {"state": "open", "hidden": true}, "undo of reset brings both back")
	# Fog: a move reveals what the token sees, as one undo step.
	c.set_fog(sid, true)
	check(st.explored(sid).is_empty(), "fog on, nothing explored yet")
	var steps := h._undo.size()
	c.move_token(sid, hero, g.cell_center(g.offset_to_axial(4, 7)))
	check(h._undo.size() == steps + 1 and h.undo_label() == "Move Hero", "move + reveal is one step")
	var seen := st.explored(sid).size()
	check(seen > 10 and st.token(sid, hero).pos == [g.cell_center(g.offset_to_axial(4, 7)).x, g.cell_center(g.offset_to_axial(4, 7)).y], "moved and explored %d cells" % seen)
	c.move_token(sid, hero, g.cell_center(g.offset_to_axial(4, 7)))
	check(st.explored(sid).size() == seen, "moving in place reveals nothing new")
	h.undo()
	h.undo()
	check(st.explored(sid).is_empty(), "undoing the moves forgets what was seen")
	c.set_fog(sid, false)
	c.move_token(sid, hero, g.cell_center(g.offset_to_axial(2, 7)))
	check(st.explored(sid).is_empty(), "no fog, no exploring")
	c.set_fog(sid, true)
	c.reveal_cells(sid, [Vector2i(0, 0), "1,0", Vector2i(0, 0)])
	check(st.explored(sid).keys() == ["0,0", "1,0"], "reveal_cells takes cells or keys, once each")
	check(c.reveal_cells(sid, ["0,0"]) == "" and h.undo_label() == "Reveal", "revealing nothing new is a no-op")
	c.hide_cells(sid, [Vector2i(0, 0)])
	check(st.explored(sid).keys() == ["1,0"], "hide_cells")
	c.reset_fog(sid)
	check(st.explored(sid).is_empty(), "reset_fog")
	h.undo()
	check(st.explored(sid).keys() == ["1,0"], "reset_fog undoes")
	# Tokens.
	var orc := Encounter.new_token("Orc", Vector2(2, 2))
	c.add_token(sid, orc)
	check(st.token(sid, orc.id).name == "Orc" and h.undo_label() == "Add Orc", "add_token")
	c.remove_tokens(sid, [orc.id, gob])
	check(st.tokens(sid).size() == 1 and h.undo_label() == "Remove 2 tokens", "remove_tokens is one step")
	h.undo()
	check(st.tokens(sid).size() == 3 and st.tokens(sid)[1].id == gob and st.tokens(sid)[2].id == orc.id, "undo restores both at their places")
	c.update_token(sid, gob, {"hidden": false, "tags": ["surprised"]})
	check(st.token(sid, gob).hidden == false and st.token(sid, gob).tags == ["surprised"], "update_token")
	# Turns: modes, DM picks, and the list system wrapping rounds both ways.
	c.set_turn_mode("dm")
	c.toggle_active_token(hero)
	c.toggle_active_token(gob)
	var turns := st.encounter.turns
	check(turns.mode == "dm" and turns.active == [hero, gob] and h.undo_label() == "Who may move", "toggle_active_token adds")
	c.toggle_active_token(hero)
	check(turns.active == [gob], "toggle_active_token removes")
	check(c.start_turns(sid) == "" and turns.mode == "ordered" and turns.system == "list" and turns.order == [hero, gob, orc.id] and turns.running and turns.turn == 0 and turns.round == 1, "start_turns orders the scene's tokens with the list system: %s" % [turns.order])
	check(st.current_turn_token() == hero, "first turn")
	c.next_turn(); c.next_turn(); c.next_turn()
	check(turns.turn == 0 and turns.round == 2, "next_turn wraps to a new round")
	c.previous_turn()
	check(turns.turn == 2 and turns.round == 1, "previous_turn wraps back")
	c.previous_turn(); c.previous_turn()
	check(c.previous_turn() != "" and turns.turn == 0 and turns.round == 1, "cannot go before the start")
	c.set_turn_order([orc.id, hero, gob])
	check(turns.order[0] == orc.id and st.current_turn_token() == orc.id, "set_turn_order")
	c.stop_turns()
	check(not turns.running and st.current_turn_token() == "", "stop_turns")
	c.set_turn_order([])
	check(c.next_turn() != "", "no order, no turns")
	# Restarting keeps the surviving order and appends newcomers.
	c.set_turn_order([gob, hero])
	c.start_turns(sid)
	check(turns.order == [gob, hero, orc.id], "restart keeps the arranged order and appends the rest")
	c.set_turn_mode("free")
	# Scenes and players.
	var crypt := Encounter.new_scene(m, "crypt")
	c.add_scene(crypt)
	check(st.encounter.active_scene_id == crypt.id and h.undo_label() == "Show scene", "add_scene activates")
	h.undo(); h.undo()
	check(st.encounter.active_scene_id == sid and st.encounter.scenes.size() == 1, "undo of add_scene, twice, is back to one scene")
	c.add_scene(crypt, false)
	check(st.encounter.active_scene_id == sid, "add_scene without activating")
	c.rename_scene(crypt.id, "Below")
	check(st.encounter.scene(crypt.id).name == "Below", "rename_scene")
	c.remove_scene(sid)
	check(st.encounter.active_scene_id == crypt.id, "removing the active scene moves to another")
	h.undo()
	check(st.encounter.active_scene_id == sid, "undo restores it as active")
	var p := Encounter.new_player("Ana")
	c.add_player(p)
	c.update_player(p.id, {"name": "Anna"})
	check(st.encounter.player(p.id).name == "Anna", "players")
	c.remove_player(p.id)
	check(st.encounter.player(p.id).is_empty(), "remove_player")
	c.rename("Ambush!")
	check(st.encounter.name == "Ambush!", "rename")
	# Everything undone is the starting document.
	while h.can_undo():
		h.undo()
	check(JsonDoc.sans_modified(st.encounter.to_json()) == JsonDoc.sans_modified(start), "undoing everything restores the start")
	while h.can_redo():
		h.redo()
	check(st.encounter.name == "Ambush!" and st.encounter.scene(crypt.id).name == "Below", "redoing everything replays it")
	h.clear()


func test_example_encounter() -> void:
	# The example is built through events and must be a consistent document.
	var e := Encounter.load_file(example("chapel_ambush.encounter"))
	var st := EncounterState.new(e)
	st.resolve_maps()
	check(e.scenes.size() == 2 and e.active_scene().name == "Chapel at dusk", "two scenes, chapel active")
	var sid := e.active_scene_id
	check(st.tokens(sid).size() == 6 and st.tokens_visible_to_players(sid).size() == 2 and e.players.size() == 2, "party visible, goblins hidden")
	var off := 0
	for l in st.level_for(sid).lights:
		if st.effective(sid, "lights", l).get("on", true) == false:
			off += 1
	check(off == 4, "four braziers out")
	check(st.fog_enabled(sid) and st.explored(sid).size() > 20, "fog on with the approach explored")
	for k in st.explored(sid):
		check(st.map_for(sid).grid.in_bounds(HexMap.key_cell(k)), "explored cell %s in bounds" % k)
	check(e.turns.mode == "ordered" and e.turns.order.size() == 6 and not e.turns.running, "ordered turns set up, not running")
	for tid in e.turns.order:
		check(not st.token(sid, tid).is_empty(), "initiative token %s exists" % tid)
	check(e.map_ids().size() == 1, "one map")
	for p in e.players:
		check(st.tokens_owned_by(sid, p.id).size() == 1, "%s owns one token" % p.name)
	for s in e.scenes:
		for ref in s.overrides:
			check(st.validate({"t": "element.set", "scene": s.id, "ref": ref, "changes": {}}) == "", "override %s refers to a real element" % ref)
