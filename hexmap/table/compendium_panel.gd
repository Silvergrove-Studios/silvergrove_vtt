class_name CompendiumPanel
extends VBoxContainer
## Browse the content packs at this table, page by page: pick a
## collection, search, narrow by a facet, open an entry. A shipped entry
## can be copied into the table's homebrew and edited there in a form
## the plugin's schema generates; a homebrew entry can be edited or
## removed; the homebrew pack is saved under user://content and can be
## exported as one file to share. Plugin actions that take an entry
## (`target = "entry"`) show as buttons on the open entry. An entry
## opens as a card to read (the ruleset's, or a generic one); *Edit*
## shows the fields. *Use at this table* turns an entry off for this
## campaign — hidden from every search, picker and wizard, never
## deleted, back the moment it is ticked again — and *Import content…*
## brings a pack or a file of entries into the campaign.

var ctx: TableContext
var _collection: OptionButton
var _search: LineEdit
var _facet_field: OptionButton
var _facet_values: HFlowContainer
var _facet_value := ""
var _list: ItemList
var _page_label: Label
var _prev: Button
var _next: Button
var _detail: VBoxContainer
var _form: SchemaForm
var _json: TextEdit
var _card: ViewRenderer
var _fields: Control
var editing := false
var _show_disabled: CheckBox
var _use: CheckBox
## Set by the window: opens a file dialog and calls back with a path.
var pick_content_file: Callable
var _entry: Dictionary = {}
var _result: Dictionary = {}
var _page := 1
const PER_PAGE := 30


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	_collection = OptionButton.new()
	_collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collection.item_selected.connect(func(_i: int) -> void:
		_facet_value = ""
		_page = 1
		_refresh_facet_fields()
		_query())
	top.add_child(_collection)
	add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void:
		_page = 1
		_query())
	add_child(_search)
	var frow := HBoxContainer.new()
	_facet_field = OptionButton.new()
	_facet_field.tooltip_text = "Narrow by a field"
	_facet_field.item_selected.connect(func(_i: int) -> void:
		_facet_value = ""
		_page = 1
		_query())
	frow.add_child(_facet_field)
	_facet_values = HFlowContainer.new()
	_facet_values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(_facet_values)
	add_child(frow)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 120
	_list.item_selected.connect(func(i: int) -> void: _open(str(_list.get_item_metadata(i))))
	add_child(_list)
	var prow := HBoxContainer.new()
	_prev = Button.new()
	_prev.text = "‹"
	_prev.theme_type_variation = "ToolButton"
	_prev.pressed.connect(func() -> void:
		_page = maxi(1, _page - 1)
		_query())
	prow.add_child(_prev)
	_page_label = Label.new()
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.theme_type_variation = "DimLabel"
	prow.add_child(_page_label)
	_next = Button.new()
	_next.text = "›"
	_next.theme_type_variation = "ToolButton"
	_next.pressed.connect(func() -> void:
		_page += 1
		_query())
	prow.add_child(_next)
	var new_b := Button.new()
	new_b.text = "New"
	new_b.tooltip_text = "A new homebrew entry in this collection"
	new_b.pressed.connect(_new)
	prow.add_child(new_b)
	add_child(prow)
	var crow := HFlowContainer.new()
	_show_disabled = CheckBox.new()
	_show_disabled.text = "Show what is off"
	_show_disabled.tooltip_text = "List the entries this campaign does not use, struck through"
	_show_disabled.toggled.connect(func(_on: bool) -> void:
		_page = 1
		_query())
	crow.add_child(_show_disabled)
	var import_b := Button.new()
	import_b.text = "Import content…"
	import_b.tooltip_text = "A pack folder, a one-file pack or a file of entries, into this campaign (the table's library is a good place to look)"
	import_b.pressed.connect(func() -> void:
		if pick_content_file.is_valid():
			pick_content_file.call(func(path: String) -> void: ctx.say(import_content(path))))
	crow.add_child(import_b)
	add_child(crow)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)
	add_child(scroll)
	ctx.encounter_changed.connect(refresh)


func bind() -> void:
	refresh()


func comp() -> Compendium:
	return ctx.kernel.comp if ctx.kernel != null else null


func collection() -> String:
	return str(_collection.get_item_metadata(_collection.selected)) if _collection.selected >= 0 and _collection.item_count > 0 else ""


