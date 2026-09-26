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
##   intent {kind: dm, op, …}; need {kind: scene})
## host → client
##   welcome  {version, encounter}            the document without its rules blocks
##   joined   {player, role}                  the join was accepted
##   event    {ev}                            a scene event applied; apply it too
##   view     {view}                          the client's projection (Views.project)
##   refused  {ev | intent, why, req?}        the request was not applied (an intent's `req` with it)
##   done     {req}                           the intent sent with `req` was taken (a form says so, and clears)
##   map      {id, doc}                       a map document
##   packs    {packs: [{id, version, manifest, files}]}
##   file     {pack, file, data}              base64 of one pack file
##   asset    {map, file, data}               base64 of one of a map's files
##   comp     {req, collection, entry | page}   what was asked for, under the viewer's audience
##   error    {why}                           then the host closes
##   pong     {}
##   scene    {scene, players, clock, online, scenes?}   a web client's scene (WebScene), for it
##   dm       {state}                          the DM's web screen: the campaign as it shows it

const VERSION := 2
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
static func welcome(encounter: Encounter, gm := false) -> Dictionary:
	return {"t": "welcome", "version": VERSION, "encounter": client_document(encounter.doc, gm)}


## With `gm` (a co-GM), the scene is sent whole: GM regions, every cell,
## the scene's triggers. The rules blocks still travel as a view.
static func client_document(doc: Dictionary, gm := false) -> Dictionary:
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
	for sc in out.get("scenes", []):
		sc.erase("triggers")
		var regions: Dictionary = sc.get("regions", {})
		for id in regions.keys():
			if str(regions[id].get("audience", "all")) == "gm":
				regions.erase(id)
		var cells: Dictionary = sc.get("cells", {})
		for key in cells.keys():
			if not bool(cells[key].get("revealed", false)):
				cells.erase(key)
	return out


static func view(projection: Dictionary) -> Dictionary:
	return {"t": "view", "view": projection}


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
