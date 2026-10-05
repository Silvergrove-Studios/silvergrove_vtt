extends TestCase
## Fights in the theatre of the mind, a fight's own settings, and an
## adventure's suggestion of how a table runs it. A fight in the mind is a
## scene with no map whose tokens are only who is in it, far apart (nothing
## the rules measure is near anything by itself); the screens list them.
## Where the table leaves it to each fight, the DM chooses as it starts; a
## fight may have its own settings (those a ruleset says may: x-per-fight),
## and in the mind a setting is what it must be there (x-mind) — the rules
## load with them while it runs, and Table settings says what differs. A
## package may carry its author's suggestion (`recommended`), which the
## walkthrough offers and nothing more.


func _find(reg: Dictionary, key: String) -> Dictionary:
	for it in reg.get("settings", []):
		if str(it.key) == key:
			return it
	return {}


## Every label's words under a node, in one string.
func _texts(node: Node) -> String:
	var out := PackedStringArray()
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		out.append(_texts(c))
	return " ".join(out)


func test_a_scene_in_the_theatre_of_the_mind() -> void:
	var sc := Encounter.new_mind_scene("The bridge")
	check(Encounter.is_mind(sc) and str(sc.map) == "" and not bool(sc.fog.enabled) and sc.name == "The bridge", "a scene with no map, no fog, its space the mind")
	check(not Encounter.is_mind(Encounter.new_scene(HexMap.create("M", HexGrid.new()), "ground")), "a map's scene is not")
	check(Encounter.mind_pos(sc) == Vector2(Encounter.MIND_GAP, 0) and Encounter.mind_pos(sc, 2) == Vector2(Encounter.MIND_GAP * 3, 0), "the first creature a gap out, the third of several two more")
	var e := Encounter.create("Mind")
	e.doc.players = [{"id": "pl_1", "name": "Ana", "color": "#4f9cf6"}]
	e.actors["a_hero"] = {"id": "a_hero", "kind": "pc", "name": "Hero", "owner": "pl_1"}
	e.actors["a_gob"] = {"id": "a_gob", "kind": "npc", "name": "Goblin"}
	e.actors["a_lurk"] = {"id": "a_lurk", "kind": "npc", "name": "Lurker"}
	var st := EncounterState.new(e)
	var hist := EventLog.new()
	hist.state = st
	var k := RulesKernel.new(st, hist)
	var events := [{"t": "scene.add", "scene": sc}]
	var n := 0
	for spec in [["t_hero", "a_hero", false], ["t_gob", "a_gob", false], ["t_lurk", "a_lurk", true]]:
		n += 1
		events.append({"t": "token.add", "scene": sc.id, "token": Encounter.new_token(str(spec[1]).substr(2).capitalize(), Vector2(Encounter.MIND_GAP * n, 0), {"id": spec[0], "actor": spec[1], "hidden": spec[2]})})
	events.append({"t": "scene.activate", "id": sc.id})
	check(k.commit(events, "A fight in the mind") == "", "a fight in the mind: three creatures, one hidden")
	check(st.resolve_maps().is_empty(), "no map is looked for, and none is missed")
	check(Encounter.mind_pos(e.scene(sc.id)) == Vector2(Encounter.MIND_GAP * 4, 0), "the next comes a gap past the farthest")
	# what the screens are sent: no map, the creatures; the hidden one only to the DM
	var mine := WebScene.build(st, sc.id, "pl_1", false)
	var ids: Array = (mine.tokens as Array).map(func(t: Dictionary) -> String: return str(t.id))
	check(str(mine.get("space", "")) == "mind" and str(mine.map) == "" and not bool(mine.fog), "a player's screen: a fight in the mind, no map, no fog")
	check(ids.has("t_hero") and ids.has("t_gob") and not ids.has("t_lurk"), "the creatures in it, not the one the DM hides: %s" % [ids])
	var dm := WebScene.build(st, sc.id, "", true)
	check(str(dm.get("space", "")) == "mind" and (dm.tokens as Array).size() == 3 and (dm.tokens as Array).any(func(t: Dictionary) -> bool: return bool(t.get("hidden", false))), "the DM's: all three, the hidden one marked")
	check(not WebScene.build(st, "nope", "pl_1", false).has("space"), "no scene, nothing")
	# the rules measure nothing as near: far apart, no map to draw a template on
	var d := k.map.distance(sc.id, "token:t_hero", "token:t_gob")
	check(float(d.units) >= Encounter.MIND_GAP - 0.01 and int(d.cells) == -1, "two creatures in it are a gap apart, in no cells (%s)" % [d])
	check(k.map.within(sc.id, "token:t_hero", 60.0).is_empty(), "nobody is within 300 feet of anyone")
	check(str(k.map.template(sc.id, {"shape": "circle", "at": "token:t_gob", "radius": 4}).get("error", "")) == "no map", "an area has no map to fall on")
	check(k.map.line_of_sight(sc.id, "token:t_hero", "token:t_gob") is Dictionary and k.map.can_see(sc.id, "token:t_hero", "token:t_gob") is Dictionary, "sight asks no map, and nothing breaks")


