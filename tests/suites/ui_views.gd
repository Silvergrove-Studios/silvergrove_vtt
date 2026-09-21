extends TestCase
## ViewRenderer: declarative views drawn from data, intents from taps,
## unknown widgets as text.


func _find(root: Node, cls: String, text := "") -> Node:
	if root.get_class() == cls and (text == "" or ("text" in root and str(root.text).contains(text))):
		return root
	for c in root.get_children():
		var f := _find(c, cls, text)
		if f != null:
			return f
	return null


func _count(root: Node, cls: String) -> int:
	var n := 1 if root.get_class() == cls else 0
	for c in root.get_children():
		n += _count(c, cls)
	return n


func test_view_renderer_widgets() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	var sent := []
	r.intent.connect(func(p: Dictionary) -> void: sent.append(p))
	var data := {
		"actor": {"id": "a_1", "name": "Ana", "mine": true},
		"derived": {"defence": TypedNumber.make([{"label": "base", "type": "base", "value": 10}, {"label": "agility", "type": "ability", "value": 3}]), "hand": ["dash", {"id": "rally", "label": "Rally!", "text": "heal"}], "label": "Level 2"},
		"resources": {"hp": {"kind": "pool", "current": 4, "max": 9}, "armour": {"kind": "track", "max": 3, "marked": 1, "extra": 1, "crossed": [3]}},
		"effects": [{"key": "shaken", "label": "Shaken", "value": 2}],
		"tracks": [{"name": "Doom", "kind": "countdown", "value": 1, "max": 3, "direction": "down"}],
		"prompts": [{"id": "p_1", "to": "pl_1", "form": {"title": "Spend armour?", "fields": [{"key": "spend", "type": "bool", "label": "Spend"}]}, "default": {"spend": true}}],
		"log": [{"kind": "roll", "label": "Strike", "result": {"total": 17, "outcome": "hit"}}, {"kind": "note", "text": "hello"}],
	}
	var schema := {"type": "column", "children": [
		{"type": "text", "bind": "/actor/name", "style": "header"},
		{"type": "text", "expr": "'Level ' .. 2 .. ' ' .. @actor.name"},
		{"type": "number", "label": "Defence", "bind": "/derived/defence"},
		{"type": "pool", "label": "HP", "bind": "/resources/hp", "spend": {"kind": "action", "plugin": "p", "action": "hurt", "ctx": {"actor": "$/actor/id"}}},
		{"type": "track", "label": "Armour", "bind": "/resources/armour", "on_mark": {"kind": "action", "action": "mark", "ctx": {"actor": "$/actor/id"}}},
		{"type": "effects", "bind": "/effects"},
		{"type": "cards", "bind": "/derived/hand", "on_tap": {"kind": "action", "action": "play", "ctx": {"card": "$/card_id", "actor": "$/actor/id"}}},
		{"type": "action_bar", "actions": [{"type": "button", "label": "Act", "cost": {"actions": 1}, "intent": {"kind": "action", "action": "act"}}, {"type": "button", "label": "Never", "enabled": "@actor.mine == false", "intent": {"kind": "x"}},
			{"type": "button", "label": "Unseen", "if": "@actor.mine == false", "intent": {"kind": "x"}}]},
		{"type": "list", "bind": "/tracks", "item": {"type": "tracker", "bind": "/item"}},
		{"type": "prompt", "bind": "/prompts/0"},
		{"type": "log", "bind": "/log"},
		{"type": "hologram", "label": "3D", "bind": "/derived/label"},
		{"type": "section", "title": "Hidden", "if": "@actor.mine == false", "children": [{"type": "text", "text": "never"}]},
	]}
	r.render(schema, data)
	await tree.process_frame
	check(_find(r, "Label", "Ana") != null, "a bound text")
	check(_find(r, "Button", "Unseen") == null and _find(r, "Button", "Never") != null, "a button's `if` hides it inside an action bar")
	# a prompt form whose bool field has no default renders (bool(null) was a GDScript error)
	var r2 := ViewRenderer.new()
	root.add_child(r2)
	r2.render({"type": "prompt", "bind": "/prompts/0"}, {"prompts": [{"id": "p_2", "to": "pl_1", "form": {"title": "?", "fields": [{"key": "roll", "type": "bool", "label": "Roll"}, {"key": "insp", "type": "bool", "label": "Inspiration"}]}, "default": {"roll": true}}]})
	await tree.process_frame
	check(_count(r2, "CheckBox") == 2, "a prompt with an undefaulted bool field renders its two checkboxes")
	r2.queue_free()
	check(_find(r, "Label", "Level 2 Ana") != null, "an expression text")
	var def := _find(r, "Label", "13")
	check(def != null and def.tooltip_text.contains("agility +3"), "a typed number with its breakdown as tooltip: %s" % [def.tooltip_text if def != null else "none"])
	check(_find(r, "Label", "4 / 9") != null, "a pool")
	var boxes := 0
	var crossed := 0
	for b in _all(r, "Button"):
		if b.text == "■" or b.text == "□":
			boxes += 1
		if b.text == "✕":
			crossed += 1
	check(boxes == 3 and crossed == 1, "a track: 3 + 1 boxes, one crossed out (%d boxes, %d crossed)" % [boxes, crossed])
	check(_find(r, "Button", "Shaken 2") != null, "an effect badge with its value")
	check(_find(r, "Button", "dash") != null and _find(r, "Button", "Rally!") != null, "cards from strings and from records")
	var act := _find(r, "Button", "Act  [1 actions]")
	check(act != null and not act.disabled, "an action button with its cost")
	check(_find(r, "Button", "Never").disabled, "an enabled expression that is false disables the button")
	check(_find(r, "Label", "Doom") != null and _find(r, "Label", "■") != null, "a tracker")
	check(_find(r, "Label", "Spend armour?") != null and _find(r, "CheckBox") != null and _find(r, "Button", "Answer") != null, "a prompt renders its form and an Answer button")
	check(_find(r, "Label", "Strike: 17 — hit") != null and _find(r, "Label", "hello") != null, "log entries")
	var holo := _find(r, "Label", "hologram")
	check(holo != null and holo.text.contains("Level 2") and holo.has_meta("fallback"), "an unknown widget renders as text with its value: %s" % [holo.text if holo != null else ""])
	check(_find(r, "Label", "never") == null, "an `if` that is false hides the node")
	# intents
	act.pressed.emit()
	_find(r, "Button", "dash").pressed.emit()
	_find(r, "Button", "−").pressed.emit()
	var mark := _find(r, "Button", "□")
	mark.pressed.emit()
	_find(r, "Button", "Answer").pressed.emit()
	check(sent.size() == 5, "five intents sent: %d" % sent.size())
	check(sent[0] == {"kind": "action", "action": "act"}, "a plain intent")
	check(sent[1].ctx.card == "dash" and sent[1].ctx.actor == "a_1", "'$/pointer' values are filled from the data (and the card): %s" % [sent[1]])
	check(sent[2].ctx.actor == "a_1", "the pool's spend intent")
	check(sent[3].kind == "action" and sent[3].action == "mark", "the track's mark intent")
	check(sent[4].kind == "answer" and sent[4].prompt == "p_1" and sent[4].answer.spend == true, "the prompt's answer carries the form's values: %s" % [sent[4]])
	# rebuild with new data
	data.resources.hp.current = 2
	r.update(data)
	await tree.process_frame
	check(_find(r, "Label", "2 / 9") != null and _find(r, "Label", "4 / 9") == null, "update redraws from the new data")
	r.queue_free()
	await tree.process_frame


