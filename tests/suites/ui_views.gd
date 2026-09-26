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
	# a prompt's choices: a button each instead of Answer (a roll the DM asked
	# for is the player's own click); one sends its intent, one answers
	var r3 := ViewRenderer.new()
	root.add_child(r3)
	var sent3 := []
	r3.intent.connect(func(i: Dictionary) -> void: sent3.append(i))
	r3.render({"type": "prompt", "bind": "/prompts/0"}, {"prompts": [{"id": "p_3", "to": "pl_1", "form": {"title": "Persuasion check (DC 12)",
		"fields": [{"key": "inspiration", "type": "bool", "label": "Add my die"}],
		"choices": [{"id": "skill:persuasion", "label": "Roll Persuasion +5", "intent": {"kind": "action", "action": "answer_request", "ctx": {"choice": "skill:persuasion", "form": "$values"}}},
			{"id": "skill:deception", "label": "Roll Deception +3"}]}, "default": {"choice": "skill:persuasion"}}]})
	await tree.process_frame
	check(_find(r3, "Button", "Answer") == null and _find(r3, "Button", "Roll Persuasion +5") != null and _find(r3, "Button", "Roll Deception +3") != null, "a Roll button per choice, no Answer")
	_find(r3, "Button", "Roll Persuasion +5").pressed.emit()
	check(sent3.size() == 1 and sent3[0].kind == "action" and sent3[0].action == "answer_request" and sent3[0].ctx.form is Dictionary and sent3[0].ctx.form.has("inspiration"), "a choice with an intent sends it, the form's values at $values: %s" % [sent3])
	check((_find(r3, "Button", "Roll Deception +3") as Button).disabled, "one tap per card: the other buttons wait")
	r3.render({"type": "prompt", "bind": "/prompts/0"}, {"prompts": [{"id": "p_4", "to": "pl_1", "form": {"title": "Which?", "choices": [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}]}, "default": {}}]})
	await tree.process_frame
	_find(r3, "Button", "B").pressed.emit()
	check(sent3.size() == 2 and sent3[1].kind == "answer" and sent3[1].prompt == "p_4" and sent3[1].answer.choice == "b", "a choice without one answers with its id: %s" % [sent3])
	r3.queue_free()
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
	var act := _find(r, "Button", "Act  [1 action]")
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
	# rules text: markdown as the SRDs write it, rendered rich
	check(ViewRenderer.markdown_to_bbcode("A **bold** and *italic* word\n# Heading\n- one\n[x]") == "A [b]bold[/b] and [i]italic[/i] word\n[b]Heading[/b]\n  • one\n[lb]x]", "markdown to BBCode, brackets escaped")
	var tb := ViewRenderer.markdown_to_bbcode("Table: Skills\n\n|Skill|Ability|\n|---|---|\n|Acrobatics|**Dex**|\n|||\nAfter")
	check(tb == "[b]Skills[/b]\n\n[table=2][cell][b]Skill[/b]   [/cell][cell][b]Ability[/b]   [/cell][cell]Acrobatics   [/cell][cell][b]Dex[/b]   [/cell][/table]\nAfter", "markdown tables to BBCode tables: the caption bold, the header bold, empty rows left out (%s)" % tb)
	var up := "upload:" + "a".repeat(32)
	check(ViewRenderer.markdown_to_bbcode("A ![The door](%s) here\n![](%s)" % [up, up]) == "A [i](The door)[/i] here\n[i](a picture)[/i]", "a picture in a note: said where it is (the web screens draw it)")
	var nohead := ViewRenderer.markdown_to_bbcode("|||\n|---|---|\n|Hit Point Die|D8|")
	check(nohead == "[table=2][cell]Hit Point Die   [/cell][cell]D8   [/cell][/table]", "a table with an empty header row has no header (%s)" % nohead)
	r.render({"type": "text", "text": "**Casting Time:** Action", "rich": true}, {})
	var rich := _find(r, "RichTextLabel", "")
	check(rich != null and (rich as RichTextLabel).text == "[b]Casting Time:[/b] Action", "a rich text node is a RichTextLabel with BBCode")
	# the generic entry card: the name, the facts on one line, the text
	var data := EntryCard.data_for({"id": "x", "name": "Acid Arrow", "level": 2, "school": "evocation", "ritual": false, "concentration": true, "classes": ["wizard"], "shape": {}, "text": "A green arrow."})
	check(data.facts == ["classes wizard", "concentration", "level 2", "school evocation"], "facts: scalars and flat lists, true flags by name, nothing empty: %s" % [data.facts])
	r.render(EntryCard.generic(), data)
	check(_find(r, "Label", "Acid Arrow") != null and _find(r, "Label", "classes wizard · concentration · level 2 · school evocation") != null and _find(r, "RichTextLabel", "") != null, "the generic card renders name, facts and text")
	r.queue_free()
	await tree.process_frame


