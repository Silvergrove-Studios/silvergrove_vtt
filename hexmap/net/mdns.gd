class_name Mdns
extends RefCounted
## Multicast DNS, the small part of it Hexmap needs: a Table advertises
## itself as a Bonjour service (`_hexmap._tcp.local`) and answers queries
## for it; a Player asks for that service and reads the answers. Home
## routers commonly reflect mDNS between their subnets (that is how
## speakers and printers are found across them), and phones and desktops
## all speak it — where a private multicast group or a broadcast stops at
## the subnet edge, this gets through. RFC 6762/6763, encoded by hand:
## names, PTR/SRV/TXT/A records, and compression pointers when reading.

const GROUP := "224.0.0.251"
const PORT := 5353
const SERVICE := "_hexmap._tcp.local"
const TYPE_A := 1
const TYPE_PTR := 12
const TYPE_TXT := 16
const TYPE_SRV := 33
const CLASS_IN := 1
## Records live this long in caches; announcements go out more often.
const TTL := 120


# ------------------------------------------------------------------ encoding --

static func encode_name(p_name: String) -> PackedByteArray:
	var out := PackedByteArray()
	for label in p_name.trim_suffix(".").split("."):
		var b := label.to_utf8_buffer()
		out.append(mini(b.size(), 63))
		out.append_array(b.slice(0, 63))
	out.append(0)
	return out


static func _u16(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 8) & 0xff, v & 0xff])


static func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff])


static func _record(p_name: String, type: int, rdata: PackedByteArray, ttl := TTL, flush := true) -> PackedByteArray:
	var out := encode_name(p_name)
	out.append_array(_u16(type))
	out.append_array(_u16(CLASS_IN | (0x8000 if flush else 0)))
	out.append_array(_u32(ttl))
	out.append_array(_u16(rdata.size()))
	out.append_array(rdata)
	return out


## A query for every instance of the service.
static func query(service := SERVICE) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(_u16(0))        # id
	out.append_array(_u16(0))        # flags: standard query
	out.append_array(_u16(1))        # questions
	out.append_array(_u16(0))
	out.append_array(_u16(0))
	out.append_array(_u16(0))
	out.append_array(encode_name(service))
	out.append_array(_u16(TYPE_PTR))
	out.append_array(_u16(CLASS_IN))
	return out


## An answer (or unsolicited announcement) for one instance: PTR to the
## instance, SRV with the port and host, TXT with the table's name, and an
## A record per address. `instance` is the human name ("Chapel Ambush").
static func response(instance: String, port: int, host: String, addresses: PackedStringArray, txt: Dictionary = {}, ttl := TTL) -> PackedByteArray:
	var full := "%s.%s" % [instance.replace(".", "․"), SERVICE]
	var hostname := host if host.ends_with(".local") else host + ".local"
	var out := PackedByteArray()
	out.append_array(_u16(0))
	out.append_array(_u16(0x8400))   # response, authoritative
	out.append_array(_u16(0))
	var answers := 3 + addresses.size()
	out.append_array(_u16(answers))
	out.append_array(_u16(0))
	out.append_array(_u16(0))
	out.append_array(_record(SERVICE, TYPE_PTR, encode_name(full), ttl, false))
	var srv := _u16(0) + _u16(0) + _u16(port) + encode_name(hostname)
	out.append_array(_record(full, TYPE_SRV, srv, ttl))
	var txtdata := PackedByteArray()
	var pairs := {"name": instance, "v": "1"}
	for k in txt:
		pairs[str(k)] = str(txt[k])
	for k in pairs:
		var kv := ("%s=%s" % [k, pairs[k]]).to_utf8_buffer()
		txtdata.append(mini(kv.size(), 255))
		txtdata.append_array(kv.slice(0, 255))
	out.append_array(_record(full, TYPE_TXT, txtdata, ttl))
	for a in addresses:
		var parts := str(a).split(".")
		if parts.size() != 4:
			continue
		out.append_array(_record(hostname, TYPE_A, PackedByteArray([int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])]), ttl))
	return out


# ------------------------------------------------------------------ decoding --

