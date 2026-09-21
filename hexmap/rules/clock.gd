class_name Clock
extends RefCounted
## The second clock: time other than turns. Sessions, scenes, days and the
## minute of the day, kept in the encounter (`clock`) and moved by events.
## Rulesets subscribe through hooks (`time_advanced`, `session_start`,
## `scene_start`) and effect durations of kind `time` end against it.

const MINUTES_PER_DAY := 24 * 60

var kernel: RulesKernel


func _init(p_kernel: RulesKernel) -> void:
	kernel = p_kernel


func now() -> Dictionary:
	return kernel.state.encounter.clock


## Absolute minutes since day 1, for durations.
func absolute_minutes() -> float:
	var c := now()
	return (float(c.get("day", 1)) - 1.0) * MINUTES_PER_DAY + float(c.get("minute", 0))


## Move time forward by `minutes`: the clock event, effects that ran out,
## and the `time_advanced` hook (handlers may add events).
func advance(minutes: float, label := "Time passes") -> String:
	if minutes <= 0.0:
		return "time only moves forward"
	var c := now()
	var total := float(c.get("minute", 0)) + minutes
	var day := int(c.get("day", 1)) + int(total / MINUTES_PER_DAY)
	var minute := fmod(total, float(MINUTES_PER_DAY))
	var before := absolute_minutes()
	return kernel.transaction(label, func() -> String:
		var why := kernel.commit([{"t": "clock.set", "changes": {"day": day, "minute": minute}}], label)
		if why == "":
			why = kernel.commit(kernel.expire({"kind": "time", "now": absolute_minutes()}), "Timed effects")
		if why == "":
			why = kernel.fire("time_advanced", {"from": before, "to": absolute_minutes(), "minutes": minutes, "day": day}, label)
		return why)


## A new session: the counter, session refills and expiries, the hook.
func next_session() -> String:
	var n := int(now().get("session", 1)) + 1
	return kernel.transaction("Session %d" % n, func() -> String:
		var why := kernel.commit([{"t": "clock.set", "changes": {"session": n}}], "Session %d" % n)
		if why == "":
			why = kernel.commit(kernel.expire({"kind": "session"}) + Resources.refill(kernel.state, "session") + Tracks.on_trigger(kernel.state, "session"), "Session reset")
		if why == "":
			why = kernel.fire("session_start", {"session": n}, "Session %d" % n)
		return why)


## A new scene of play (not a map scene): scene-long effects end.
func next_scene() -> String:
	var n := int(now().get("scene", 1)) + 1
	return kernel.transaction("Scene %d" % n, func() -> String:
		var why := kernel.commit([{"t": "clock.set", "changes": {"scene": n}}], "Scene %d" % n)
		if why == "":
			why = kernel.commit(kernel.expire({"kind": "scene"}), "Scene effects")
		if why == "":
			why = kernel.fire("scene_start", {"scene": n}, "Scene %d" % n)
		return why)
