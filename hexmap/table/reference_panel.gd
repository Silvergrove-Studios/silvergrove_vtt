class_name ReferencePanel
extends VBoxContainer
## The DM's book. Most of a session is talk, exploring and looking things up
## (playtest 1), so this is on screen whatever the DM is doing. Above, the
## campaign's contents — notes for the DM, the party, the places (each with
## its people), the people, the handouts, what the players have been shown,
## the pictures, the maps, and the rules as a glossary — with one search
## over all of it. Below, the card of whatever is open, with what can be
## done from it: a place's picture and description, a person's portrait and
## the DM's notes on them, a note, a rule. Anything with something for the
## players on it has a Show the players menu (everyone, or one of them) and
## says who has seen it (Sharing). It follows the map: select a place
## marker and its card opens; select a character and their sheet does.
##
## Refs: "actor:<id>", "place:<id>", "note:<id>", "handout:<id>",
## "picture:<pack:asset>", "map:<id>", "entry:<collection>/<id>".

var ctx: TableContext
## The ref of the card open now ("" for none) and the ones before it.
var current := ""
var history: Array = []
## Set by the window: go to a place (launch its encounter, show its map…).
var go_place: Callable = Callable()
## Set by the window: show a library map as the scene.
var show_map: Callable = Callable()
## Set by the window: ask for an image file, then call back with its path.
var pick_picture_file: Callable = Callable()
var _search: LineEdit
var _tree: Tree
var _back: Button
var _title: Label
var _card: VBoxContainer
var _renderers: Array = []
var _bound_encounter: Encounter
var _refresh_queued := false
## Rules collections opened in the contents (filled when first opened).
var _open_collections: Dictionary = {}
## What the card's Show the players menu shares: {ref, title, text, image}.
var _shareable: Dictionary = {}

const KINDS_PEOPLE := ["npc", "environment", "hazard", "custom"]
const KINDS_PARTY := ["pc", "companion"]


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search = LineEdit.new()
	_search.placeholder_text = "Look up anything — a person, a place, a note, a spell, a monster, a rule"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: refresh_list())
	_search.text_submitted.connect(func(_t: String) -> void:
		var first := _first_ref(_tree.get_root())
		if first != "":
			open(first))
	add_child(_search)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = -80
	add_child(split)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(0, 90)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(func() -> void:
		var it := _tree.get_selected()
		var ref := str(it.get_metadata(0)) if it != null else ""
		if ref != "":
			open(ref))
	_tree.item_collapsed.connect(_on_collapsed)
	split.add_child(_tree)
	var card_box := VBoxContainer.new()
	card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_box.custom_minimum_size = Vector2(0, 140)
	var head := HBoxContainer.new()
	_back = Button.new()
	_back.text = "‹ Back"
	_back.theme_type_variation = "ToolButton"
	_back.tooltip_text = "The card before this one"
	_back.pressed.connect(back)
	head.add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = "HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	card_box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card = VBoxContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.add_theme_constant_override("separation", 6)
	scroll.add_child(_card)
	card_box.add_child(scroll)
	split.add_child(card_box)
	ctx.selection_changed.connect(_follow_selection)
	ctx.art_changed.connect(_queue_refresh)


func header_actions() -> Array:
	return []


func bind() -> void:
	if _bound_encounter != null and _bound_encounter.changed.is_connected(_on_changed):
		_bound_encounter.changed.disconnect(_on_changed)
	_bound_encounter = ctx.encounter()
	_bound_encounter.changed.connect(_on_changed)
	if not ctx.campaign_changed.is_connected(_queue_refresh):
		ctx.campaign_changed.connect(_queue_refresh)
	if current != "" and not _exists(current):
		current = ""
		history.clear()
	_open_collections.clear()
	refresh()


func _on_changed(what: String, _s: String) -> void:
	if what in ["actors", "resources", "effects", "log", "players", "restore", "encounter", "scenes", "tokens"]:
		_queue_refresh()


## Many changes arrive together (a fight's round): draw once, next frame.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	# (a method, not a lambda: a pane freed before the frame ends is skipped)
	_flush_refresh.call_deferred()


func _flush_refresh() -> void:
	_refresh_queued = false
	refresh()


func refresh() -> void:
	refresh_list()
	# never pull a field out from under the DM's typing: the card waits
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and _card.is_ancestor_of(focus) and (focus is TextEdit or focus is LineEdit):
		return
	_render_card()


## Cmd/Ctrl+L: straight to the search.
func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


# ------------------------------------------------------------- the contents --

