class_name PlayerNotes
extends RefCounted
## The players' own notes, kept in the campaign on the DM's computer. Each
## player writes their own; a note is private unless its writer shares it —
## with the DM, with some of the other players, or with everyone — and the
## DM's screen never shows a private one. A note:
##
##   {id, owner, title, text, folder, about, share, created, updated}
##
## `share` lists who else may read it: "gm", player ids, or "all" (everyone
## at the table); `about` is what it is a note on (a ref: "place:<id>", the
## `ref` of something the DM showed); `folder` is the player's own
## grouping in their Journal. A player changes only their own notes.

const MAX_TITLE := 200
const MAX_TEXT := 20000
const MAX_NOTES := 500


## May this viewer read this note? The writer always; the GM when it is
## shared with the GM or everyone; another player when it is shared with
## them or everyone; a display never.
static func can_see(note: Dictionary, player_id: String, role: String) -> bool:
	var share: Array = note.get("share", []) if note.get("share") is Array else []
	if role == Views.ROLE_GM:
		return share.has("gm") or share.has("all")
	if role != Views.ROLE_PLAYER or player_id == "":
		return false
	return str(note.get("owner", "")) == player_id or share.has("all") or share.has(player_id)


## The notes this viewer may read, copied.
static func for_viewer(notes: Array, player_id: String, role: String) -> Array:
	var out := []
	for n in notes:
		if n is Dictionary and can_see(n, player_id, role):
			out.append(JsonDoc.deep(n))
	return out


static func find(notes: Array, id: String) -> Dictionary:
	for n in notes:
		if n is Dictionary and str(n.get("id", "")) == id:
			return n
	return {}


## A new note's id (the phone makes it, so it can go on editing the note
## before the Table's answer comes back).
static func new_id() -> String:
	return "pn_%08x%04x" % [randi(), randi() % 0x10000]


## A player's change to their own notes: {op: "save", note: {id, title,
## text, folder, about, share}} or {op: "delete", id}. Changes `notes` in
## place. "" or why not.
static func apply(notes: Array, change: Dictionary, player_id: String, players: Array) -> String:
	if player_id == "":
		return "only a player keeps notes here"
	match str(change.get("op", "")):
		"save":
			var n: Dictionary = change.get("note", {}) if change.get("note") is Dictionary else {}
			var id := str(n.get("id", ""))
			if not id.begins_with("pn_") or id.length() > 40:
				return "a note needs an id"
			var have := find(notes, id)
			if not have.is_empty() and str(have.get("owner", "")) != player_id:
				return "that note is someone else's"
			if have.is_empty() and notes.filter(func(x: Variant) -> bool: return x is Dictionary and str(x.get("owner", "")) == player_id).size() >= MAX_NOTES:
				return "that is as many notes as one player may keep"
			var rec: Dictionary = have if not have.is_empty() else {"id": id, "owner": player_id, "created": JsonDoc.now()}
			rec.title = str(n.get("title", "")).strip_edges().left(MAX_TITLE)
			rec.text = str(n.get("text", "")).left(MAX_TEXT)
			rec.folder = str(n.get("folder", "")).strip_edges().left(80)
			rec.about = str(n.get("about", "")).left(200)
			rec.share = share_list(n.get("share", []), players, player_id)
			rec.updated = JsonDoc.now()
			if have.is_empty():
				notes.append(rec)
			return ""
		"delete":
			var id := str(change.get("id", ""))
			for i in notes.size():
				if notes[i] is Dictionary and str(notes[i].get("id", "")) == id:
					if str(notes[i].get("owner", "")) != player_id:
						return "that note is someone else's"
					notes.remove_at(i)
					return ""
			return "no such note"
	return "unknown note change '%s'" % str(change.get("op", ""))


## Who a note is shared with, cleaned: "all" alone, or "gm" and the ids of
## players at the table (never the writer), sorted.
static func share_list(v: Variant, players: Array, owner: String) -> Array:
	var ids := {}
	for p in players:
		if p is Dictionary:
			ids[str(p.get("id", ""))] = true
	var out := []
	if v is Array:
		for s in v:
			var k := str(s)
			if k == "all":
				return ["all"]
			if (k == "gm" or (ids.has(k) and k != owner)) and not out.has(k):
				out.append(k)
	out.sort()
	return out
