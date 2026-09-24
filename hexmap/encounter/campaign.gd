class_name Campaign
extends RefCounted
## The campaign document: what a group keeps between sessions
## (docs/campaign-format.md). Players, the persistent actors (PCs,
## companions, recurring NPCs), the rulesets in play with their settings
## and order, the packs the table added, the clock, campaign-scoped
## plugin state, long-running tracks, the journal (notes, handouts and
## rulings with their session), and the sessions played.
##
## Since version 2 the campaign is the live document (docs/campaign-plan.md):
## the Table opens it into a kernel — `runtime_encounter()` gives the
## encounter it runs on, built from the campaign or restored from the
## `runtime` block the last save kept — so sheets, rolls and rests work
## between sessions. `capture()` writes the live state back into the
## document (the summary fields and the runtime) whenever it is saved;
## `begin_session()` and `end_session()` are the ritual around a
## session (the counter, the checkpoint, the journal stamp, the recap).
## Old encounter-first files still work: `begin_session(e, path, true)`
## brings a campaign into a foreign encounter as version 1 did, and
## `bank()` takes a session back. The document is plain JSON, stable key
## order, meant to live in git beside the adventure.

const FORMAT := "silvergrove.campaign"
const VERSION := 3
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
		# content packs of this campaign's own, by path relative to the file
		"packs": [],
		# the entries this table does not use ("<plugin>:<collection>/<id>",
		# hidden from every offer, never deleted) and what was imported when
		"content": {"disabled": [], "imported": []},
		"players": [],
		"actors": {},
		# the persistent actors' pools and tracks: "actor:<id>" -> plugin -> name -> record
		"resources": {},
		"state": {"ext": {}},
		"clock": {"session": 0, "day": 1, "minute": 0},
		"tracks": {},
		"journal": [],
		# the campaign's maps (places), by id; prepared encounters (recipes for
		# a scene over a map); places on regional maps; where the party is
		"maps": [],
		"encounters": [],
		"places": [],
		"party": {},
		# the sessions played: {n, started, ended, recap, file (v1 encounters)}
		"sessions": [],
		# the live encounter document as of the last save; {} until then
		"runtime": {},
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
var maps: Array:
	get: return doc.maps
var places: Array:
	get: return doc.places
var sessions: Array:
	get: return doc.sessions
var packs: Array:
	get: return doc.packs
var content: Dictionary:
	get: return doc.content


## The campaign's folder: where its maps, packs and rules live.
func base_dir() -> String:
	return path.get_base_dir() if path != "" else ""


## A path the campaign names (a map, a pack), resolved against its folder.
func resolve(p: String) -> String:
	if p == "" or p.is_absolute_path() or p.begins_with("res://") or p.begins_with("user://"):
		return p
	var dir := base_dir()
	return dir.path_join(p) if dir != "" else p


## Every pack of this campaign's own, as absolute paths (missing ones included).
func pack_paths() -> Array:
	var out := []
	for p in packs:
		if p is Dictionary and str(p.get("path", "")) != "":
			out.append(resolve(str(p.path)))
	return out


## "<plugin>:<collection>/<id>" — how a disabled entry is named.
static func content_key(plugin: String, collection: String, id: String) -> String:
	return "%s:%s/%s" % [plugin, collection, id]


## The disabled keys as {collection: {id: true}} for the compendium.
func disabled_index() -> Dictionary:
	var out := {}
	for key in content.get("disabled", []):
		var s := str(key)
		var coll := s.substr(s.find(":") + 1).get_slice("/", 0) if s.contains(":") else s.get_slice("/", 0)
		var eid := s.substr(s.find("/") + 1) if s.contains("/") else ""
		if coll == "" or eid == "":
			continue
		if not out.has(coll):
			out[coll] = {}
		out[coll][eid] = true
	return out


## Turn an entry off (hidden from every offer) or on again. Whether it changed.
func set_disabled(plugin: String, collection: String, id: String, off: bool) -> bool:
	var key := content_key(plugin, collection, id)
	var list: Array = content.disabled
	var at := list.find(key)
	if off == (at >= 0):
		return false
	if off:
		list.append(key)
		list.sort()
	else:
		list.remove_at(at)
	touch()
	return true


