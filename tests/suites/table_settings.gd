extends TestCase
## How a table runs (TableSettings): the DM, not the app, decides how much
## the app does. The model made from the plugins' metadata (x-question,
## x-levels, x-notice, x-next-fight), a level applied as one undoable step,
## "Customized" and a section reset, the preview of a level switch, a
## campaign from before levels running as Automated, the walkthrough a new
## campaign opens with (and one started from a package), Table settings on
## the Table, the DM's web screen's operations, and what the players are told.


## A ruleset's settings with the metadata, and some without or wrong.
func _manifest() -> Dictionary:
	return {"id": "test.rules", "version": "1.0.0", "api": 1, "name": "Test rules", "settings": {
		"schema": {"type": "object", "properties": {
			"auto_hit": {"type": "boolean", "title": "Apply a hit at once", "x-question": "outcomes",
				"x-levels": {"bookkeeping": false, "rolling": false, "assisted": true, "automated": true}, "x-notice": "everyone"},
			"who_rolls": {"type": "string", "enum": ["app", "players"], "enumNames": ["The app rolls it", "The players roll it"], "title": "Initiative",
				"x-question": "dice", "x-levels": {"bookkeeping": "players", "rolling": "players", "automated": "app"}, "x-notice": "players", "x-next-fight": true},
			"wait": {"type": "integer", "minimum": 0, "maximum": 600, "title": "Seconds to answer", "description": "0: wait for ever",
				"x-question": "prompting", "x-levels": {"bookkeeping": 0, "rolling": 0, "assisted": 30, "automated": 30}, "x-notice": "players"},
			"edition": {"type": "string", "enum": ["2024", "2014"], "title": "Rules version", "x-question": "rules", "x-notice": "everyone"},
			"ask_dm": {"type": "boolean", "title": "Ask the DM first", "x-question": "prompting",
				"x-levels": {"bookkeeping": true, "rolling": true, "assisted": true, "automated": false}, "x-notice": "dm"},
			"odd": {"type": "boolean", "title": "Odd", "x-question": "nowhere", "x-levels": {"bookkeeping": "nope", "weird": true, "rolling": true}},
			"blob": {"type": "object", "title": "Not shown"}}},
		"defaults": {"auto_hit": true, "who_rolls": "app", "wait": 30, "edition": "2024", "ask_dm": false, "odd": false}}}


func _find(reg: Dictionary, key: String) -> Dictionary:
	for it in reg.get("settings", []):
		if str(it.key) == key:
			return it
	return {}


func test_the_registry_from_a_plugins_metadata() -> void:
	var m := _manifest()
	var values := {"auto_hit": true, "who_rolls": "app", "wait": 30.0, "edition": "2024", "ask_dm": false, "odd": false}
	var reg := TableSettings.build([{"id": "test.rules", "name": "Test rules", "manifest": m, "values": values}], {})
	check(reg.level == TableSettings.EXISTING_LEVEL and reg.level == "automated" and not reg.level_set, "a campaign with no level runs as Automated, and says it chose none")
	check(not reg.customized and int(reg.differs) == 0, "today's values are Automated's: nothing differs")
	check((reg.settings as Array).size() == 6 and _find(reg, "blob").is_empty(), "every setting a screen can show, an object's left out")
	var hit := _find(reg, "auto_hit")
	check(hit.question == "outcomes" and hit.notice == "everyone" and hit.levels.bookkeeping == false and hit.levels.automated == true and hit.id == "test.rules/auto_hit", "a switch: its question, who notices, each level's value")
	var who := _find(reg, "who_rolls")
	check(who.question == "dice" and who.next_fight and who.notice == "players" and not (who.levels as Dictionary).has("assisted") and who.labels == ["The app rolls it", "The players roll it"], "a choice: its labels, waits for the next fight, a level that leaves it alone")
	var wait := _find(reg, "wait")
	check(wait.type == "integer" and int(wait.minimum) == 0 and int(wait.maximum) == 600 and wait.levels.bookkeeping is int and wait.description == "0: wait for ever", "a number: its bounds and words")
	var ed := _find(reg, "edition")
	check(ed.question == "rules" and (ed.levels as Dictionary).is_empty(), "a rules option follows no level")
	var odd := _find(reg, "odd")
	check(odd.question == "rules" and odd.notice == "" and odd.levels.keys() == ["rolling"], "an unknown question is a rules option; a level value the schema refuses, and a level that isn't one, are left out")
	var qs := {}
	for q in reg.questions:
		qs[str(q.id)] = q
	check(reg.questions.size() == TableSettings.QUESTIONS.size() and qs.dice.settings == ["test.rules/who_rolls"] and qs.prompting.settings.size() == 2 and bool(qs.outcomes.level) and not bool(qs.rules.level), "the questions, each with its settings; the ones a level answers marked")
	check(reg.levels.size() == 4 and str(reg.levels[2].id) == "assisted" and (reg.levels[2].lines as Array).size() == 3, "four levels, three lines each")
	check(reg.space == "maps" and reg.house_rules == "" and not reg.pending, "on maps by default, no house rules, nothing waiting")
	# a level chosen: what differs from it is "Customized"
	var bk := TableSettings.build([{"id": "test.rules", "name": "Test rules", "manifest": m, "values": values}], {"level": "bookkeeping", "space": "mind", "house_rules": "Potions as a bonus action"})
	check(bk.level == "bookkeeping" and bk.level_set and bk.customized and int(bk.differs) == 4, "Bookkeeping chosen, today's values kept: 4 settings differ (%d)" % int(bk.differs))
	check(bool(_find(bk, "auto_hit").differs) and not bool(_find(bk, "edition").differs) and _find(bk, "auto_hit").level_value == false, "each says whether it differs, and the level's value")
	check(bk.space == "mind" and bk.house_rules == "Potions as a bonus action", "the table's own fields")
	check(TableSettings.build([], {"level": "chaos", "space": "moon"}).level == "automated" and TableSettings.build([], {"space": "moon"}).space == "maps", "a level or a place it doesn't know is the default")
	check(TableSettings.build([], {"setup": "pending"}).pending, "a campaign whose walkthrough waits says so")


