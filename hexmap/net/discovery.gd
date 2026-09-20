class_name Discovery
extends RefCounted
## Finding tables on the local network without typing addresses. Two ways,
## because phones are picky: the Table multicasts and broadcasts an
## announcement once a second (which a laptop hears, and a phone only
## sometimes — Android drops multicast unless an app holds a lock Godot
## cannot take), and the Player also *asks* — a query sent to the same
## group and broadcast addresses — which the Table answers by unicast
## straight back to the asker, and nothing filters that. Plain UDP;
## nothing leaves the LAN. Both sides need poll() called regularly.


## The query a browser sends; a table replies with its announcement.
static func query() -> Dictionary:
	return {"hexmap": Protocol.VERSION, "q": 1}


static func is_query(text: String) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return false
	var d: Dictionary = json.data
	return int(d.get("hexmap", 0)) == Protocol.VERSION and d.has("q")


## Where to shout: the multicast group, the limited broadcast, and the
## directed broadcast of every IPv4 network this machine is on (assumed
## /24, which home and small-office wifi almost always is).
static func shout_targets() -> Array:
	# 127.0.0.1 too: Linux and Android do not loop a broadcast back to the
	# sender, and a Table and a Player on one device should still meet.
	var out := [Protocol.DISCOVERY_GROUP, "255.255.255.255", "127.0.0.1"]
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.is_valid_ip_address() and not s.contains(":") and not s.begins_with("127."):
			var parts := s.split(".")
			var directed := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not out.has(directed):
				out.append(directed)
	return out


## Names of the interfaces that have an IPv4 address: the only ones an
## IPv4 multicast group can be joined on (a VPN tunnel or awdl cannot).
static func ipv4_interfaces() -> PackedStringArray:
	var out := PackedStringArray()
	for iface in IP.get_local_interfaces():
		for a in iface.get("addresses", []):
			if str(a).is_valid_ip_address() and not str(a).contains(":"):
				out.append(str(iface.get("name", "")))
				break
	return out


## Send one text to every shout target through `udp`.
static func shout(udp: PacketPeerUDP, text: String) -> void:
	var bytes := text.to_utf8_buffer()
	for target in shout_targets():
		if udp.set_dest_address(target, Protocol.DISCOVERY_PORT) == OK:
			udp.put_packet(bytes)


class Announcer extends RefCounted:
	## A query (ours or mDNS) was answered, with the asker's address.
	signal answered(ip: String)
	var name := ""
	var port := Protocol.DEFAULT_PORT
	var every := 1.0
	## Also a Bonjour service, so routers that reflect mDNS between their
	## subnets carry us the way they carry printers and speakers.
	var mdns := Mdns.Responder.new()
	var _shout := PacketPeerUDP.new()
	## Bound on the discovery port to hear queries and answer them.
	var _listen := PacketPeerUDP.new()
	var _since := 10.0
	var _ok := false
	var _listening := false
	var listen_error: Error = OK

	func start(p_name: String, p_port: int) -> Error:
		name = p_name
		port = p_port
		_shout.set_broadcast_enabled(true)
		_listen.set_broadcast_enabled(true)
		listen_error = _listen.bind(Protocol.DISCOVERY_PORT, "0.0.0.0")
		_listening = listen_error == OK
		if _listening:
			for iface in Discovery.ipv4_interfaces():
				_listen.join_multicast_group(Protocol.DISCOVERY_GROUP, iface)
		mdns.start(p_name, p_port)
		mdns.answered.connect(func(ip: String) -> void: answered.emit(ip))
		_ok = true
		return OK

	func stop() -> void:
		_shout.close()
		_listen.close()
		mdns.stop()
		_ok = false
		_listening = false

	## What is working, for the status bar.
	func summary() -> String:
		return "mDNS %s, direct queries %s" % ["on" if mdns.listening() else "announce only", "on" if _listening else "off"]

	func announcement_text() -> String:
		var host := OS.get_environment("HOSTNAME")
		if host == "":
			host = OS.get_environment("COMPUTERNAME")
		return Protocol.encode(Protocol.announcement(name, port, host))

	func poll(delta: float) -> void:
		if not _ok:
			return
		_since += delta
		if _since >= every:
			_since = 0.0
			announce()
		answer_queries()
		mdns.poll(delta)

	func announce() -> void:
		Discovery.shout(_shout, announcement_text())

	## Reply to anyone asking, straight to where they asked from.
	func answer_queries() -> int:
		if not _listening:
			return 0
		var n := 0
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			if not Discovery.is_query(pkt.get_string_from_utf8()):
				continue
			var reply := PacketPeerUDP.new()
			var ip := _listen.get_packet_ip()
			if reply.set_dest_address(ip, _listen.get_packet_port()) == OK:
				reply.put_packet(announcement_text().to_utf8_buffer())
				n += 1
				answered.emit(ip)
			reply.close()
		return n