func _all(root: Node, cls: String) -> Array:
	var out := []
	if root.get_class() == cls:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all(c, cls))
	return out


func test_view_helpers() -> void:
	var doc := {"a": {"b": [1, {"c": "x"}]}, "k/y": 2}
	check(ViewRenderer.at_pointer(doc, "/a/b/1/c") == "x" and ViewRenderer.at_pointer(doc, "a/b/0") == 1 and ViewRenderer.at_pointer(doc, "/a/zz") == null and ViewRenderer.at_pointer(doc, "/k~1y") == 2, "JSON pointers, escapes included")
	check(ViewRenderer.fill_intent({"x": "$/a/b/1/c", "y": ["$/k~1y", "lit"], "z": "$notapointer"}, doc) == {"x": "x", "y": [2, "lit"], "z": "$notapointer"}, "fill_intent resolves $/ strings deep inside")
	check(ViewRenderer.value_of({"expr": "@a.b[0] + 1"}, doc) == 2.0 and ViewRenderer.value_of({"bind": "/k~1y"}, doc) == 2 and ViewRenderer.value_of({"text": "t"}, doc, "text") == "t", "value_of: expr, bind, literal")
	var r := ViewRenderer.new()
	root.add_child(r)
	r.render({"type": "column", "children": [{"type": "column", "children": [{"type": "text", "text": "deep"}]}]}, {})
	check(_find(r, "Label", "deep") != null, "nested columns")
	r.render({"type": "text", "text": "top"}, {})
	check(_find(r, "Label", "top") != null and _find(r, "Label", "deep") == null, "render replaces")
	r.render({"type": "list", "bind": "/nope", "empty": "nothing here"}, {})
	check(_find(r, "Label", "nothing here") != null, "a list with no data shows its empty text")
	r.queue_free()
	await tree.process_frame


