class_name PlayerJournal
extends VBoxContainer
## A player's own book, on their phone: their notes (in folders of their
## own, and on the things they were shown), what the DM has shown them —
## places, people, pictures, handouts, for as long as the DM leaves it
## shown — and the notes other players shared with them; one search over
## all of it. Notes are kept by the Table in the campaign (PlayerNotes):
## private unless shared with the DM, some of the players, or everyone.
##
## Keys: "mine:<note id>", "other:<note id>", "shown:<ref or handout id>".

## Set by the window: the session, where to send an intent, the art.
var session: Session
var send: Callable = Callable()
var packs: PackLibrary
var current := ""
var _search: LineEdit
var _tree: Tree
var _card: VBoxContainer
## Notes changed here and not yet echoed back by the Table: what the
## editor shows (a late echo must not undo the last few words typed).
var _local: Dictionary = {}
## Notes deleted here, until the Table's view no longer has them.
var _deleted: Dictionary = {}
var _delete_armed := ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	_search = LineEdit.new()
	_search.placeholder_text = "Search your journal"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.y = 40
	_search.text_changed.connect(func(_t: String) -> void: refresh_tree())
	top.add_child(_search)
	var add := Button.new()
	add.name = "NewNote"
	add.text = "New note"
	add.custom_minimum_size = Vector2(0, 40)
	add.pressed.connect(func() -> void: new_note())
	top.add_child(add)
	add_child(top)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(0, 220)
	_tree.item_selected.connect(func() -> void:
		var it := _tree.get_selected()
		if it != null and str(it.get_metadata(0)) != "":
			open(str(it.get_metadata(0))))
	add_child(_tree)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 8)
	add_child(_card)


## The notes, the things shown and the tree, again (the view changed). The
## card waits while the player is typing in it.
func refresh() -> void:
	_settle_local()
	refresh_tree()
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and _card.is_ancestor_of(focus) and (focus is TextEdit or focus is LineEdit):
		return
	_render_card()


func me() -> String:
	return session.player_id if session != null else ""


## My notes: the Table's, with what I changed here and not yet echoed.
func my_notes() -> Array:
	var out := []
	var seen := {}
	for n in _view_notes():
		var id := str(n.get("id", ""))
		if str(n.get("owner", "")) != me() or _deleted.has(id):
			continue
		seen[id] = true
		out.append(_local.get(id, n))
	for id in _local:
		if not seen.has(id) and not _deleted.has(id):
			out.append(_local[id])
	return out


## Notes other players shared with me.
func others_notes() -> Array:
	return _view_notes().filter(func(n: Dictionary) -> bool: return str(n.get("owner", "")) != me())


## What the DM has shown me, newest last, once per thing shown.
func shown() -> Array:
	var by_key := {}
	var order := []
	if session == null:
		return []
	var all: Array = []
	all.append_array(session.view.get("journal", []))
	for h in session.view.get("log", []):
		if h is Dictionary and str(h.get("kind", "")) == "handout":
			all.append(h)
	for h in all:
		if not (h is Dictionary):
			continue
		var key := str(h.get("ref", "")) if str(h.get("ref", "")) != "" else str(h.get("id", ""))
		if not by_key.has(key):
			order.append(key)
		by_key[key] = h
	return order.map(func(k: String) -> Dictionary: return by_key[k])


func _view_notes() -> Array:
	if session == null:
		return []
	return (session.view.get("notes", []) as Array).filter(func(n: Variant) -> bool: return n is Dictionary)


## Drop local copies the Table has caught up with, and deletions it has made.
func _settle_local() -> void:
	var there := {}
	for n in _view_notes():
		there[str(n.get("id", ""))] = n
	for id in _local.keys():
		var t: Dictionary = there.get(id, {})
		var l: Dictionary = _local[id]
		if not t.is_empty() and str(t.get("title", "")) == str(l.get("title", "")) and str(t.get("text", "")) == str(l.get("text", "")) \
				and str(t.get("folder", "")) == str(l.get("folder", "")) and t.get("share", []) == l.get("share", []):
			_local.erase(id)
	for id in _deleted.keys():
		if not there.has(id):
			_deleted.erase(id)


# ------------------------------------------------------------------ the tree --