func test_a_signed_number() -> void:
	# a modifier reads with its sign (an Initiative of +2 read "2")
	var r := ViewRenderer.new()
	root.add_child(r)
	r.render({"type": "row", "children": [
		{"type": "number", "label": "Initiative", "bind": "/derived/init", "signed": true},
		{"type": "number", "label": "Penalty", "bind": "/derived/penalty", "signed": true},
		{"type": "number", "label": "Even", "bind": "/derived/even", "signed": true},
		{"type": "number", "label": "AC", "bind": "/derived/ac"}]},
		{"derived": {"init": TypedNumber.make([{"label": "dexterity", "type": "ability", "value": 2}]), "penalty": -1, "even": 0,
			"ac": TypedNumber.make([{"label": "base", "type": "base", "value": 12}])}})
	await tree.process_frame
	var init := _find(r, "Label", "+2")
	check(init != null and init.tooltip_text.contains("dexterity +2"), "a typed number with its sign, its breakdown still the tooltip")
	check(_find(r, "Label", "-1") != null and _find(r, "Label", "+0") != null, "a plain number too; nought is +0")
	check(_find(r, "Label", "12") != null and _find(r, "Label", "+12") == null, "without `signed`, as before")
	check(ViewRenderer._signed("—") == "—", "a value that isn't a number reads as it is")
	r.queue_free()
	await tree.process_frame


## A form or wizard field may take its choices from a collection: what
## the campaign has, less what it turned off, plus what it imported.
func test_choice_fields_come_from_the_compendium() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	var asked := []
	var entries := [{"id": "fighter", "name": "Fighter"}, {"id": "wizard", "name": "Wizard"}]
	r.comp_source = func(coll: String, req: Dictionary, on_reply: Callable) -> void:
		asked.append({"collection": coll, "req": req})
		on_reply.call({"collection": coll, "page": {"entries": entries, "total": entries.size()}})
	var sent := []
	r.intent.connect(func(p: Dictionary) -> void: sent.append(p))
	r.render({"type": "form", "fields": [
		{"key": "name", "label": "Name", "type": "string"},
		{"key": "class", "label": "Class", "type": "enum", "collection": "classes", "query": {"filter": {"subclass_of": ""}}}],
		"submit_label": "Make", "submit": {"kind": "action", "plugin": "p", "action": "create", "ctx": {"form": "$values"}}}, {})
	await tree.process_frame
	check(asked.size() == 1 and str(asked[0].collection) == "classes" and asked[0].req.query.filter == {"subclass_of": ""}, "the collection is asked for, with the field's filter: %s" % [asked])
	var ob := _find(r, "OptionButton") as OptionButton
	check(ob != null and ob.item_count == 2 and ob.get_item_text(0) == "Fighter" and ob.get_item_text(1) == "Wizard", "the entries are the choices, by name")
	ob.select(1)
	ob.item_selected.emit(1)
	_find(r, "Button", "Make").pressed.emit()
	check(sent.size() == 1 and str(sent[0].ctx.form["class"]) == "wizard", "and the id is what the intent carries: %s" % [sent])
	# what the campaign turned off is simply not in the answer, so it is not a choice
	entries.remove_at(1)
	r.render({"type": "wizard", "steps": [{"title": "Who", "fields": [
		{"key": "class", "label": "Class", "type": "enum", "collection": "classes"}]}], "submit": {"kind": "action", "plugin": "p", "action": "go"}}, {})
	await tree.process_frame
	var ob2 := _find(r, "OptionButton") as OptionButton
	check(ob2 != null, "the wizard step has a choice control")
	if ob2 != null:
		check(ob2.item_count == 1 and ob2.get_item_text(0) == "Fighter", "with the campaign's choices: %d items, first '%s'" % [ob2.item_count, ob2.get_item_text(0) if ob2.item_count > 0 else ""])
	r.queue_free()
	await tree.process_frame