func test_the_preview_of_a_level_switch() -> void:
	var m := _manifest()
	var values := {"auto_hit": true, "who_rolls": "app", "wait": 30, "edition": "2024", "ask_dm": false, "odd": false}
	var reg := TableSettings.build([{"id": "test.rules", "name": "Test rules", "manifest": m, "values": values}], {})
	var to_bk := TableSettings.changes_for_level(reg, "bookkeeping")
	check(to_bk.size() == 4, "Automated to Bookkeeping: four settings change (%d; Odd's Bookkeeping value is not one it takes)" % to_bk.size())
	var by_key := {}
	for ch in to_bk:
		by_key[str(ch.key)] = ch
	check(by_key.auto_hit.from_words == "On" and by_key.auto_hit.to_words == "Off" and by_key.who_rolls.to_words == "The players roll it" and by_key.wait.to_words == "0", "each change in words: %s" % [to_bk.map(func(c: Dictionary) -> String: return "%s %s→%s" % [c.key, c.from_words, c.to_words])])
	check(bool(by_key.who_rolls.next_fight) and str(by_key.who_rolls.notice) == "players", "and whether it waits for the next fight, and who notices")
	var words := TableSettings.change_words(to_bk)
	check(words.begins_with("4 settings change: ") and words.contains("Apply a hit at once (On → Off)"), "said in a sentence: %s" % words)
	var to_assisted := TableSettings.changes_for_level(reg, "assisted")
	check(to_assisted.size() == 1 and str(to_assisted[0].key) == "ask_dm", "to Assisted: only what Assisted names and differs (Initiative is left alone)")
	check(TableSettings.change_words([]).begins_with("Nothing changes"), "and nothing to change is said too")
	check(TableSettings.change_words(to_assisted).begins_with("1 setting changes: "), "one change reads as one")


func test_values_are_checked_against_their_schema() -> void:
	var reg := TableSettings.build([{"id": "test.rules", "name": "T", "manifest": _manifest(), "values": {}}], {})
	var wait := _find(reg, "wait")
	check(TableSettings.check_value(wait, 30.0) == ["", 30] and TableSettings.check_value(wait, 30.0)[1] is int, "a whole number comes as an int")
	check(str(TableSettings.check_value(wait, 601)[0]) == "Seconds to answer: at most 600", "too many: %s" % str(TableSettings.check_value(wait, 601)[0]))
	check(str(TableSettings.check_value(wait, -1)[0]).ends_with("at least 0"), "too few")
	check(str(TableSettings.check_value(wait, 2.5)[0]).ends_with("a whole number"), "not whole")
	check(str(TableSettings.check_value(wait, "lots")[0]).ends_with("a number"), "not a number")
	check(str(TableSettings.check_value(_find(reg, "auto_hit"), 1)[0]).ends_with("on or off"), "a switch is on or off")
	check(str(TableSettings.check_value(_find(reg, "who_rolls"), "dm")[0]).ends_with("not one of the choices"), "a choice is one of its choices")
	check(TableSettings.value_words(_find(reg, "who_rolls"), "players") == "The players roll it" and TableSettings.value_words(wait, 30.0) == "30", "values in words: a choice's label, a number without .0")
	var problems := TableSettings.check_manifest(_manifest())
	check(problems.size() == 3, "the metadata's mistakes, each said: %s" % [problems])
	check(problems.any(func(p: String) -> bool: return p.contains("x-question 'nowhere'")) and problems.any(func(p: String) -> bool: return p.contains("'weird'")) and problems.any(func(p: String) -> bool: return p.contains("bookkeeping value")), "an unknown question, an unknown level, a level value the schema refuses")
	var fine := TableSettings.check_manifest(JsonDoc.parse(FileAccess.get_file_as_string("res://tests/plugins/sample.ordered/manifest.json")))
	check(fine.is_empty(), "the reference plugin's metadata is right: %s" % [fine])


