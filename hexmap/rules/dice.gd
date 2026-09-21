class_name Dice
extends RefCounted
## The roll service. A roll is a *spec* — an expression like "2d6+3" or
## "4d6kh3", optionally with named groups ("hope": "1d12", "fear": "1d12")
## and typed modifier parts — and yields a *result* with every die face,
## kept/dropped/rerolled flags, per-group totals and the grand total, so
## a client can show the dice and a plugin can classify the outcome.
##
## Randomness is a deterministic stream: face(seed, index, sides) is a
## pure function, so a roll records where it drew from ({seed, index,
## count}) and a replay reads the same faces instead of rolling again.
## A roll may also be satisfied by faces typed in from real dice.
##
## Expression grammar (whitespace ignored):
##   expr   := term (('+' | '-') term)*
##   term   := INT 'd' INT suffix* | INT
##   suffix := 'kh' INT | 'kl' INT | 'dh' INT | 'dl' INT | 'r' INT | '!' | 'min' INT
##   kh/kl keep highest/lowest N; dh/dl drop; rN rerolls faces <= N once;
##   ! explodes on the maximum face (at most EXPLODE_LIMIT times);
##   minN raises faces below N to N.

const EXPLODE_LIMIT := 10
const MAX_DICE := 100
const MAX_SIDES := 1000


# --------------------------------------------------------------- stream --

## Logical right shift for 64-bit ints.
static func _ushr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)


## The face (1..sides) at position `index` of the stream seeded `seed`.
## splitmix64 over (seed, index): any position without stepping.
static func face(seed: int, index: int, sides: int) -> int:
	if sides <= 0:
		return 0
	var z := seed + index * -7046029254386353131
	z = (z ^ _ushr(z, 30)) * -4658895280553007687
	z = (z ^ _ushr(z, 27)) * -7723592293110705685
	z = z ^ _ushr(z, 31)
	return int(_ushr(z, 33) % sides) + 1


# --------------------------------------------------------------- parsing --

## Parse an expression into groups: [{count, sides, keep, drop, reroll,
## explode, min, sign}] and a constant. {} with `error` when malformed.
static func parse(expr: String) -> Dictionary:
	var src := expr.replace(" ", "").to_lower()
	var terms := []
	var constant := 0.0
	var i := 0
	var sign := 1
	if src == "":
		return {"error": "empty expression"}
	while i < src.length():
		var c := src[i]
		if c == "+" or c == "-":
			sign = 1 if c == "+" else -1
			i += 1
			if i >= src.length():
				return {"error": "dangling '%s'" % c}
			continue
		var j := i
		while j < src.length() and src[j].is_valid_int():
			j += 1
		if j == i:
			return {"error": "unexpected '%s' at %d" % [c, i]}
		var n := int(src.substr(i, j - i))
		i = j
		if i < src.length() and src[i] == "d":
			i += 1
			j = i
			while j < src.length() and src[j].is_valid_int():
				j += 1
			if j == i:
				return {"error": "missing sides after 'd'"}
			var sides := int(src.substr(i, j - i))
			i = j
			if n < 1 or n > MAX_DICE:
				return {"error": "dice count must be 1..%d" % MAX_DICE}
			if sides < 1 or sides > MAX_SIDES:
				return {"error": "sides must be 1..%d" % MAX_SIDES}
			var term := {"count": n, "sides": sides, "keep": 0, "keep_high": true, "drop": 0, "drop_high": false, "reroll": 0, "explode": false, "min": 0, "sign": sign}
			while i < src.length():
				if src.substr(i, 2) in ["kh", "kl", "dh", "dl"]:
					var op := src.substr(i, 2)
					i += 2
					j = i
					while j < src.length() and src[j].is_valid_int():
						j += 1
					if j == i:
						return {"error": "missing count after '%s'" % op}
					var k := int(src.substr(i, j - i))
					i = j
					if op[0] == "k":
						term.keep = k
						term.keep_high = op == "kh"
					else:
						term.drop = k
						term.drop_high = op == "dh"
				elif src.substr(i, 3) == "min":
					i += 3
					j = i
					while j < src.length() and src[j].is_valid_int():
						j += 1
					if j == i:
						return {"error": "missing value after 'min'"}
					term.min = int(src.substr(i, j - i))
					i = j
				elif src[i] == "r":
					i += 1
					j = i
					while j < src.length() and src[j].is_valid_int():
						j += 1
					if j == i:
						return {"error": "missing value after 'r'"}
					term.reroll = int(src.substr(i, j - i))
					i = j
				elif src[i] == "!":
					term.explode = true
					i += 1
				else:
					break
			terms.append(term)
		else:
			constant += sign * n
		sign = 1
	return {"terms": terms, "constant": constant}


# --------------------------------------------------------------- rolling --