## A field's choices from the view's own data: "who" — the whole party, or
## one of the characters in the data.
func test_choice_fields_come_from_the_data() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	var sent := []
	r.intent.connect(func(p: Dictionary) -> void: sent.append(p))
	var data := {"actors": [{"id": "a_1", "name": "Brakka", "kind": "pc"}, {"id": "g_1", "name": "Goblin", "kind": "monster"}, {"id": "a_2", "name": "Mira", "kind": "pc"}]}
	r.render({"type": "form", "fields": [
		{"key": "who", "label": "Who", "type": "enum", "from": {"bind": "/actors", "if": "@item.kind == 'pc'", "first": [{"id": "", "name": "The whole party"}]}}],
		"values": {"who": ""}, "submit_label": "Ask", "submit": {"kind": "action", "plugin": "p", "action": "ask", "ctx": {"form": "$values"}}}, data)
	var ob := _find(r, "OptionButton") as OptionButton
	check(ob != null and ob.item_count == 3 and ob.get_item_text(0) == "The whole party" and ob.get_item_text(1) == "Brakka" and ob.get_item_text(2) == "Mira", "the whole party, then the characters, not the goblin")
	ob.select(2)
	ob.item_selected.emit(2)
	_find(r, "Button", "Ask").pressed.emit()
	check(sent.size() == 1 and str(sent[0].ctx.form.who) == "a_2", "the id is what is sent: %s" % [sent])
	check(ViewRenderer.options_from({"bind": "/actors", "label": "@item.name .. ' (' .. @item.kind .. ')'"}, data).map(func(o: Dictionary) -> String: return str(o.name)) == ["Brakka (pc)", "Goblin (monster)", "Mira (pc)"], "a label expression")
	check(ViewRenderer.options_from({"bind": "/nothing"}, data).is_empty(), "nothing at the pointer: no choices")
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
	# the words typed, in any order, each the start of a word (a playtest's DM found
	# nothing for "Lantern, Hooded" nor "thieves' tools")
	check(ViewRenderer.match_words("Lantern, Hooded", "hooded lan") and ViewRenderer.match_words("Lantern, Hooded", "Lantern, Hooded")
		and ViewRenderer.match_words("Thieves' Tools", "thieves' tools") and ViewRenderer.match_words("Anything", ""), "every word typed starts one of the name's")
	check(not ViewRenderer.match_words("Lantern, Hooded", "hooded lamp") and not ViewRenderer.match_words("Rope", "ope"), "and not a word it doesn't start")
	# a `sub` beside each name (the price of what a player buys)
	var shop := ViewRenderer.new()
	root.add_child(shop)
	shop.render({"type": "picker", "bind": "/gear", "sub": "@item.cost .. ' GP'", "on_pick": {}}, {"gear": [{"id": "rope", "name": "Rope", "cost": 1}, "Chalk"]})
	var sl: ItemList = _all(shop, "ItemList")[0]
	check(sl.get_item_text(0) == "Rope  ·  1 GP" and sl.get_item_text(1) == "Chalk", "the sub line beside a record's name: %s" % [sl.get_item_text(0)])
	shop.queue_free()
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
	check(_find(r, "Label", "New hero: Kind (2/2)") != null and _find(r, "RichTextLabel", "Pick one") != null and _find(r, "Button", "Submit") != null, "the second step, with its text and Submit")
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


## A card's heading, facts and tags: the name with the line under it, the
## labelled facts (an empty one left out), the tags that apply.
func test_title_facts_and_tags() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	r.render({"type": "column", "children": [
		{"type": "title", "bind": "/entry/name", "sub": {"expr": "'Level ' .. @entry.level .. ' ' .. @entry.school"}, "icon": {"bind": "/entry/icon"}},
		{"type": "facts", "items": [
			{"label": "Casting time", "bind": "/entry/casting_time"},
			{"label": "Range", "text": "60 feet"},
			{"label": "Material", "bind": "/entry/material"},
			{"label": "Hidden", "text": "x", "if": "false"}]},
		{"type": "tags", "items": [{"text": "Concentration", "if": "@entry.concentration"}, {"text": "Ritual", "if": "@entry.ritual"}]}]},
		{"entry": {"name": "Faerie Fire", "level": 1, "school": "evocation", "casting_time": "Action", "material": "", "concentration": true, "ritual": false}})
	check(_find(r, "Label", "Faerie Fire") != null and _find(r, "Label", "Level 1 evocation") != null, "the title and the line under it")
	check(_all(r, "TextureRect").is_empty(), "no icon when the entry has none")
	check(_find(r, "Label", "Casting time") != null and _find(r, "Label", "Action") != null and _find(r, "Label", "60 feet") != null, "the facts, labelled")
	check(_find(r, "Label", "Material") == null and _find(r, "Label", "Hidden") == null, "an empty fact and one whose if is false are left out")
	check(_find(r, "Label", "[Concentration]") != null and _find(r, "Label", "[Ritual]") == null, "the tags that apply")
	check(_find(r, "Label", "title:") == null and _find(r, "Label", "facts:") == null, "none of them falls back to text")
	r.queue_free()
	await tree.process_frame


