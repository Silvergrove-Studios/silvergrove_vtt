extends TestCase
## Phase 5: content packs and the compendium index, at scale; the editor
## generated from a schema; the Table's Compendium panel; character files
## that go through a phone and back.


func _pack(id: String, entries: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var m := {"format": Compendium.FORMAT, "version": 1, "id": id, "name": id, "pack_version": "1", "plugin": "sample.degrees"}
	m.merge(extra, true)
	return {"manifest": m, "collections": entries}


func test_compendium_index_and_layers() -> void:
	var c := Compendium.new()
	c.user_dir = "user://test_content"
	check(c.load_path("res://tests/plugins/sample.degrees/packs/core") == "", "the shipped pack loads from its directory")
	check(c.collections() == ["conditions", "creatures", "feats"] and c.count("creatures") == 6, "collections and counts")
	check(c.get_entry("creatures", "wolf").name == "Wolf" and c.get_entry("creatures", "wolf").__pack == "sample.degrees.core", "an entry carries its pack")
	check(c.get_entry("creatures", "nope").is_empty(), "unknown ids are empty")
	# queries
	var r := c.query("creatures", {"filter": {"kind": "humanoid"}})
	check(r.total == 2 and r.entries.size() == 2 and r.entries[0].name < r.entries[1].name, "a filter, sorted by name")
	r = c.query("creatures", {"filter": {"traits": "goblin", "kind": ["humanoid", "fey"]}})
	check(r.total == 2, "filters on list fields and any-of values")
	r = c.query("creatures", {"filter": {"level": 3}})
	check(r.total == 2, "numbers match numbers")
	r = c.query("creatures", {"text": "hun"})
	check(r.total == 2, "text matches a prefix in any string field (hunts, hungry)")
	r = c.query("creatures", {"text": "goblin fight"})
	check(r.total == 1 and r.entries[0].id == "goblin-chief", "every word must match")
	r = c.query("creatures", {"sort": "-level", "fields": ["name", "level"]})
	check(r.entries[0].id == "ogre" and r.entries[0].keys().size() == 4 and not r.entries[0].has("stats"), "sort descending; only the fields asked for")
	r = c.query("creatures", {"per_page": 4, "page": 2})
	check(r.total == 6 and r.pages == 2 and r.entries.size() == 2, "pages")
	r = c.query("creatures", {"facets": ["kind", "traits"]})
	check(r.facets.kind.humanoid == 2 and r.facets.traits.goblin == 2 and r.facets.traits.small == 2, "facet counts over the matches")
	# ranges, negation, paths
	r = c.query("creatures", {"filter": {"level": {"min": 2, "max": 3}}})
	check(r.total == 3 and r.entries.map(func(e): return e.id) == ["goblin-chief", "skeleton", "will-o-wisp"], "a range on a number: %s" % [r.entries.map(func(e): return e.id)])
	check(c.query("creatures", {"filter": {"level": {"min": 4}}}).total == 1 and c.query("creatures", {"filter": {"level": {"max": 1}}}).total == 2, "either end may be open")
	check(c.query("creatures", {"filter": {"kind": {"not": "humanoid"}}}).total == 4 and c.query("creatures", {"filter": {"kind": {"not": ["humanoid", "fey"]}}}).total == 3, "not one, not any of")
	r = c.query("creatures", {"filter": {"stats/might": {"min": 2}}, "sort": "-stats/might"})
	check(r.total == 4 and r.entries[0].id == "ogre" and r.entries[-1].id in ["goblin-chief", "wolf", "skeleton"], "a path into an object filters and sorts: %s" % [r.entries.map(func(e): return e.id)])
	check(c.query("creatures", {"filter": {"stats/mind": 3}}).total == 1 and c.query("creatures", {"filter": {"stats/mind": {"not": {"min": 0}}}}).total == 3, "paths take values and nested ranges")
	r = c.query("creatures", {"filter": {"kind": "humanoid", "level": {"min": 2}}, "facets": ["stats/agility"]})
	check(r.total == 1 and r.facets["stats/agility"]["2"] == 1, "filters combine; facets over a path")
	check(c.facets("creatures").has("stats/might"), "paths are facet fields")
	check(c.facets("creatures").has("kind") and c.facets("creatures").has("level") and not c.facets("creatures").has("text"), "facet fields (not free text)")
	# a user pack layered on top: same id wins, others add
	var up := c.user_pack("hb", "Homebrew", "sample.degrees")
	check(up.user == true and c.packs.has("hb"), "a writable pack")
	var schema := JsonSchema.new({"type": "object", "required": ["id", "name", "level"], "properties": {"level": {"type": "integer", "maximum": 25}}})
	check(c.put("creatures", {"id": "wolf", "name": "Dire wolf", "level": 2, "kind": "animal"}, "hb", schema) == "", "an override goes in")
	check(c.put("creatures", {"id": "x", "name": "X", "level": 99}, "hb", schema).contains("level"), "the schema refuses bad entries")
	check(c.put("creatures", {"id": "y", "name": "Y", "level": 1}, "sample.degrees.core") != "", "shipped packs are not writable")
	check(c.get_entry("creatures", "wolf").name == "Dire wolf" and c.get_entry("creatures", "wolf").__pack == "hb" and c.count("creatures") == 6, "the homebrew wolf wins; the count is unchanged")
	check(c.query("creatures", {"filter": {"level": 2}}).total == 2 and c.query("creatures", {"text": "packs"}).total == 0, "the index follows the override")
	check(c.remove("creatures", "wolf", "hb") == "" and c.get_entry("creatures", "wolf").name == "Wolf", "removing it lets the shipped one win again")
	check(c.remove("creatures", "wolf", "hb") != "", "twice is an error")
	c.put("creatures", {"id": "wolf", "name": "Dire wolf", "level": 2}, "hb")
	c.put("feats", {"id": "brew", "name": "Brew", "level": 1}, "hb")
	c.unload("hb")
	check(c.get_entry("creatures", "wolf").name == "Wolf" and c.get_entry("feats", "brew").is_empty() and not c.packs.has("hb"), "unloading a layer restores what it covered")
	# save, reload, export, import
	c.user_pack("hb", "Homebrew", "sample.degrees")
	c.put("creatures", {"id": "kobold", "name": "Kobold", "level": 1, "kind": "humanoid"}, "hb")
	check(c.save_user_pack("hb") == "" and FileAccess.file_exists("user://test_content/hb/pack.json") and FileAccess.file_exists("user://test_content/hb/creatures.json"), "a user pack is written")
	var c2 := Compendium.new()
	c2.user_dir = "user://test_content"
	check(c2.load_user_packs().size() >= 1 and c2.get_entry("creatures", "kobold").name == "Kobold" and c2.packs.hb.user, "and loads back as a user pack")
	check(c.export_pack("hb", "user://test_content/hb.pack.json") == "", "exported as one file")
	var c3 := Compendium.new()
	check(c3.load_path("user://test_content/hb.pack.json") == "" and c3.get_entry("creatures", "kobold").name == "Kobold", "which loads")
	# versions
	check(c.versions("sample.degrees").has("sample.degrees.core") and c.outdated({"packs": {"sample.degrees.core": "0"}}).has("sample.degrees.core") and c.outdated({"packs": {"sample.degrees.core": "1"}}).is_empty(), "pack versions and outdated actors")
	check(c.load_path("user://test_content/none").contains("no pack.json"), "a missing pack says so")


func test_compendium_scale() -> void:
	var c := Compendium.new()
	var entries := []
	var kinds := ["humanoid", "animal", "giant", "undead", "fey"]
	var words := ["marsh", "cave", "hill", "tower", "river", "forest", "ruin", "road"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 5000:
		entries.append({"id": "c%d" % i, "name": "Creature %d" % i, "level": rng.randi_range(0, 20), "kind": kinds[i % 5], "traits": [words[i % 8], words[(i * 3) % 8]],
			"stats": {"might": rng.randi_range(-2, 6)}, "text": "It lives by the %s and the %s." % [words[i % 8], words[(i * 5) % 8]]})
	var t0 := Time.get_ticks_usec()
	check(c.load_pack({"id": "big", "name": "Big", "plugin": "x"}, {"creatures": entries}) == "", "5,000 entries load")
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var r := c.query("creatures", {"filter": {"kind": "fey", "level": [3, 4, 5]}, "facets": ["traits"], "per_page": 20})
	var q1 := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var r2 := c.query("creatures", {"text": "cave forest", "sort": "-level", "per_page": 20})
	var q2 := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var r3 := c.query("creatures", {"per_page": 50, "page": 60})
	var q3 := (Time.get_ticks_usec() - t0) / 1000.0
	say.call("  5,000 entries: indexed in %.0f ms; faceted filter %.1f ms (%d hits), text %.1f ms (%d hits), a page of all %d: %.1f ms" % [load_ms, q1, r.total, q2, r2.total, r3.total, q3])
	check(r.total > 0 and r.entries.size() == 20 and r.facets.traits.size() > 0, "the faceted query answers")
	check(r2.total > 0 and r3.entries.size() == 50 and r3.total == 5000, "the text query and the page answer")
	var budget := 20.0 if not OS.has_feature("mobile") else 120.0
	check(q1 < budget and q2 < budget * 4, "a faceted query on 5,000 entries stays under %d ms (%.1f, text %.1f)" % [int(budget), q1, q2])
	check(c.get_entry("creatures", "c4999").name == "Creature 4999", "random access")


func test_schema_form() -> void:
	var schema := {"type": "object", "required": ["id", "name", "level"], "properties": {
		"id": {"type": "string"}, "name": {"type": "string", "minLength": 1, "description": "What it is called"},
		"level": {"type": "integer", "minimum": 0, "maximum": 25},
		"kind": {"type": "string", "enum": ["humanoid", "animal", "fey"]},
		"fierce": {"type": "boolean"},
		"traits": {"type": "array", "items": {"type": "string"}},
		"stats": {"type": "object", "properties": {"might": {"type": "integer"}, "agility": {"type": "integer"}}},
		"attacks": {"type": "array", "items": {"type": "object", "properties": {"name": {"type": "string"}, "damage": {"type": "string"}}}},
		"text": {"type": "string", "format": "text"}}}
	var f := SchemaForm.new()
	root.add_child(f)
	f.build(schema, {"id": "wolf", "name": "Wolf", "level": 1, "kind": "animal", "traits": ["animal", "pack"], "stats": {"might": 2, "agility": 2}, "attacks": [{"name": "bite", "damage": "1d6"}]})
	await tree.process_frame
	check(f.control("/level") is SpinBox and (f.control("/level") as SpinBox).value == 1 and (f.control("/level") as SpinBox).max_value == 25, "an integer with its bounds")
	check(f.control("/kind") is OptionButton and (f.control("/kind") as OptionButton).get_item_text((f.control("/kind") as OptionButton).selected) == "animal", "an enum, selected")
	check(f.control("/fierce") is CheckBox and f.control("/traits") is LineEdit and (f.control("/traits") as LineEdit).text == "animal, pack", "a boolean, a list as a comma line")
	check(f.control("/stats/might") is SpinBox and (f.control("/stats/might") as SpinBox).value == 2, "a nested object's fields")
	check(f.control("/attacks/0/name") is LineEdit and (f.control("/attacks/0/name") as LineEdit).text == "bite", "a repeater's item fields")
	check(f.control("/text") is TextEdit and f.control("/name").tooltip_text == "What it is called", "long text as a text box; descriptions as tooltips")
	var changes := [0]
	f.changed.connect(func() -> void: changes[0] += 1)
	(f.control("/level") as SpinBox).value = 30
	(f.control("/kind") as OptionButton).item_selected.emit(2)
	(f.control("/traits") as LineEdit).text = "fey, tiny"
	(f.control("/traits") as LineEdit).text_submitted.emit("fey, tiny")
	(f.control("/stats/might") as SpinBox).value = 5
	var v := f.values()
	check(v.level == 25 and v.kind == "fey" and v.traits == ["fey", "tiny"] and v.stats.might == 5 and v.attacks[0].name == "bite", "edits land in the record (the spin box clamps to the schema's maximum): %s" % [v])
	check(changes[0] >= 4, "the form reports changes")
	(f.control("/name") as LineEdit).text = ""
	(f.control("/name") as LineEdit).text_submitted.emit("")
	check(not f.validate() and f._errors.text.contains("/name"), "validate points at the field that is wrong: " + f._errors.text)
	(f.control("/name") as LineEdit).text_submitted.emit("Wolf")
	check(f.validate() and f._errors.text == "", "…and is clean again")
	f.queue_free()
	await tree.process_frame


func test_compendium_panel() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var ctx := TableContext.new()
	ctx.app = App.new("user://test_prefs_comp.json")
	ctx.plugin_dirs = ["res://tests/plugins"]
	var e := Encounter.load_file(example("chapel_ambush.encounter"))
	ctx.set_encounter(e)
	ctx.state.resolve_maps()
	ctx.kernel.comp.user_dir = "user://test_content_panel"
	if ctx.campaign == null:
		ctx.campaign = Campaign.create("Panel")
	var panel := CompendiumPanel.new(ctx)
	root.add_child(panel)
	panel.bind()
	await tree.process_frame
	var colls := []
	for i in panel._collection.item_count:
		colls.append(panel._collection.get_item_metadata(i))
	check(colls == ["conditions", "creatures", "feats"], "the collections the plugins ship: %s" % [colls])
	panel._collection.select(1)
	panel._collection.item_selected.emit(1)
	check(panel._list.item_count == 6 and panel._page_label.text.begins_with("1–6 of 6"), "creatures listed")
	panel._search.text = "gob"
	panel._search.text_changed.emit("gob")
	check(panel._list.item_count == 2, "search narrows")
	panel._search.text = ""
	panel._search.text_changed.emit("")
	var kind_idx := -1
	for i in panel._facet_field.item_count:
		if panel._facet_field.get_item_metadata(i) == "kind":
			kind_idx = i
	panel._facet_field.select(kind_idx)
	panel._facet_field.item_selected.emit(kind_idx)
	check(panel._facet_values.get_child_count() >= 4, "facet buttons for the kinds")
	var fey: Button = null
	for b in panel._facet_values.get_children():
		if str(b.text).begins_with("fey"):
			fey = b
	fey.pressed.emit()
	check(panel._list.item_count == 1 and panel._list.get_item_text(0).begins_with("Will"), "a facet narrows to the wisp")
	fey.pressed.emit()
	panel._open("wolf")
	await tree.process_frame
	check(panel._card != null and panel._card.visible and not panel._fields.visible and _find_label(panel._card, "Wolf") != null and _find_label(panel._card, "Level ") != null, "a shipped entry opens as the ruleset's card, the fields hidden")
	check(_button(panel._detail, "Fields") != null, "read-only: a Fields button")
	_button(panel._detail, "Fields").pressed.emit()
	check(panel._fields.visible and not panel._card.visible and _button(panel._detail, "Done") != null, "Fields shows the form")
	await tree.process_frame
	check(panel._form != null and panel._form.control("/level") is SpinBox, "a shipped entry opens in the plugin's schema form")
	check(_button(panel._detail, "Copy to homebrew") != null and _button(panel._detail, "Save") == null and _button(panel._detail, "Add to the scene") != null, "read-only: copy, no save; the plugin's entry action is offered")
	_button(panel._detail, "Copy to homebrew").pressed.emit()
	await tree.process_frame
	check(panel._entry.__pack == "sample.degrees.homebrew" and panel._entry.name == "Wolf (homebrew)" and _button(panel._detail, "Save") != null, "a homebrew copy, editable")
	(panel._form.control("/level") as SpinBox).value = 4
	(panel._form.control("/name") as LineEdit).text = "Dire wolf"
	(panel._form.control("/name") as LineEdit).text_submitted.emit("Dire wolf")
	_button(panel._detail, "Save").pressed.emit()
	await tree.process_frame
	var saved := ctx.kernel.comp.get_entry("creatures", str(panel._entry.id))
	check(saved.level == 4 and saved.name == "Dire wolf" and FileAccess.file_exists("user://test_content_panel/sample.degrees.homebrew/creatures.json"), "saved into the homebrew pack on disk")
	check(ctx.kernel.comp.count("creatures") == 7, "seven creatures now")
	# the plugin's entry action works on the homebrew entry: spawn it
	_button(panel._detail, "Add to the scene").pressed.emit()
	var spawned := ""
	for aid in ctx.state.encounter.actors:
		if ctx.state.encounter.actors[aid].name == "Dire wolf":
			spawned = str(aid)
	check(spawned != "" and ctx.state.encounter.actor(spawned).derived["sample.degrees"].ac.total == 14 and ctx.state.encounter.actor(spawned).packs.has("sample.degrees.core"), "spawned from the homebrew entry with derived numbers and pack versions stamped")
	_button(panel._detail, "Delete").pressed.emit()
	await tree.process_frame
	check(ctx.kernel.comp.count("creatures") == 6, "deleted")
	# turning an entry off from the pane: marked, not offered, back on a tick
	panel._open("goblin")
	await tree.process_frame
	check(panel._use != null and panel._use.button_pressed, "the open entry is in play")
	check(panel.set_used("creatures", "goblin", false).contains("off at this table"), "turned off from the pane")
	check(ctx.campaign != null and ctx.campaign.is_disabled("sample.degrees", "creatures", "goblin"), "the campaign records it")
	var hits := ctx.kernel.comp.query("creatures", {"text": "goblin"})
	check(hits.entries.all(func(e: Dictionary) -> bool: return str(e.id) != "goblin"), "the skirmisher is offered nowhere (the chief still is: %d)" % int(hits.total))
	panel._search.text = ""
	panel._show_disabled.button_pressed = true
	panel._query()
	var listed := ""
	for i in panel._list.item_count:
		if str(panel._list.get_item_text(i)).contains("skirmisher"):
			listed = str(panel._list.get_item_text(i))
	check(listed.begins_with("✗ "), "Show what is off lists it, marked: %s" % listed)
	panel._show_disabled.button_pressed = false
	check(panel.set_used("creatures", "goblin", true).contains("in play again") and ctx.kernel.comp.query("creatures", {"text": "goblin"}).total == 2, "and back on a tick")
	# a table that loads later gets its homebrew back from disk
	var ctx2 := TableContext.new()
	ctx2.app = ctx.app
	ctx2.plugin_dirs = ["res://tests/plugins"]
	var c2 := Compendium.new()
	c2.user_dir = "user://test_content_panel"
	c2.load_user_packs()
	check(c2.packs.has("sample.degrees.homebrew"), "the homebrew pack is on disk for next time")
	panel.queue_free()
	await tree.process_frame


func test_character_files_round_trip() -> void:
	var doc := CharacterFile.make({"id": "a_ana", "kind": "pc", "name": "Ana's rogue", "owner": "pl_x", "ext": {"sample.focus": {"traits": {"nerve": 1, "grace": 2, "wit": 0}}}, "derived": {"x": 1}, "packs": {"p": "1"}}, [{"id": "sample.focus", "version": "0.1.0"}])
	check(doc.format == CharacterFile.FORMAT and not doc.actor.has("owner") and not doc.actor.has("derived") and doc.actor.packs.p == "1" and doc.plugins[0].id == "sample.focus", "a character file is the actor without what the table owns")
	check(CharacterFile.check(doc) == "" and CharacterFile.check({"format": "x"}) != "" and CharacterFile.check({"format": CharacterFile.FORMAT, "version": 1, "actor": {"id": "a"}}) != "", "checks")
	var path := "user://test_characters/ana.json"
	check(CharacterFile.save(doc, path) == "" and CharacterFile.load_file(path).actor.name == "Ana's rogue", "save and load")
	check(CharacterFile.list("user://test_characters").size() >= 1, "listed")
	var a := CharacterFile.to_actor(doc, "pl_1")
	check(a.owner == "pl_1" and a.kind == "pc" and a.has("derived") and a.derived.is_empty(), "to_actor gives the player the actor")
	if not PluginHost.available():
		skip("no Lua runtime in this build (the wire part)")
		return
	# over the wire: bring it, the table adopts it, keep it
	var app := App.new("user://test_prefs_char.json")
	var table := TableWindow.new()
	table.app = app
	root.add_child(table)
	table.ctx.plugin_dirs = ["res://tests/plugins"]
	table._open_path(_example("chapel_ambush.encounter"))
	table._set_hosting(true)
	var player := PlayerWindow.new()
	player.app = app
	root.add_child(player)
	var pump := func(done: Callable, max_ms := 4000) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < max_ms:
			table._process(0.05)
			player._process(0.05)
			if done.call():
				return true
			OS.delay_msec(10)
		return false
	player._address.text = "127.0.0.1:%d" % table.host.port
	player._join_address()
	check(pump.call(func() -> bool: return player.screen == "pick"), "welcomed")
	var ana_id := str(table.ctx.state.encounter.players[0].id)
	player._start(ana_id)
	check(pump.call(func() -> bool: return player.screen == "play" and not player.session.view.is_empty()), "joined")
	check(player.session.my_actors().is_empty() and player.characters_to_bring().size() == 0, "no character of hers at the table; the test file is not in the device's folder")
	check(player.bring_character(doc) == "", "she brings her rogue")
	check(pump.call(func() -> bool: return player.session.my_actors().size() == 1), "the table adopted it and her view has it")
	var at_table := table.ctx.state.encounter.actor("a_ana")
	check(at_table.owner == ana_id and at_table.derived["sample.focus"].evade.total == 10 and at_table.packs.has("p"), "as hers, derived, with its pack versions")
	check(player.session.view.actors.a_ana.sheets.size() == 1, "with the plugin's sheet")
	# a bad one is refused
	var told := []
	player.session.status.connect(func(t: String) -> void: told.append(t))
	var bad: Dictionary = JsonDoc.deep(doc)
	bad.actor.id = "a_bad"
	bad.actor.ext["sample.focus"].traits.nerve = "x"
	check(player.bring_character(bad) == "" and pump.call(func() -> bool: return told.any(func(t: String) -> bool: return t.contains("nerve")), 2000), "the ruleset's schema refuses a bad one: %s" % [told])
	# bring the same one again with a change: an update, not a duplicate
	var again: Dictionary = JsonDoc.deep(doc)
	again.actor.ext["sample.focus"].traits.grace = 4
	player.bring_character(again)
	check(pump.call(func() -> bool: return table.ctx.state.encounter.actor("a_ana").ext["sample.focus"].traits.grace == 4), "bringing it again updates it")
	check(table.ctx.state.encounter.actors.size() == 1 + 0, "and does not duplicate")
	# keep it: the file on the device equals what the table has
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CharacterFile.DIR))
	check(pump.call(func() -> bool: return player.session.view.actors.a_ana.ext["sample.focus"].traits.grace == 4), "the view caught up")
	check(player.keep_character("a_ana") == "", "kept")
	var kept := CharacterFile.load_file(CharacterFile.DIR.path_join("a_ana.json"))
	check(kept.actor.name == "Ana's rogue" and kept.actor.ext["sample.focus"].traits.grace == 4 and kept.actor.packs.has("p") and kept.plugins.size() >= 1, "the kept file has the table's version of her: %s" % [kept.actor.keys()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CharacterFile.DIR.path_join("a_ana.json")))
	player._leave()
	table._set_hosting(false)
	player.queue_free()
	table.queue_free()
	await tree.process_frame