## The plugin that declared a schema for the collection, or "".
func plugin_for(coll: String) -> String:
	if ctx.host == null:
		return ""
	for pid in ctx.host.plugins:
		if (ctx.host.plugins[pid] as PluginHost.Plugin).schemas.has(coll):
			return str(pid)
	return ""


func schema_for(coll: String) -> JsonSchema:
	var pid := plugin_for(coll)
	return (ctx.host.plugins[pid] as PluginHost.Plugin).schemas[coll] if pid != "" else null


## The writable pack a homebrew entry of this collection goes into.
## The campaign's writable pack for this collection's plugin, or "" when
## the campaign has nowhere to keep it yet.
func homebrew_pack(coll: String) -> String:
	var pid := plugin_for(coll)
	var id := (pid + ".homebrew") if pid != "" else "table.homebrew"
	if comp().user_dir == "":
		return ""
	comp().user_pack(id, ("%s homebrew" % str(ctx.host.plugins[pid].manifest.get("name", pid))) if pid != "" else "Table homebrew", pid)
	# a pack of the campaign's own is listed by it, so it loads next time
	if ctx.campaign != null and not ctx.campaign.packs.any(func(e: Dictionary) -> bool: return str(e.get("id", "")) == id):
		ctx.campaign.packs.append({"id": id, "path": "packs/%s" % id, "version": "1"})
		ctx.campaign.touch()
	return id


func refresh() -> void:
	if comp() == null:
		return
	var current := collection()
	_collection.clear()
	var i := 0
	for c in comp().collections():
		_collection.add_item("%s (%d)" % [str(c), comp().count(str(c))])
		_collection.set_item_metadata(i, str(c))
		if str(c) == current:
			_collection.select(i)
		i += 1
	_refresh_facet_fields()
	_query()


func _refresh_facet_fields() -> void:
	var current := str(_facet_field.get_item_metadata(_facet_field.selected)) if _facet_field.selected >= 0 and _facet_field.item_count > 0 else ""
	_facet_field.clear()
	_facet_field.add_item("(any field)")
	_facet_field.set_item_metadata(0, "")
	var i := 1
	var fields := comp().facets(collection()).keys() if collection() != "" else []
	fields.sort()
	for f in fields:
		_facet_field.add_item(str(f))
		_facet_field.set_item_metadata(i, str(f))
		if str(f) == current:
			_facet_field.select(i)
		i += 1


func _query() -> void:
	var coll := collection()
	_list.clear()
	for c in _facet_values.get_children():
		_facet_values.remove_child(c)
		c.queue_free()
	if coll == "" or comp() == null:
		_page_label.text = "No content packs loaded."
		return
	var field := str(_facet_field.get_item_metadata(_facet_field.selected)) if _facet_field.selected >= 0 else ""
	var opts := {"text": _search.text, "page": _page, "per_page": PER_PAGE, "fields": ["name"], "facets": [field] if field != "" else [],
		"disabled": _show_disabled.button_pressed}
	if field != "" and _facet_value != "":
		opts.filter = {field: _facet_value}
	_result = comp().query(coll, opts)
	for e in _result.entries:
		var off := comp().is_disabled(coll, str(e.id))
		var idx := _list.add_item("%s%s   ·  %s" % ["✗ " if off else "", str(e.get("name", e.id)), str(e.get("__pack", ""))])
		_list.set_item_metadata(idx, str(e.id))
		if off:
			_list.set_item_custom_fg_color(idx, Color(0.6, 0.6, 0.62))
		if not _entry.is_empty() and str(_entry.get("id", "")) == str(e.id):
			_list.select(idx)
	var n_off := comp().disabled_count(coll)
	_page_label.text = "%d–%d of %d%s" % [(_page - 1) * PER_PAGE + 1, mini(_page * PER_PAGE, int(_result.total)), int(_result.total),
		("  ·  %d off" % n_off) if n_off > 0 and not _show_disabled.button_pressed else ""] if int(_result.total) > 0 else "Nothing matches."
	_prev.disabled = _page <= 1
	_next.disabled = _page >= int(_result.pages)
	if field != "":
		var counts: Dictionary = _result.facets.get(field, {})
		var values := counts.keys()
		values.sort()
		for v in values.slice(0, 24):
			var b := Button.new()
			b.text = "%s (%d)" % [str(v), int(counts[v])]
			b.toggle_mode = true
			b.button_pressed = str(v) == _facet_value
			b.theme_type_variation = "ToolButton"
			b.pressed.connect(func() -> void:
				_facet_value = "" if _facet_value == str(v) else str(v)
				_page = 1
				_query())
			_facet_values.add_child(b)