## The campaign's contents matching the search (all of them when it is
## empty), then the rules: a glossary of every collection, or the matches.
func refresh_list() -> void:
	_tree.clear()
	var root := _tree.create_item()
	if ctx.state == null:
		return
	var q := _search.text.strip_edges().to_lower()
	for g in contents(q):
		if (g.items as Array).is_empty():
			continue
		var head := _heading(root, str(g.title))
		head.collapsed = bool(g.get("collapsed", false)) and q == ""
		for it in g.items:
			_add_row(head, it)
	if q == "":
		var colls := _collections()
		if not colls.is_empty():
			var rules := _heading(root, "Rules")
			rules.collapsed = _open_collections.is_empty()
			for coll in colls:
				var node := _tree.create_item(rules)
				node.set_text(0, "%s  %d" % [_collection_title(coll), ctx.kernel.comp.count(coll)])
				node.set_metadata(0, "")
				node.set_selectable(0, false)
				node.set_meta("collection", coll)
				if _open_collections.has(coll):
					_fill_collection(node, coll)
					node.collapsed = false
				else:
					_tree.create_item(node).set_text(0, "…")
					node.collapsed = true
	else:
		var matches := rules_matches(q)
		if not matches.is_empty():
			var rules := _heading(root, "Rules")
			for it in matches:
				_add_row(rules, it)
		if _first_ref(root) == "":
			var none := _tree.create_item(root)
			none.set_text(0, "Nothing by that name.")
			none.set_selectable(0, false)
			none.set_metadata(0, "")
	_select_current()


func _heading(parent: TreeItem, text: String) -> TreeItem:
	var h := _tree.create_item(parent)
	h.set_text(0, text)
	h.set_selectable(0, false)
	h.set_custom_color(0, Color(0.62, 0.64, 0.7))
	h.set_metadata(0, "")
	return h


func _add_row(parent: TreeItem, it: Dictionary) -> void:
	var row := _tree.create_item(parent)
	row.set_text(0, str(it.label))
	row.set_metadata(0, str(it.ref))
	for child in it.get("children", []):
		_add_row(row, child)


## Opening a rules collection in the contents fills it.
func _on_collapsed(item: TreeItem) -> void:
	if item == null or item.collapsed or not item.has_meta("collection"):
		return
	var coll := str(item.get_meta("collection"))
	if _open_collections.has(coll):
		return
	_open_collections[coll] = true
	for c in item.get_children():
		item.remove_child(c)
		c.free()
	_fill_collection(item, coll)


func _fill_collection(node: TreeItem, coll: String) -> void:
	var page: Dictionary = ctx.kernel.comp.query_for(coll, {"per_page": 1000, "fields": ["name"], "sort": "name"}, true)
	for en in page.get("entries", []):
		var row := _tree.create_item(node)
		row.set_text(0, str(en.get("name", en.get("id", ""))))
		row.set_metadata(0, "entry:%s/%s" % [coll, str(en.get("id", ""))])


func _collections() -> Array:
	if ctx.kernel == null:
		return []
	var out: Array = Array(ctx.kernel.comp.collections()).duplicate()
	out.sort_custom(func(a: String, b: String) -> bool: return _collection_title(a) < _collection_title(b))
	return out


static func _collection_title(coll: String) -> String:
	return {"rules": "Rules glossary", "magic_items": "Magic items", "weapon_properties": "Weapon properties"}.get(coll, coll.replace("_", " ").capitalize())