func _button(root_node: Node, text: String) -> Button:
	if root_node is Button and str(root_node.text).begins_with(text):
		return root_node
	for c in root_node.get_children():
		var b := _button(c, text)
		if b != null:
			return b
	return null


## A ruleset arrives as a zip: installed under the plugins folder, loaded
## without a restart, replaced by a newer zip.
func test_install_ruleset_zip() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var dest := "user://test_installed_plugins"
	if DirAccess.dir_exists_absolute(dest):
		PluginHost._rm_rf(dest)
	# the zip a plugin repo's release would carry: one top folder with the manifest inside
	var zip_path := "user://test_ruleset.zip"
	var zp := ZIPPacker.new()
	check(zp.open(zip_path) == OK, "a zip to write")
	var src := "res://tests/plugins/sample.ordered"
	var da := DirAccess.open(src)
	var listed := PackedStringArray()
	for n in da.get_files():
		listed.append(n)
	for n in listed:
		zp.start_file("sample.ordered-1.0/" + n)
		zp.write_file(FileAccess.get_file_as_bytes(src.path_join(n)))
		zp.close_file()
	zp.close()
	var r := PluginHost.install_zip(zip_path, dest)
	check(str(r.error) == "" and str(r.id) == "sample.ordered" and int(r.files) == listed.size(), "installed from the zip's top folder: %s" % [r])
	check(FileAccess.file_exists(dest.path_join("sample.ordered/manifest.json")), "the manifest is under <plugins>/<id>")
	var found := PluginHost.discover([dest])
	check(found.size() == 1 and str(found[0].id) == "sample.ordered", "discover finds it")
	# a live Table loads it on reload
	var ctx := TableContext.new()
	ctx.app = App.new("user://test_prefs_install.json")
	ctx.plugin_dirs = [dest]
	var e := Encounter.load_file(example("chapel_ambush.encounter"))
	ctx.set_encounter(e)
	check(ctx.host != null and ctx.host.plugins.has("sample.ordered"), "loaded at open")
	check(ctx.kernel.commit([{"t": "actor.add", "actor": {"id": "a_h", "kind": "pc", "name": "Hero", "ext": {"sample.ordered": {"level": 2, "stats": {"agi": 2, "str": 1, "wit": 0}}}}}], "Hero") == "", "a hero with the ruleset's data")
	check(int(ctx.encounter().actor("a_h").derived["sample.ordered"].defence.total) == 12, "derived by the installed ruleset")
	ctx.encounter().actor("a_h").derived = {}
	# a newer zip, manifest at the root this time, replaces it
	var zp2 := ZIPPacker.new()
	zp2.open(zip_path)
	for n in listed:
		var bytes := FileAccess.get_file_as_bytes(src.path_join(n))
		if n == "manifest.json":
			var m := JsonDoc.parse(bytes.get_string_from_utf8(), [])
			m.version = "9.9.9"
			bytes = JsonDoc.stringify(m).to_utf8_buffer()
		zp2.start_file(n)
		zp2.write_file(bytes)
		zp2.close_file()
	zp2.close()
	var panel := RulesPanel.new(ctx)
	root.add_child(panel)
	panel.bind()
	var said := panel.install_zip(zip_path)
	check(said.begins_with("Installed") and said.contains("9.9.9"), "the Rules pane installs and reloads: %s" % said)
	check(ctx.host.plugins.has("sample.ordered") and str(ctx.host.plugins["sample.ordered"].manifest.version) == "9.9.9", "the new version is the one loaded")
	check(int(ctx.encounter().actor("a_h").get("derived", {}).get("sample.ordered", {}).get("defence", {}).get("total", 0)) == 12, "the sheets derived again")
	check(PluginHost.install_zip("user://no_such.zip", dest).error != "", "not a zip: refused")
	var bad := ZIPPacker.new()
	bad.open("user://test_bad.zip")
	bad.start_file("readme.txt")
	bad.write_file("hi".to_utf8_buffer())
	bad.close_file()
	bad.close()
	check(PluginHost.install_zip("user://test_bad.zip", dest).error.contains("manifest"), "no manifest: refused")
	root.remove_child(panel)
	panel.free()
	PluginHost._rm_rf(dest)


