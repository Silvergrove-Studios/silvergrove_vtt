class_name Protocol
extends RefCounted
## The wire format between a Table (host) and Players (clients): JSON text
## messages over a WebSocket, each with a type `t`. Kept tiny and versioned
## so a relay can sit in the middle one day without understanding much.
##
## client → host
##   hello    {version, name}                 first thing on connect
##   join     {player}                        which player this client is
##   request  {ev}                            an event the player asks for
##   need     {kind: map, id} | {kind: packs} | {kind: file, pack, file}
##   ping     {}
## host → client
##   welcome  {version, encounter}            the whole document
##   joined   {player}                        the join was accepted
##   event    {ev}                            applied; apply it too
##   refused  {ev, why}                       the request was not applied
##   map      {id, doc}                       a map document
##   packs    {packs: [{id, version, manifest, files}]}
##   file     {pack, file, data}              base64 of one pack file
##   error    {why}                           then the host closes
##   pong     {}

const VERSION := 1
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


static func welcome(encounter: Encounter) -> Dictionary:
	return {"t": "welcome", "version": VERSION, "encounter": encounter.doc}


static func event(ev: Dictionary) -> Dictionary:
	return {"t": "event", "ev": ev}


static func refused(ev: Dictionary, why: String) -> Dictionary:
	return {"t": "refused", "ev": ev, "why": why}


static func error(why: String) -> Dictionary:
	return {"t": "error", "why": why}


## The announcement a Table multicasts: enough to list it and connect.
static func announcement(p_name: String, port: int, host_name: String) -> Dictionary:
	return {"hexmap": VERSION, "name": p_name, "port": port, "host": host_name}


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
