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
## Stops the registration when this process is gone, however it went (a
## crash, a kill): an orphaned `dns-sd -R` would go on announcing a table
## that is not there (playtest 1's phones listed three).
var watchdog_pid := -1


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
	if pid > 0:
		watchdog_pid = watchdog(OS.get_process_id(), pid)
	return pid > 0


## A shell that waits for `parent` to end and then stops `child`. Its pid.
static func watchdog(parent: int, child: int) -> int:
	if OS.has_feature("windows"):
		return -1
	return OS.create_process("/bin/sh", ["-c", "while kill -0 %d 2>/dev/null; do sleep 1; done; kill %d 2>/dev/null" % [parent, child]])


func registered() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func unregister() -> void:
	if pid > 0:
		OS.kill(pid)
	if watchdog_pid > 0:
		OS.kill(watchdog_pid)
	pid = -1
	watchdog_pid = -1