## [{title, items: [{label, ref, children}], collapsed}] — the campaign's own
## things whose name (or words) match `q`; everything when it is empty.
func contents(q: String) -> Array:
	var e := ctx.encounter()
	var party := []
	var people := []
	var ids := e.actors.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return str(e.actors[a].get("name", a)).naturalnocasecmp_to(str(e.actors[b].get("name", b))) < 0)
	var world_ids := []
	for aid in ids:
		var a: Dictionary = e.actors[aid]
		var kind := str(a.get("kind", ""))
		# the goblins of a running fight are the fight's, not the world's
		if KINDS_PEOPLE.has(kind) and not bool(a.get("persistent", false)) and ctx.campaign != null and not ctx.campaign.actors.has(aid):
			continue
		world_ids.append(aid)
		var hay := ("%s %s %s" % [str(a.get("name", "")), str(a.get("notes", "")), str(a.get("public", ""))]).to_lower()
		if q != "" and not hay.contains(q):
			continue
		var label := str(a.get("name", aid))
		if KINDS_PARTY.has(kind):
			var owner := str(a.get("owner", ""))
			if owner != "":
				label += "  · " + str(e.player(owner).get("name", owner))
			party.append({"label": label, "ref": "actor:" + str(aid)})
		elif KINDS_PEOPLE.has(kind):
			var where := place_name(str(a.get("place", "")))
			people.append({"label": label + ("  · " + where if where != "" else ""), "ref": "actor:" + str(aid)})
	var places := []
	var notes := []
	var handouts := []
	var shown := []
	var pictures := []
	var maps := []
	if ctx.campaign != null:
		for p in ctx.campaign.places:
			var pid := str(p.get("id", ""))
			var here := []
			for aid in world_ids:
				if str(e.actors[aid].get("place", "")) == pid:
					here.append({"label": str(e.actors[aid].get("name", aid)), "ref": "actor:" + str(aid)})
			var hay := ("%s %s %s" % [str(p.get("name", "")), str(p.get("text", "")), str(p.get("notes", ""))]).to_lower()
			if q == "" or hay.contains(q):
				places.append({"label": str(p.get("name", "")), "ref": "place:" + pid, "children": here if q == "" else []})
		for n in journal():
			var kind := str(n.get("kind", "note"))
			var hay := ("%s %s %s" % [str(n.get("title", "")), str(n.get("text", "")), " ".join(PackedStringArray(n.get("tags", [])))]).to_lower()
			if q != "" and not hay.contains(q):
				continue
			var title := str(n.get("title", "")) if str(n.get("title", "")) != "" else str(n.get("text", "")).left(40)
			if kind == "handout" and str(n.get("ref", "")) != "":
				# a record of something shown
				shown.append({"label": "%s  → %s" % [title, Sharing.audience_words(ctx, str(n.get("audience", "gm")))], "ref": "handout:" + str(n.get("id", ""))})
			elif kind == "handout":
				handouts.append({"label": title, "ref": "note:" + str(n.get("id", ""))})
			else:
				var entry := {"label": ("Ruling: " if kind == "ruling" else "") + title, "ref": "note:" + str(n.get("id", ""))}
				# the author's "Start here" first
				if (n.get("tags", []) as Array).has("start"):
					notes.push_front(entry)
				else:
					notes.append(entry)
		for pic in CampaignPictures.all(ctx):
			if q == "" or str(pic.name).to_lower().contains(q) or " ".join(PackedStringArray(pic.tags)).to_lower().contains(q):
				pictures.append({"label": str(pic.name), "ref": "picture:" + str(pic.ref)})
		for m in ctx.campaign.maps:
			if q == "" or str(m.get("name", "")).to_lower().contains(q):
				maps.append({"label": "%s  · %s" % [str(m.get("name", "")), "the region" if str(m.get("role", "")) == "regional" else "a battle map"], "ref": "map:" + str(m.get("id", ""))})
	shown.reverse()
	return [{"title": "Notes for you", "items": notes}, {"title": "The party", "items": party}, {"title": "Places", "items": places},
		{"title": "People", "items": people}, {"title": "Handouts", "items": handouts}, {"title": "Shown to the players", "items": shown, "collapsed": true},
		{"title": "Pictures", "items": pictures, "collapsed": true}, {"title": "Maps", "items": maps}]


## Rules entries matching `q`: a few from every collection, as "Name (spells)".
func rules_matches(q: String) -> Array:
	var out := []
	if ctx.kernel == null or q.length() < 2:
		return out
	for coll in ctx.kernel.comp.collections():
		var page: Dictionary = ctx.kernel.comp.query_for(str(coll), {"text": q, "per_page": 6, "fields": ["name"]}, true)
		for en in page.get("entries", []):
			out.append({"label": "%s  (%s)" % [str(en.get("name", en.get("id", ""))), str(coll).replace("_", " ")], "ref": "entry:%s/%s" % [str(coll), str(en.get("id", ""))]})
	return out


## The text of every row the contents hold (open or not), in order: for tests.
func rows() -> PackedStringArray:
	var out := PackedStringArray()
	_walk_rows(_tree.get_root(), out)
	return out


func _walk_rows(item: TreeItem, out: PackedStringArray) -> void:
	if item == null:
		return
	for c in item.get_children():
		out.append(c.get_text(0))
		_walk_rows(c, out)


## The row showing `ref`, or null.
func row_for(ref: String) -> TreeItem:
	return _find_row(_tree.get_root(), ref)


func _find_row(item: TreeItem, ref: String) -> TreeItem:
	if item == null:
		return null
	for c in item.get_children():
		if str(c.get_metadata(0)) == ref:
			return c
		var f := _find_row(c, ref)
		if f != null:
			return f
	return null


