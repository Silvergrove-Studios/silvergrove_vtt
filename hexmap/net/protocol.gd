class_name Protocol
extends RefCounted
## The wire format between a Table (host) and its clients: JSON text
## messages over a WebSocket, each with a type `t`. Kept tiny and versioned
## so a relay can sit in the middle one day without understanding much.
##
## Version 2: clients hold the *scene* (maps, tokens, fog, doors, turns)
## and receive the rules — sheets, effects, tracks, prompts, the log — as
## a projected `view` for their audience. Rules actions are `intent`s the
## Table resolves. A client joins with a role: `player` (one of the
## encounter's players), `display` (a screen everyone can see: the "all"
## audience, no controls) or `cogm` (a co-GM: the GM audience and the
## GM's powers on a second device; joins with the code the Table shows).
##
## client → host
##   hello    {version, name}                 first thing on connect
##   join     {player, role, code}            which player (or display, or co-GM with the code) this client is
##   request  {ev}                            a scene event the player asks for (a move)
##   intent   {intent, req?}                  a rules action: {kind: action|answer|focus|contribute, …};
##                                            with `req` (a string) the host answers done or refused with it
##   need     {kind: map, id} | {kind: packs} | {kind: file, pack, file}
##            | {kind: asset, map, file}       a map's own file (a backdrop image)
##            | {kind: comp, req, collection, id | query}   a compendium entry or page
##   ping     {}
##   (web clients: hello {web: true}; join {role: player, name} adds or
##   finds a player by name; join {role: dm, token} is the DM's own screen,
##   on this machine; intent {kind: chat, text, to, private};
##   intent {kind: typing, to, private} while the chat box holds something
##   being written, every few seconds at most, never kept;
##   intent {kind: dm, op, …}; need {kind: scene})
##   mark     {op: set, mark} | {op: remove, id} | {op: clear, whose}
##                                            the table's shared marks (Marks): a ruler, a
##                                            template, a spell's preview, a ping — one's own;
##                                            the DM may remove or clear anyone's. Never kept.
## host → client
##   welcome  {version, encounter}            a co-GM's: the document without its rules blocks; a
##                                             player's Godot client's (a display's): what their
##                                             screen shows, the scene the players see and the
##                                             tokens they see (player_document); a web client's,
##                                             and any client's before it joins: the table's name
##                                             and players alone
##   joined   {player, role}                  the join was accepted
##   event    {ev}                            a scene event applied; apply it too (a player's
##                                             client: what it sees of it — its tokens and the
##                                             order kept in step, token.add / token.remove as
##                                             they come into its sight or leave it)
##   view     {view}                          the client's projection (Views.project; since 4, by Wire); the DM seeing
##                                             as a player also gets their chat (view.preview_chat)
##   refused  {ev | intent, why, req?}        the request was not applied (an intent's `req` with it)
##   done     {req}                           the intent sent with `req` was taken (a form says so, and clears);
##                                             sent after the views it changed, so its result is there
##   typing   {from, name}                    a web client: someone ("gm" or a player id) is writing
##                                             in the chat to this viewer (see intent kind typing)
##   map      {id, doc}                       a map document
##   packs    {packs: [{id, version, manifest, files}]}
##   file     {pack, file, data}              base64 of one pack file
##   asset    {map, file, data}               base64 of one of a map's files
##   comp     {req, collection, entry | page}   what was asked for, under the viewer's audience
##   error    {why}                           then the host closes
##   pong     {}
##   scene    {scene, players, clock, online, scenes?, preview?, preview_as?, preview_why?, preview_marks?}
##                                             a web client's scene (WebScene), for it (by Wire); the
##                                             DM seeing as a player gets theirs, why each
##                                             creature they don't see isn't there, and the
##                                             marks on the map as that player is sent them
##   seen_marks {as, marks}                   the DM seeing as a player: their marks again (one
##                                             put, changed or gone)
##   Every message reaches a screen with the rulesets' marked words put right
##   for it (Knowledge): a creature's name, its conditions, as it may read them.
##   dm       {state}                          the DM's web screen: the campaign as it shows it (by Wire)
##   marks    {marks}                          every shared mark this client may see (on joining)
##   mark     {mark}                           one put or changed, with its owner's name and
##                                             colour (a ruler's `measure` the Table's)
##   unmark   {ids}                            gone, or no longer for this client
##
## Version 3: sight follows the light. A scene is lit by daylight, dim light
## or dark (its own `light`, else its map level's, else daylight), a
## token's `vision` may be in `units`, and `radius` no longer limits how
## far it sees. A client that works out its own sight (a Godot one) must
## do it the table's way, so older ones are refused. A player's device is
## sent a map without the DM's notes on it (player_map).
##
## Version 4: views travel by what changed (Wire). A view schema — a sheet's,
## the status view's, an entry's card, the DM's party view — is sent to a
## connection once: in its place a record carries `schema_ref`
## ("<plugin>/<kind>@<hash of its contents>"), the message that first needs
## it carries it in `schemas` ({id: schema}), and one registered again with
## other contents has another id. A view, a scene and a DM state are sent
## whole once per connection (with `n`), then as a patch on the one before:
##   view   {view, n, schemas?} | {patch, base, n, schemas?}
##   dm     {state, n, schemas?} | {patch, base, n, schemas?}
##   scene  {scene, players, …, n} | {patch, base, n}
## (Wire has the patch's form.) A client that can't read one asks for it whole:
##   need   {kind: view | dm | scene}
## and says on joining which schemas it holds, which are not sent again:
##   join   {…, have: [schema ids]}
## A client of version 3 would draw a view of references and patches as
## nothing, so it is refused.