func _find_label(root_node: Node, text: String) -> Label:
	if root_node is Label and str((root_node as Label).text).begins_with(text):
		return root_node
	for c in root_node.get_children():
		var l := _find_label(c, text)
		if l != null:
			return l
	return null


## A campaign carries content: its own packs load with it, entries it
## turns off are offered nowhere but still answer by id, and a pack or a
## file of entries can be imported at any time.
func test_campaign_content() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var dir := "user://test_campaign_content"
	if DirAccess.dir_exists_absolute(dir):
		PluginHost._rm_rf(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	# a campaign with a pack of its own, beside the file
	var c := Campaign.create("Content")
	c.plugins.append({"id": "sample.degrees"})
	check(ContentImport.write_pack(dir.path_join("packs/reach"), {"id": "reach", "name": "The Reach", "plugin": "sample.degrees"},
		{"creatures": [{"id": "reach-eel", "name": "Reach eel", "level": 2, "kind": "animal", "stats": {"might": 1, "agility": 2, "mind": 0}, "ac_base": 12, "hp": 9}]}) == "", "a pack written beside the campaign")
	c.packs.append({"id": "reach", "path": "packs/reach", "version": "1"})
	check(c.save(dir.path_join("reach.campaign")) == OK, "saved")
	var ctx := TableContext.new()
	ctx.app = App.new("user://test_prefs_campaign_content.json")
	ctx.plugin_dirs = ["res://tests/plugins"]
	var err := []
	var opened := Campaign.load_file(dir.path_join("reach.campaign"), err)
	check(opened != null and int(opened.doc.version) == Campaign.VERSION and opened.content.has("disabled"), "opened, upgraded to v%d with a content block" % Campaign.VERSION)
	ctx.open_campaign(opened)
	check(ctx.kernel.comp.get_entry("creatures", "reach-eel").name == "Reach eel", "the campaign's own pack loaded with it")
	check(ctx.kernel.comp.query("creatures", {"text": "eel"}).total == 1, "and is offered")
	# turned off: offered nowhere, still there by id
	check(opened.set_disabled("sample.degrees", "creatures", "wolf", true), "the wolf is turned off")
	ctx.kernel.comp.disabled = opened.disabled_index()
	check(ctx.kernel.comp.query("creatures", {"text": "wolf"}).total == 0, "no search finds it")
	check(ctx.kernel.comp.query("creatures", {}).entries.all(func(e: Dictionary) -> bool: return str(e.id) != "wolf"), "no listing offers it")
	check(ctx.kernel.comp.query("creatures", {"disabled": true}).entries.any(func(e: Dictionary) -> bool: return str(e.id) == "wolf"), "asking for the disabled ones finds it")
	check(ctx.kernel.comp.get_entry("creatures", "wolf").name != "" and ctx.kernel.comp.entry_for("creatures", "wolf", true).name != "", "it still answers by id: what is already built on it keeps working")
	check(ctx.kernel.comp.is_disabled("creatures", "wolf") and ctx.kernel.comp.disabled_count("creatures") == 1, "the compendium says it is off")
	check(opened.set_disabled("sample.degrees", "creatures", "wolf", false) and not opened.set_disabled("sample.degrees", "creatures", "wolf", false), "turned on again, and again is no change")
	ctx.kernel.comp.disabled = opened.disabled_index()
	check(ctx.kernel.comp.query("creatures", {"text": "wolf"}).total == 1, "back in the search")
	# import: a one-file pack of two creatures, mid-campaign
	var one := dir.path_join("supplement.json")
	var f := FileAccess.open(one, FileAccess.WRITE)
	f.store_string(JsonDoc.stringify({"pack": {"id": "supplement", "name": "A supplement", "plugin": "sample.degrees", "pack_version": "2"},
		"collections": {"creatures": [
			{"id": "sea-drake", "name": "Sea drake", "level": 5, "kind": "other", "stats": {"might": 3, "agility": 2, "mind": 1}, "ac_base": 15, "hp": 40},
			{"id": "wolf", "name": "Wolf (of the Reach)", "level": 2, "kind": "animal", "stats": {"might": 2, "agility": 2, "mind": 0}, "ac_base": 13, "hp": 12}]}}))
	f.close()
	var info := ContentImport.inspect(one)
	check(info.ok and info.id == "supplement" and int(info.collections.creatures) == 2, "inspected before importing: %s" % [info])
	var r := ContentImport.import_into(one, opened, ctx.host, ctx.kernel.comp)
	check(r.ok and int(r.added.creatures) == 2, "imported: %s" % [r])
	check(ctx.kernel.comp.get_entry("creatures", "sea-drake").name == "Sea drake", "the new creature is in the compendium at once")
	check(ctx.kernel.comp.get_entry("creatures", "wolf").name == "Wolf (of the Reach)", "and an import overrides a shipped entry by id")
	check(opened.packs.size() == 2 and opened.content.imported.size() == 1 and str(opened.content.imported[0].id) == "supplement", "the campaign records the pack and how it arrived")
	check(FileAccess.file_exists(dir.path_join("packs/supplement/pack.json")), "copied into the campaign's folder")
	# and it comes back with the campaign
	var ctx2 := TableContext.new()
	ctx2.app = ctx.app
	ctx2.plugin_dirs = ["res://tests/plugins"]
	check(opened.save() == OK, "saved with its imports")
	ctx2.open_campaign(Campaign.load_file(dir.path_join("reach.campaign"), err))
	check(ctx2.kernel.comp.get_entry("creatures", "sea-drake").name == "Sea drake" and ctx2.kernel.comp.get_entry("creatures", "reach-eel").name == "Reach eel", "both packs load when the campaign is opened again")
	# what will not import
	var bad := dir.path_join("bad.json")
	var bf := FileAccess.open(bad, FileAccess.WRITE)
	bf.store_string(JsonDoc.stringify({"pack": {"id": "bad", "plugin": "sample.degrees"},
		"collections": {"creatures": [{"id": "broken", "name": "Broken", "level": "two", "kind": "animal", "ac_base": 12, "hp": 9}]}}))
	bf.close()
	var br := ContentImport.import_into(bad, opened, ctx.host, ctx.kernel.comp)
	check(not br.ok and str(br.why).contains("creatures/broken"), "a bad entry is refused, naming it: %s" % br.why)
	check(ctx.kernel.comp.get_entry("creatures", "broken").is_empty() and opened.packs.size() == 2, "and nothing was copied in")
	var newer := dir.path_join("newer.json")
	var nf := FileAccess.open(newer, FileAccess.WRITE)
	nf.store_string(JsonDoc.stringify({"pack": {"id": "newer", "name": "From the future", "plugin": "sample.degrees", "content_api": 9},
		"collections": {"creatures": []}}))
	nf.close()
	var nr := ContentImport.import_into(newer, opened, ctx.host, ctx.kernel.comp)
	check(not nr.ok and str(nr.why).contains("content API 9"), "a pack for a newer content API is refused: %s" % nr.why)
	PluginHost._rm_rf(dir)


## A campaign parses its own content and nothing else: the rulesets it
## plays, their packs, and its own — not another ruleset's, and not the
## table's library, which is only read when something is imported from it.
func test_content_is_the_campaigns() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var dir := "user://test_content_scope"
	if DirAccess.dir_exists_absolute(dir):
		PluginHost._rm_rf(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	# a library pack lying about, belonging to no campaign
	var lib := "user://test_content_scope_library"
	if DirAccess.dir_exists_absolute(lib):
		PluginHost._rm_rf(lib)
	check(ContentImport.write_pack(lib.path_join("library"), {"id": "library", "name": "The table's library", "plugin": "sample.degrees"},
		{"creatures": [{"id": "library-lion", "name": "Library lion", "level": 3, "kind": "animal", "stats": {"might": 2, "agility": 2, "mind": 0}, "ac_base": 13, "hp": 14}]}) == "", "a pack in the table's library")
	var c := Campaign.create("Scoped")
	c.plugins.append({"id": "sample.degrees"})
	check(c.save(dir.path_join("scoped.campaign")) == OK, "a campaign that plays one ruleset")
	var ctx := TableContext.new()
	ctx.app = App.new("user://test_prefs_scope.json")
	ctx.plugin_dirs = ["res://tests/plugins"]
	ctx.library_dir = lib
	ctx.open_campaign(Campaign.load_file(dir.path_join("scoped.campaign"), []))
	check(ctx.host.plugins.has("sample.degrees"), "its ruleset loaded")
	check(not ctx.host.plugins.has("sample.ordered") and not ctx.host.plugins.has("sample.focus"), "the rulesets it does not play did not: %s" % [ctx.host.plugins.keys()])
	check(ctx.kernel.comp.count("creatures") == 6, "its ruleset's content is there (%d creatures)" % ctx.kernel.comp.count("creatures"))
	check(ctx.kernel.comp.get_entry("creatures", "library-lion").is_empty(), "the library's pack was not parsed into the campaign")
	check(ctx.kernel.comp.collections().all(func(coll: String) -> bool:
		return not ctx.kernel.comp.query(coll, {"text": "spark"}).entries.any(func(e: Dictionary) -> bool: return str(e.get("__pack", "")).begins_with("sample.focus"))), "nor another ruleset's")
	# the library is what an import reads from, on purpose
	var r := ContentImport.import_into(lib.path_join("library"), ctx.campaign, ctx.host, ctx.kernel.comp)
	check(r.ok and ctx.kernel.comp.get_entry("creatures", "library-lion").name == "Library lion", "importing from the library brings it into the campaign: %s" % [r.why])
	check(ctx.campaign.packs.any(func(p: Dictionary) -> bool: return str(p.id) == "library"), "and the campaign now carries it")
	# a campaign's homebrew is its own, under its folder
	check(ctx.kernel.comp.user_dir == dir.path_join("packs"), "homebrew is written into the campaign: %s" % ctx.kernel.comp.user_dir)
	# a campaign with nowhere to keep content yet says so rather than writing somewhere else
	var loose := TableContext.new()
	loose.app = ctx.app
	loose.plugin_dirs = ["res://tests/plugins"]
	loose.library_dir = lib
	loose.open_campaign(Campaign.create("Unsaved"))
	check(loose.kernel.comp.user_dir == "", "an unsaved campaign has nowhere to write")
	check(loose.kernel.comp.get_entry("creatures", "library-lion").is_empty(), "and the library is still not parsed into it")
	loose.kernel.comp.user_pack("scratch", "Scratch", "sample.degrees")
	check(loose.kernel.comp.save_user_pack("scratch").contains("save the campaign first"), "keeping a pack waits for the campaign to be saved")
	PluginHost._rm_rf(dir)
	PluginHost._rm_rf(lib)