func refresh_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var q := _search.text.strip_edges().to_lower()
	var mine := my_notes()
	# my notes, by my folders
	var mine_head := _heading(root, "My notes")
	var folders := {}
	for n in mine:
		if not _matches(n, q):
			continue
		var f := str(n.get("folder", ""))
		var parent := mine_head
		if f != "":
			if not folders.has(f):
				folders[f] = _heading(mine_head, f)
			parent = folders[f]
		_row(parent, _note_label(n), "mine:" + str(n.get("id", "")))
	if mine_head.get_child_count() == 0:
		var none := _tree.create_item(mine_head)
		none.set_text(0, "None yet — New note" if q == "" else "Nothing matches")
		none.set_selectable(0, false)
		none.set_metadata(0, "")
	# what the DM showed me, by kind, each with my notes on it
	var groups := {"place": "Places", "actor": "People", "picture": "Pictures", "": "Handouts"}
	var heads := {}
	var from_dm := _heading(root, "From the DM")
	for h in shown():
		var ref := str(h.get("ref", ""))
		var on_it := mine.filter(func(n: Dictionary) -> bool: return ref != "" and str(n.get("about", "")) == ref)
		if not _matches(h, q) and on_it.filter(func(n: Dictionary) -> bool: return _matches(n, q)).is_empty():
			continue
		var kind := ref.get_slice(":", 0) if ref.contains(":") else ""
		if not groups.has(kind):
			kind = ""
		if not heads.has(kind):
			heads[kind] = _heading(from_dm, str(groups[kind]))
		var key := "shown:" + (ref if ref != "" else str(h.get("id", "")))
		var row := _row(heads[kind], str(h.get("title", "")) if str(h.get("title", "")) != "" else "From the DM", key)
		for n in on_it:
			_row(row, "✎ " + _note_label(n), "mine:" + str(n.get("id", "")))
	if from_dm.get_child_count() == 0:
		from_dm.visible = false
	# what other players shared with me
	var others := others_notes().filter(func(n: Dictionary) -> bool: return _matches(n, q))
	if not others.is_empty():
		var head := _heading(root, "From other players")
		for n in others:
			_row(head, "%s  — %s" % [_note_label(n), _player_name(str(n.get("owner", "")))], "other:" + str(n.get("id", "")))
	_select_current()


func _heading(parent: TreeItem, text: String) -> TreeItem:
	var h := _tree.create_item(parent)
	h.set_text(0, text)
	h.set_selectable(0, false)
	h.set_custom_color(0, Color(0.62, 0.64, 0.7))
	h.set_metadata(0, "")
	return h


func _row(parent: TreeItem, text: String, key: String) -> TreeItem:
	var r := _tree.create_item(parent)
	r.set_text(0, text)
	r.set_metadata(0, key)
	return r


func _select_current() -> void:
	var row := row_for(current) if current != "" else null
	if row != null:
		row.select(0)


## The row for a key, or null.
func row_for(key: String) -> TreeItem:
	var stack: Array = [_tree.get_root()]
	while not stack.is_empty():
		var it: TreeItem = stack.pop_back()
		if it == null:
			continue
		for c in it.get_children():
			if str(c.get_metadata(0)) == key:
				return c
			stack.append(c)
	return null


## Every row's text, in order: for tests.
func rows() -> PackedStringArray:
	var out := PackedStringArray()
	var walk := func(item: TreeItem, f: Callable) -> void:
		if item == null:
			return
		for c in item.get_children():
			out.append(c.get_text(0))
			f.call(c, f)
	walk.call(_tree.get_root(), walk)
	return out


static func _matches(rec: Dictionary, q: String) -> bool:
	if q == "":
		return true
	return ("%s %s %s" % [str(rec.get("title", "")), str(rec.get("text", "")), str(rec.get("folder", ""))]).to_lower().contains(q)


static func _note_label(n: Dictionary) -> String:
	if str(n.get("title", "")).strip_edges() != "":
		return str(n.title)
	var t := str(n.get("text", "")).strip_edges().get_slice("\n", 0)
	return t.left(40) if t != "" else "Untitled note"


func _player_name(pid: String) -> String:
	if session == null or session.state == null:
		return pid
	return str(session.state.encounter.player(pid).get("name", pid))