class Browser extends RefCounted:
	## Something changed in `tables`.
	signal updated
	## key "host:port" -> {name, host, port, address, seen}
	var tables: Dictionary = {}
	## Forget a table not heard from for this long.
	var expire := 6.0
	## How often to ask.
	var every := 1.0
	## Addresses to ask directly (by unicast) as well as shouting: tables
	## joined before, and anything the player types. Reaches a table on
	## another subnet when nothing multicast does.
	var known: PackedStringArray = []
	## Bonjour browsing, for routers that reflect mDNS between subnets.
	var mdns := Mdns.Browser.new()
	## Counters for a diagnostics line.
	var asked := 0
	var heard_answers := 0
	## Bound on the discovery port for announcements (may fail when a Table
	## on this same machine holds it; querying still works).
	var _udp := PacketPeerUDP.new()
	## An ephemeral socket to ask from; replies come back to it unicast.
	var _ask := PacketPeerUDP.new()
	var _ok := false
	var _passive := false
	var _clock := 0.0
	var _since := 10.0

	func start() -> Error:
		_ask.set_broadcast_enabled(true)
		# An IPv4 socket on purpose: "*" gives a dual-stack IPv6 socket, and
		# IPv4 multicast joins fail on those on macOS.
		_udp.set_broadcast_enabled(true)
		_passive = _udp.bind(Protocol.DISCOVERY_PORT, "0.0.0.0") == OK
		if _passive:
			for iface in Discovery.ipv4_interfaces():
				_udp.join_multicast_group(Protocol.DISCOVERY_GROUP, iface)
		mdns.start()
		mdns.found.connect(func(p_name: String, address: String, port: int) -> void:
			heard_answers += 1
			if heard({"name": p_name, "port": port}, address):
				updated.emit())
		_ok = true
		return OK

	func stop() -> void:
		_udp.close()
		_ask.close()
		mdns.stop()
		_ok = false
		_passive = false

	func summary() -> String:
		return "asked %d, heard %d, mDNS %s" % [asked, heard_answers, "on" if mdns.listening() else "query only"]

	func poll(delta: float) -> void:
		if not _ok:
			return
		_clock += delta
		_since += delta
		if _since >= every:
			_since = 0.0
			ask()
		mdns.poll(delta)
		var changed := false
		for sock in [_udp, _ask]:
			while (sock as PacketPeerUDP).get_available_packet_count() > 0:
				var pkt := (sock as PacketPeerUDP).get_packet()
				var from := (sock as PacketPeerUDP).get_packet_ip()
				var a := Protocol.parse_announcement(pkt.get_string_from_utf8())
				if a.is_empty():
					continue
				heard_answers += 1
				changed = heard(a, from) or changed
		var gone := []
		for k in tables:
			if _clock - float(tables[k].seen) > expire:
				gone.append(k)
		for k in gone:
			tables.erase(k)
			changed = true
		if changed:
			updated.emit()

	## Ask every table on the network to answer us directly, and the known
	## addresses one by one.
	func ask() -> void:
		var text := Protocol.encode(Discovery.query())
		Discovery.shout(_ask, text)
		for addr in known:
			probe(str(addr), text)
		asked += 1

	## Ask one address directly (unicast).
	func probe(address: String, text := "") -> void:
		if address == "":
			return
		if text == "":
			text = Protocol.encode(Discovery.query())
		if _ask.set_dest_address(address, Protocol.DISCOVERY_PORT) == OK:
			_ask.put_packet(text.to_utf8_buffer())

	func remember(address: String) -> void:
		if address != "" and not known.has(address):
			known.append(address)

	## Record an announcement from `from`. Returns whether the list changed.
	func heard(a: Dictionary, from: String) -> bool:
		var key := "%s:%d" % [from, int(a.port)]
		var fresh := not tables.has(key) or str(tables[key].name) != str(a.name)
		tables[key] = {"name": str(a.name), "host": str(a.get("host", "")), "address": from, "port": int(a.port), "seen": _clock}
		return fresh

	func list() -> Array:
		var out := tables.values()
		out.sort_custom(func(x, y) -> bool: return str(x.name) < str(y.name))
		return out