## A Table with sample.ordered (its settings carry the metadata), on a
## campaign that may or may not say how the table runs.
func _table(dir: String, table: Dictionary = {}, list_plugin := true) -> TableWindow:
	DirAccess.make_dir_recursive_absolute(dir)
	var app := App.new("user://test_prefs_table_settings.json")
	app.prefs.campaigns_dir = ProjectSettings.globalize_path(dir.path_join("campaigns"))
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	win.ctx.plugin_dirs = ["res://tests/plugins"]
	var c := Campaign.create("Settings")
	c.players.append({"id": "pl_1", "name": "Ana", "color": "#4f9cf6"})
	c.actors["a_h"] = {"id": "a_h", "kind": "pc", "name": "Hero", "owner": "pl_1", "ext": {"sample.ordered": {"level": 2, "stats": {"agi": 2, "str": 1, "wit": 0}}}}
	if list_plugin:
		c.plugins.append({"id": "sample.ordered"})
	if not table.is_empty():
		c.doc.table = table
	c.save(dir.path_join("settings.campaign"))
	win._open_path(dir.path_join("settings.campaign"))
	return win


func test_a_level_applied_as_one_undoable_step() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var win := _table("user://table_settings_level_test")
	await tree.process_frame
	var ctx := win.ctx
	var ts := win.table_settings
	var reg := ts.registry()
	check(reg.level == "automated" and not reg.level_set and not reg.customized, "a campaign from before levels: Automated, nothing differs")
	check(_find(reg, "armour_reduces").question == "outcomes" and _find(reg, "critical_on").question == "rules", "the reference plugin's settings by their questions")
	var depth := ctx.history.undo_depth()
	check(ts.set_level("bookkeeping") == "", "Bookkeeping picked")
	check(int(ctx.campaign.plugin_settings("sample.ordered").armour_reduces) == 0 and str(ctx.campaign.doc.table.level) == "bookkeeping", "its values written into the campaign, and the level")
	check(int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 0, "the rules loaded again with them")
	check(not ctx.campaign.plugin_settings("sample.ordered").has("critical_on"), "a rules option is left as it was")
	check(ctx.history.undo_depth() == depth + 1 and ctx.history.undo_label() == "Table level: Bookkeeping", "as one step of the Table's undo: %s" % ctx.history.undo_label())
	reg = ts.registry()
	check(reg.level == "bookkeeping" and reg.level_set and not reg.customized and reg.undo == "Table level: Bookkeeping", "running at Bookkeeping, as Bookkeeping has it")
	ctx.history.undo()
	reg = ts.registry()
	check(reg.level == "automated" and not reg.level_set and not ctx.campaign.plugin_settings("sample.ordered").has("armour_reduces") and int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 2, "undone: as it was, the default in force again")
	check(str(reg.undo) == "", "and nothing left for the web screen's Undo")
	ctx.history.redo()
	check(ts.registry().level == "bookkeeping" and int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 0, "redone")
	# Customized, and a section back to the level
	check(win.web_dm.op({"op": "rules_setting", "plugin": "sample.ordered", "key": "armour_reduces", "value": 3}) == "", "a setting changed by hand")
	reg = ts.registry()
	check(reg.customized and int(reg.differs) == 1 and bool(_find(reg, "armour_reduces").differs) and ctx.history.undo_label().contains("3"), "Customized: one setting differs from Bookkeeping")
	check(ts.reset_question("rules").contains("nothing in Rules options follows the level"), "a section with nothing a level sets has nothing to reset")
	check(win.web_dm.op({"op": "table_reset", "question": "outcomes"}) == "", "What a roll does, back to Bookkeeping")
	reg = ts.registry()
	check(not reg.customized and int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 0 and ctx.history.undo_label() == "What a roll does back to Bookkeeping", "as the level has it again")
	# the preview of a switch, then the switch from the DM's screen, and its Undo there
	var changes := TableSettings.changes_for_level(reg, "assisted")
	check(changes.size() == 1 and str(changes[0].key) == "armour_reduces" and str(changes[0].to_words) == "2", "Bookkeeping to Assisted: one setting changes, 0 → 2")
	check(win.web_dm.op({"op": "table_level", "level": "assisted"}) == "" and ts.registry().level == "assisted", "switched from the DM's screen")
	check(win.web_dm.state().table.level == "assisted" and win.web_dm.state().table.undo == "Table level: Assisted", "the DM's screen has the model, and its Undo")
	check(win.web_dm.op({"op": "table_undo"}) == "" and ts.registry().level == "bookkeeping" and int(ctx.host.plugins["sample.ordered"].settings.armour_reduces) == 0, "Undo on the DM's screen: Bookkeeping again")
	check(ctx.history.undo_label() == "Undo Table level: Assisted", "and that too is a step of the Table's undo")
	# the table's own, and refusals that change nothing
	check(win.web_dm.op({"op": "table_set", "space": "mind", "house_rules": "Potions as a bonus action."}) == "", "where fights happen and the house rules")
	check(str(ctx.campaign.doc.table.space) == "mind" and str(ctx.campaign.doc.table.house_rules) == "Potions as a bonus action.", "kept in the campaign")
	check(ts.set_level("chaos").begins_with("which level?"), "a level that isn't one: refused")
	check(ts.set_table({"space": "the moon"}) != "" and str(ctx.campaign.doc.table.space) == "mind", "a place fights can't happen: refused")
	check(ts.set_table({"colour": "red"}).contains("no 'colour'"), "a field the table hasn't: refused")
	check(ts.set_setting("sample.ordered", "critical_on", 25).ends_with("at most 20") and ts.set_setting("nobody", "x", 1).contains("no ruleset"), "a value the schema refuses, a ruleset not here")
	check(ts.registry().level == "bookkeeping" and not ts.registry().customized, "and nothing changed by the refusals")
	win.queue_free()
	await tree.process_frame


