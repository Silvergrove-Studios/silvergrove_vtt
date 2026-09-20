class_name Bonjour
extends RefCounted
## Register the table as a Bonjour service with the operating system's own
## mDNS responder, which owns port 5353 and answers queries for us —
## reflected across subnets by routers that do that, and unicast back to a
## phone that could not bind the port itself. macOS: `dns-sd -R`; Linux:
## `avahi-publish`; Windows has no command for it (Mdns.Responder in
## hexmap/net is used there when it can bind). Desktop-only, by design.

var pid := -1
var tool := ""


func available() -> bool:
	return _command() != ""


func _command() -> String:
	if OS.has_feature("macos"):
		return "dns-sd"
	if OS.has_feature("linuxbsd"):
		return "avahi-publish"
	return ""


## Start the registration; it lives as long as the process does.
func register(p_name: String, port: int) -> bool:
	unregister()
	tool = _command()
	if tool == "":
		return false
	var args: PackedStringArray
	match tool:
		"dns-sd":
			args = PackedStringArray(["-R", p_name, Mdns.SERVICE.trim_suffix(".local"), "local", str(port), "name=" + p_name, "v=1"])
		"avahi-publish":
			args = PackedStringArray(["-s", p_name, Mdns.SERVICE.trim_suffix(".local"), str(port), "name=" + p_name, "v=1"])
	pid = OS.create_process(tool, args)
	return pid > 0


func registered() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func unregister() -> void:
	if pid > 0:
		OS.kill(pid)
	pid = -1