func is_disabled(plugin: String, collection: String, id: String) -> bool:
	return (content.disabled as Array).has(content_key(plugin, collection, id))


func map_entry(mid: String) -> Dictionary:
	for m in maps:
		if str(m.get("id", "")) == mid:
			return m
	return {}


func encounter_entry(eid: String) -> Dictionary:
	for e in encounters:
		if str(e.get("id", "")) == eid:
			return e
	return {}


# ------------------------------------------------------------- runtime --

## The encounter the Table runs this campaign on: the one the last save
## kept, or a fresh one with the campaign's players, actors, resources,
## tracks, clock and state in it. Its path is the campaign's, so map
## paths in its scenes resolve beside the campaign file.
func runtime_encounter() -> Encounter:
	var e: Encounter = null
	if doc.get("runtime") is Dictionary and not (doc.runtime as Dictionary).is_empty():
		var err := []
		e = Encounter.from_json(JsonDoc.stringify(doc.runtime), err)
	if e == null:
		e = Encounter.create(name)
		var st := EncounterState.new(e)
		for ev in begin_session(e, path, true, false):
			st.apply(ev)
	e.path = path
	e.dirty = false
	e.doc.name = name
	return e


## Write the live encounter into the document: the summary fields the
## journal, players, actors, resources, tracks, clock and state — and the
## runtime itself. No session stamping. What `save()` does first.
func capture(e: Encounter) -> void:
	_take_state(e)
	var rt: Dictionary = JsonDoc.deep(e.doc)
	rt.erase("checkpoints")   # the ones worth keeping between sessions are in `sessions`
	doc.runtime = rt
	touch()


## The ritual at the end of a session: journal-worthy log entries stamped
## with the session, the session listed with its recap, the state
## captured. Returns the summary.
func end_session(e: Encounter, recap := "") -> Dictionary:
	var summary := bank(e, "")
	var n := int(e.clock.get("session", clock.get("session", 0)))
	var rec := session_entry(n)
	if rec.is_empty():
		rec = {"n": n, "started": ""}
		sessions.append(rec)
	rec.ended = JsonDoc.now()
	if recap != "":
		rec.recap = recap
	capture(e)
	return summary


func session_entry(n: int) -> Dictionary:
	for s in sessions:
		if int(s.get("n", 0)) == n:
			return s
	return {}


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

## The events that start a session. On the campaign's own runtime the
## ritual is small (`full = false`): the clock to the next session and
## the campaign reference. Into a foreign encounter (`full`, the
## version-1 way) the players, the actors (added, or their data refreshed
## when the encounter already has them), their resources and the tracks
## come in too. `bump` false loads the clock as it stands (a fresh runtime).
## Nothing is applied here.
func begin_session(e: Encounter, campaign_path := "", full := false, bump := true) -> Array:
	var events := []
	var session := int(clock.get("session", 0)) + (1 if bump else 0)
	if not full:
		events.append({"t": "clock.set", "changes": {"session": session}})
		events.append({"t": "encounter.set", "changes": {"campaign": {"id": id, "path": campaign_path, "ext": JsonDoc.deep(e.campaign.get("ext", doc.state.get("ext", {})))}}})
		var rec := session_entry(session)
		if rec.is_empty():
			sessions.append({"n": session, "started": JsonDoc.now()})
		return events
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
	var summary := _take_state(e)
	var session := int(e.clock.get("session", int(clock.get("session", 0)) + 1))
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
	if encounter_path != "":
		var rec := session_entry(session)
		if rec.is_empty():
			rec = {"n": session, "started": ""}
			sessions.append(rec)
		rec.file = encounter_path
	touch()
	return summary


