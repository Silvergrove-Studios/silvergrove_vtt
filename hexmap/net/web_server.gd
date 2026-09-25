class_name WebServer
extends RefCounted
## The web clients' side door: a small HTTP server beside the Table's
## WebSocket. It serves the web clients themselves (the player's screen at
## `/`, the DM's at `/dm` — one page, the path decides), the art they draw
## with (`/art/<pack>/<file>`, the packs the Table holds), the maps' own
## files (`/mapfile/<map id>/<file>`, a backdrop), and `/config.json` (where
## the WebSocket is). Players open it from any phone or computer on the
## network: nothing to install. Only GET and HEAD; nothing outside those
## roots is served. Non-blocking: poll it every frame.
##
## The web clients are built (web/, `npm run build`) into one zip,
## `webclient.zip`, which the exports carry as it is: a folder of fonts and
## images would be imported by Godot and not be there as files.

const DEFAULT_PORT := 47780
const MAX_REQUEST := 16384
const TIMEOUT_MS := 15000
const CHUNK := 65536
const TYPES := {"html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
	"json": "application/json; charset=utf-8", "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
	"webp": "image/webp", "gif": "image/gif", "ico": "image/x-icon", "woff2": "font/woff2", "woff": "font/woff", "ttf": "font/ttf",
	"txt": "text/plain; charset=utf-8", "map": "application/json; charset=utf-8"}
## The pages of the one-page web client: each serves index.html.
const PAGES := ["/", "/play", "/dm", "/dm/card", "/join"]

## Where the built web clients are (index.html and assets/): a zip, or a folder.
var root := "res://webclient.zip"
var port := 0
## (pack: String, file: String) -> PackedByteArray: a pack's file, or empty.
var art_source: Callable = Callable()
## (map_id: String, file: String) -> PackedByteArray: a map's own file, or empty.
var map_file_source: Callable = Callable()
## () -> Dictionary: what /config.json says.
var config_source: Callable = Callable()
var _server := TCPServer.new()
var _conns: Array = []
var _zip: ZIPReader = null
var _zip_files: Dictionary = {}
var _zip_time := 0


func start(p_port := DEFAULT_PORT) -> Error:
	var err := _server.listen(p_port)
	if err != OK and p_port != 0:
		err = _server.listen(0)
	if err != OK:
		return err
	port = _server.get_local_port()
	return OK


func stop() -> void:
	for c in _conns:
		(c.stream as StreamPeerTCP).disconnect_from_host()
	_conns.clear()
	_server.stop()
	port = 0
	if _zip != null:
		_zip.close()
		_zip = null


func is_running() -> bool:
	return _server.is_listening()


## Take new connections, read their requests, answer them a chunk at a time.
func poll() -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		_conns.append({"stream": _server.take_connection(), "in": PackedByteArray(), "out": PackedByteArray(), "sent": 0,
			"born": Time.get_ticks_msec(), "answered": false})
	for c in _conns.duplicate():
		var s: StreamPeerTCP = c.stream
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(c.born) > TIMEOUT_MS:
			s.disconnect_from_host()
			_conns.erase(c)
			continue
		if not bool(c.answered):
			var n := s.get_available_bytes()
			if n > 0:
				var got: Array = s.get_partial_data(n)
				if int(got[0]) == OK:
					# (a packed array is a value: append to it, then put it back)
					var buf: PackedByteArray = c["in"]
					buf.append_array(got[1])
					c["in"] = buf
			var head := (c["in"] as PackedByteArray).get_string_from_ascii()
			if head.contains("\r\n\r\n"):
				c.out = respond(head)
				c.answered = true
			elif (c["in"] as PackedByteArray).size() > MAX_REQUEST:
				c.out = _status(431, "Request Header Fields Too Large")
				c.answered = true
		if bool(c.answered):
			var out: PackedByteArray = c.out
			var sent := int(c.sent)
			if sent < out.size():
				var put: Array = s.put_partial_data(out.slice(sent, mini(sent + CHUNK, out.size())))
				if int(put[0]) == OK:
					c.sent = sent + int(put[1])
			if int(c.sent) >= out.size():
				s.disconnect_from_host()
				_conns.erase(c)