## A campaign that names no rulesets plays every one installed: once a level
## writes settings it names them all, so the same rules load as before.
func test_a_level_keeps_every_ruleset_a_campaign_played() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var win := _table("user://table_settings_all_test", {}, false)
	await tree.process_frame
	var ctx := win.ctx
	var before := ctx.host.plugins.keys()
	before.sort()
	check(before.size() > 1 and ctx.campaign.plugin_order().is_empty(), "every ruleset here loads: %s" % [before])
	check(win.table_settings.set_level("rolling") == "", "Rolling help")
	var after := ctx.host.plugins.keys()
	after.sort()
	check(after == before and ctx.campaign.plugin_order().size() == before.size(), "the same rulesets load after it, each now named: %s" % [ctx.campaign.plugin_order()])
	win.queue_free()
	await tree.process_frame


func test_existing_campaigns_run_as_automated() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var c := Campaign.create("Old")
	check(TableSettings.level_of(c) == TableSettings.EXISTING_LEVEL and not TableSettings.pending(c) and TableSettings.table_of(c).is_empty(), "no table block: the one constant's level, nothing waiting")
	# one whose DM turned a rule off before levels: Automated, customized
	var dir := "user://table_settings_old_test"
	var win := _table(dir)
	await tree.process_frame
	win.ctx.campaign.set_plugin_setting("sample.ordered", "armour_reduces", 1)
	win.ctx.reload_plugins()
	var reg := win.table_settings.registry()
	check(reg.level == "automated" and not reg.level_set and reg.customized and int(reg.differs) == 1, "a setting changed before levels: Automated, Customized")
	check(win.table_settings.players_summary().title == "Automated" and not win.table_settings.players_summary().set, "and the players are told it runs Automated")
	check(not TableSettings.pending(win.ctx.campaign) and win._walkthrough == null, "and no walkthrough is offered: it was set up before levels")
	win.queue_free()
	await tree.process_frame