const VERSION := 4
const ROLES := ["player", "display", "cogm", "dm"]
## Events clients apply themselves; everything else reaches them as a view.
const SCENE_EVENTS := ["encounter.set", "scene.add", "scene.remove", "scene.set", "scene.activate",
	"token.add", "token.remove", "token.set", "element.set", "fog.set", "fog.reveal", "fog.hide", "turns.set",
	"player.add", "player.remove", "player.set", "clock.set"]
## Scene events the host filters by audience before sending (regions with
## a GM audience, cells that are not revealed).
const AUDIENCE_EVENTS := ["region.add", "region.remove", "region.set", "cell.set", "ext.set"]
## Document blocks a client does not hold.
const RULES_BLOCKS := ["actors", "effects", "resources", "tracks", "pending", "log", "rng", "checkpoints"]
const DEFAULT_PORT := 47777
## Multicast group and port the Table announces on.
const DISCOVERY_GROUP := "239.255.42.7"
const DISCOVERY_PORT := 47778
## WebSocket buffers: pack images can be megabytes.
const BUFFER_SIZE := 32 * 1024 * 1024


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


## Parse a message; {} when it is not one.
static func decode(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary) or not (json.data as Dictionary).has("t"):
		return {}
	return json.data


static func hello(p_name: String) -> Dictionary:
	return {"t": "hello", "version": VERSION, "name": p_name}


## The document as a client holds it: without the rules blocks (those
## reach it projected, as a view) and with the plugin state emptied.
## `known`: what the rulesets say the players know of a creature no player
## owns (Knowledge), for a player's document.
static func welcome(encounter: Encounter, gm := false, known: Array = []) -> Dictionary:
	return {"t": "welcome", "version": VERSION, "encounter": client_document(encounter.doc, gm, known)}


## A web screen's welcome: the table's name and its players (a returning one
## taps their name). It holds no document: its scene comes as snapshots.
static func welcome_web(encounter: Encounter) -> Dictionary:
	# (a document a Godot client can read: nothing in it but who the players are,
	# for a screen that hasn't said who it is yet)
	return {"t": "welcome", "version": VERSION, "encounter": {"format": Encounter.FORMAT, "version": Encounter.VERSION, "name": encounter.name,
		"players": public_players(encounter.players), "rng": {}}}


