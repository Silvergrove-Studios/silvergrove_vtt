class_name Campaign
extends RefCounted
## The campaign document: what a group keeps between sessions
## (docs/campaign-format.md). Players, the persistent actors (PCs,
## companions, recurring NPCs), the rulesets in play with their settings
## and order, the packs the table added, the clock, campaign-scoped
## plugin state, long-running tracks, the journal (notes, handouts and
## rulings with their session), and the sessions played.
##
## A campaign is not event-sourced: it is read at the start of a session
## — `begin_session()` produces the events that bring it into a fresh
## encounter — and written at the end — `bank()` takes what the session
## changed back. Everything in between happens in the encounter through
## the kernel. The document is plain JSON, stable key order, meant to
## live in git beside the adventure.

const FORMAT := "silvergrove.campaign"
const VERSION := 1
## Actor kinds that belong to the campaign when a session ends even if
## the campaign had not seen them before (a character brought by a
## player, a companion gained).
const PERSISTENT_KINDS := ["pc", "companion"]
## Log entry kinds the journal keeps between sessions.
const JOURNAL_KINDS := ["ruling", "handout", "note"]

var doc: Dictionary = {}
var path := ""
var dirty := false


static func create(p_name: String) -> Campaign:
	var c := Campaign.new()
	var now := JsonDoc.now()
	c.doc = {
		"format": FORMAT,
		"version": VERSION,
		"id": JsonDoc.uuid(),
		"name": p_name,
		"plugins": [],
		"packs": [],
		"players": [],
		"actors": {},
		# the persistent actors' pools and tracks: "actor:<id>" -> plugin -> name -> record
		"resources": {},
		"state": {"ext": {}},
		"clock": {"session": 0, "day": 1, "minute": 0},
		"tracks": {},
		"journal": [],
		"encounters": [],
		"meta": {"author": "", "description": "", "created": now, "modified": now},
		"ext": {},
	}
	return c


# ------------------------------------------------------------- accessors --

var name: String:
	get: return str(doc.get("name", "Untitled"))
var id: String:
	get: return str(doc.get("id", ""))
var players: Array:
	get: return doc.players
var actors: Dictionary:
	get: return doc.actors
var plugins: Array:
	get: return doc.plugins
var tracks: Dictionary:
	get: return doc.tracks
var resources: Dictionary:
	get: return doc.resources
var journal: Array:
	get: return doc.journal
var clock: Dictionary:
	get: return doc.clock
var encounters: Array:
	get: return doc.encounters


func player(pid: String) -> Dictionary:
	for p in players:
		if str(p.get("id", "")) == pid:
			return p
	return {}


func actor(aid: String) -> Dictionary:
	return doc.actors.get(aid, {})


## The plugin ids in the campaign's order (load order; later ones layer
## over earlier ones).
func plugin_order() -> Array:
	var out := []
	for p in plugins:
		if p is Dictionary and str(p.get("id", "")) != "":
			out.append(str(p.id))
	return out


## The settings the campaign gives a plugin ({} when it names none).
func plugin_settings(pid: String) -> Dictionary:
	for p in plugins:
		if p is Dictionary and str(p.get("id", "")) == pid:
			return JsonDoc.deep(p.get("settings", {}))
	return {}


func touch() -> void:
	dirty = true
	doc.meta.modified = JsonDoc.now()


# ------------------------------------------------------------ sessions --

## The events that bring the campaign into an encounter at the start of
## a session: its players, its actors (added, or their data refreshed
## when the encounter already has them), its tracks, the clock advanced
## to the next session, the campaign reference and campaign-scoped
## state. Nothing is applied here.
func begin_session(e: Encounter, campaign_path := "") -> Array:
	var events := []
	for p in players:
		if e.player(str(p.id)).is_empty():
			events.append({"t": "player.add", "player": JsonDoc.deep(p)})
	var ids := actors.keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = JsonDoc.deep(actors[aid])
		a.erase("derived")
		if e.actor(str(aid)).is_empty():
			events.append({"t": "actor.add", "actor": a})
		else:
			var changes := {}
			for k in ["name", "kind", "owner", "ext", "token", "audience", "packs", "art"]:
				if a.has(k):
					changes[k] = a[k]
			events.append({"t": "actor.set", "id": str(aid), "changes": changes})
		for pid in resources.get("actor:" + str(aid), {}):
			for n in resources["actor:" + str(aid)][pid]:
				events.append({"t": "resource.set", "ref": "actor:" + str(aid), "plugin": str(pid), "name": str(n), "record": JsonDoc.deep(resources["actor:" + str(aid)][pid][n])})
	var tids := tracks.keys()
	tids.sort()
	for tid in tids:
		if not e.tracks.has(tid):
			var tr: Dictionary = JsonDoc.deep(tracks[tid])
			tr.campaign = true
			events.append({"t": "track.add", "track": tr})
	var session := int(clock.get("session", 0)) + 1
	events.append({"t": "clock.set", "changes": {"session": session, "day": int(clock.get("day", 1)), "minute": int(clock.get("minute", 0))}})
	events.append({"t": "encounter.set", "changes": {"campaign": {"id": id, "path": campaign_path, "ext": JsonDoc.deep(doc.state.get("ext", {}))}}})
	return events