func test_the_walkthrough_on_a_new_campaign() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var c := Campaign.create("Fresh")
	TableSettings.mark_pending(c)
	check(TableSettings.pending(c), "a new campaign waits for its walkthrough")
	var win := _table("user://table_settings_walk_test", {"setup": "pending"})
	await tree.process_frame
	var w := win._walkthrough
	check(w != null and w.visible, "it opens with the campaign")
	if w == null:
		win.queue_free()
		return
	check(w.step_name() == "space" and w.draft.space == "maps", "first: where fights happen (maps unless the DM says)")
	w.choose_space("mind")
	w.next()
	check(w.step_name() == "level" and w.draft.level == "assisted", "then the level, Assisted offered first")
	check(w._body.find_child("Level_assisted", true, false) != null and (w._body.find_child("Level_assisted", true, false) as Button).button_pressed, "four cards, Assisted chosen until the DM says otherwise")
	w.choose_level("bookkeeping")
	check(int(w.draft.values["sample.ordered/armour_reduces"]) == 0, "Bookkeeping's values in the draft")
	w.next()
	check(w.step_name() == "questions" and w._body.find_child("Question_outcomes", true, false) != null, "the questions a level answers, each with its line")
	check(w.question_preview("outcomes") == "What a marked armour slot takes off a hit: 0", "the line says the answer: %s" % w.question_preview("outcomes"))
	w.opened = "outcomes"
	w._show()
	check(w._body.find_child("Setting_armour_reduces", true, false) != null, "Change opens the question's settings")
	w.set_value("sample.ordered/armour_reduces", 1)
	check(w.question_preview("outcomes").ends_with(": 1"), "a change says itself in the line")
	w.next()
	check(w.step_name() == "rules" and w._body.find_child("Setting_critical_on", true, false) != null and w._body.find_child("HouseRules", true, false) != null, "then the rules options and the house rules")
	w.set_house_rules("No flanking.")
	w.next()
	var summary := w.summary_text()
	check(w.step_name() == "summary" and summary.contains("How much the app does: Bookkeeping") and summary.contains("Where fights happen: In the theatre of the mind") and summary.contains("House rules: No flanking.") and summary.begins_with("Change any of this later in Table settings."), "a summary: %s" % summary)
	check(w._see_all.visible and w.get_ok_button().text == "Done", "with See every setting, and Done")
	var depth := win.ctx.history.undo_depth()
	w.next()
	await tree.process_frame
	var t: Dictionary = win.ctx.campaign.doc.table
	check(str(t.level) == "bookkeeping" and str(t.space) == "mind" and str(t.house_rules) == "No flanking." and not t.has("setup"), "done: the table set up as answered")
	check(int(win.ctx.campaign.plugin_settings("sample.ordered").armour_reduces) == 1, "the DM's own answer over the level's")
	check(win.ctx.history.undo_depth() == depth + 1 and win.ctx.history.undo_label() == "Set up the table: Bookkeeping", "one step of the Table's undo")
	check(win._walkthrough == null and win.table_settings.registry().customized, "the walkthrough gone; one setting is the DM's own: Customized")
	win.ctx.history.undo()
	check(not win.ctx.campaign.doc.table.has("level") and not TableSettings.pending(win.ctx.campaign) and not win.ctx.campaign.plugin_settings("sample.ordered").has("armour_reduces"), "undone: the settings as they were, and the walkthrough not asked again")
	win.queue_free()
	await tree.process_frame


## Starting an adventure is starting a campaign: its walkthrough opens; a
## harness that only hosts it can leave it as from before levels.
func test_the_walkthrough_when_a_package_starts() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var home := "user://table_settings_pkg_test"
	if DirAccess.dir_exists_absolute(home):
		PluginHost._rm_rf(home)
	DirAccess.make_dir_recursive_absolute(home.path_join("author"))
	var author := Campaign.create("The Test Hall")
	author.plugins.append({"id": "sample.ordered"})
	author.doc.table = {"level": "automated", "house_rules": "The author's"}
	check(author.save(home.path_join("author/hall.campaign")) == OK, "an author's campaign")
	var pkg := home.path_join("hall.campaignpkg")
	var made := CampaignPackage.export_from(author, pkg, {"plugin_dirs": ["res://tests/plugins"]})
	check(made.ok, "packaged: %s" % str(made.get("why", "")))
	var win := TableWindow.new()
	win.app = App.new("user://test_prefs_table_settings_pkg.json")
	win.app.prefs.campaigns_dir = ProjectSettings.globalize_path(home.path_join("campaigns"))
	root.add_child(win)
	win.ctx.plugin_dirs = []
	win._start_package(pkg, CampaignPackage.read(pkg), "Mine")
	await tree.process_frame
	check(win.ctx.campaign != null and TableSettings.pending(win.ctx.campaign) and win._walkthrough != null, "started: the walkthrough opens with it")
	check(win._walkthrough != null and win._walkthrough.draft.house_rules == "The author's" and win._walkthrough.draft.level == "assisted", "the package's house rules offered; Assisted offered, not the author's level")
	check(win.web_dm.state().table.pending, "and the DM's web screen offers it too")
	# finished on the DM's web screen: the Table's window goes
	check(win.web_dm.op({"op": "table_setup", "level": "automated", "space": "per_fight"}) == "", "the walkthrough's answers from the DM's screen")
	check(win._walkthrough == null and not TableSettings.pending(win.ctx.campaign) and str(win.ctx.campaign.doc.table.space) == "per_fight", "set up; the Table's own window closed")
	win._start_package(pkg, CampaignPackage.read(pkg), "Hosted only", false)
	await tree.process_frame
	check(win.ctx.campaign.name == "Hosted only" and not TableSettings.pending(win.ctx.campaign) and win._walkthrough == null, "without the walkthrough: a campaign as from before levels")
	win.queue_free()
	await tree.process_frame
	PluginHost._rm_rf(home)