func test_pickers_wizards_repeaters_and_fields() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	var sent := []
	r.intent.connect(func(p: Dictionary) -> void: sent.append(p))
	# a picker over a bound list, single choice
	var data := {"actor": {"id": "a_1"}, "feats": [{"id": "alert", "name": "Alert"}, {"id": "tough", "name": "Tough"}, "Lucky"],
		"spells": {"fb": {"id": "fb", "name": "Fire bolt"}, "mm": "Magic missile"}, "notes": "hi", "items": [{"name": "Sword", "qty": 1}]}
	r.render({"type": "column", "children": [
		{"type": "picker", "label": "Feat", "bind": "/feats", "on_pick": {"kind": "action", "action": "take", "ctx": {"actor": "$/actor/id", "feat": "$/pick_id", "name": "$/pick/name"}}},
		{"type": "picker", "label": "Spells", "bind": "/spells", "multi": true, "on_pick": {"kind": "action", "action": "prepare", "ctx": {"ids": "$/picks"}}},
	]}, data)
	await tree.process_frame
	var lists := _all(r, "ItemList")
	check(lists.size() == 2 and lists[0].item_count == 3 and lists[0].get_item_text(2) == "Lucky", "options from records and strings")
	var search: LineEdit = _all(r, "LineEdit")[0]
	search.text = "tou"
	search.text_changed.emit("tou")
	check(lists[0].item_count == 1 and lists[0].get_item_text(0) == "Tough", "the search narrows the list")
	lists[0].select(0)
	lists[0].item_selected.emit(0)
	check(sent.size() == 1 and sent[0].ctx.feat == "tough" and sent[0].ctx.name == "Tough" and sent[0].ctx.actor == "a_1", "a pick sends the intent with the record and its id: %s" % [sent])
	check(lists[1].item_count == 2, "a dictionary of options lists its values")
	lists[1].select(0)
	lists[1].select(1, false)
	_find(r, "Button", "Done").pressed.emit()
	check(sent.size() == 2 and sent[1].ctx.ids == ["fb", "mm"], "multi: Done sends the chosen ids: %s" % [sent[1]])
	# a picker over a collection, through comp_source
	var asked := []
	r.comp_source = func(collection: String, req: Dictionary, on_reply: Callable) -> void:
		asked.append([collection, req])
		on_reply.call({"collection": collection, "page": {"entries": [{"id": "goblin", "name": "Goblin", "level": 1}], "total": 6}})
	r.render({"type": "picker", "collection": "creatures", "query": {"filter": {"kind": "humanoid"}}, "fields": ["name", "level"], "per_page": 1,
		"on_pick": {"kind": "action", "action": "spawn", "ctx": {"entry": "$/pick_id"}}}, data)
	await tree.process_frame
	check(asked.size() == 1 and asked[0][0] == "creatures" and asked[0][1].query.filter.kind == "humanoid" and asked[0][1].query.per_page == 1 and asked[0][1].query.fields == ["name", "level"], "the collection was asked with the query: %s" % [asked])
	var cl: ItemList = _all(r, "ItemList")[0]
	check(cl.item_count == 1 and _find(r, "Label", "1 of 6 — narrow the search") != null, "a page, with a hint that there is more")
	var cs: LineEdit = _all(r, "LineEdit")[0]
	cs.text = "gob"
	cs.text_changed.emit("gob")
	check(asked.size() == 2 and asked[1][1].query.text == "gob", "typing asks again with the text")
	cl.select(0)
	cl.item_selected.emit(0)
	check(sent.size() == 3 and sent[2].ctx.entry == "goblin", "picking an entry sends its id")
	r.comp_source = Callable()
	r.render({"type": "picker", "collection": "creatures", "on_pick": {}}, data)
	check(_find(r, "Label", "No compendium here") != null, "without a source, the picker says so")
	# a wizard: steps, back, submit with every step's values
	r.render({"type": "wizard", "label": "New hero", "steps": [
		{"title": "Name", "fields": [{"key": "name", "type": "string"}]},
		{"title": "Kind", "text": "Pick one", "fields": [{"key": "kind", "type": "enum", "options": ["fighter", "mage"]}]},
	], "submit": {"kind": "action", "action": "create", "ctx": {"actor": "$/actor/id", "values": "$values"}}}, data)
	await tree.process_frame
	check(_find(r, "Label", "New hero: Name (1/2)") != null and _find(r, "Button", "Back").disabled, "the first step, no way back")
	(_all(r, "LineEdit")[0] as LineEdit).text = "Ana"
	_find(r, "Button", "Next").pressed.emit()
	check(_find(r, "Label", "New hero: Kind (2/2)") != null and _find(r, "Label", "Pick one") != null and _find(r, "Button", "Submit") != null, "the second step, with its text and Submit")
	_find(r, "Button", "Back").pressed.emit()
	check(_find(r, "Label", "New hero: Name (1/2)") != null and (_all(r, "LineEdit")[0] as LineEdit).text == "Ana", "back keeps what was typed")
	_find(r, "Button", "Next").pressed.emit()
	(_all(r, "OptionButton")[0] as OptionButton).select(1)
	_find(r, "Button", "Submit").pressed.emit()
	check(sent.size() == 4 and sent[3].ctx.values == {"name": "Ana", "kind": "mage"} and sent[3].ctx.actor == "a_1", "submit carries every step's values: %s" % [sent[3]])
	# a repeater inside a form
	r.render({"type": "form", "fields": [{"key": "items", "label": "Items", "type": "list", "fields": [{"key": "name", "type": "string"}, {"key": "qty", "type": "int"}]}],
		"values": {"items": data.items}, "submit": {"kind": "action", "action": "inventory", "ctx": {"items": "$values"}}}, data)
	await tree.process_frame
	var rep: PropertyForm.ListField = null
	for pf in _all(r, "PropertyForm") + _all(r, "GridContainer"):
		if pf is PropertyForm and (pf as PropertyForm).control("items") is PropertyForm.ListField:
			rep = (pf as PropertyForm).control("items")
	check(rep != null and rep.count() == 1 and rep.get_values()[0].name == "Sword", "the repeater shows the one item")
	(rep.get_node("add") as Button).pressed.emit()
	check(rep.count() == 2, "add makes a row")
	((rep.get_child(1) as HBoxContainer).get_child(0) as PropertyForm).set_values({"name": "Shield", "qty": 2})
	_find(r, "Button", "Submit").pressed.emit()
	check(sent.size() == 5 and sent[4].ctx.items.items.size() == 2 and sent[4].ctx.items.items[1].name == "Shield" and sent[4].ctx.items.items[1].qty == 2, "submit carries the rows: %s" % [sent[4]])
	((rep.get_child(0) as HBoxContainer).get_child(1) as Button).pressed.emit()
	check(rep.count() == 1 and rep.get_values()[0].name == "Shield", "remove drops a row")
	# a field edited in place
	r.render({"type": "field", "label": "Notes", "bind": "/notes", "kind": "string", "on_change": {"kind": "action", "action": "note", "ctx": {"actor": "$/actor/id", "text": "$value"}}}, data)
	await tree.process_frame
	var le: LineEdit = _all(r, "LineEdit")[0]
	check(le.text == "hi", "the bound value")
	le.text = "hello"
	le.text_submitted.emit("hello")
	check(sent.size() == 6 and sent[5].ctx.text == "hello" and sent[5].ctx.actor == "a_1", "a change sends the intent with the value: %s" % [sent[5]])
	# an image without packs degrades to its ref
	r.render({"type": "image", "src": "dungeons_and_castles:altar"}, data)
	check(_find(r, "Label", "dungeons_and_castles:altar") != null, "no packs: the ref as text")
	r.packs = PackLibrary.new()
	r.packs.reload()
	r.render({"type": "image", "bind": "/art"}, {"art": "dungeons_and_castles:goblin"})
	check(_all(r, "TextureRect").size() == 1 or _find(r, "Label", "dungeons_and_castles:goblin") != null, "with packs: a texture when the art exists")
	r.queue_free()
	await tree.process_frame