## Take what a session changed back into the campaign: its players, the
## persistent actors (the campaign's own, and any pc or companion new to
## it) without their derived blocks, the tracks it owns, the clock,
## campaign-scoped state, journal-worthy log entries (rulings, handouts,
## notes marked for the journal) stamped with the session, and the
## session's path. Returns a summary of what moved.
func bank(e: Encounter, encounter_path := "") -> Dictionary:
	var summary := {"actors": 0, "players": 0, "tracks": 0, "journal": 0}
	for p in e.players:
		if player(str(p.id)).is_empty():
			players.append(JsonDoc.deep(p))
			summary.players += 1
		else:
			var mine := player(str(p.id))
			for k in p:
				mine[k] = JsonDoc.deep(p[k])
	var ids := e.actors.keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = e.actors[aid]
		if not actors.has(aid) and not PERSISTENT_KINDS.has(str(a.get("kind", ""))):
			continue
		var kept: Dictionary = JsonDoc.deep(a)
		kept.erase("derived")
		actors[str(aid)] = kept
		summary.actors += 1
		var res: Dictionary = e.resources.get("actor:" + str(aid), {})
		if res.is_empty():
			resources.erase("actor:" + str(aid))
		else:
			resources["actor:" + str(aid)] = JsonDoc.deep(res)
	var tids := e.tracks.keys()
	tids.sort()
	for tid in tids:
		var tr: Dictionary = e.tracks[tid]
		if tracks.has(tid) or bool(tr.get("campaign", false)):
			var kept: Dictionary = JsonDoc.deep(tr)
			kept.erase("campaign")
			tracks[str(tid)] = kept
			summary.tracks += 1
	var session := int(e.clock.get("session", int(clock.get("session", 0)) + 1))
	clock.session = session
	clock.day = int(e.clock.get("day", clock.get("day", 1)))
	clock.minute = int(e.clock.get("minute", clock.get("minute", 0)))
	doc.state.ext = JsonDoc.deep(e.campaign.get("ext", {}))
	for entry in e.log:
		if not JOURNAL_KINDS.has(str(entry.get("kind", ""))):
			continue
		if str(entry.kind) == "note" and not bool(entry.get("journal", false)):
			continue
		if not journal_entry(str(entry.get("id", ""))).is_empty():
			continue
		var j: Dictionary = JsonDoc.deep(entry)
		j.session = session
		j.encounter = e.name
		journal.append(j)
		summary.journal += 1
	if encounter_path != "" and not encounters.has(encounter_path):
		encounters.append(encounter_path)
	touch()
	return summary


func journal_entry(jid: String) -> Dictionary:
	for j in journal:
		if str(j.get("id", "")) == jid:
			return j
	return {}


## Journal entries whose text, tags or rule mention every word of `query`
## (case-insensitive), newest first. Empty query: everything.
func search_journal(query: String, kinds: Array = []) -> Array:
	var words := []
	for w in query.to_lower().split(" ", false):
		words.append(w)
	var out := []
	for j in journal:
		if not kinds.is_empty() and not kinds.has(str(j.get("kind", ""))):
			continue
		var hay := ("%s %s %s %s" % [str(j.get("text", "")), str(j.get("title", "")), str(j.get("rule", "")), " ".join(PackedStringArray(j.get("tags", [])))]).to_lower()
		var ok := true
		for w in words:
			if not hay.contains(w):
				ok = false
				break
		if ok:
			out.append(j)
	out.reverse()
	return out


# ------------------------------------------------------------------- io --

func to_json() -> String:
	doc["format"] = FORMAT
	doc["version"] = VERSION
	return JsonDoc.stringify(doc)


static func from_json(text: String, error: Array = []) -> Campaign:
	var d := JsonDoc.parse(text, error)
	if d.is_empty():
		return null
	if d.get("format", "") != FORMAT:
		error.append("not a %s document (format is '%s')" % [FORMAT, d.get("format", "")])
		return null
	if int(d.get("version", 0)) > VERSION:
		error.append("written by a newer Hexmap (version %d, this reads %d)" % [int(d.get("version", 0)), VERSION])
		return null
	var c := Campaign.new()
	c.doc = d
	c._upgrade()
	return c


func _upgrade() -> void:
	for k in ["plugins", "packs", "players", "journal", "encounters"]:
		if not (doc.get(k) is Array):
			doc[k] = []
	for k in ["actors", "resources", "state", "tracks", "meta", "ext", "clock"]:
		if not (doc.get(k) is Dictionary):
			doc[k] = {}
	if not (doc.state.get("ext") is Dictionary):
		doc.state.ext = {}
	for k in {"session": 0, "day": 1, "minute": 0}:
		if not doc.clock.has(k):
			doc.clock[k] = {"session": 0, "day": 1, "minute": 0}[k]
	if not doc.has("id"):
		doc.id = JsonDoc.uuid()
	if not doc.has("name"):
		doc.name = "Untitled"
	for aid in doc.actors:
		Encounter.fill_actor(doc.actors[aid])
	doc.version = VERSION


func save(p_path := "") -> Error:
	if p_path != "":
		path = p_path
	if path == "":
		return ERR_FILE_BAD_PATH
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	f.close()
	dirty = false
	return OK


static func load_file(p_path: String, error: Array = []) -> Campaign:
	if not FileAccess.file_exists(p_path):
		error.append("no such file: " + p_path)
		return null
	var c := from_json(FileAccess.get_file_as_string(p_path), error)
	if c != null:
		c.path = p_path
	return c


## The campaign an encounter references, loaded from beside it (its
## `campaign.path` is relative to the encounter file, or absolute).
static func for_encounter(e: Encounter, error: Array = []) -> Campaign:
	var rel := str(e.campaign.get("path", ""))
	if rel == "":
		return null
	var p := rel if rel.is_absolute_path() or rel.begins_with("res://") or rel.begins_with("user://") else e.base_dir().path_join(rel)
	return load_file(p, error)