func test_table_settings_on_the_table() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var win := _table("user://table_settings_dialog_test", {"level": "assisted"})
	await tree.process_frame
	check(win.rules._table_line.text.begins_with("Assisted") and not win.rules._setup_button.visible, "the Rules pane says how the table runs: %s" % win.rules._table_line.text)
	win.open_table_settings()
	await tree.process_frame
	var d := win._settings_dialog
	check(d != null and d.visible and d.badge_text() == "As Assisted has it", "Table settings open: %s" % (d.badge_text() if d != null else ""))
	if d == null:
		win.queue_free()
		return
	check(d._body.find_child("Section_outcomes", true, false) != null and d._body.find_child("Section_rules", true, false) != null and d._body.find_child("Section_dice", true, false) == null, "sections by question, only those with settings (and the table's own)")
	check(d._body.find_child("Section_space", true, false) != null and d._body.find_child("HouseRules", true, false) != null, "where fights happen, and the house rules")
	d._search.text = "armour"
	d.refresh()
	check(d._body.find_child("Setting_armour_reduces", true, false) != null and d._body.find_child("Setting_critical_on", true, false) == null, "a search finds the setting it names")
	d._search.text = ""
	d.refresh()
	d.ask_level("bookkeeping")
	check(d.preview_text() == "Switch to Bookkeeping? 1 setting changes:\n   •  What a marked armour slot takes off a hit:  2 → 0", "a switch says what it changes before it does: %s" % d.preview_text())
	check(win.table_settings.registry().level == "assisted", "nothing changed yet")
	d.cancel_level()
	check(d.preview_text() == "" and win.table_settings.registry().level == "assisted", "Cancel: nothing")
	d.ask_level("bookkeeping")
	check(d.confirm_level() == "" and win.table_settings.registry().level == "bookkeeping", "Switch: Bookkeeping")
	await tree.process_frame
	check(d.badge_text() == "As Bookkeeping has it" and d._undo.visible and d._undo.text == "Undo: Table level: Bookkeeping", "the badge follows, with an Undo")
	check(win.table_settings.set_setting("sample.ordered", "armour_reduces", 4) == "", "a setting by hand")
	await tree.process_frame
	check(d.badge_text().begins_with("Customized: 1 setting differs from Bookkeeping"), "Customized: %s" % d.badge_text())
	var reset := d._body.find_child("Reset_outcomes", true, false) as Button
	check(reset != null and not reset.disabled and reset.text == "Reset to Bookkeeping", "its section offers Reset to Bookkeeping")
	if reset != null:
		reset.pressed.emit()
	await tree.process_frame
	check(not win.table_settings.registry().customized and d.badge_text() == "As Bookkeeping has it", "reset")
	check(d.save_house_rules("Rests take a night's sleep.") == "" and str(win.ctx.campaign.doc.table.house_rules) == "Rests take a night's sleep.", "the house rules kept")
	check(win.rules._table_line.text.begins_with("Bookkeeping"), "and the Rules pane follows: %s" % win.rules._table_line.text)
	var fm := win._menu("File")
	check(fm != null and not fm.is_item_disabled(fm.get_item_index(TableWindow.M_TABLE_SETTINGS)), "File → Table settings… while a campaign is open")
	# another campaign opens: the last one's window goes with it
	var other := Campaign.create("Other")
	other.plugins.append({"id": "sample.ordered"})
	other.save("user://table_settings_dialog_test/other.campaign")
	win._open_campaign_path("user://table_settings_dialog_test/other.campaign")
	await tree.process_frame
	check(win._settings_dialog == null and win.ctx.campaign.name == "Other" and win.table_settings.registry().level == "automated", "another campaign open: the last one's Table settings closed, this one's model in it")
	win.queue_free()
	await tree.process_frame


