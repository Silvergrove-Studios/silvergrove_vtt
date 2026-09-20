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
	## Bound on the discovery port to hear queries and answer them: one on
	## every address (0.0.0.0), for broadcast and multicast, and one per
	## IPv4 address for unicast, so a reply leaves from the address the
	## query was sent to — a multi-homed host would otherwise answer from
	## whichever address its kernel prefers, which the asker may not reach.
	var _listen := PacketPeerUDP.new()
	var _per_address: Array = []
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
			for addr in App.local_ipv4():
				var s := PacketPeerUDP.new()
				if s.bind(Protocol.DISCOVERY_PORT, addr) == OK:
					_per_address.append(s)
				else:
					s.close()
		mdns.start(p_name, p_port)
		mdns.answered.connect(func(ip: String) -> void: answered.emit(ip))
		_ok = true
		return OK

	func stop() -> void:
		_shout.close()
		_listen.close()
		for s in _per_address:
			(s as PacketPeerUDP).close()
		_per_address.clear()
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
		return Protocol.encode(Protocol.announcement(name, port, host, App.local_ipv4()))

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

	## Reply to anyone asking, straight to where they asked from, and from
	## the socket the query arrived on: a firewall between subnets only lets
	## back what matches the query's address and port, and the per-address
	## socket answers with the address the asker used.
	func answer_queries() -> int:
		if not _listening:
			return 0
		var n := 0
		for sock in [_listen] + _per_address:
			var udp: PacketPeerUDP = sock
			while udp.get_available_packet_count() > 0:
				var pkt := udp.get_packet()
				if not Discovery.is_query(pkt.get_string_from_utf8()):
					continue
				var ip := udp.get_packet_ip()
				if udp.set_dest_address(ip, udp.get_packet_port()) == OK:
					udp.put_packet(announcement_text().to_utf8_buffer())
					n += 1
					answered.emit(ip)
		return n


class Browser extends RefCounted:
	## Something changed in `tables`.
	signal updated
	## key "name|port" -> {name, host, port, address, addresses, seen, via}.
	## `address` is the best guess; `addresses` every one heard, best first.
	var tables: Dictionary = {}
	## Addresses that answered a direct query: proven reachable from here.
	var confirmed: Dictionary = {}
	## The last thing heard, for a diagnostics line.
	var last_heard := ""
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
		mdns.found.connect(func(p_name: String, address: String, port: int, addresses: PackedStringArray) -> void:
			heard_answers += 1
			# Every address the record names is worth a direct query: the one
			# that answers is the one this device can reach.
			for a in addresses:
				remember(str(a))
			if heard({"name": p_name, "port": port, "addresses": Array(addresses)}, address, "mdns"):
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
		return "asked %d, heard %d, mDNS %s%s" % [asked, heard_answers, "on" if mdns.listening() else "query only", ("; last: " + last_heard) if last_heard != "" else ""]

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
				if sock == _ask and known.has(from):
					confirmed[from] = true   # it answered a direct query
				changed = heard(a, from, "direct" if sock == _ask else "announce") or changed
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

	## Record an announcement from `from`, heard `via` "direct" (an answer
	## to our unicast query), "announce" (broadcast/multicast) or "mdns".
	## Returns whether the list changed. A table with several addresses
	## answers from whichever its kernel picks, so the address to connect
	## to is chosen by evidence: one that answered a direct query, then one
	## we already knew, then the packet's source, then the rest.
	func heard(a: Dictionary, from: String, via := "announce") -> bool:
		var all: Array = []
		for x in a.get("addresses", []):
			if str(x) != "" and not all.has(str(x)):
				all.append(str(x))
		if from != "" and not all.has(from):
			all.append(from)
		var key := "%s|%d" % [str(a.name), int(a.port)]
		var prev: Dictionary = tables.get(key, {})
		for x in prev.get("addresses", []):
			if not all.has(str(x)):
				all.append(str(x))
		var previous := str(prev.get("address", ""))
		all.sort_custom(func(x: String, y: String) -> bool: return _rank(x, from, previous) < _rank(y, from, previous))
		var entry := {"name": str(a.name), "host": str(a.get("host", "")), "port": int(a.port), "address": all[0] if not all.is_empty() else from,
			"addresses": all, "seen": _clock, "via": via}
		last_heard = "%s via %s from %s → %s" % [str(a.name), via, from, entry.address]
		var fresh := prev.is_empty() or str(prev.address) != str(entry.address)
		tables[key] = entry
		return fresh

	## Lower is better; the address chosen last time stays unless better
	## evidence arrives, so a list entry does not flap between sources.
	func _rank(x: String, from: String, previous: String) -> int:
		if confirmed.has(x):
			return 0
		if known.has(x):
			return 1
		if x == previous:
			return 2
		if x == from:
			return 3
		return 4

	func list() -> Array:
		var out := tables.values()
		out.sort_custom(func(x, y) -> bool: return str(x.name) < str(y.name))
		return out