## `choose` and `scores` fields on the desktop: check boxes that stop at
## the count with what is had already ticked and locked; spin boxes under
## the method with the background's bonus where the class wants it.
func test_choose_and_scores_fields() -> void:
	var pf := PropertyForm.new()
	root.add_child(pf)
	var skills := {"key": "skills", "label": "Skills", "type": "choose", "count": 2, "allowed": ["arcana", "nature", "perception"], "fixed": ["stealth"],
		"options": [{"id": "arcana", "name": "Arcana"}, {"id": "nature", "name": "Nature"}, {"id": "perception", "name": "Perception"}, {"id": "stealth", "name": "Stealth"}, {"id": "athletics", "name": "Athletics"}]}
	var abil := {"key": "abilities", "label": "Abilities", "type": "scores", "method": "point_buy", "stats": [{"id": "str", "name": "Strength"}, {"id": "dex", "name": "Dexterity"}, {"id": "wis", "name": "Wisdom"}],
		"suggest": {"str": 8, "dex": 14, "wis": 15}, "primary": ["wis"], "bonus": {"among": ["dex", "con", "wis"], "cap": 20}}
	var kit := {"key": "kit", "label": "Kit", "type": "choose", "single": true, "options": [{"id": "A", "name": "Package A"}, {"id": "B", "name": "155 GP"}]}
	pf.build([skills, abil, kit], {"skills": ["arcana"]})
	var boxes := _all(pf, "CheckBox")
	check(boxes.size() == 4 and _find(pf, "CheckBox", "Athletics") == null, "the allowed options and the one had already, nothing else (%d boxes)" % boxes.size())
	var stealth := _find(pf, "CheckBox", "Stealth") as CheckBox
	check(stealth != null and stealth.button_pressed and stealth.disabled, "what is had already: ticked and locked")
	(_find(pf, "CheckBox", "Nature") as CheckBox).button_pressed = true
	check(pf.get_values().skills == ["arcana", "nature"], "two chosen: %s" % [pf.get_values().skills])
	check((_find(pf, "CheckBox", "Perception") as CheckBox).disabled, "and no more can be")
	var sc: Dictionary = pf.get_values().abilities
	check(sc.method == "point_buy" and sc.base == {"str": 8, "dex": 8, "wis": 8}, "the scores start from the minimums, not the class's suggestion: %s" % [sc])
	check(sc.bonus == {"wis": 2, "dex": 1} and sc.final.wis == 10 and sc.final.dex == 9, "the bonus goes on the class's key ability, then the next offered: %s" % [sc])
	check(pf.get_values().kit == "", "a single choice starts unchosen")
	var ob := _find(pf, "OptionButton") as OptionButton
	ob.select(2)
	check(pf.get_values().kit == "B", "and takes the id picked")
	pf.queue_free()
	await tree.process_frame