func test_players_are_told_how_the_table_runs() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var win := _table("user://table_settings_players_test", {"level": "bookkeeping", "space": "mind", "house_rules": "No flanking."})
	await tree.process_frame
	var ctx := win.ctx
	check(win.table_settings.set_level("bookkeeping") == "", "the level's values written")
	# a host that never listens: the projection a player's screen gets
	var host := HostSession.new(ctx.state, ctx.art)
	host.kernel = ctx.kernel
	host.plugins = ctx.host
	host.table_source = func() -> Dictionary: return win.table_settings.players_summary()
	var view := host.projection({"player": "pl_1", "role": Views.ROLE_PLAYER, "see_as": ""})
	var t: Dictionary = view.get("table", {})
	check(t.get("title", "") == "Bookkeeping" and (t.get("lines", []) as Array).size() == 3 and bool(t.get("set", false)), "the level in plain words, three lines")
	check(t.get("space_title", "") == "In the theatre of the mind" and t.get("house_rules", "") == "No flanking.", "where fights happen, and the house rules")
	var answers: Array = t.get("answers", [])
	check(answers.size() == 2 and str(answers[0].question) == "outcomes" and str(answers[1].question) == "rules", "the answers players notice, by question: %s" % [answers.map(func(a: Dictionary) -> String: return str(a.question))])
	check(str(answers[0].items[0].value) == "0" and str(answers[1].items[0].title) == "Natural roll that is a critical", "each with its value")
	var summary := TableSettings.player_summary(TableSettings.build([{"id": "test.rules", "name": "T", "manifest": _manifest(), "values": {}}], {}))
	var asked: Array = summary.answers.map(func(a: Dictionary) -> String: return str(a.question))
	check(not asked.has("table") and summary.answers.filter(func(a: Dictionary) -> bool: return a.items.any(func(i: Dictionary) -> bool: return str(i.title) == "Ask the DM first")).is_empty(), "what only the DM notices isn't said to the players")
	check(not summary.set and summary.title == "Automated" and not summary.pending, "a table set up before levels: Automated, nothing waiting (its players are told on joining)")
	var waiting := TableSettings.player_summary(TableSettings.build([{"id": "test.rules", "name": "T", "manifest": _manifest(), "values": {}}], {"setup": "pending"}))
	check(waiting.pending and not waiting.set, "a new table whose walkthrough waits: nothing to tell its players yet")
	check(not bool(t.get("pending", true)), "this one's set up")
	win.queue_free()
	await tree.process_frame


## What each player chooses for themselves (PlayerPrefs): a ruleset's
## preferences, offered while its settings say so (`x-when`); a player sets
## their own from their screen, within what the DM allows; the DM sees each
## player's and changes anyone's, one step of the Table's undo; the campaign
## keeps them on the player's record; a plugin reads them (hm.players.pref).
func test_players_preferences() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var win := _table("user://table_settings_prefs_test")
	await tree.process_frame
	var ctx := win.ctx
	var ts := win.table_settings
	var reg := ts.registry()
	var prefs: Array = reg.get("prefs", [])
	check(prefs.size() == 1 and str(prefs[0].id) == "sample.ordered/armour" and bool(prefs[0].offered) and prefs[0].labels == ["Ask me each time", "Always mark a slot", "Never: I'd rather keep it"], "the reference plugin's preference, offered (its armour takes something off a hit): %s" % [prefs])
	var players: Array = reg.get("players", [])
	check(players.size() == 1 and str(players[0].name) == "Ana" and str(players[0].values["sample.ordered/armour"]) == "ask" and not bool((players[0].own as Dictionary).get("sample.ordered/armour", false)), "Ana's: the default, not her own choice yet: %s" % [players])
	# Ana chooses from her screen (a host that never listens: the Table's own commands)
	var host := HostSession.new(ctx.state, ctx.art)
	host.kernel = ctx.kernel
	host.plugins = ctx.host
	host.table_source = func() -> Dictionary: return ts.players_summary()
	var ana := {"player": "pl_1", "role": Views.ROLE_PLAYER, "see_as": ""}
	var view := host.projection(ana)
	check((view.table.prefs as Array).size() == 1 and str(view.table.prefs[0].key) == "armour", "her screen is told what she may choose")
	check(host._handle_intent(ana, {"kind": "prefs", "plugin": "sample.ordered", "key": "armour", "value": "always"}) == "", "her choice taken")
	check(ctx.encounter().player("pl_1").get("prefs") == {"sample.ordered": {"armour": "always"}}, "kept on her record at the table: %s" % [ctx.encounter().player("pl_1").get("prefs")])
	check(str(ts.registry().players[0].values["sample.ordered/armour"]) == "always" and bool(ts.registry().players[0].own["sample.ordered/armour"]), "the DM's Table settings list it as hers")
	var plugin: PluginHost.Plugin = ctx.host.plugins["sample.ordered"]
	check(PlayerPrefs.value(ctx.encounter(), plugin.manifest, plugin.settings, "sample.ordered", "pl_1", "armour") == "always", "what the plugin reads (hm.players.pref)")
	check(host._handle_intent(ana, {"kind": "prefs", "plugin": "sample.ordered", "key": "armour", "value": "loudly"}).ends_with("not one of the choices"), "a value it can't be")
	check(host._handle_intent(ana, {"kind": "prefs", "plugin": "sample.ordered", "key": "colour", "value": "red"}).contains("no preference"), "a preference it doesn't have")
	check(PlayerPrefs.change(ctx.encounter(), ctx.host, "pl_1", "sample.ordered", "armour", "never", "pl_2", func(_e: Array, _l: String, _r: Dictionary) -> String: return "") == "your own preferences only", "nobody else's")
	check(host._handle_intent({"player": "", "role": Views.ROLE_DM, "see_as": ""}, {"kind": "prefs", "plugin": "sample.ordered", "key": "armour", "value": "never"}).contains("Table settings"), "the DM's are changed in Table settings")
	# the table stops offering it: Ana can't change it, the DM can, and it reads as the default
	check(ts.set_setting("sample.ordered", "armour_reduces", 0) == "", "armour takes nothing off a hit now")
	check(not bool(ts.registry().prefs[0].offered) and (ts.players_summary().prefs as Array).is_empty(), "not offered: her screen offers nothing")
	# (the rules loaded again with it: the host hears of them as the Table's does)
	host.plugins = ctx.host
	var refused := host._handle_intent(ana, {"kind": "prefs", "plugin": "sample.ordered", "key": "armour", "value": "never"})
	check(refused.ends_with("is the DM's to choose at this table"), "her change refused, saying why: %s" % refused)
	plugin = ctx.host.plugins["sample.ordered"]
	check(PlayerPrefs.value(ctx.encounter(), plugin.manifest, plugin.settings, "sample.ordered", "pl_1", "armour") == "ask", "and the plugin reads the default")
	var depth := ctx.history.undo_depth()
	check(win.web_dm.op({"op": "player_pref", "player": "pl_1", "plugin": "sample.ordered", "key": "armour", "value": "never"}) == "", "the DM changes it anyway, from the web screen")
	check(ctx.history.undo_depth() == depth + 1 and ctx.history.undo_label().begins_with("Ana: My armour"), "one step of the Table's undo: %s" % ctx.history.undo_label())
	check(ctx.encounter().player("pl_1").prefs["sample.ordered"]["armour"] == "never", "on her record")
	check(ts.set_pref("pl_9", "sample.ordered", "armour", "never") == "no such player", "a player who isn't here")
	check(ts.set_setting("sample.ordered", "armour_reduces", 2) == "", "armour back")
	# the campaign keeps it with the player
	ctx.campaign.capture(ctx.encounter())
	check(ctx.campaign.player("pl_1").get("prefs") == {"sample.ordered": {"armour": "never"}}, "the campaign's player record keeps it: %s" % [ctx.campaign.player("pl_1").get("prefs")])
	# the Table's own window lists it, the DM's to change
	win.open_table_settings()
	await tree.process_frame
	var d := win._settings_dialog
	check(d != null and d._body.find_child("Section_prefs", true, false) != null and d._body.find_child("Pref_pl_1_armour", true, false) != null, "Table settings on the Table: Players' preferences, Ana's row")
	win.queue_free()
	await tree.process_frame


