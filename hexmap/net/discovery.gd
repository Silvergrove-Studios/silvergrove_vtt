class_name Discovery
extends RefCounted
## Finding tables on the local network without typing addresses: the Table
## multicasts a small announcement once a second (Announcer); the Player
## listens on the group and keeps a list of what it has heard lately
## (Browser). Plain UDP multicast; nothing leaves the LAN. Both need
## poll() called regularly.


class Announcer extends RefCounted:
	var name := ""
	var port := Protocol.DEFAULT_PORT
	var every := 1.0
	var _udp := PacketPeerUDP.new()
	var _since := 10.0
	var _ok := false

	func start(p_name: String, p_port: int) -> Error:
		name = p_name
		port = p_port
		var err := _udp.set_dest_address(Protocol.DISCOVERY_GROUP, Protocol.DISCOVERY_PORT)
		_ok = err == OK
		return err

	func stop() -> void:
		_udp.close()
		_ok = false

	func poll(delta: float) -> void:
		if not _ok:
			return
		_since += delta
		if _since < every:
			return
		_since = 0.0
		announce()

	func announce() -> void:
		var text := Protocol.encode(Protocol.announcement(name, port, OS.get_environment("HOSTNAME") if OS.get_environment("HOSTNAME") != "" else OS.get_environment("COMPUTERNAME")))
		_udp.put_packet(text.to_utf8_buffer())


class Browser extends RefCounted:
	## Something changed in `tables`.
	signal updated
	## key "host:port" -> {name, host, port, address, seen}
	var tables: Dictionary = {}
	## Forget a table not heard from for this long.
	var expire := 4.0
	var _udp := PacketPeerUDP.new()
	var _ok := false
	var _clock := 0.0

	func start() -> Error:
		# An IPv4 socket on purpose: "*" gives a dual-stack IPv6 socket, and
		# IPv4 multicast joins fail on those on macOS.
		var err := _udp.bind(Protocol.DISCOVERY_PORT, "0.0.0.0")
		if err != OK:
			return err
		# Join the group on every interface that has an IPv4 address, so a
		# laptop on wifi and a phone on the same wifi hear each other
		# whichever way the OS routes.
		var joined := false
		for iface in IP.get_local_interfaces():
			var v4 := false
			for a in iface.get("addresses", []):
				if str(a).is_valid_ip_address() and not str(a).contains(":"):
					v4 = true
			if v4 and _udp.join_multicast_group(Protocol.DISCOVERY_GROUP, str(iface.get("name", ""))) == OK:
				joined = true
		_ok = true
		return OK if joined else ERR_CANT_CONNECT

	func stop() -> void:
		_udp.close()
		_ok = false

	func poll(delta: float) -> void:
		if not _ok:
			return
		_clock += delta
		var changed := false
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet()
			var from := _udp.get_packet_ip()
			var a := Protocol.parse_announcement(pkt.get_string_from_utf8())
			if a.is_empty():
				continue
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