func _first_ref(item: TreeItem) -> String:
	if item == null:
		return ""
	for c in item.get_children():
		if str(c.get_metadata(0)) != "":
			return str(c.get_metadata(0))
		var f := _first_ref(c)
		if f != "":
			return f
	return ""


func _select_current() -> void:
	var row := row_for(current) if current != "" else null
	if row == null:
		return
	var p := row.get_parent()
	while p != null:
		p.collapsed = false
		p = p.get_parent()
	row.select(0)
	_tree.scroll_to_item(row)


## The journal's notes, handouts and rulings, and this session's not yet kept.
func journal() -> Array:
	var out := []
	var seen := {}
	if ctx.campaign != null:
		for j in ctx.campaign.journal:
			out.append(j)
			seen[str(j.get("id", ""))] = true
	for en in ctx.encounter().log:
		var kind := str(en.get("kind", ""))
		if Campaign.JOURNAL_KINDS.has(kind) and not seen.has(str(en.get("id", ""))) and (kind != "note" or bool(en.get("journal", false))):
			out.append(en)
	return out


func place(pid: String) -> Dictionary:
	if ctx.campaign != null:
		for p in ctx.campaign.places:
			if str(p.get("id", "")) == pid:
				return p
	return {}


func place_name(pid: String) -> String:
	return str(place(pid).get("name", "")) if pid != "" else ""


# ----------------------------------------------------------------- the card --

## Open a card. The one before it is kept for Back.
func open(ref: String) -> void:
	if ref == "" or ref == current:
		_render_card()
		return
	if current != "":
		history.append(current)
		if history.size() > 40:
			history.pop_front()
	current = ref
	_render_card()
	_select_current()


func back() -> void:
	if history.is_empty():
		return
	current = str(history.pop_back())
	_render_card()
	_select_current()


## The map's selection opens its card: a place marker, a character, a creature.
func _follow_selection() -> void:
	if ctx.state == null or ctx.selection.size() != 1 or str(ctx.selection[0].get("kind", "")) != "token":
		return
	var tk := ctx.state.token(ctx.scene_id, str(ctx.selection[0].id))
	if tk.is_empty():
		return
	if (tk.get("tags", []) as Array).has("place") and not place(str(tk.id)).is_empty():
		open("place:" + str(tk.id))
	elif str(tk.get("actor", "")) != "" and not ctx.encounter().actor(str(tk.actor)).is_empty():
		open("actor:" + str(tk.actor))


func _exists(ref: String) -> bool:
	var kind := ref.get_slice(":", 0)
	var id := ref.substr(kind.length() + 1)
	match kind:
		"actor": return not ctx.encounter().actor(id).is_empty()
		"place": return not place(id).is_empty()
		"note", "handout": return not _journal_entry(id).is_empty()
		"picture": return ctx.art != null and not ctx.art.picture(id).is_empty()
		"map": return ctx.campaign != null and not ctx.campaign.map_entry(id).is_empty()
		"entry": return ctx.kernel != null and not ctx.kernel.comp.get_entry(id.get_slice("/", 0), id.substr(id.find("/") + 1)).is_empty()
	return false


func _clear_card() -> void:
	for r in _renderers:
		if is_instance_valid(r):
			r.queue_free()
	_renderers.clear()
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	_shareable = {}


func _render_card() -> void:
	_clear_card()
	_back.disabled = history.is_empty()
	if ctx.state == null or current == "" or not _exists(current):
		_title.text = "Reference"
		_dim("Look something up above, or open anything in the contents. Selecting a place or a character on the map opens it here. What the players see is up to you: each card says who has been shown it.")
		return
	var kind := current.get_slice(":", 0)
	var id := current.substr(kind.length() + 1)
	match kind:
		"actor": _actor_card(id)
		"place": _place_card(id)
		"note": _note_card(id)
		"handout": _handout_card(id)
		"picture": _picture_card(id)
		"map": _map_card(id)
		"entry": _entry_card(id.get_slice("/", 0), id.substr(id.find("/") + 1))