## With `gm` (a co-GM), the scene is sent whole: GM regions, every cell,
## the scene's triggers. The rules blocks still travel as a view. A
## player's has of a monster's tokens what `known` says the players know
## (Knowledge): the marks of its health and its conditions' tags they see,
## and — its name kept from them — "a creature", labelled as they see it.
static func client_document(doc: Dictionary, gm := false, known: Array = []) -> Dictionary:
	var out: Dictionary = JsonDoc.deep(doc)
	for k in RULES_BLOCKS:
		if out.has(k):
			out[k] = {} if out[k] is Dictionary else []
	out.pending = {"prompts": {}, "rolls": {}}
	out.state = {"ext": {}}
	if out.get("campaign") is Dictionary:
		out.campaign.ext = {}
	if gm:
		return out
	# the encounter's own notes are the DM's
	if out.get("notes") is Array:
		out.notes = []
	var actors: Dictionary = doc.get("actors", {}) if doc.get("actors") is Dictionary else {}
	# the order as a player sees it: no creature the DM hides in any part of it,
	# no initiative where a creature's rolls are the DM's (Knowledge)
	if out.get("turns") is Dictionary:
		out.turns = Knowledge.player_turns(out.turns, doc, known)
	for sc in out.get("scenes", []):
		sc.erase("triggers")
		if Knowledge.hides(known) and sc.get("tokens") is Array:
			var labels := Knowledge.player_labels(sc.tokens, actors, known)
			var kept := []
			for tk in sc.tokens:
				kept.append(Knowledge.player_token(tk, doc, known, str(labels.get(str(tk.get("id", "")), ""))) if tk is Dictionary else tk)
			sc.tokens = kept
		var regions: Dictionary = sc.get("regions", {})
		for id in regions.keys():
			if str(regions[id].get("audience", "all")) == "gm":
				regions.erase(id)
		var cells: Dictionary = sc.get("cells", {})
		for key in cells.keys():
			if not bool(cells[key].get("revealed", false)):
				cells.erase(key)
	return out


## A player's welcome (Godot, a display too): their document (player_document).
static func player_welcome(doc: Dictionary) -> Dictionary:
	return {"t": "welcome", "version": VERSION, "encounter": doc}


## The fields a player's Godot client is sent of a token that isn't the
## party's: what a web screen's snapshot has of it (no darkvision, nothing the
## DM keeps on it), and the light it carries (a client lights its own map).
const PLAYER_TOKEN_KEYS := ["id", "name", "pos", "size", "color", "label", "art", "owner", "actor", "rot", "tags", "elevation", "light"]
## The fields of a scene a player's Godot client is sent: not its triggers, a
## ruleset's own data on it, nor where the DM keeps its map.
const PLAYER_SCENE_KEYS := ["id", "name", "map", "level", "fog", "light", "space"]


## The document a player's Godot client holds (a display's: `player_id` "",
## what every player's characters see): only what their screen would show —
## the scene the players see (`scene_id`) and of it the tokens they see
## (`seen`: WebScene.seen), each as they may know it (player_token); its
## regions and cells as far as they're shown; the order as they see it
## (Knowledge.player_turns); the table's players, clock and name. No other
## scene (a fight staged ahead, a map they haven't been shown), no token the
## DM hides or they can't see, no rules blocks, no DM's notes, nothing a
## ruleset keeps on the encounter or the campaign. `known`: what the
## rulesets say the players know (Knowledge).
static func player_document(state: EncounterState, scene_id: String, player_id: String, seen: Dictionary, known: Array) -> Dictionary:
	var e := state.encounter
	var out := {"format": Encounter.FORMAT, "version": int(e.doc.get("version", Encounter.VERSION)), "id": str(e.doc.get("id", "")), "name": e.name,
		"active_scene": scene_id, "players": public_players(e.players), "clock": JsonDoc.deep(e.clock),
		"campaign": {"id": str(e.campaign.get("id", ""))}, "scenes": [], "rng": {},
		"turns": Knowledge.player_turns(e.turns, e.doc, known, seen if WebScene.turns_here(e, scene_id) else {})}
	var sc := e.scene(scene_id)
	if not sc.is_empty():
		out.scenes.append(player_scene(state, sc, player_id, seen, known))
	return out


## A scene as a player's Godot client holds it (player_document).
static func player_scene(state: EncounterState, sc: Dictionary, player_id: String, seen: Dictionary, known: Array) -> Dictionary:
	var out := {}
	for k in PLAYER_SCENE_KEYS:
		if sc.has(k):
			out[k] = JsonDoc.deep(sc[k])
	out.tokens = player_tokens(state, str(sc.get("id", "")), player_id, seen, known).values()
	out.overrides = player_overrides(sc.get("overrides", {}), state.level_for(str(sc.get("id", ""))))
	var regions := {}
	for id in sc.get("regions", {}):
		if str(sc.regions[id].get("audience", "all")) != "gm":
			regions[id] = JsonDoc.deep(sc.regions[id])
	out.regions = regions
	var cells := {}
	for key in sc.get("cells", {}):
		if bool(sc.cells[key].get("revealed", false)):
			cells[key] = JsonDoc.deep(sc.cells[key])
	out.cells = cells
	return out