func test_preferences_metadata_is_checked() -> void:
	var m := {"id": "test.rules", "version": "1.0.0", "api": 1, "name": "T", "settings": {"schema": {"type": "object", "properties": {
		"dice": {"type": "string", "enum": ["app", "typed", "choice"], "title": "Dice", "x-question": "dice"}}}, "defaults": {"dice": "app"}},
		"preferences": {"schema": {"type": "object", "properties": {
			"mine": {"type": "string", "enum": ["app", "typed"], "title": "My dice", "x-when": {"dice": "choice"}},
			"lost": {"type": "boolean", "title": "Lost", "x-when": {"nothing": true}},
			"blob": {"type": "object", "title": "Blob"},
			"wrong": {"type": "string", "enum": ["a", "b"], "title": "Wrong"}}},
			"defaults": {"mine": "app", "lost": true, "wrong": "c"}}}
	var problems := PlayerPrefs.check_manifest(m)
	check(problems.size() == 3, "three mistakes said: %s" % [problems])
	check(problems.any(func(p: String) -> bool: return p.contains("'nothing'")) and problems.any(func(p: String) -> bool: return p.contains("'blob'")) and problems.any(func(p: String) -> bool: return p.contains("'wrong'") and p.contains("not one of the choices")), "an x-when naming no setting, a type no screen shows, a default the schema refuses")
	var mine: Dictionary = m.preferences.schema.properties.mine
	check(PlayerPrefs.offered(mine, {"dice": "choice"}) and not PlayerPrefs.offered(mine, {"dice": "typed"}), "offered while its setting says so")
	check(PlayerPrefs.offered({"x-when": {"n": [1, 2]}}, {"n": 2}) and not PlayerPrefs.offered({"x-when": {"n": [1, 2]}}, {"n": 0}) and PlayerPrefs.offered({}, {}), "one of several values; none named: always")
	var fine := PlayerPrefs.check_manifest(JsonDoc.parse(FileAccess.get_file_as_string("res://tests/plugins/sample.ordered/manifest.json")))
	check(fine.is_empty(), "the reference plugin's preferences are right: %s" % [fine])