# ---------------------------------------------------------------- detail --

func _open(id: String) -> void:
	_entry = comp().get_entry(collection(), id)
	_show_entry()


func _new() -> void:
	var coll := collection()
	if coll == "":
		return
	var pid := homebrew_pack(coll)
	if pid == "":
		ctx.say("Save the campaign first: its content is kept beside it")
		return
	_entry = {"id": JsonDoc.new_id("hb"), "name": "New entry", "__pack": pid}
	_show_entry()


func _show_entry() -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	_form = null
	_json = null
	if _entry.is_empty():
		return
	var coll := collection()
	var pack_id := str(_entry.get("__pack", ""))
	var writable := comp().packs.has(pack_id) and bool(comp().packs[pack_id].get("user", false))
	var head := Label.new()
	head.text = "%s — %s%s" % [str(_entry.get("name", _entry.id)), pack_id, "" if writable else " (read-only; Copy to homebrew to edit)"]
	head.theme_type_variation = "HeaderLabel"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(head)
	var prov: Dictionary = comp().packs.get(pack_id, {}).get("provenance", {})
	if not prov.is_empty():
		var pl := Label.new()
		pl.text = "%s%s" % [str(prov.get("attribution", prov.get("source", ""))), (" · " + str(prov.license)) if prov.has("license") else ""]
		pl.theme_type_variation = "DimLabel"
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(pl)
	var record: Dictionary = JsonDoc.deep(_entry)
	record.erase("__pack")
	# the card first; the fields behind Edit (a new homebrew entry opens on them)
	_card = ViewRenderer.new()
	_card.render(EntryCard.schema_for(EntryCard.cards_of(ctx.host), coll), EntryCard.data_for(_entry))
	_detail.add_child(_card)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_child(_fields)
	var schema := schema_for(coll)
	if schema != null:
		_form = SchemaForm.new()
		_form.build(schema.root, record)
		_fields.add_child(_form)
	else:
		_json = TextEdit.new()
		_json.custom_minimum_size.y = 160
		_json.text = JsonDoc.stringify(record)
		_fields.add_child(_json)
	if str(_entry.get("name", "")) == "New entry":
		editing = true
	_card.visible = not editing
	_fields.visible = editing
	var row := HFlowContainer.new()
	# in or out of this campaign: the entry stays in its pack either way
	_use = CheckBox.new()
	_use.text = "Use at this table"
	_use.tooltip_text = "Off: hidden from every search, picker and wizard here. The entry stays in its pack and comes back the moment this is ticked."
	_use.button_pressed = not comp().is_disabled(coll, str(_entry.get("id", "")))
	_use.disabled = ctx.campaign == null
	_use.toggled.connect(func(on: bool) -> void: ctx.say(set_used(coll, str(_entry.get("id", "")), on)))
	row.add_child(_use)
	var edit := Button.new()
	edit.text = "Done" if editing else ("Edit" if writable else "Fields")
	edit.tooltip_text = "The entry's fields" if not editing else "Back to the card"
	edit.pressed.connect(func() -> void:
		editing = not editing
		_card.visible = not editing
		_fields.visible = editing
		edit.text = "Done" if editing else ("Edit" if writable else "Fields"))
	row.add_child(edit)
	if writable:
		var save := Button.new()
		save.text = "Save"
		save.theme_type_variation = "AccentButton"
		save.pressed.connect(_save)
		row.add_child(save)
		var del := Button.new()
		del.text = "Delete"
		del.pressed.connect(func() -> void:
			ctx.say(comp().remove(coll, str(_entry.id), pack_id))
			comp().save_user_pack(pack_id)
			_entry = {}
			refresh()
			_show_entry())
		row.add_child(del)
	else:
		var copy := Button.new()
		copy.text = "Copy to homebrew"
		copy.tooltip_text = "A copy of this entry in the campaign's homebrew pack, to edit"
		copy.pressed.connect(func() -> void:
			var dup: Dictionary = JsonDoc.deep(record)
			dup.id = str(record.id) + "-" + JsonDoc.new_id("hb").substr(3)
			dup.name = str(record.get("name", record.id)) + " (homebrew)"
			var pid := homebrew_pack(coll)
			if pid == "":
				ctx.say("Save the campaign first: its content is kept beside it")
				return
			ctx.say(comp().put(coll, dup, pid, schema))
			comp().save_user_pack(pid)
			_entry = comp().get_entry(coll, str(dup.id))
			refresh()
			_show_entry())
		row.add_child(copy)
	var export := Button.new()
	export.text = "Export pack…"
	export.tooltip_text = "Write this entry's pack as one file, to share"
	export.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(ctx.library_dir)
		var path := ctx.library_dir.path_join("%s.pack.json" % pack_id)
		var why := comp().export_pack(pack_id, path)
		ctx.say("Exported to %s" % ProjectSettings.globalize_path(path) if why == "" else why))
	row.add_child(export)
	# plugin actions that take an entry
	if ctx.host != null:
		for pid in ctx.host.plugins:
			var p: PluginHost.Plugin = ctx.host.plugins[pid]
			for name in p.actions:
				var spec: Dictionary = p.actions[name]
				if str(spec.get("target", "")) != "entry" or (spec.has("collection") and str(spec.collection) != coll):
					continue
				var b := Button.new()
				b.text = str(spec.get("label", name))
				b.pressed.connect(func() -> void:
					var pc := ctx.host.dispatch(str(pid), str(name), {"entry": record, "collection": coll, "scene": ctx.scene_id})
					if pc.status == PluginHost.PluginCall.ERROR:
						ctx.say(pc.error)
					else:
						ctx.kernel.pending.drive(pc, str(pid)))
				row.add_child(b)
	_detail.add_child(row)