## Read a name at `pos`, following compression pointers. Returns
## [name, position after the name as written].
static func read_name(data: PackedByteArray, pos: int) -> Array:
	var labels := PackedStringArray()
	var jumped := false
	var after := pos
	var hops := 0
	while pos < data.size():
		var n := data[pos]
		if n == 0:
			pos += 1
			break
		if n & 0xC0 == 0xC0:
			if pos + 1 >= data.size():
				break
			var ptr := ((n & 0x3F) << 8) | data[pos + 1]
			if not jumped:
				after = pos + 2
			jumped = true
			hops += 1
			if hops > 32:
				break
			pos = ptr
			continue
		pos += 1
		labels.append(data.slice(pos, pos + n).get_string_from_utf8())
		pos += n
	if not jumped:
		after = pos
	return [".".join(labels), after]


static func _r16(d: PackedByteArray, p: int) -> int:
	return (d[p] << 8) | d[p + 1] if p + 1 < d.size() else 0


## Parse a message into {"query": bool, "questions": [{name, type}],
## "records": [{name, type, ttl, ...}]}; {} if it is not DNS.
static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() < 12:
		return {}
	var flags := _r16(data, 2)
	var qd := _r16(data, 4)
	var an := _r16(data, 6) + _r16(data, 8) + _r16(data, 10)
	var pos := 12
	var out := {"query": (flags & 0x8000) == 0, "questions": [], "records": []}
	for i in qd:
		var nm := read_name(data, pos)
		pos = nm[1]
		if pos + 4 > data.size():
			return out
		out.questions.append({"name": str(nm[0]), "type": _r16(data, pos)})
		pos += 4
	for i in an:
		var nm := read_name(data, pos)
		pos = nm[1]
		if pos + 10 > data.size():
			return out
		var type := _r16(data, pos)
		var ttl := (_r16(data, pos + 4) << 16) | _r16(data, pos + 6)
		var rdlen := _r16(data, pos + 8)
		var rpos := pos + 10
		pos = rpos + rdlen
		if pos > data.size():
			return out
		var rec := {"name": str(nm[0]), "type": type, "ttl": ttl}
		match type:
			TYPE_PTR:
				rec["target"] = str(read_name(data, rpos)[0])
			TYPE_SRV:
				rec["port"] = _r16(data, rpos + 4)
				rec["target"] = str(read_name(data, rpos + 6)[0])
			TYPE_TXT:
				var txt := {}
				var p := rpos
				while p < rpos + rdlen:
					var n := data[p]
					var kv := data.slice(p + 1, p + 1 + n).get_string_from_utf8()
					var eq := kv.find("=")
					if eq > 0:
						txt[kv.substr(0, eq)] = kv.substr(eq + 1)
					p += 1 + n
				rec["txt"] = txt
			TYPE_A:
				if rdlen == 4:
					rec["address"] = "%d.%d.%d.%d" % [data[rpos], data[rpos + 1], data[rpos + 2], data[rpos + 3]]
		out.records.append(rec)
	return out


## The tables in a parsed response: [{name, port, host, addresses}].
static func tables_in(msg: Dictionary) -> Array:
	var out := []
	var by_instance := {}
	for r in msg.get("records", []):
		if r.type == TYPE_PTR and str(r.name) == SERVICE:
			by_instance[str(r.target)] = {"instance": str(r.target), "name": "", "port": 0, "host": "", "addresses": PackedStringArray()}
	if by_instance.is_empty():
		return out
	var a_records := {}
	for r in msg.records:
		if r.type == TYPE_A:
			if not a_records.has(str(r.name)):
				a_records[str(r.name)] = PackedStringArray()
			a_records[str(r.name)].append(str(r.address))
	for r in msg.records:
		var inst: Dictionary = by_instance.get(str(r.name), {})
		if inst.is_empty():
			continue
		if r.type == TYPE_SRV:
			inst.port = int(r.port)
			inst.host = str(r.target)
		elif r.type == TYPE_TXT:
			inst.name = str(r.txt.get("name", ""))
	for k in by_instance:
		var inst: Dictionary = by_instance[k]
		if inst.name == "":
			inst.name = str(k).trim_suffix("." + SERVICE).replace("․", ".")
		inst.addresses = a_records.get(inst.host, PackedStringArray())
		if inst.port > 0:
			out.append(inst)
	return out


# ------------------------------------------------------------------- sockets --