## Players, persistent actors and their resources, campaign tracks, the
## clock and campaign state from the live encounter into the document.
func _take_state(e: Encounter) -> Dictionary:
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
		# the campaign's own: what it had, player characters and companions, and
		# anything marked `persistent` (an NPC the DM added to the roster)
		if not actors.has(aid) and not PERSISTENT_KINDS.has(str(a.get("kind", ""))) and not bool(a.get("persistent", false)):
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
	clock.session = int(e.clock.get("session", int(clock.get("session", 0))))
	clock.day = int(e.clock.get("day", clock.get("day", 1)))
	clock.minute = int(e.clock.get("minute", clock.get("minute", 0)))
	doc.state.ext = JsonDoc.deep(e.campaign.get("ext", {}))
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
	# version 1 listed the sessions' encounter files under `encounters`;
	# version 2 keeps prepared encounters there and the sessions apart
	if int(doc.get("version", 1)) < 2 and doc.get("encounters") is Array:
		var files: Array = []
		for f in doc.encounters:
			if f is String:
				files.append({"n": files.size() + 1, "file": str(f)})
		if not files.is_empty() or (doc.encounters as Array).is_empty():
			doc.sessions = files
			doc.encounters = []
	for k in ["plugins", "packs", "players", "journal", "encounters", "maps", "places", "sessions"]:
		if not (doc.get(k) is Array):
			doc[k] = []
	# version 3: content the campaign carries — what is turned off, what was imported
	if not (doc.get("content") is Dictionary):
		doc.content = {}
	for k in ["disabled", "imported"]:
		if not (doc.content.get(k) is Array):
			doc.content[k] = []
	for k in ["actors", "resources", "state", "tracks", "meta", "ext", "clock", "party", "runtime"]:
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


## The same campaign again in a folder of its own — its maps, its
## content, its rules and its play — with a new id and name. A copy is
## a copy: nothing is shared with the original. {ok, why, path}.
static func duplicate_to(source: Campaign, dest: String, p_name: String, fresh := false) -> Dictionary:
	var out := {"ok": false, "why": "", "path": ""}
	if source == null or source.path == "":
		out.why = "save the campaign first"
		return out
	if DirAccess.dir_exists_absolute(dest):
		out.why = "%s already exists" % dest
		return out
	if DirAccess.make_dir_recursive_absolute(dest) != OK:
		out.why = "cannot make %s" % dest
		return out
	var why := _copy_tree(source.base_dir(), dest, source.path.get_file())
	if why != "":
		out.why = why
		return out
	var err := []
	var c := Campaign.load_file(dest.path_join(source.path.get_file()), err)
	if c == null:
		out.why = ", ".join(PackedStringArray(err))
		return out
	c.doc.id = JsonDoc.uuid()
	c.doc.name = p_name
	if fresh:
		# for another group: the adventure, none of this one's play
		c.doc.runtime = {}
		c.doc.sessions = []
		c.doc.journal = []
		c.doc.players = []
		c.doc.resources = {}
		c.doc.clock = {"session": 0, "day": 1, "minute": 0}
		var keep := {}
		for aid in c.doc.actors:
			if str(c.doc.actors[aid].get("kind", "")) != "pc":
				keep[aid] = c.doc.actors[aid]
		c.doc.actors = keep
		for e in c.encounters:
			if e is Dictionary:
				e.erase("live")
				e.played = []
	var path := dest.path_join("%s.campaign" % CampaignPackage._slug(p_name))
	if c.save(path) != OK:
		out.why = "cannot write %s" % path
		return out
	if path != dest.path_join(source.path.get_file()):
		DirAccess.remove_absolute(dest.path_join(source.path.get_file()))
	out.path = path
	out.ok = true
	return out


## Copy a campaign folder: everything but the autosaves.
static func _copy_tree(from: String, to: String, campaign_file: String) -> String:
	var da := DirAccess.open(from)
	if da == null:
		return "cannot read %s" % from
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not n.begins_with(".") and not n.ends_with(".autosave"):
			if da.current_is_dir():
				DirAccess.make_dir_recursive_absolute(to.path_join(n))
				var why := _copy_tree(from.path_join(n), to.path_join(n), "")
				if why != "":
					da.list_dir_end()
					return why
			elif n == campaign_file or campaign_file == "" or not n.ends_with(".campaign"):
				if JsonDoc.copy_file(from.path_join(n), to.path_join(n)) != OK:
					da.list_dir_end()
					return "cannot copy %s" % n
		n = da.get_next()
	da.list_dir_end()
	return ""


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