func _actor_card(aid: String) -> void:
	var e := ctx.encounter()
	var a := e.actor(aid)
	_title.text = str(a.get("name", aid))
	var kind := str(a.get("kind", ""))
	var line := PackedStringArray()
	if KINDS_PARTY.has(kind):
		var owner := str(a.get("owner", ""))
		line.append("played by " + str(e.player(owner).get("name", owner)) if owner != "" else "no player yet")
	else:
		line.append({"npc": "a person of the world", "environment": "the surroundings", "hazard": "a hazard"}.get(kind, kind))
	for sc in e.scenes:
		for tk in sc.tokens:
			if str(tk.get("actor", "")) == aid:
				line.append("on " + str(sc.get("name", "a map")) + (" (hidden)" if bool(tk.get("hidden", false)) else ""))
	_dim(" · ".join(line))
	if KINDS_PEOPLE.has(kind):
		var image := str(a.get("image", ""))
		_picture(image, func(ref: String) -> void:
			ctx.commands.run({"t": "actor.set", "id": aid, "changes": {"image": ref}}, "Picture of " + str(a.get("name", ""))))
		_share_row("actor:" + aid, str(a.get("name", "")), str(a.get("public", "")), image)
		# where they are, and what the DM knows about them
		var row := HBoxContainer.new()
		var wl := Label.new()
		wl.text = "Where"
		wl.theme_type_variation = "DimLabel"
		row.add_child(wl)
		var where := OptionButton.new()
		where.name = "Where"
		where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		where.add_item("(nowhere in particular)")
		where.set_item_metadata(0, "")
		var at := str(a.get("place", ""))
		if ctx.campaign != null:
			for p in ctx.campaign.places:
				var i := where.item_count
				where.add_item(str(p.get("name", "")))
				where.set_item_metadata(i, str(p.get("id", "")))
				if str(p.get("id", "")) == at:
					where.select(i)
		where.item_selected.connect(func(i: int) -> void:
			ctx.commands.run({"t": "actor.set", "id": aid, "changes": {"place": str(where.get_item_metadata(i))}}, "Where %s is" % str(a.get("name", ""))))
		row.add_child(where)
		if at != "":
			var go := Button.new()
			go.text = "Open"
			go.tooltip_text = "Open the place's card"
			go.pressed.connect(func() -> void: open("place:" + at))
			row.add_child(go)
		_card.add_child(row)
		_field_label("For the players — what they may know of them (shown with the picture)")
		_notes_field("Public", str(a.get("public", "")), "How they look, what they say of themselves", func(text: String) -> void:
			ctx.commands.run({"t": "actor.set", "id": aid, "changes": {"public": text}}, "About " + str(a.get("name", ""))))
		_field_label("Your notes — only you see these")
		_notes_field("Notes", str(a.get("notes", "")), "Who they are, what they want, what they know, and the DCs to learn it", func(text: String) -> void:
			ctx.commands.run({"t": "actor.set", "id": aid, "changes": {"notes": text}}, "Notes on " + str(a.get("name", ""))))
	var host := ctx.host
	if host == null:
		_dim("No rules are loaded, so there is no sheet to show.")
		return
	var projection := Views.project(ctx.kernel, host, "", Views.ROLE_GM)
	var sheets: Array = projection.actors.get(aid, {}).get("sheets", [])
	if sheets.is_empty():
		_dim("No sheet: this one carries no ruleset's data.")
	for sh in sheets:
		var r := GmIntents.renderer(ctx, _queue_refresh)
		_card.add_child(r)
		r.render(sh.get("schema", {}), sh.get("data", {}))
		_renderers.append(r)