# ------------------------------------------------------------------ the card --

func open(key: String) -> void:
	current = key
	_delete_armed = ""
	_render_card()
	_select_current()


## A new note of mine (on `about`, a ref, when given), open to write.
func new_note(about := "", title := "") -> String:
	var n := {"id": PlayerNotes.new_id(), "owner": me(), "title": title, "text": "", "folder": "", "about": about, "share": []}
	_local[str(n.id)] = n
	_save(n)
	refresh_tree()
	open("mine:" + str(n.id))
	var title_edit := _card.find_child("Title", true, false) as LineEdit
	if title_edit != null and title_edit.is_inside_tree():
		title_edit.grab_focus()
	return str(n.id)


func _clear_card() -> void:
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()


func _render_card() -> void:
	_clear_card()
	var kind := current.get_slice(":", 0)
	var id := current.substr(kind.length() + 1)
	match kind:
		"mine":
			var n := _find(my_notes(), id)
			if not n.is_empty():
				_my_note_card(n)
				return
		"other":
			var n := _find(others_notes(), id)
			if not n.is_empty():
				_other_note_card(n)
				return
		"shown":
			for h in shown():
				if str(h.get("ref", "")) == id or str(h.get("id", "")) == id:
					_shown_card(h)
					return
	current = ""
	_dim("Your notes, and everything the DM has shown you. Write a note with New note; it is yours alone until you share it.")


func _my_note_card(n: Dictionary) -> void:
	var id := str(n.id)
	var title := LineEdit.new()
	title.name = "Title"
	title.placeholder_text = "Title"
	title.text = str(n.get("title", ""))
	title.custom_minimum_size.y = 40
	_card.add_child(title)
	var frow := HBoxContainer.new()
	var fl := Label.new()
	fl.text = "Folder"
	fl.theme_type_variation = "DimLabel"
	frow.add_child(fl)
	var folder := LineEdit.new()
	folder.name = "Folder"
	folder.placeholder_text = "none — or name one to group your notes"
	folder.text = str(n.get("folder", ""))
	folder.custom_minimum_size.y = 40
	folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(folder)
	_card.add_child(frow)
	var about := str(n.get("about", ""))
	if about != "":
		var on := _shown_title(about)
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "On: " + (on if on != "" else "something no longer shown")
		l.theme_type_variation = "DimLabel"
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		if on != "":
			var go := Button.new()
			go.text = "Open"
			go.pressed.connect(func() -> void: open("shown:" + about))
			row.add_child(go)
		_card.add_child(row)
	var text := TextEdit.new()
	text.name = "Text"
	text.placeholder_text = "Your note"
	text.text = str(n.get("text", ""))
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.custom_minimum_size = Vector2(0, 180)
	_card.add_child(text)
	# saved a moment after typing stops, and when a field is left
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.8
	_card.add_child(timer)
	var keep := func() -> void:
		var cur: Dictionary = _local.get(id, n).duplicate()
		if cur.get("title", "") == title.text and cur.get("text", "") == text.text and cur.get("folder", "") == folder.text:
			return
		cur.title = title.text
		cur.text = text.text
		cur.folder = folder.text
		_local[id] = cur
		_save(cur)
		refresh_tree()
	timer.timeout.connect(keep)
	for w in [title, folder]:
		(w as LineEdit).text_changed.connect(func(_t: String) -> void: timer.start())
		(w as LineEdit).focus_exited.connect(func() -> void:
			timer.stop()
			keep.call())
	text.text_changed.connect(func() -> void: timer.start())
	text.focus_exited.connect(func() -> void:
		timer.stop()
		keep.call())
	# who may read it
	var share: Array = n.get("share", [])
	var head := Label.new()
	head.name = "ReadBy"
	head.text = "Who can read it: " + _share_words(share)
	head.theme_type_variation = "DimLabel"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(head)
	var boxes := VBoxContainer.new()
	boxes.name = "Share"
	var targets := [["gm", "The DM"]]
	if session != null and session.state != null:
		for p in session.state.encounter.players:
			if str(p.get("id", "")) != me():
				targets.append([str(p.id), str(p.get("name", p.id))])
	targets.append(["all", "Everyone"])
	for t in targets:
		var cb := CheckBox.new()
		cb.text = str(t[1])
		cb.name = "Share_" + str(t[0])
		cb.button_pressed = share.has(t[0])
		cb.custom_minimum_size.y = 40
		var who: String = t[0]
		cb.toggled.connect(func(on: bool) -> void: set_share(id, who, on))
		boxes.add_child(cb)
	_card.add_child(boxes)
	var del := Button.new()
	del.name = "Delete"
	del.text = "Delete this note" if _delete_armed != id else "Tap again to delete it"
	del.custom_minimum_size.y = 40
	del.pressed.connect(func() -> void:
		if _delete_armed != id:
			_delete_armed = id
			del.text = "Tap again to delete it"
			return
		delete_note(id))
	_card.add_child(del)


