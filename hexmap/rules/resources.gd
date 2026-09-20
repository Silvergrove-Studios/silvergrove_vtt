class_name Resources
extends RefCounted
## Pools and slot tracks on any entity, per plugin, by name:
##   pool   {"kind": "pool", "current": 3, "max": 5, "recharge": "rest"}
##   track  {"kind": "track", "max": 6, "marked": 2, "extra": 1, "crossed": [5]}
## A pool is a number with a ceiling and a refill rule; a track is a row
## of boxes that get marked, cleared, permanently added or crossed out.
## Recharge kinds are whatever the plugin says ("rest", "long_rest",
## "session", "day", "turn_start", "manual"…); refill() answers for one
## of them at a time.
##
## Everything here returns `resource.set` events (a full record, so the
## inverse is the previous record); nothing mutates state.

const POOL := "pool"
const TRACK := "track"


static func pool(current: float, max_value: float, recharge := "manual") -> Dictionary:
	return {"kind": POOL, "current": current, "max": max_value, "recharge": recharge}


static func track(max_slots: int, marked := 0, extra := 0, crossed: Array = [], recharge := "manual") -> Dictionary:
	return {"kind": TRACK, "max": max_slots, "marked": marked, "extra": extra, "crossed": crossed.duplicate(), "recharge": recharge}


static func get_record(state: EncounterState, ref: String, plugin: String, p_name: String) -> Dictionary:
	return state.encounter.resources.get(ref, {}).get(plugin, {}).get(p_name, {})


## All of an entity's resources for a plugin: name -> record.
static func of(state: EncounterState, ref: String, plugin: String) -> Dictionary:
	return state.encounter.resources.get(ref, {}).get(plugin, {})


static func set_event(ref: String, plugin: String, p_name: String, record: Variant) -> Dictionary:
	return {"t": "resource.set", "ref": ref, "plugin": plugin, "name": p_name, "record": record}


## Usable slots of a track: max plus permanent extras minus crossed-out.
static func track_capacity(rec: Dictionary) -> int:
	return int(rec.get("max", 0)) + int(rec.get("extra", 0)) - (rec.get("crossed", []) as Array).size()


## Spend from a pool. {} when there is not enough.
static func spend(state: EncounterState, ref: String, plugin: String, p_name: String, amount: float) -> Dictionary:
	var rec := get_record(state, ref, plugin, p_name)
	if rec.get("kind") != POOL or float(rec.current) < amount:
		return {}
	var next: Dictionary = JsonDoc.deep(rec)
	next.current = float(rec.current) - amount
	return set_event(ref, plugin, p_name, next)


## Add to a pool, capped at max (or beyond it with `overflow`).
static func gain(state: EncounterState, ref: String, plugin: String, p_name: String, amount: float, overflow := false) -> Dictionary:
	var rec := get_record(state, ref, plugin, p_name)
	if rec.get("kind") != POOL:
		return {}
	var next: Dictionary = JsonDoc.deep(rec)
	next.current = float(rec.current) + amount if overflow else minf(float(rec.max), float(rec.current) + amount)
	return set_event(ref, plugin, p_name, next)


## Mark `n` boxes of a track. {} when they would not fit.
static func mark(state: EncounterState, ref: String, plugin: String, p_name: String, n := 1) -> Dictionary:
	var rec := get_record(state, ref, plugin, p_name)
	if rec.get("kind") != TRACK:
		return {}
	var cap := track_capacity(rec)
	if int(rec.marked) + n > cap:
		return {}
	var next: Dictionary = JsonDoc.deep(rec)
	next.marked = int(rec.marked) + n
	return set_event(ref, plugin, p_name, next)


## Clear `n` marked boxes (all with n < 0).
static func clear(state: EncounterState, ref: String, plugin: String, p_name: String, n := 1) -> Dictionary:
	var rec := get_record(state, ref, plugin, p_name)
	if rec.get("kind") != TRACK:
		return {}
	var next: Dictionary = JsonDoc.deep(rec)
	next.marked = 0 if n < 0 else maxi(0, int(rec.marked) - n)
	return set_event(ref, plugin, p_name, next)


## Cross out (permanently lose) one box by index, or uncross it.
static func cross(state: EncounterState, ref: String, plugin: String, p_name: String, slot: int, crossed := true) -> Dictionary:
	var rec := get_record(state, ref, plugin, p_name)
	if rec.get("kind") != TRACK:
		return {}
	var next: Dictionary = JsonDoc.deep(rec)
	var list: Array = next.get("crossed", [])
	if crossed and not list.has(slot):
		list.append(slot)
		list.sort()
	elif not crossed:
		list.erase(slot)
	next.crossed = list
	next.marked = mini(int(next.marked), track_capacity(next))
	return set_event(ref, plugin, p_name, next)


## Events refilling every pool (current = max) and clearing every track
## whose recharge is `kind`, for one plugin or all.
static func refill(state: EncounterState, kind: String, plugin := "") -> Array:
	var out := []
	var refs := state.encounter.resources.keys()
	refs.sort()
	for ref in refs:
		var plugins: Dictionary = state.encounter.resources[ref]
		var pids := plugins.keys()
		pids.sort()
		for pid in pids:
			if plugin != "" and str(pid) != plugin:
				continue
			var names: Array = plugins[pid].keys()
			names.sort()
			for n in names:
				var rec: Dictionary = plugins[pid][n]
				if str(rec.get("recharge", "manual")) != kind:
					continue
				var next: Dictionary = JsonDoc.deep(rec)
				if rec.get("kind") == POOL:
					if float(rec.current) == float(rec.max):
						continue
					next.current = float(rec.max)
				elif rec.get("kind") == TRACK:
					if int(rec.marked) == 0:
						continue
					next.marked = 0
				else:
					continue
				out.append(set_event(str(ref), str(pid), str(n), next))
	return out