func _place_card(pid: String) -> void:
	var p := place(pid)
	_title.text = str(p.get("name", ""))
	var kind := str(p.get("kind", ""))
	var target := str(p.get("target", ""))
	var what := ""
	match kind:
		"encounter":
			var enc := ctx.campaign.encounter_entry(target) if ctx.campaign != null else {}
			what = "An encounter: %s" % str(enc.get("name", "?")) if not enc.is_empty() else "An encounter (gone)"
		"map":
			what = "Leads to the map %s" % str(ctx.campaign.map_entry(target).get("name", "?")) if ctx.campaign != null else ""
		_:
			what = "A place"
	# its marker, where a map is up: seen by the players or not
	var marker := {}
	var marker_scene := ""
	for sc in ctx.encounter().scenes:
		for tk in sc.tokens:
			if str(tk.get("id", "")) == pid:
				marker = tk
				marker_scene = str(sc.id)
	if not marker.is_empty():
		what += " · the players %s it on the map" % ("do not see" if bool(marker.get("hidden", false)) else "see")
	_dim(what)
	var image := str(p.get("image", ""))
	_picture(image, func(ref: String) -> void:
		p.image = ref
		_campaign_changed())
	var actions := HFlowContainer.new()
	if kind == "encounter":
		var enc := ctx.campaign.encounter_entry(target) if ctx.campaign != null else {}
		var live: bool = not enc.is_empty() and enc.has("live") and not (enc.live as Dictionary).is_empty()
		_button(actions, "Go to the fight" if live else "Run this encounter", "Make the scene, place its creatures hidden, and switch to the fight", func() -> void:
			if go_place.is_valid():
				go_place.call(pid))
	elif kind == "map":
		_button(actions, "Show that map", "Show the map this place leads to", func() -> void:
			if go_place.is_valid():
				go_place.call(pid))
	if not marker.is_empty():
		var hidden := bool(marker.get("hidden", false))
		_button(actions, "Mark it on their map" if hidden else "Hide it from their map", "Whether the players see this place's marker", func() -> void:
			ctx.say(ctx.commands.run({"t": "token.set", "scene": marker_scene, "id": pid, "changes": {"hidden": not hidden}}, ("Reveal " if hidden else "Hide ") + str(p.get("name", "")))))
	if actions.get_child_count() > 0:
		_card.add_child(actions)
	_share_row("place:" + pid, str(p.get("name", "")), place_text(p), image)
	_field_label("For the players — the description you read out (shown with the picture)")
	_notes_field("Description", str(p.get("text", "")), "What the party finds here: the sights, the sounds, who and what is here", func(text: String) -> void:
		p.text = text
		_campaign_changed(false))
	_field_label("Your notes — only you see these")
	_notes_field("Notes", str(p.get("notes", "")), "Secrets, DCs, what happens here", func(text: String) -> void:
		p.notes = text
		_campaign_changed(false))
	if kind == "note" and target != "":
		var n := _journal_entry(target)
		if not n.is_empty():
			_subhead("From the note " + str(n.get("title", "")))
			_rich(str(n.get("text", "")))
	var here := []
	for aid in ctx.encounter().actors:
		if str(ctx.encounter().actors[aid].get("place", "")) == pid:
			here.append(str(aid))
	_subhead("People here")
	if here.is_empty():
		_dim("Nobody yet — open a person and set where they are.")
	var people := HFlowContainer.new()
	for aid in here:
		var id := str(aid)
		_button(people, str(ctx.encounter().actor(id).get("name", id)), "Open their card", func() -> void: open("actor:" + id))
	_card.add_child(people)


## A place's description, or its note's, for showing the players.
func place_text(p: Dictionary) -> String:
	if str(p.get("text", "")).strip_edges() != "":
		return str(p.text)
	if str(p.get("kind", "")) == "note":
		return str(_journal_entry(str(p.get("target", ""))).get("text", ""))
	return ""


func _note_card(nid: String) -> void:
	var n := _journal_entry(nid)
	_title.text = str(n.get("title", "")) if str(n.get("title", "")) != "" else "A note"
	var meta := PackedStringArray()
	meta.append({"handout": "a handout, for the players", "ruling": "a ruling", "note": "a note"}.get(str(n.get("kind", "note")), "a note"))
	if (n.get("tags", []) as Array).size() > 0:
		meta.append(", ".join(PackedStringArray(n.tags)))
	_dim(" · ".join(meta))
	var image := str(n.get("image", ""))
	_picture(image, func(ref: String) -> void:
		n.image = ref
		_campaign_changed())
	if str(n.get("kind", "")) != "ruling":
		_share_row("note:" + nid, str(n.get("title", "")), str(n.get("text", "")), image)
	_rich(str(n.get("text", "")))


## Something shown to the players: to whom, what, and taking it back.
func _handout_card(hid: String) -> void:
	var h := _journal_entry(hid)
	_title.text = str(h.get("title", "")) if str(h.get("title", "")) != "" else "Shown to the players"
	var aud := str(h.get("audience", "gm"))
	var when := (" in session %d" % int(h.session)) if h.has("session") else " this session"
	_dim(("Shown to %s%s" % [Sharing.audience_words(ctx, aud), when]) if aud != "gm" else "No longer shown to anyone")
	var actions := HFlowContainer.new()
	var from := str(h.get("ref", ""))
	if from != "" and _exists(from):
		_button(actions, "Open what it was shown from", "The card it came from", func() -> void: open(from))
	if aud != "gm":
		_button(actions, "Stop showing it", "Take it back: the players' phones drop it", func() -> void:
			ctx.say(stop_showing(hid)))
	_card.add_child(actions)
	_picture_view(str(h.get("image", "")))
	_rich(str(h.get("text", "")))


## Take back one thing shown: this session's leaves the log (and the
## phones); an earlier one goes back to being the DM's. What happened.
func stop_showing(hid: String) -> String:
	for entry in ctx.encounter().log:
		if str(entry.get("id", "")) == hid:
			var why := ctx.kernel.commit([{"t": "log.remove", "id": hid}], "Stop showing it", {"by": "gm"})
			return why if why != "" else "Taken back"
	if ctx.campaign != null:
		var j := ctx.campaign.journal_entry(hid)
		if not j.is_empty():
			j.audience = "gm"
			_campaign_changed()
			return "Taken back"
	return "not found"