## The whole response to a request's head (its first line and headers):
## status line, headers and body. Public for tests.
func respond(head: String) -> PackedByteArray:
	var parts := head.get_slice("\r\n", 0).split(" ")
	if parts.size() < 2:
		return _status(400, "Bad Request")
	var method := parts[0]
	if method != "GET" and method != "HEAD":
		return _status(405, "Method Not Allowed")
	var raw := parts[1].get_slice("?", 0).get_slice("#", 0)
	if raw.to_lower().contains("%00"):
		return _status(404, "Not Found")
	var path := raw.uri_decode()
	if path.contains("..") or path.contains("\\"):
		return _status(404, "Not Found")
	var body := PackedByteArray()
	var type := ""
	var cache := "no-cache"
	if PAGES.has(path.trim_suffix("/") if path != "/" else path):
		body = _client_file("index.html")
		type = TYPES.html
	elif path == "/config.json":
		var cfg: Dictionary = config_source.call() if config_source.is_valid() else {}
		body = JSON.stringify(cfg).to_utf8_buffer()
		type = TYPES.json
	elif path.begins_with("/assets/"):
		body = _client_file(path.substr(1))
		type = _type(path)
		cache = "max-age=31536000, immutable"
	elif path.begins_with("/art/"):
		var rest := path.substr(5)
		var pack := rest.get_slice("/", 0)
		var file := rest.substr(pack.length() + 1)
		if pack != "" and file != "" and art_source.is_valid():
			body = art_source.call(pack, file)
		type = _type(file)
		cache = "max-age=3600"
	elif path.begins_with("/mapfile/"):
		var rest := path.substr(9)
		var mid := rest.get_slice("/", 0)
		var file := rest.substr(mid.length() + 1)
		if mid != "" and file != "" and map_file_source.is_valid():
			body = map_file_source.call(mid, file)
		type = _type(file)
		cache = "max-age=3600"
	elif path == "/favicon.ico":
		return _status(204, "No Content")
	if body.is_empty():
		return _status(404, "Not Found")
	var headers := "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: %s\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % [type, body.size(), cache]
	var out := headers.to_utf8_buffer()
	if method == "GET":
		out.append_array(body)
	return out


## A file of the web clients, from the zip or the folder they were built into.
func _client_file(rel: String) -> PackedByteArray:
	if not root.get_extension().to_lower() == "zip":
		return _file(root.path_join(rel))
	# rebuilt while the table runs (developing the web clients): opened again
	var t := FileAccess.get_modified_time(root)
	if _zip != null and t != _zip_time:
		_zip.close()
		_zip = null
	if _zip == null:
		_zip = ZIPReader.new()
		_zip_files.clear()
		if _zip.open(root) != OK:
			_zip = null
			return PackedByteArray()
		_zip_time = t
		for f in _zip.get_files():
			_zip_files[f] = true
	if not _zip_files.has(rel):
		return PackedByteArray()
	return _zip.read_file(rel)


static func _type(path: String) -> String:
	return str(TYPES.get(path.get_extension().to_lower(), "application/octet-stream"))


static func _file(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


static func _status(code: int, text: String) -> PackedByteArray:
	var body := ("%d %s\n" % [code, text]).to_utf8_buffer()
	return ("HTTP/1.1 %d %s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, text, body.size()]).to_utf8_buffer() + body


## The addresses this machine answers on for other devices: "http://ip:port",
## the likeliest first — a home or office network before the bridges of
## virtual machines (…​.1) and overlay networks (100.64/10, a VPN's).
static func urls(web_port: int) -> PackedStringArray:
	var ips := []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.is_valid_ip_address() and not s.contains(":") and not s.begins_with("127.") and not s.begins_with("169.254."):
			ips.append(s)
	ips.sort_custom(func(a: String, b: String) -> bool:
		var ra := address_rank(a)
		var rb := address_rank(b)
		return ra < rb or (ra == rb and a < b))
	var out := PackedStringArray()
	for ip in ips:
		out.append("http://%s:%d" % [ip, web_port])
	return out


## How likely other devices reach us at an IPv4 address: 0 a private
## network, 1 a private network's .1 (usually this machine's side of a
## virtual one), 2 an overlay network (100.64/10), 3 anything else.
static func address_rank(ip: String) -> int:
	var p := ip.split(".")
	if p.size() != 4:
		return 3
	var a := int(p[0])
	var b := int(p[1])
	if a == 100 and b >= 64 and b < 128:
		return 2
	var private := a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b < 32)
	if private:
		return 1 if p[3] == "1" else 0
	return 3