## Roll a spec drawing from the stream at (seed, index). `spec` is a
## String expression or {expr, named: {name: expr}, parts: [typed parts],
## kind, visibility, faces: {group: [faces…]} for typed-in dice, meta}.
## Result: {ok, error, expr, kind, visibility, total, dice: [...],
## groups: {name: {expr, total, faces}}, parts, modifier, draw: {seed,
## index, count}} — `dice` entries are {group, sides, face, kept,
## rerolled, exploded}.
static func roll(spec: Variant, seed: int, index: int) -> Dictionary:
	var s: Dictionary = {"expr": spec} if spec is String else spec
	var groups := {}
	if str(s.get("expr", "")) != "":
		groups["main"] = str(s.expr)
	for name in s.get("named", {}):
		groups[str(name)] = str(s.named[name])
	if groups.is_empty():
		return {"ok": false, "error": "nothing to roll"}
	var typed: Dictionary = s.get("faces", {})
	var result := {"ok": true, "error": "", "kind": str(s.get("kind", "check")), "visibility": str(s.get("visibility", "all")),
		"total": 0.0, "dice": [], "groups": {}, "parts": [], "modifier": 0.0, "draw": {"seed": seed, "index": index, "count": 0}, "meta": JsonDoc.deep(s.get("meta", {}))}
	var cursor := index
	var names := groups.keys()
	names.sort()
	if groups.has("main"):
		names.erase("main")
		names.insert(0, "main")
	for name in names:
		var parsed := parse(groups[name])
		if parsed.has("error"):
			return {"ok": false, "error": "%s: %s" % [name, parsed.error]}
		var given: Array = typed.get(name, [])
		var gi := 0
		var gtotal: float = parsed.constant
		var gfaces := []
		for term in parsed.terms:
			var faces := []
			for k in term.count:
				var f: int
				if gi < given.size():
					f = int(given[gi])
					gi += 1
				else:
					f = face(seed, cursor, term.sides)
					cursor += 1
				var die := {"group": name, "sides": term.sides, "face": f, "kept": true, "rerolled": false, "exploded": false}
				if term.reroll > 0 and f <= term.reroll:
					die.rerolled = true
					die.kept = false
					result.dice.append(die)
					f = face(seed, cursor, term.sides) if gi >= given.size() else int(given[gi])
					if gi < given.size():
						gi += 1
					else:
						cursor += 1
					die = {"group": name, "sides": term.sides, "face": f, "kept": true, "rerolled": false, "exploded": false}
				if term.min > 0 and f < term.min:
					die.raised_from = f
					die.face = term.min
				faces.append(die)
				if term.explode:
					var extra := 0
					var last := die
					while int(last.face) == term.sides and extra < EXPLODE_LIMIT:
						last.exploded = true
						var ef := face(seed, cursor, term.sides) if gi >= given.size() else int(given[gi])
						if gi < given.size():
							gi += 1
						else:
							cursor += 1
						last = {"group": name, "sides": term.sides, "face": ef, "kept": true, "rerolled": false, "exploded": false}
						faces.append(last)
						extra += 1
			# keep / drop
			if term.keep > 0 or term.drop > 0:
				var order := faces.duplicate()
				order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.face) > int(b.face))
				if term.keep > 0:
					if not term.keep_high:
						order.reverse()
					for k in range(term.keep, order.size()):
						order[k].kept = false
				else:
					if not term.drop_high:
						order.reverse()
					for k in mini(term.drop, order.size()):
						order[k].kept = false
			for d in faces:
				result.dice.append(d)
				gfaces.append(int(d.face))
				if d.kept:
					gtotal += term.sign * int(d.face)
		result.groups[name] = {"expr": groups[name], "total": gtotal, "faces": gfaces}
		result.total += gtotal
	for p in s.get("parts", []):
		var part := {"label": str(p.get("label", "")), "type": str(p.get("type", "untyped")), "value": float(p.get("value", 0)), "source": str(p.get("source", ""))}
		result.parts.append(part)
	result.modifier = TypedNumber.total(result.parts, s.get("policy", {}))
	result.total += result.modifier
	result.draw.count = cursor - index
	return result


## The faces of a result as {group: [faces…]}: what a typed-in spec
## carries, and what a Player client renders.
static func faces_of(result: Dictionary) -> Dictionary:
	var out := {}
	for d in result.get("dice", []):
		if not out.has(d.group):
			out[d.group] = []
		out[d.group].append(int(d.face))
	return out


## A roll that gathers contributions (help dice, a joined action) before
## it resolves. Contributions are named groups from other participants.
class PendingRoll:
	var spec: Dictionary
	var contributions: Array = []   # [{by, name, expr}]
	var resolved: Dictionary = {}

	func _init(p_spec: Variant) -> void:
		spec = {"expr": p_spec} if p_spec is String else JsonDoc.deep(p_spec)
		if not spec.has("named"):
			spec.named = {}

	func contribute(by: String, name: String, expr: String) -> String:
		if resolved.has("ok"):
			return "already resolved"
		var parsed := Dice.parse(expr)
		if parsed.has("error"):
			return parsed.error
		for c in contributions:
			if c.name == name:
				return "a '%s' contribution exists" % name
		contributions.append({"by": by, "name": name, "expr": expr})
		spec.named[name] = expr
		return ""

	func resolve(seed: int, index: int) -> Dictionary:
		resolved = Dice.roll(spec, seed, index)
		resolved.contributions = JsonDoc.deep(contributions)
		return resolved