func _picture_card(ref: String) -> void:
	var pic := ctx.art.picture(ref)
	_title.text = str(pic.get("name", ref))
	var users := []
	if ctx.campaign != null:
		for p in ctx.campaign.places:
			if str(p.get("image", "")) == ref:
				users.append(["place:" + str(p.id), str(p.get("name", ""))])
	for aid in ctx.encounter().actors:
		if str(ctx.encounter().actors[aid].get("image", "")) == ref:
			users.append(["actor:" + str(aid), str(ctx.encounter().actors[aid].get("name", ""))])
	_dim("A picture from %s" % str(ctx.art.manifest(PackLibrary.split_ref(ref)[0]).get("name", "the campaign's art")))
	_share_row("picture:" + ref, str(pic.get("name", "")), str(pic.get("caption", "")), ref)
	_picture_view(ref, 360.0)
	if not users.is_empty():
		_subhead("The picture of")
		var flow := HFlowContainer.new()
		for u in users:
			var r: String = u[0]
			_button(flow, str(u[1]), "Open its card", func() -> void: open(r))
		_card.add_child(flow)


func _map_card(mid: String) -> void:
	var m := ctx.campaign.map_entry(mid)
	_title.text = str(m.get("name", ""))
	_dim("The region: places and the party are marked on it." if str(m.get("role", "")) == "regional" else "A battle map.")
	var actions := HFlowContainer.new()
	_button(actions, "Show this map", "Put it on screen — the players see it too", func() -> void:
		if show_map.is_valid():
			show_map.call(mid))
	_card.add_child(actions)
	var here := []
	if ctx.campaign != null:
		for p in ctx.campaign.places:
			if str(p.get("map", "")) == mid:
				here.append(p)
	if not here.is_empty():
		_subhead("Places on it")
		var flow := HFlowContainer.new()
		for p in here:
			var pid := str(p.get("id", ""))
			_button(flow, str(p.get("name", "")), "Open the place's card", func() -> void: open("place:" + pid))
		_card.add_child(flow)


func _entry_card(coll: String, id: String) -> void:
	var entry := ctx.kernel.comp.get_entry(coll, id)
	_title.text = str(entry.get("name", id))
	var r := GmIntents.renderer(ctx, _queue_refresh)
	_card.add_child(r)
	r.render(EntryCard.schema_for(EntryCard.cards_of(ctx.host), coll), EntryCard.data_for(entry))
	_renderers.append(r)


func _journal_entry(nid: String) -> Dictionary:
	for n in journal():
		if str(n.get("id", "")) == nid:
			return n
	return {}


func _campaign_changed(redraw := true) -> void:
	if ctx.campaign == null:
		return
	ctx.campaign.touch()
	if redraw:
		ctx.campaign_changed.emit()


# ------------------------------------------------------------- sharing --

## "Players see it: nothing yet / everyone / Ana" and Show the players ▾
## (everyone, or one of them; take it back).
func _share_row(ref: String, title: String, text: String, image: String) -> void:
	_shareable = {"ref": ref, "title": title, "text": text, "image": image}
	var row := HBoxContainer.new()
	var shown := Sharing.shown_to(ctx, ref)
	var l := Label.new()
	l.name = "ShownTo"
	l.text = "Players see it: " + ("nothing yet" if shown == "" else Sharing.audience_words(ctx, shown))
	l.theme_type_variation = "DimLabel"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var mb := MenuButton.new()
	mb.name = "ShowPlayers"
	mb.text = "Show the players ▾"
	mb.flat = false
	mb.tooltip_text = "Put it on their phones now: the picture and what is written for them. Their Journal keeps it."
	var pm := mb.get_popup()
	var targets := {}
	pm.add_item("Everyone", 0)
	targets[0] = "all"
	var i := 1
	for p in ctx.encounter().players:
		pm.add_item("Only " + str(p.get("name", p.id)), i)
		targets[i] = Sharing.for_player(str(p.id))
		i += 1
	if shown != "":
		pm.add_separator()
		pm.add_item("Stop showing it", 999)
	pm.id_pressed.connect(func(id: int) -> void:
		if id == 999:
			ctx.say(_say_or(Sharing.unshare(ctx, ref), "Taken back from the players"))
		elif targets.has(id):
			ctx.say(share_current(str(targets[id]))))
	row.add_child(mb)
	_card.add_child(row)