## A socket on the mDNS port, joined to the group on every IPv4 interface.
## Other responders (the OS's own) hold the port too; binding with address
## reuse usually works, and when it does not, `bound` says so and the
## caller can still send from an ephemeral socket.
static func open_socket() -> Dictionary:
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	var err := udp.bind(PORT, "0.0.0.0")
	var joined := 0
	if err == OK:
		for iface in Discovery.ipv4_interfaces():
			if udp.join_multicast_group(GROUP, iface) == OK:
				joined += 1
	return {"udp": udp, "bound": err == OK, "joined": joined, "error": err}


## The Table's side: answer queries for the service, and announce
## unasked every few seconds so browsers that missed a query catch up.
class Responder extends RefCounted:
	signal answered(ip: String)
	var instance := ""
	var port := 0
	var every := 3.0
	var _sock: Dictionary = {}
	var _send := PacketPeerUDP.new()
	var _since := 10.0
	var _ok := false

	func start(p_instance: String, p_port: int) -> void:
		instance = p_instance
		port = p_port
		_sock = Mdns.open_socket()
		_send.set_dest_address(Mdns.GROUP, Mdns.PORT)
		_ok = true

	func stop() -> void:
		if not _sock.is_empty():
			(_sock.udp as PacketPeerUDP).close()
		_send.close()
		_ok = false

	func listening() -> bool:
		return not _sock.is_empty() and bool(_sock.bound)

	func hostname() -> String:
		var h := OS.get_environment("HOSTNAME")
		if h == "":
			h = OS.get_environment("COMPUTERNAME")
		if h == "":
			h = "hexmap-table"
		return h.split(".")[0].to_lower().replace(" ", "-") + ".local"

	func message() -> PackedByteArray:
		return Mdns.response(instance, port, hostname(), App.local_ipv4())

	func poll(delta: float) -> void:
		if not _ok:
			return
		_since += delta
		if _since >= every:
			_since = 0.0
			_send.put_packet(message())
		if not listening():
			return
		var udp: PacketPeerUDP = _sock.udp
		while udp.get_available_packet_count() > 0:
			var pkt := udp.get_packet()
			var ip := udp.get_packet_ip()
			var from_port := udp.get_packet_port()
			var msg := Mdns.parse(pkt)
			if msg.is_empty() or not bool(msg.query):
				continue
			var asked := false
			for q in msg.questions:
				if int(q.type) == Mdns.TYPE_PTR and str(q.name) == Mdns.SERVICE:
					asked = true
			if not asked:
				continue
			# Multicast the answer (reflectors carry it; other browsers hear
			# it) and unicast it to the asker (legacy queriers on other ports).
			_send.put_packet(message())
			if from_port != Mdns.PORT and udp.set_dest_address(ip, from_port) == OK:
				udp.put_packet(message())   # from the port they asked, for firewalls
			answered.emit(ip)


## The Player's side: ask for the service, collect answers.
class Browser extends RefCounted:
	## A table was heard: (name, address, port).
	signal found(p_name: String, address: String, port: int)
	var every := 2.0
	var asked := 0
	var heard := 0
	var _sock: Dictionary = {}
	var _ask := PacketPeerUDP.new()
	var _since := 10.0
	var _ok := false

	func start() -> void:
		_sock = Mdns.open_socket()
		_ask.set_broadcast_enabled(true)
		_ask.set_dest_address(Mdns.GROUP, Mdns.PORT)
		_ok = true

	func stop() -> void:
		if not _sock.is_empty():
			(_sock.udp as PacketPeerUDP).close()
		_ask.close()
		_ok = false

	func listening() -> bool:
		return not _sock.is_empty() and bool(_sock.bound)

	func ask() -> void:
		_ask.put_packet(Mdns.query())
		asked += 1

	func poll(delta: float) -> void:
		if not _ok:
			return
		_since += delta
		if _since >= every:
			_since = 0.0
			ask()
		var socks := [_ask]
		if listening():
			socks.append(_sock.udp)
		for s in socks:
			var udp: PacketPeerUDP = s
			while udp.get_available_packet_count() > 0:
				var pkt := udp.get_packet()
				var from := udp.get_packet_ip()
				var msg := Mdns.parse(pkt)
				if msg.is_empty() or bool(msg.query):
					continue
				for t in Mdns.tables_in(msg):
					heard += 1
					# The address that reached us beats what the A record says:
					# it is the one this device can route to.
					var addr := from
					if addr == "" and not (t.addresses as PackedStringArray).is_empty():
						addr = str(t.addresses[0])
					found.emit(str(t.name), addr, int(t.port))