## Share a note of mine with someone ("gm", a player id, "all"), or stop.
func set_share(id: String, who: String, on: bool) -> void:
	var n := _find(my_notes(), id)
	if n.is_empty():
		return
	var cur: Dictionary = n.duplicate(true)
	var share: Array = (cur.get("share", []) as Array).duplicate()
	if who == "all":
		share = ["all"] if on else []
	else:
		share.erase("all")
		if on and not share.has(who):
			share.append(who)
		elif not on:
			share.erase(who)
	share.sort()
	cur.share = share
	_local[id] = cur
	_save(cur)
	refresh_tree()
	_render_card()


func delete_note(id: String) -> void:
	_deleted[id] = true
	_local.erase(id)
	if send.is_valid():
		send.call({"kind": "note", "op": "delete", "id": id})
	current = ""
	refresh_tree()
	_render_card()


func _save(n: Dictionary) -> void:
	if send.is_valid():
		send.call({"kind": "note", "op": "save", "note": {"id": n.id, "title": n.get("title", ""), "text": n.get("text", ""),
			"folder": n.get("folder", ""), "about": n.get("about", ""), "share": n.get("share", [])}})


func _other_note_card(n: Dictionary) -> void:
	_header(str(n.get("title", "")) if str(n.get("title", "")) != "" else "A note")
	_dim("From %s" % _player_name(str(n.get("owner", ""))))
	_rich(str(n.get("text", "")))


func _shown_card(h: Dictionary) -> void:
	_header(str(h.get("title", "")) if str(h.get("title", "")) != "" else "From the DM")
	_dim(("Shown to you in session %d" % int(h.session)) if h.has("session") else "Shown to you this session")
	var tex := packs.picture_texture(str(h.get("image", "")), 1024.0) if packs != null and str(h.get("image", "")) != "" else null
	if tex != null:
		var tr := TextureRect.new()
		tr.name = "Picture"
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(0, 220)
		_card.add_child(tr)
	_rich(str(h.get("text", "")))
	var ref := str(h.get("ref", "")) if str(h.get("ref", "")) != "" else str(h.get("id", ""))
	var mine := my_notes().filter(func(n: Dictionary) -> bool: return str(n.get("about", "")) == ref)
	if not mine.is_empty():
		_header("My notes on this")
		for n in mine:
			var b := Button.new()
			b.text = _note_label(n)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var nid := str(n.id)
			b.pressed.connect(func() -> void: open("mine:" + nid))
			_card.add_child(b)
	var add := Button.new()
	add.name = "NoteOnThis"
	add.text = "Add a note on this"
	add.custom_minimum_size.y = 40
	var title := str(h.get("title", ""))
	add.pressed.connect(func() -> void: new_note(ref, title))
	_card.add_child(add)


func _shown_title(ref: String) -> String:
	for h in shown():
		if str(h.get("ref", "")) == ref or str(h.get("id", "")) == ref:
			return str(h.get("title", ""))
	return ""


func _share_words(share: Array) -> String:
	if share.has("all"):
		return "everyone"
	if share.is_empty():
		return "only you"
	var names := PackedStringArray()
	for s in share:
		names.append("the DM" if str(s) == "gm" else _player_name(str(s)))
	return "you and " + ", ".join(names)


static func _find(list: Array, id: String) -> Dictionary:
	for n in list:
		if str(n.get("id", "")) == id:
			return n
	return {}


func _header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HeaderLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(l)


func _dim(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(l)


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