## The tokens of a scene a player's Godot client holds, {id: token}, in the
## scene's order: those `seen`, each as player_token has it, the creatures
## whose names they don't know labelled as they see them (only those they see
## counted: Knowledge.player_labels).
static func player_tokens(state: EncounterState, scene_id: String, player_id: String, seen: Dictionary, known: Array) -> Dictionary:
	var shown: Array = state.tokens(scene_id).filter(func(tk: Dictionary) -> bool: return seen.has(str(tk.get("id", ""))))
	var labels := Knowledge.player_labels(shown, state.encounter.actors, known)
	var out := {}
	for tk in shown:
		out[str(tk.id)] = player_token(state, tk, player_id, known, str(labels.get(str(tk.id), "")))
	return out


## A token as a player's Godot client holds it: the party's whole (their
## eyes are what a client works out its sight from); any other only
## PLAYER_TOKEN_KEYS, and of a creature no player owns what the players know
## of it (Knowledge.player_token: its health's marks and conditions' tags as
## they see them, its name kept where they don't know it, `label`).
static func player_token(state: EncounterState, tk: Dictionary, player_id: String, known: Array, label := "") -> Dictionary:
	var out := {}
	if WebScene._owns(state, tk, player_id) or WebScene._party(state, tk):
		out = JsonDoc.deep(tk)
	else:
		for k in PLAYER_TOKEN_KEYS:
			if tk.has(k) and tk[k] != null:
				out[k] = JsonDoc.deep(tk[k])
	return Knowledge.player_token(out, state.encounter.doc, known, label)


## The table's players as every screen may know them: who they are, not the
## secret a seat is claimed with.
static func public_players(players: Array) -> Array:
	var out := []
	for p in players:
		if p is Dictionary:
			var q: Dictionary = JsonDoc.deep(p)
			q.erase("seat")
			out.append(q)
	return out


## A map as a player's screen is sent it, under the scene's `overrides` (the
## scene the players see on it): nothing on it the players aren't shown —
## no DM's note (`gm_only`, unless the scene shows it), no prop or light the
## DM hides (`hidden`, the map's or the scene's) or on a layer not shown; a
## secret door is the wall it looks like (`door` "none", no state: the scene
## makes it a door once it opens — player_overrides); a locked door just a
## closed one (a locked door is found by trying it). A hidden wall (one drawn
## by a prop, a pillar's) is left out — but for a client that works out its
## own sight (`sight_walls`: a Godot one), which keeps those that block sight
## as no more than where sight stops, still hidden (not drawn). With
## `level_id`, the scene's level alone: not the crypt below the chapel.
static func player_map(doc: Dictionary, overrides: Dictionary = {}, sight_walls := false, level_id := "") -> Dictionary:
	var out: Dictionary = JsonDoc.deep(doc)
	if level_id != "" and out.get("levels") is Array:
		out.levels = (out.levels as Array).filter(func(l: Variant) -> bool: return l is Dictionary and str(l.get("id", "")) == level_id)
	for lvl in out.get("levels", []):
		if not (lvl is Dictionary):
			continue
		var visible := LayerTree.visible_refs(lvl)
		for coll in ["notes", "props", "lights", "walls"]:
			var kept := []
			for o in lvl.get(coll, []):
				if not (o is Dictionary):
					continue
				var ref := LayerTree.ref(coll, str(o.get("id", "")))
				var ov: Dictionary = overrides.get(ref, {}) if overrides.get(ref) is Dictionary else {}
				var eff: Dictionary = (o as Dictionary).duplicate()
				for k in ov:
					eff[k] = ov[k]
				var unseen := not bool(visible.get(ref, true))
				match coll:
					"notes":
						if bool(eff.get("gm_only", false)) or unseen:
							continue
						o.erase("gm_only")
					"props", "lights":
						if bool(eff.get("hidden", false)) or unseen:
							continue
					"walls":
						if bool(eff.get("hidden", false)) or unseen:
							var blocks: Dictionary = o.get("blocks", {}) if o.get("blocks") is Dictionary else {}
							if not sight_walls or not bool(blocks.get("sight", true)):
								continue
							o = {"id": o.get("id", ""), "points": o.get("points", []), "blocks": blocks, "hidden": true}
						else:
							_as_seen_door(o)
				kept.append(o)
			lvl[coll] = kept
		# (and their leaves in the layer tree)
		LayerTree.ensure(lvl)
	return out