func _save() -> void:
	var coll := collection()
	var pack_id := str(_entry.get("__pack", ""))
	var record: Dictionary
	if _form != null:
		if not _form.validate():
			ctx.say("Fix the fields marked below the form")
			return
		record = _form.values()
	else:
		var err := []
		record = JsonDoc.parse(_json.text, err)
		if record.is_empty():
			ctx.say("Not valid JSON: " + ", ".join(PackedStringArray(err)))
			return
	record.id = str(_entry.id)
	var why := comp().put(coll, record, pack_id, schema_for(coll))
	if why != "":
		ctx.say(why)
		return
	why = comp().save_user_pack(pack_id)
	ctx.say("Saved %s" % str(record.get("name", record.id)) if why == "" else why)
	_entry = comp().get_entry(coll, str(record.id))
	refresh()
	_show_entry()


## Turn an entry on or off for this campaign. What happened, for the status line.
func set_used(coll: String, id: String, on: bool) -> String:
	if ctx.campaign == null:
		return "No campaign is open"
	if id == "":
		return ""
	var e := comp().get_entry(coll, id)
	var plugin := plugin_for(coll)
	ctx.campaign.set_disabled(plugin, coll, id, not on)
	comp().disabled = ctx.campaign.disabled_index()
	ctx.campaign_changed.emit()
	_query()
	if on:
		return "%s is in play again" % str(e.get("name", id))
	var used := _in_play(coll, id)
	return "%s is off at this table%s" % [str(e.get("name", id)), ("; %s already uses it and keeps working" % used) if used != "" else ""]


## The name of a character already built on this entry, or "" — turning
## something off never breaks what is already in play, and the DM should hear so.
func _in_play(coll: String, id: String) -> String:
	for a in ctx.encounter().actors.values():
		var ext: Dictionary = a.get("ext", {})
		for pid in ext:
			var blob := JsonDoc.stringify(ext[pid])
			if blob.contains("\"%s\"" % id):
				return str(a.get("name", a.get("id", "someone")))
	return ""


## Import a pack or a file of entries into the campaign. What happened.
func import_content(path: String) -> String:
	if ctx.campaign == null:
		return "No campaign is open"
	var r := ContentImport.import_into(path, ctx.campaign, ctx.host, comp())
	if not r.ok:
		return "Not imported: " + str(r.why)
	var parts := PackedStringArray()
	for name in r.added:
		parts.append("%d %s" % [int(r.added[name]), str(name)])
	refresh()
	_query()
	return "Imported %s: %s" % [str(r.id), ", ".join(parts) if not parts.is_empty() else "nothing"]