## A Table on a campaign that plays sample.degrees (creatures to spawn) and
## sample.ordered (settings with the metadata), with a player's character.
func _table(dir: String, table: Dictionary = {}) -> TableWindow:
	if DirAccess.dir_exists_absolute(dir):
		PluginHost._rm_rf(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var app := App.new("user://test_prefs_table_mind.json")
	app.prefs.campaigns_dir = ProjectSettings.globalize_path(dir.path_join("campaigns"))
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	win.ctx.plugin_dirs = ["res://tests/plugins"]
	var c := Campaign.create("Mind")
	c.players.append({"id": "pl_1", "name": "Ana", "color": "#4f9cf6"})
	c.actors["a_h"] = {"id": "a_h", "kind": "pc", "name": "Hero Vale", "owner": "pl_1", "ext": {"sample.ordered": {"level": 2, "stats": {"agi": 2, "str": 1, "wit": 0}}}}
	c.plugins.append({"id": "sample.degrees"})
	c.plugins.append({"id": "sample.ordered"})
	if not table.is_empty():
		c.doc.table = table
	c.save(dir.path_join("mind.campaign"))
	win._open_path(dir.path_join("mind.campaign"))
	return win


func test_a_fight_in_the_theatre_of_the_mind() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var win := _table("user://table_mind_fight_test", {"level": "automated", "space": "per_fight"})
	await tree.process_frame
	var ctx := win.ctx
	var dm := win.web_dm
	# a fight made at the table with no map: where the table leaves it to each fight
	check(dm.op({"op": "new_fight", "id": "enc_bridge", "name": "On the bridge", "map": ""}) == "", "a fight with no map")
	var fe := ctx.campaign.encounter_entry("enc_bridge")
	check(str(fe.get("map", "x")) == "" and str(fe.get("level", "x")) == "", "made without a map or a level")
	check(dm.op({"op": "fight_add", "encounter": "enc_bridge", "collection": "creatures", "entry": "goblin", "name": "Goblin skirmisher", "count": 2, "hidden": false}) == "", "two goblins in it")
	var listed: Dictionary = (dm.state().encounters as Array).filter(func(x: Dictionary) -> bool: return str(x.id) == "enc_bridge")[0]
	check(str(listed.plays_in) == "mind" and str(listed.space) == "", "the DM's screen: with no map of its own it's fought in the mind (%s)" % str(listed.plays_in))
	check(int(ctx.host.plugins["sample.ordered"].settings.reach_checked) == 1 and not ctx.host.mind, "before it: the table's rules (reach checked)")
	var actors_before := ctx.encounter().actors.size()
	check(dm.op({"op": "launch", "encounter": "enc_bridge", "space": "mind"}) == "", "started in the theatre of the mind")
	fe = ctx.campaign.encounter_entry("enc_bridge")
	var live: Dictionary = fe.get("live", {})
	var sid := str(live.get("scene", ""))
	var sc := ctx.encounter().scene(sid)
	check(Encounter.is_mind(sc) and ctx.encounter().active_scene_id == sid and str(live.get("space", "")) == "mind", "a scene with no map, in front of everybody")
	check((live.get("actors", []) as Array).size() == 2 and ctx.encounter().actors.size() == actors_before + 2, "the two goblins made")
	var xs := []
	var hero := {}
	for tk in ctx.state.tokens(sid):
		xs.append(float(tk.pos[0]))
		if str(tk.get("actor", "")) == "a_h":
			hero = tk
	xs.sort()
	check(xs.size() == 3 and xs[0] >= Encounter.MIND_GAP - 0.01 and xs[1] - xs[0] >= Encounter.MIND_GAP - 0.01 and xs[2] - xs[1] >= Encounter.MIND_GAP - 0.01, "each far from the rest: %s" % [xs])
	check(not hero.is_empty() and str(hero.get("owner", "")) == "pl_1" and str(hero.get("label", "")) == "HV" and not bool(hero.get("hidden", true)), "the party with them: Ana's Hero, hers")
	check(ctx.host.mind and int(ctx.host.plugins["sample.ordered"].settings.reach_checked) == 0, "the rules loaded for the mind: reach not checked there (x-mind)")
	var reg := win.table_settings.registry()
	var reach := _find(reg, "reach_checked")
	check(reg.has("this_fight") and str(reg.this_fight.space) == "mind" and str(reg.this_fight.name) == "On the bridge" and int(reg.this_fight.differs) == 1, "Table settings: this fight is in the mind, and one setting differs for it")
	check(reach.value == true and reach.fight_value == false and str(reach.fight_why) == "mind" and str(reach.fight_words) == "Off", "Check reach: the table's On, this fight's Off (the theatre of the mind)")
	check(not reg.customized, "the table itself is as its level has it")
	check(TableSettings.this_fight_words(reg) == "This fight (On the bridge, in the theatre of the mind) runs otherwise: 1 setting differs for it, and only while it runs.", "said: %s" % TableSettings.this_fight_words(reg))
	win.open_table_settings()
	await tree.process_frame
	var dlg := win._settings_dialog
	var reach_row: Node = dlg._body.find_child("Setting_reach_checked", true, false) if dlg != null else null
	check(dlg != null and dlg._body.find_child("FightNote", true, false) != null, "Table settings on the Table says it too")
	check(reach_row != null and _texts(reach_row).contains("this fight: Off (the theatre of the mind: yours to judge)"), "beside Check reach: %s" % (_texts(reach_row) if reach_row != null else ""))
	if dlg != null:
		dlg._close()
	await tree.process_frame
	# (the DM's list says what the players see of a monster's health, as the rules declare it: none do here)
	check(dm.state().has("players_see_health") and str(dm.state().players_see_health) == "", "what the players see of health, for the DM's list (no ruleset here says)")
	# the players' screens: who's in it, no map — the goblins once the DM reveals them
	check(str(WebScene.build(ctx.state, sid, "pl_1", false).get("space", "")) == "mind" and (WebScene.build(ctx.state, sid, "pl_1", false).tokens as Array).size() == 1, "a player's screen: the hero, the goblins still hidden")
	for tk in ctx.state.tokens(sid):
		if bool(tk.get("hidden", false)):
			dm.op({"op": "token", "scene": sid, "id": str(tk.id), "hidden": false})
	var sent := WebScene.build(ctx.state, sid, "pl_1", false)
	check(str(sent.get("space", "")) == "mind" and (sent.tokens as Array).size() == 3, "revealed: a player's screen lists the three")
	# a creature into the fight: no token to put down
	check(dm.op({"op": "fight_join", "entry": "wolf", "name": "Wolf", "count": 1, "hidden": true}) == "", "a wolf joins the fight")
	live = ctx.campaign.encounter_entry("enc_bridge").live
	var wolf := ctx.state.tokens(sid).filter(func(t: Dictionary) -> bool: return str(t.get("name", "")) == "Wolf")
	check(wolf.size() == 1 and bool(wolf[0].hidden) and float(wolf[0].pos[0]) >= xs[2] + Encounter.MIND_GAP - 0.01 and (live.actors as Array).size() == 3, "far past the rest, hidden as asked, and the fight's own")
	check(not ctx.host.mind or win.maps.join_fight({"collection": "creatures", "id": "nobody", "name": "Nobody"}) != "", "a creature the compendium hasn't: said")
	# the end: the rules as the table has them again
	check(dm.op({"op": "end_fight"}) == "", "ended")
	check(ctx.encounter().scene(sid).is_empty() and ctx.encounter().actors.size() == actors_before and not ctx.campaign.encounter_entry("enc_bridge").has("live"), "its scene and its creatures gone; the party stays")
	check(not ctx.host.mind and int(ctx.host.plugins["sample.ordered"].settings.reach_checked) == 1 and not win.table_settings.registry().has("this_fight"), "the table's rules again")
	check(dm.op({"op": "fight_join", "entry": "wolf"}) == "no fight is running", "no fight, nobody joins")
	# on a table whose fights are on maps: a fight needs its map
	check(win.table_settings.set_table({"space": "maps"}) == "", "fights on maps")
	check(dm.op({"op": "new_fight", "id": "enc_x", "name": "X", "map": ""}).begins_with("choose a map"), "a new one needs a map")
	check(win.maps.launch("enc_bridge").contains("has no map"), "and one without can't start on a map: %s" % win.maps.launch("enc_bridge"))
	# on a table whose fights are all in the mind: every fight is, its map or not
	check(win.table_settings.set_table({"space": "mind"}) == "", "fights in the mind")
	check(TableSettings.fight_space(ctx.campaign, {"map": "m_1", "space": "maps"}) == "mind" and TableSettings.fight_space(ctx.campaign, {}, "maps") == "mind", "every fight, whatever it or the DM asks")
	win.table_settings.set_table({"space": "per_fight"})
	check(TableSettings.fight_space(ctx.campaign, {"map": "m_1"}) == "maps" and TableSettings.fight_space(ctx.campaign, {"map": "m_1", "space": "mind"}) == "mind"
		and TableSettings.fight_space(ctx.campaign, {"map": "m_1", "space": "mind"}, "maps") == "maps", "each fight decides: its own, the DM's at the start over it, its map otherwise")
	win.queue_free()
	await tree.process_frame


func test_a_fights_own_settings() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var win := _table("user://table_mind_settings_test", {"level": "automated", "space": "per_fight"})
	await tree.process_frame
	var ctx := win.ctx
	var ts := win.table_settings
	var mp := win.maps
	check(mp.add_map(TestCase.example("ruined_chapel.hexmap")) == "", "the chapel in the library")
	var mid := str(ctx.campaign.maps[0].id)
	var enc := mp.new_encounter("The nave", mid, "ground")
	check(TableSettings.fight_space(ctx.campaign, ctx.campaign.encounter_entry(enc)) == "maps", "a fight with a map: on its map unless the DM says")
	# its own settings, kept on it, each a step of the Table's undo
	var depth := ctx.history.undo_depth()
	check(ts.set_fight(enc, {"settings": {"sample.ordered/armour_reduces": 0}}) == "", "this fight: armour takes nothing off")
	check(int(ctx.campaign.encounter_entry(enc).settings["sample.ordered/armour_reduces"]) == 0 and ctx.history.undo_depth() == depth + 1, "kept on the fight, one undo step: %s" % ctx.history.undo_label())
	check(int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 2, "not running: the rules as the table has them")
	check(ts.set_fight(enc, {"settings": {"sample.ordered/critical_on": 19}}).contains("the table's, not one fight's"), "a rules option is the table's alone")
	check(ts.set_fight(enc, {"settings": {"sample.ordered/armour_reduces": "lots"}}).ends_with("a number"), "a value its schema refuses")
	check(ts.set_fight(enc, {"settings": {"nobody/x": 1}}).begins_with("no setting"), "a setting not here")
	check(ts.set_fight(enc, {"space": "the moon"}) != "" and ts.set_fight("enc_nope", {"space": "mind"}) == "no such fight", "a place a fight can't be, a fight that isn't")
	check(ts.set_fight(enc, {"space": "mind"}) == "" and str(ctx.campaign.encounter_entry(enc).space) == "mind" and TableSettings.fight_space(ctx.campaign, ctx.campaign.encounter_entry(enc)) == "mind", "the DM prepares it for the mind")
	ctx.history.undo()
	check(not ctx.campaign.encounter_entry(enc).has("space") and int(ctx.campaign.encounter_entry(enc).settings["sample.ordered/armour_reduces"]) == 0, "undone: on its map again, its own setting kept")
	# the Table's Maps pane: where it's fought (the table leaves it to each fight), and its settings
	mp.selected_enc = enc
	mp._show_encounter()
	check(mp._space_row.visible and mp._space.visible and str(mp._space.get_item_metadata(mp._space.selected)) == "maps", "the Maps pane offers where it's fought: on its map")
	check(mp._fight_settings.text == "This fight's settings (1 of its own)…", "and its settings: %s" % mp._fight_settings.text)
	mp._fight_settings_dialog()
	await tree.process_frame
	var dlg := mp.find_child("FightSettings", true, false)
	check(dlg != null and dlg.find_child("Fight_armour_reduces", true, false) != null and dlg.find_child("Fight_reach_checked", true, false) != null and dlg.find_child("Fight_critical_on", true, false) == null,
		"its dialog: the settings a fight may have of its own, not the rules options")
	if dlg != null:
		var cb := (dlg.find_child("Fight_armour_reduces", true, false) as Node).get_child(0) as CheckBox
		check(cb != null and cb.button_pressed, "this fight's own is ticked")
		dlg.queue_free()
	# running: the rules with its own; Table settings says it differs
	check(mp.launch(enc) == "", "started on its map")
	check(int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 0 and not ctx.host.mind, "the rules with this fight's own: armour takes nothing off")
	var reg := ts.registry()
	var armour := _find(reg, "armour_reduces")
	check(str(reg.this_fight.space) == "maps" and int(reg.this_fight.differs) == 1 and int(armour.value) == 2 and int(armour.fight_value) == 0 and str(armour.fight_why) == "fight", "Table settings: the table's 2, this fight's own 0")
	check(not reg.customized and int(_find(reg, "reach_checked").get("fight_value", -1)) == -1, "the table unchanged; reach as the table has it on a map")
	check(win.web_dm.op({"op": "fight_set", "encounter": enc, "settings": {"sample.ordered/armour_reduces": null, "sample.ordered/reach_checked": false}}) == "", "the DM's screen: armour as the table has it, reach unchecked")
	check(int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 2 and int(ctx.host.plugins["sample.ordered"].settings.reach_checked) == 0, "the rules follow at once")
	check(str(_find(ts.registry(), "reach_checked").fight_why) == "fight", "Table settings follows")
	check(win.web_dm.op({"op": "fight_set", "encounter": enc, "space": "mind"}) == "" and Encounter.is_mind(ctx.encounter().active_scene()) == false, "where it's fought changes the next start, not this one")
	ctx.history.undo()
	check(int(ctx.host.plugins["sample.ordered"].settings.reach_checked) == 0 and not ctx.campaign.encounter_entry(enc).has("space"), "undo takes back the newest")
	ctx.history.undo()
	check(int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 0 and int(ctx.host.plugins["sample.ordered"].settings.reach_checked) == 1, "and the one before: its own armour again, reach checked")
	check(mp.return_from(enc) == "", "ended")
	check(int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 2 and not ts.registry().has("this_fight"), "its own end with it")
	check(int(ctx.campaign.encounter_entry(enc).settings["sample.ordered/armour_reduces"]) == 0, "and stay on it for next time")
	win.queue_free()
	await tree.process_frame


## Suggest how to run it, in the package release dialog: a level, where
## fights happen and a note, opened on what the campaign suggested last,
## kept on the campaign and carried by the package as `recommended` (what
## the walkthrough offers); no level and no place, nothing suggested.
func test_the_release_dialog_suggests_how_to_run_it() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var home := "user://table_release_suggest_test"
	if DirAccess.dir_exists_absolute(home):
		PluginHost._rm_rf(home)
	DirAccess.make_dir_recursive_absolute(home.path_join("author"))
	var author := Campaign.create("The Test Hall")
	author.plugins.append({"id": "sample.ordered"})
	author.doc.table = {"level": "automated"}
	author.doc.meta.recommended = {"level": "assisted", "note": "Old words.", "answers": {"sample.ordered/armour_reduces": 1}}
	check(author.save(home.path_join("author/hall.campaign")) == OK, "an author's campaign")
	var win := TableWindow.new()
	win.app = App.new("user://test_prefs_release_suggest.json")
	win.app.prefs.campaigns_dir = ProjectSettings.globalize_path(home.path_join("campaigns"))
	root.add_child(win)
	win.ctx.plugin_dirs = ["res://tests/plugins"]
	win._open_campaign_path(home.path_join("author/hall.campaign"))
	await tree.process_frame
	check(win.ctx.campaign != null and win.ctx.campaign.name == "The Test Hall", "open on the Table")
	var pkg := home.path_join("hall.campaignpkg")
	var d := win.release_dialog(pkg, "1.0.0", "First release.")
	var sug := d.find_child("Suggestion", true, false) as PropertyForm
	check(sug != null and str(sug.get_values().level) == "assisted" and str(sug.get_values().space) == "" and str(sug.get_values().note) == "Old words.",
		"Suggest how to run it opens on what the campaign suggested: %s" % [sug.get_values() if sug != null else {}])
	sug.set_values({"level": "rolling", "space": "mind", "note": "Short fights, told."})
	d.confirmed.emit()
	await tree.process_frame
	var info := CampaignPackage.read(pkg)
	check(info.ok if info.has("ok") else not info.is_empty(), "released")
	var rec: Dictionary = info.get("recommended", {})
	check(str(rec.get("level", "")) == "rolling" and str(rec.get("space", "")) == "mind" and str(rec.get("note", "")) == "Short fights, told."
		and int((rec.get("answers", {}) as Dictionary).get("sample.ordered/armour_reduces", 0)) == 1 and (rec.get("answers", {}) as Dictionary).size() == 1,
		"its package.json carries the suggestion, the settings it suggested kept: %s" % [rec])
	check(CampaignPackage.suggestion_of(win.ctx.campaign).get("level", "") == "rolling", "and the campaign keeps it for the next release")
	# no level and no place: the next release suggests nothing
	var r := win.release_with(pkg, {"notes": "Second", "level": "", "space": "", "note": "words alone"})
	check(r.ok and (CampaignPackage.read(pkg).recommended as Dictionary).is_empty() and not (win.ctx.campaign.doc.meta as Dictionary).has("recommended"), "No suggestion: none carried, none kept")
	win.queue_free()
	await tree.process_frame
	PluginHost._rm_rf(home)


func test_a_package_suggests_how_its_table_runs() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	check(CampaignPackage.clean_recommended({"level": "assisted", "space": 3, "answers": {"a/b": true, "c/d": {"x": 1}}, "note": "  Why.  "}) == {"level": "assisted", "answers": {"a/b": true}, "note": "Why."},
		"a suggestion kept as the package carries it: %s" % [CampaignPackage.clean_recommended({"level": "assisted", "space": 3, "answers": {"a/b": true, "c/d": {"x": 1}}, "note": "  Why.  "})])
	check(CampaignPackage.clean_recommended("assisted").is_empty() and CampaignPackage.clean_recommended({"note": "only words"}).is_empty(), "nothing to suggest, nothing kept")
	var home := "user://table_mind_pkg_test"
	if DirAccess.dir_exists_absolute(home):
		PluginHost._rm_rf(home)
	DirAccess.make_dir_recursive_absolute(home.path_join("author"))
	var author := Campaign.create("The Test Hall")
	author.plugins.append({"id": "sample.ordered"})
	author.doc.table = {"level": "automated"}
	author.doc.meta.recommended = {"level": "bookkeeping", "space": "per_fight", "note": "The hall's fights are short; the maze is better told.",
		"answers": {"sample.ordered/armour_reduces": 1, "sample.ordered/nope": 3, "sample.ordered/critical_on": 99}}
	check(author.save(home.path_join("author/hall.campaign")) == OK, "an author's campaign with a suggestion")
	var pkg := home.path_join("hall.campaignpkg")
	check(CampaignPackage.export_from(author, pkg, {"plugin_dirs": ["res://tests/plugins"]}).ok, "packaged")
	var info := CampaignPackage.read(pkg)
	check(str(info.recommended.level) == "bookkeeping" and str(info.manifest.recommended.space) == "per_fight" and (info.recommended.answers as Dictionary).size() == 3, "its manifest carries the suggestion")
	var other := home.path_join("other.campaignpkg")
	check(CampaignPackage.export_from(author, other, {"plugin_dirs": ["res://tests/plugins"], "recommended": {"level": "automated", "space": "maps"}}).ok
		and str(CampaignPackage.read(other).recommended.level) == "automated", "an export may say another")
	var win := TableWindow.new()
	win.app = App.new("user://test_prefs_table_mind_pkg.json")
	win.app.prefs.campaigns_dir = ProjectSettings.globalize_path(home.path_join("campaigns"))
	root.add_child(win)
	win.ctx.plugin_dirs = []
	win._start_package(pkg, info, "Mine")
	await tree.process_frame
	var c := win.ctx.campaign
	check(c != null and str(c.doc.package.recommended.level) == "bookkeeping", "the campaign started from it keeps the suggestion")
	var reg := win.table_settings.registry()
	var rec: Dictionary = reg.get("recommended", {})
	check(str(rec.get("level", "")) == "bookkeeping" and str(rec.get("space", "")) == "per_fight" and rec.get("answers", {}) == {"sample.ordered/armour_reduces": 1},
		"what this table knows of it: the level, the place, the one answer its schema allows: %s" % [rec])
	check(str(rec.get("words", "")) == "The author suggests Bookkeeping, each fight decides, 1 setting of their own." and str(rec.get("by", "")) == "The Test Hall", "said: %s" % str(rec.get("words", "")))
	check(win.web_dm.state().table.recommended.level == "bookkeeping", "the DM's web screen has it")
	var w := win._walkthrough
	check(w != null and w.draft.level == "bookkeeping" and w.draft.space == "per_fight" and int(w.draft.values["sample.ordered/armour_reduces"]) == 1, "the walkthrough offers it, chosen until the DM says otherwise")
	if w != null:
		check(w.suggestion().begins_with("The author suggests Bookkeeping, each fight decides, 1 setting of their own for The Test Hall. The hall's fights are short") and w.suggestion().ends_with("only a suggestion: choose what suits your table."),
			"in words: %s" % w.suggestion())
		check(w._body.find_child("Suggestion", true, false) != null, "where fights happen says it")
		w.choose_level("automated")
		w.next()
		check(w.step_name() == "level" and w._body.find_child("Suggestion", true, false) != null and (w._body.find_child("Level_automated", true, false) as Button).button_pressed, "the DM chooses otherwise: it's only a suggestion")
	check(win.web_dm.op({"op": "table_setup", "level": "automated", "space": "maps"}) == "", "the DM's answers, not the author's")
	check(str(c.doc.table.level) == "automated" and str(c.doc.table.space) == "maps" and not win.table_settings.registry().customized, "set up as the DM said")
	win.queue_free()
	await tree.process_frame
	PluginHost._rm_rf(home)