## A wall as a player knows it: a secret door the wall it looks like, a
## locked door closed. In place.
static func _as_seen_door(w: Dictionary) -> void:
	if str(w.get("door", "none")) == "secret":
		w.door = "none"
		w.erase("state")
	elif str(w.get("state", "")) == "locked":
		w.state = "closed"


## A scene's overrides of its map's elements as a player's screen is sent
## them (`level`: the scene's level of its map, as stored): none for what
## player_map leaves out; a secret door, found open, a door then (`door`
## "door"), else nothing; a locked door closed; no `hidden` (what they have
## isn't), a note's `gm_only` only where it shows the note.
static func player_overrides(overrides: Dictionary, level: Dictionary) -> Dictionary:
	var out := {}
	var visible := LayerTree.visible_refs(level)
	for ref in overrides:
		if not (overrides[ref] is Dictionary):
			continue
		var parts := LayerTree.split(str(ref))
		if parts.size() != 2:
			continue
		var base := {}
		for o in level.get(parts[0], []):
			if o is Dictionary and str(o.get("id", "")) == parts[1]:
				base = o
				break
		if base.is_empty() or not bool(visible.get(str(ref), true)):
			continue
		var ov: Dictionary = JsonDoc.deep(overrides[ref])
		var eff := base.duplicate()
		for k in ov:
			eff[k] = ov[k]
		if bool(eff.get("hidden", false)) or (parts[0] == "notes" and bool(eff.get("gm_only", false))):
			continue
		ov.erase("hidden")
		if parts[0] == "notes":
			ov.erase("gm_only")
			if bool(base.get("gm_only", false)):
				ov.gm_only = false
		elif parts[0] == "walls":
			if str(base.get("door", "none")) == "secret":
				ov = {"door": "door", "state": "open"} if str(eff.get("state", "closed")) == "open" else {}
			elif str(ov.get("state", "")) == "locked":
				ov.state = "closed"
		if not ov.is_empty():
			out[str(ref)] = ov
	return out


## An intent refused, with the `req` it was sent with (if it had one).
static func intent_refused(intent: Dictionary, why: String, req := "") -> Dictionary:
	var out := {"t": "refused", "intent": intent, "why": why}
	if req != "":
		out.req = req
	return out


## The intent sent with `req` was taken: its screen may say so.
static func done(req: String) -> Dictionary:
	return {"t": "done", "req": req}


static func event(ev: Dictionary) -> Dictionary:
	return {"t": "event", "ev": ev}


static func refused(ev: Dictionary, why: String) -> Dictionary:
	return {"t": "refused", "ev": ev, "why": why}


static func error(why: String) -> Dictionary:
	return {"t": "error", "why": why}


## The announcement a Table multicasts: enough to list it and connect.
## `addresses` are all of the table's IPv4 addresses: the packet's source
## is whichever the sender's kernel chose, not always the one that works.
static func announcement(p_name: String, port: int, host_name: String, addresses: PackedStringArray = [], web_port := 0) -> Dictionary:
	var out := {"hexmap": VERSION, "name": p_name, "port": port, "host": host_name, "addresses": Array(addresses)}
	if web_port > 0:
		out.web = web_port
	return out


static func parse_announcement(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	var d: Dictionary = json.data
	if int(d.get("hexmap", 0)) != VERSION or not d.has("port") or not d.has("name"):
		return {}
	return d


## "host", "host:port" or "ws://host:port" -> [host, port].
static func parse_address(text: String) -> Array:
	var s := text.strip_edges()
	if s.begins_with("ws://"):
		s = s.substr(5)
	s = s.trim_suffix("/")
	var port := DEFAULT_PORT
	var i := s.rfind(":")
	if i > 0 and s.substr(i + 1).is_valid_int():
		port = int(s.substr(i + 1))
		s = s.substr(0, i)
	return [s, port]