## A wizard's steps and fields see the answers so far: a step whose `if`
## is false is skipped, `{expr}` properties are worked out, and only the
## answers of what applied are sent.
func test_wizard_steps_follow_the_answers() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	var sent := []
	r.intent.connect(func(p: Dictionary) -> void: sent.append(p))
	r.render({"type": "wizard", "steps": [
		{"title": "Who", "fields": [{"key": "caster", "label": "Caster", "type": "bool"}]},
		{"title": "Spells", "if": "@values.caster", "fields": [{"key": "spells", "label": "Spells", "type": "choose", "count": {"expr": "@values.caster ? 1 : 0"}, "options": ["a", "b"]}]},
		{"title": "Done", "fields": [{"key": "note", "label": "Note", "type": "string"}]}],
		"submit": {"kind": "action", "plugin": "p", "action": "make", "ctx": {"form": "$values"}}}, {})
	await tree.process_frame
	check(_find(r, "Label", "Who (1/3)") != null or _find(r, "Label", "Who") != null, "the first step")
	_find(r, "Button", "Next").pressed.emit()
	check(_find(r, "Label", "Done") != null and _find(r, "Label", "Spells") == null, "a step whose if is false is skipped")
	_find(r, "Button", "Back").pressed.emit()
	(_find(r, "CheckBox") as CheckBox).button_pressed = true
	_find(r, "Button", "Next").pressed.emit()
	check(_find(r, "Label", "Spells") != null, "and shown when the answers call for it")
	(_find(r, "CheckBox", "a") as CheckBox).button_pressed = true
	check((_find(r, "CheckBox", "b") as CheckBox).disabled, "its count worked out from the answers (one)")
	_find(r, "Button", "Next").pressed.emit()
	_find(r, "Button", "Submit").pressed.emit()
	check(sent.size() == 1 and sent[0].ctx.form.spells == ["a"] and sent[0].ctx.form.caster == true, "the answers sent: %s" % [sent])
	# the same wizard without the caster: the spells are not sent
	sent.clear()
	r.render({"type": "wizard", "steps": [
		{"title": "Who", "fields": [{"key": "caster", "label": "Caster", "type": "bool"}]},
		{"title": "Spells", "if": "@values.caster", "fields": [{"key": "spells", "label": "Spells", "type": "choose", "count": 1, "options": ["a", "b"]}]}],
		"submit": {"kind": "action", "plugin": "p", "action": "make", "ctx": {"form": "$values"}}}, {})
	await tree.process_frame
	_find(r, "Button", "Submit").pressed.emit()
	check(sent.size() == 1 and not sent[0].ctx.form.has("spells"), "a skipped step's fields are not sent: %s" % [sent])
	r.queue_free()
	await tree.process_frame


## A step's text may be `{expr}` too, and an answer picked from a list of
## records puts that record in @chosen, as on the web (the character maker's
## weapons step says the packages chosen before it; its last step says what
## the choices give).
func test_wizard_text_and_chosen_records() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	var sent := []
	r.intent.connect(func(p: Dictionary) -> void: sent.append(p))
	r.render({"type": "wizard", "steps": [
		{"title": "Kit", "text": "Choose **one**.", "fields": [{"key": "kit", "label": "Kit", "type": "choose", "single": true, "options": [
			{"id": "A", "name": "Package A", "text": "a sword and a shield"}, {"id": "B", "name": "Package B", "text": "a bow"}]}]},
		{"title": "Weapons", "text": {"expr": "@chosen.kit != null ? 'Your package: ' .. @chosen.kit.text .. '.' : 'No package.'"},
			"fields": [{"key": "note", "label": "Note", "type": "string"}]},
		{"title": "Done", "text": {"expr": "'You wrote **' .. @values.note .. '**.'"}}],
		"submit": {"kind": "action", "plugin": "p", "action": "make", "ctx": {"form": "$values"}}}, {})
	await tree.process_frame
	check(_find(r, "RichTextLabel", "Choose [b]one[/b].") != null, "a step's text reads as Markdown")
	var pick := _find(r, "OptionButton") as OptionButton
	pick.select(2)
	_find(r, "Button", "Next").pressed.emit()
	check(_find(r, "RichTextLabel", "Your package: a bow.") != null, "the next step's text, worked out from the record picked")
	(_all(r, "LineEdit")[0] as LineEdit).text = "Hi"
	_find(r, "Button", "Next").pressed.emit()
	check(_find(r, "RichTextLabel", "You wrote [b]Hi[/b].") != null, "and from the answers: a last step with no fields")
	_find(r, "Button", "Back").pressed.emit()
	_find(r, "Button", "Back").pressed.emit()
	pick = _find(r, "OptionButton") as OptionButton
	pick.select(0)
	_find(r, "Button", "Next").pressed.emit()
	check(_find(r, "RichTextLabel", "No package.") != null, "nothing picked: no record")
	_find(r, "Button", "Next").pressed.emit()
	_find(r, "Button", "Submit").pressed.emit()
	check(sent.size() == 1 and sent[0].ctx.form == {"kit": "", "note": "Hi"}, "the answers sent, as ever: %s" % [sent])
	r.queue_free()
	await tree.process_frame
