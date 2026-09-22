class_name LookupPopup
extends AcceptDialog
## Look something up: a search across every collection at the table, a
## list of what matched, and the entry as a card (the ruleset's, or a
## generic one). Opened from the Table's View menu (Ctrl/Cmd+L) or by a
## `lookup` intent from a sheet's button, on the Table and on a phone.
## `source` is Callable(collection, req, on_reply) shaped like
## Session.comp: the Table's compendium, or a phone's link to it.

var source: Callable = Callable()
## {collection: {plugin, schema}} — the projection's cards (or a host's).
var cards: Dictionary = {}
var collections: Array = []
var role := "gm"
var _search: LineEdit
var _results: ItemList
var _card: ViewRenderer
var _seq := 0


func _init() -> void:
	title = "Look up"
	ok_button_text = "Close"
	min_size = Vector2i(520, 560)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_search = LineEdit.new()
	_search.placeholder_text = "A spell, a creature, an item, a feature…"
	_search.text_changed.connect(func(_t: String) -> void: search())
	_search.text_submitted.connect(func(_t: String) -> void:
		if _results.item_count > 0:
			_results.select(0)
			_open_selected())
	box.add_child(_search)
	_results = ItemList.new()
	_results.custom_minimum_size = Vector2(0, 120)
	_results.item_selected.connect(func(_i: int) -> void: _open_selected())
	box.add_child(_results)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card = ViewRenderer.new()
	scroll.add_child(_card)
	box.add_child(scroll)
	add_child(box)
	confirmed.connect(hide)
	close_requested.connect(hide)


## Open with a search typed in (or empty), the search box focused.
func open(query := "") -> void:
	popup_centered()
	_search.text = query
	search()
	_search.grab_focus()
	_search.caret_column = query.length()


## Open straight on an entry.
func show_entry(collection: String, id: String) -> void:
	popup_centered()
	_results.clear()
	_search.text = ""
	if not source.is_valid():
		_card.render(EntryCard.generic(), EntryCard.data_for({"name": "No compendium here"}))
		return
	source.call(collection, {"id": id}, func(reply: Dictionary) -> void:
		if reply.has("entry"):
			_card.render(EntryCard.schema_for(cards, collection), EntryCard.data_for(reply.entry, role))
		else:
			_card.render(EntryCard.generic(), EntryCard.data_for({"name": str(reply.get("error", "not found")), "text": "%s: %s" % [collection, id]})))


## Every collection, a few names each, the query's words in them.
func search() -> void:
	var q := _search.text.strip_edges()
	_results.clear()
	if q == "" or not source.is_valid():
		return
	_seq += 1
	var seq := _seq
	for coll in collections:
		source.call(coll, {"query": {"text": q, "per_page": 8, "fields": ["name"]}}, func(reply: Dictionary) -> void:
			if seq != _seq or not reply.has("page"):
				return
			for e in reply.page.get("entries", []):
				var i := _results.add_item("%s  (%s)" % [str(e.get("name", e.get("id", ""))), str(coll)])
				_results.set_item_metadata(i, {"collection": str(coll), "id": str(e.get("id", ""))}))


func _open_selected() -> void:
	var sel := _results.get_selected_items()
	if sel.is_empty():
		return
	var m: Dictionary = _results.get_item_metadata(sel[0])
	if not source.is_valid():
		return
	source.call(str(m.collection), {"id": str(m.id)}, func(reply: Dictionary) -> void:
		if reply.has("entry"):
			_card.render(EntryCard.schema_for(cards, str(m.collection)), EntryCard.data_for(reply.entry, role)))