## Show the open card's thing to `audience` ("all", "players:<id>…"). What happened.
func share_current(audience: String) -> String:
	if _shareable.is_empty():
		return "nothing here to show"
	var why := Sharing.share(ctx, str(_shareable.ref), str(_shareable.title), str(_shareable.text), str(_shareable.image), audience)
	return _say_or(why, "Shown to %s: %s" % [Sharing.audience_words(ctx, audience), str(_shareable.title)])


static func _say_or(why: String, ok: String) -> String:
	return why if why != "" else ok


# ------------------------------------------------------------ pictures --

## The thing's picture, and Picture ▾: choose one of the campaign's, add
## one from a file, or none.
func _picture(image: String, set_to: Callable) -> void:
	if image != "":
		_picture_view(image)
	var row := HBoxContainer.new()
	var mb := MenuButton.new()
	mb.name = "PictureMenu"
	mb.text = "Change the picture ▾" if image != "" else "Add a picture ▾"
	mb.flat = false
	var pm := mb.get_popup()
	pm.add_item("Choose from the campaign's pictures…", 0)
	pm.add_item("From a file…", 1)
	if image != "":
		pm.add_item("No picture", 2)
	pm.id_pressed.connect(_on_picture_menu.bind(set_to))
	row.add_child(mb)
	_card.add_child(row)


func _on_picture_menu(id: int, set_to: Callable) -> void:
	if id == 0:
		choose_picture(set_to)
	elif id == 1 and pick_picture_file.is_valid():
		pick_picture_file.call(func(path: String) -> void:
			var r := CampaignPictures.add_file(ctx, path)
			if r.has("why"):
				ctx.say(str(r.why))
			else:
				set_to.call(str(r.ref)))
	elif id == 2:
		set_to.call("")


func _picture_view(ref: String, height := 220.0) -> void:
	if ref == "" or ctx.art == null:
		return
	var tex := ctx.art.picture_texture(ref, 512.0)
	if tex == null:
		_dim("(the picture %s is not in the campaign's art)" % ref)
		return
	var tr := TextureRect.new()
	tr.name = "Picture"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(0, height)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.add_child(tr)


## The campaign's pictures, to pick one. The dialog, for tests.
func choose_picture(set_to: Callable) -> AcceptDialog:
	var pics := CampaignPictures.all(ctx)
	var d := AcceptDialog.new()
	d.title = "Choose a picture"
	d.ok_button_text = "Cancel"
	var box := VBoxContainer.new()
	var list := ItemList.new()
	list.name = "Pictures"
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_icon_size = Vector2i(128, 96)
	list.max_columns = 0
	list.same_column_width = true
	list.custom_minimum_size = Vector2(560, 360)
	for pic in pics:
		var i := list.add_item(str(pic.name), ctx.art.picture_texture(str(pic.ref), 128.0))
		list.set_item_metadata(i, str(pic.ref))
	box.add_child(list)
	if pics.is_empty():
		var l := Label.new()
		l.text = "The campaign has no pictures yet: add one from a file."
		l.theme_type_variation = "DimLabel"
		box.add_child(l)
	d.add_child(box)
	list.item_selected.connect(func(i: int) -> void:
		set_to.call(str(list.get_item_metadata(i)))
		d.hide())
	d.visibility_changed.connect(func() -> void:
		if not d.visible:
			d.queue_free())
	add_child(d)
	d.popup_centered()
	return d


# ------------------------------------------------------------------ helpers --

func _field_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = "DimLabel"
	_card.add_child(l)


func _notes_field(p_name: String, text: String, placeholder: String, save: Callable) -> void:
	var te := TextEdit.new()
	te.name = p_name
	te.text = text
	te.placeholder_text = placeholder
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size = Vector2(0, 70)
	te.scroll_fit_content_height = true
	# saved a moment after typing stops, and when the field is left
	var last := {"v": text}
	var keep := func() -> void:
		if te.text != str(last.v):
			last.v = te.text
			save.call(te.text)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.8
	timer.timeout.connect(keep)
	te.add_child(timer)
	te.text_changed.connect(func() -> void: timer.start())
	te.focus_exited.connect(func() -> void:
		timer.stop()
		keep.call())
	_card.add_child(te)


func _rich(text: String) -> void:
	if text.strip_edges() == "":
		return
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.selection_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.text = ViewRenderer.markdown_to_bbcode(text)
	_card.add_child(rt)


func _dim(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = "DimLabel"
	_card.add_child(l)


func _subhead(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HeaderLabel"
	_card.add_child(l)


func _button(parent: Control, text: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(fn)
	parent.add_child(b)
	return b
