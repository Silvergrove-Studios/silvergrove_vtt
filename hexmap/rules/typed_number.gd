class_name TypedNumber
extends RefCounted
## Numbers a plugin computes are breakdowns, not scalars:
##   {"total": 13, "parts": [{"label": "base", "type": "base", "value": 10, "source": ""},
##                           {"label": "agility", "type": "ability", "value": 3}]}
## so a Player can see why, and so bonuses of the same type can be
## combined the way the ruleset says. A *stacking policy* maps a part
## type to how its parts combine:
##   "stack"    add them all (the default)
##   "best"     the largest bonus and the largest penalty of that type count
##   "override" the last part of that type wins
## Anything not a typed number (a plain float) is left alone by the
## helpers, so plugins may mix.


static func is_typed(v: Variant) -> bool:
	return v is Dictionary and v.has("parts") and v.parts is Array


## A typed number from parts, totalled under `policy`.
static func make(parts: Array, policy: Dictionary = {}) -> Dictionary:
	var out := {"total": 0.0, "parts": []}
	for p in parts:
		out.parts.append(_part(p))
	out.total = total(out.parts, policy)
	return out


## A plain number as a typed one with a single part.
static func of(value: float, label := "base", type := "base") -> Dictionary:
	return make([{"label": label, "type": type, "value": value}])


## `num` plus one part, re-totalled. `num` may be a plain number.
static func add(num: Variant, part: Dictionary, policy: Dictionary = {}) -> Dictionary:
	var out: Dictionary = JsonDoc.deep(num) if is_typed(num) else of(float(num) if num != null else 0.0)
	out.parts.append(_part(part))
	out.total = total(out.parts, policy)
	return out


## The total of parts under a policy.
static func total(parts: Array, policy: Dictionary = {}) -> float:
	var by_type := {}
	var order := []
	for p in parts:
		var t := str(p.get("type", "untyped"))
		if not by_type.has(t):
			by_type[t] = []
			order.append(t)
		by_type[t].append(float(p.get("value", 0)))
	var sum := 0.0
	for t in order:
		var vals: Array = by_type[t]
		match str(policy.get(t, policy.get("*", "stack"))):
			"best":
				var best_bonus := 0.0
				var worst_penalty := 0.0
				for v in vals:
					if v > best_bonus:
						best_bonus = v
					if v < worst_penalty:
						worst_penalty = v
				sum += best_bonus + worst_penalty
			"override":
				sum += vals[vals.size() - 1]
			_:
				for v in vals:
					sum += v
	return sum


## The number as a float whatever its form.
static func value(v: Variant) -> float:
	if is_typed(v):
		return float(v.total)
	return float(v) if (v is float or v is int) else 0.0


## Re-total every typed number in a derived block (after effects touched
## their parts).
static func retotal(derived: Dictionary, policy: Dictionary = {}) -> void:
	for k in derived:
		if is_typed(derived[k]):
			derived[k].total = total(derived[k].parts, policy)


static func _part(p: Dictionary) -> Dictionary:
	return {"label": str(p.get("label", "")), "type": str(p.get("type", "untyped")), "value": float(p.get("value", 0)), "source": str(p.get("source", ""))}
