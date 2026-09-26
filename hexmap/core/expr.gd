class_name Expr
extends RefCounted
## A small, total, side-effect-free expression language for the numbers
## and conditions plugins put in data instead of code: an effect's value
## (`@actor.level * 2 + 1`), a predicate (`@target.size == "large" and
## not @self.prone`), a label (`"Level " .. @actor.level`). It always
## terminates: there are no loops, no recursion, no assignment, no calls
## into the host — only the functions below. Parse once, evaluate many
## times against a context Dictionary.
##
## Syntax
##   literals     12  2.5  "text"  'text'  true  false  null  [1, "a"]
##   paths        @actor.level  @tags[0]  @stats["dex"]  @pools["hp_" .. @id].max   (null when absent)
##   arithmetic   + - * / % ^   unary -   (+ also joins two lists)
##   strings      ..  (concatenate; numbers are formatted)
##   compare      == != < <= > >=      (== is JSON equality)
##   logic        and or not           (short-circuit; null/false are falsy)
##   membership   x in list            (also substring for strings)
##   default      a ?? b               (b when a is null)
##   choice       cond ? a : b
##   functions    min max abs floor ceil round clamp len num str lower upper title
##                sum has contains starts ends join sign
##
## Errors: parse errors leave `error` set and eval() returns null;
## evaluation problems (a function on the wrong type) also yield null and
## set `error`, never an exception. deps() lists the paths an expression
## reads, for dependency tracking.

const MAX_DEPTH := 48

var error := ""
var text := ""
var _ast: Variant = null
var _deps: Array = []

static var _cache: Dictionary = {}


static func parse(source: String) -> Expr:
	var e := Expr.new()
	e.text = source
	var p := _Parser.new(source)
	e._ast = p.parse()
	e.error = p.error
	if e.error != "":
		e._ast = null
	e._deps = p.paths
	return e


## Parse (cached by text) and evaluate in one call.
static func evaluate(source: String, ctx: Dictionary = {}) -> Variant:
	var e: Expr = _cache.get(source)
	if e == null:
		e = parse(source)
		if _cache.size() > 4096:
			_cache.clear()
		_cache[source] = e
	return e.eval(ctx)


## Same, but "" on error rather than null, for labels.
static func evaluate_text(source: String, ctx: Dictionary = {}) -> String:
	var v: Variant = evaluate(source, ctx)
	return "" if v == null else _to_text(v)


func is_valid() -> bool:
	return _ast != null


## The context paths this expression reads, as "actor.level" strings.
func deps() -> Array:
	return _deps.duplicate()


func eval(ctx: Dictionary = {}) -> Variant:
	if _ast == null:
		return null
	error = ""
	return _eval(_ast, ctx)


## Truthiness as the language sees it.
static func truthy(v: Variant) -> bool:
	# a String compared to a bool is a GDScript error, not false
	return not (v == null or (v is bool and not v))


# ------------------------------------------------------------------- eval --

func _eval(n: Variant, ctx: Dictionary) -> Variant:
	if not (n is Array):
		return n   # a literal
	var op: String = n[0]
	match op:
		"lit":
			return n[1]
		"path":
			return _lookup(ctx, n[1])
		"index":
			var base: Variant = _eval(n[1], ctx)
			var key: Variant = _eval(n[2], ctx)
			return _index(base, key)
		"neg":
			var v: Variant = _eval(n[1], ctx)
			return -float(v) if _is_num(v) else _fail("unary - on %s" % _type(v))
		"not":
			return not truthy(_eval(n[1], ctx))
		"and":
			var a: Variant = _eval(n[1], ctx)
			return a if not truthy(a) else _eval(n[2], ctx)
		"or":
			var a: Variant = _eval(n[1], ctx)
			return a if truthy(a) else _eval(n[2], ctx)
		"??":
			var a: Variant = _eval(n[1], ctx)
			return a if a != null else _eval(n[2], ctx)
		"?:":
			return _eval(n[2], ctx) if truthy(_eval(n[1], ctx)) else _eval(n[3], ctx)
		"call":
			var args := []
			for a in n[2]:
				args.append(_eval(a, ctx))
			return _call(n[1], args)
		_:
			var a: Variant = _eval(n[1], ctx)
			var b: Variant = _eval(n[2], ctx)
			return _binary(op, a, b)


func _binary(op: String, a: Variant, b: Variant) -> Variant:
	match op:
		"==": return _equal(a, b)
		"!=": return not _equal(a, b)
		"..": return _to_text(a) + _to_text(b)
		"in":
			if b is Array:
				for item in b:
					if _equal(item, a):
						return true
				return false
			if b is Dictionary:
				return b.has(a)
			if b is String and a is String:
				return b.contains(a)
			return _fail("'in' needs a list, object or string on the right")
	# two lists joined: a class's skills and a background's, say
	if op == "+" and a is Array and b is Array:
		return (a as Array) + (b as Array)
	if not (_is_num(a) and _is_num(b)):
		if op in ["<", "<=", ">", ">="] and a is String and b is String:
			match op:
				"<": return a < b
				"<=": return a <= b
				">": return a > b
				">=": return a >= b
		return _fail("%s on %s and %s" % [op, _type(a), _type(b)])
	var x := float(a)
	var y := float(b)
	match op:
		"+": return x + y
		"-": return x - y
		"*": return x * y
		"/": return _fail("division by zero") if y == 0.0 else x / y
		"%": return _fail("modulo by zero") if y == 0.0 else fmod(x, y)
		"^": return pow(x, y)
		"<": return x < y
		"<=": return x <= y
		">": return x > y
		">=": return x >= y
	return _fail("unknown operator " + op)


func _call(fn: String, a: Array) -> Variant:
	var n := a.size()
	match fn:
		"__list":
			return a
		"min", "max":
			var vals: Array = a[0] if n == 1 and a[0] is Array else a
			if vals.is_empty():
				return null
			var best: Variant = null
			for v in vals:
				if not _is_num(v):
					return _fail("%s of a non-number" % fn)
				if best == null or (float(v) < float(best) if fn == "min" else float(v) > float(best)):
					best = v
			return float(best)
		"abs": return absf(float(a[0])) if n == 1 and _is_num(a[0]) else _fail("abs(number)")
		"floor": return floorf(float(a[0])) if n == 1 and _is_num(a[0]) else _fail("floor(number)")
		"ceil": return ceilf(float(a[0])) if n == 1 and _is_num(a[0]) else _fail("ceil(number)")
		"round": return roundf(float(a[0])) if n == 1 and _is_num(a[0]) else _fail("round(number)")
		"sign": return signf(float(a[0])) if n == 1 and _is_num(a[0]) else _fail("sign(number)")
		"clamp":
			if n == 3 and _is_num(a[0]) and _is_num(a[1]) and _is_num(a[2]):
				return clampf(float(a[0]), float(a[1]), float(a[2]))
			return _fail("clamp(number, lo, hi)")
		"len":
			if n == 1 and (a[0] is Array or a[0] is Dictionary or a[0] is String):
				return float(a[0].length() if a[0] is String else a[0].size())
			return _fail("len(list|object|string)")
		"num":
			if n == 1:
				if _is_num(a[0]):
					return float(a[0])
				if a[0] is String and (a[0] as String).strip_edges().is_valid_float():
					return (a[0] as String).to_float()
				if a[0] is bool:
					return 1.0 if a[0] else 0.0
			return null
		"str": return _to_text(a[0]) if n == 1 else _fail("str(value)")
		"lower": return (a[0] as String).to_lower() if n == 1 and a[0] is String else _fail("lower(string)")
		"upper": return (a[0] as String).to_upper() if n == 1 and a[0] is String else _fail("upper(string)")
		"title": return (a[0] as String).capitalize() if n == 1 and a[0] is String else _fail("title(string)")
		"sum":
			if n == 1 and a[0] is Array:
				var s := 0.0
				for v in a[0]:
					if not _is_num(v):
						return _fail("sum of a non-number")
					s += float(v)
				return s
			return _fail("sum(list)")
		"has":
			if n == 2 and a[0] is Dictionary:
				return (a[0] as Dictionary).has(a[1])
			if n == 2 and a[0] is Array:
				return _binary("in", a[1], a[0])
			return _fail("has(object|list, key)")
		"contains": return (a[0] as String).contains(str(a[1])) if n == 2 and a[0] is String else _fail("contains(string, part)")
		"starts": return (a[0] as String).begins_with(str(a[1])) if n == 2 and a[0] is String else _fail("starts(string, part)")
		"ends": return (a[0] as String).ends_with(str(a[1])) if n == 2 and a[0] is String else _fail("ends(string, part)")
		"join":
			if n == 2 and a[0] is Array and a[1] is String:
				var parts := PackedStringArray()
				for v in a[0]:
					parts.append(_to_text(v))
				return (a[1] as String).join(parts)
			return _fail("join(list, separator)")
	return _fail("unknown function " + fn)


func _fail(msg: String) -> Variant:
	if error == "":
		error = msg
	return null


static func _lookup(ctx: Dictionary, parts: Array) -> Variant:
	var v: Variant = ctx
	for p in parts:
		v = _index(v, p)
		if v == null:
			return null
	return v


static func _index(base: Variant, key: Variant) -> Variant:
	if base is Dictionary:
		if base.has(key):
			return base[key]
		if _is_num(key) and base.has(str(int(key))):
			return base[str(int(key))]
		return null
	if base is Array and _is_num(key):
		var i := int(key)
		return base[i] if i >= 0 and i < base.size() else null
	if base is String and _is_num(key):
		var i := int(key)
		return base[i] if i >= 0 and i < base.length() else null
	return null


static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and not (v is bool)


static func _type(v: Variant) -> String:
	if v == null: return "null"
	if v is bool: return "boolean"
	if _is_num(v): return "number"
	if v is String: return "string"
	if v is Array: return "list"
	if v is Dictionary: return "object"
	return type_string(typeof(v))


static func _equal(a: Variant, b: Variant) -> bool:
	if _is_num(a) and _is_num(b):
		return is_equal_approx(float(a), float(b))
	if a is bool or b is bool:
		return a is bool and b is bool and a == b
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _equal(a[k], b[k]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


static func _to_text(v: Variant) -> String:
	if v == null:
		return ""
	if _is_num(v):
		var f := float(v)
		return str(int(f)) if is_equal_approx(f, floor(f)) and absf(f) < 1e15 else str(f)
	if v is bool:
		return "true" if v else "false"
	if v is String:
		return v
	return JSON.stringify(v)


# ------------------------------------------------------------------ parser --

## Tokens → AST (nested Arrays: [op, …]). Precedence, lowest first:
## ?:  ??  or  and  not  in/compare  ..  + -  * / %  unary -  ^  postfix
class _Parser:
	var src: String
	var toks: Array = []
	var pos := 0
	var error := ""
	var paths: Array = []
	var depth := 0

	func _init(s: String) -> void:
		src = s
		_tokenize()

	func parse() -> Variant:
		if error != "":
			return null
		var ast: Variant = _ternary()
		if error == "" and pos < toks.size():
			error = "unexpected '%s'" % str(toks[pos].v)
		return null if error != "" else ast

	# --- tokens: {t: num|str|id|path|op, v}
	func _tokenize() -> void:
		var i := 0
		var n := src.length()
		while i < n:
			var c := src[i]
			if c == " " or c == "\t" or c == "\n" or c == "\r":
				i += 1
				continue
			if c.is_valid_int() or (c == "." and i + 1 < n and src[i + 1].is_valid_int()):
				var j := i
				while j < n and (src[j].is_valid_int() or src[j] == "."):
					if src[j] == "." and j + 1 < n and src[j + 1] == ".":
						break
					j += 1
				var t := src.substr(i, j - i)
				if not t.is_valid_float():
					error = "bad number '%s'" % t
					return
				toks.append({"t": "num", "v": t.to_float()})
				i = j
				continue
			if c == "\"" or c == "'":
				var j := i + 1
				var s := ""
				while j < n and src[j] != c:
					if src[j] == "\\" and j + 1 < n:
						j += 1
						match src[j]:
							"n": s += "\n"
							"t": s += "\t"
							_: s += src[j]
					else:
						s += src[j]
					j += 1
				if j >= n:
					error = "unterminated string"
					return
				toks.append({"t": "str", "v": s})
				i = j + 1
				continue
			if c == "@":
				var j := i + 1
				while j < n and (_is_ident_char(src[j]) or src[j] == "."):
					j += 1
				var p := src.substr(i + 1, j - i - 1)
				if p == "" or p.begins_with(".") or p.ends_with(".") or p.contains(".."):
					error = "bad path '@%s'" % p
					return
				toks.append({"t": "path", "v": p})
				i = j
				continue
			if _is_ident_start(c):
				var j := i
				while j < n and _is_ident_char(src[j]):
					j += 1
				toks.append({"t": "id", "v": src.substr(i, j - i)})
				i = j
				continue
			var two := src.substr(i, 2)
			if two in ["==", "!=", "<=", ">=", "..", "??"]:
				toks.append({"t": "op", "v": two})
				i += 2
				continue
			if c in "+-*/%^<>()[],?:":
				toks.append({"t": "op", "v": c})
				i += 1
				continue
			# a field after a computed index: @a["k" .. @x].total
			if c == "." and i + 1 < n and _is_ident_start(src[i + 1]):
				toks.append({"t": "op", "v": "."})
				i += 1
				continue
			error = "unexpected character '%s'" % c
			return

	static func _is_ident_start(c: String) -> bool:
		return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")

	static func _is_ident_char(c: String) -> bool:
		return _is_ident_start(c) or c.is_valid_int()

	func _peek(kind := "", value: Variant = null) -> bool:
		if pos >= toks.size():
			return false
		var t: Dictionary = toks[pos]
		return (kind == "" or t.t == kind) and (value == null or t.v == value)

	func _take() -> Dictionary:
		pos += 1
		return toks[pos - 1]

	func _expect(value: String) -> bool:
		if _peek("op", value):
			pos += 1
			return true
		if error == "":
			error = "expected '%s'" % value + ("" if pos >= toks.size() else " before '%s'" % str(toks[pos].v))
		return false

	func _enter() -> bool:
		depth += 1
		if depth > MAX_DEPTH:
			if error == "":
				error = "expression too deep"
			return false
		return true

	func _ternary() -> Variant:
		if not _enter():
			return null
		var c: Variant = _coalesce()
		if _peek("op", "?"):
			pos += 1
			var a: Variant = _ternary()
			if not _expect(":"):
				depth -= 1
				return null
			var b: Variant = _ternary()
			c = ["?:", c, a, b]
		depth -= 1
		return c

	func _coalesce() -> Variant:
		var a: Variant = _or()
		while _peek("op", "??"):
			pos += 1
			a = ["??", a, _or()]
		return a

	func _or() -> Variant:
		var a: Variant = _and()
		while _peek("id", "or"):
			pos += 1
			a = ["or", a, _and()]
		return a

	func _and() -> Variant:
		var a: Variant = _not()
		while _peek("id", "and"):
			pos += 1
			a = ["and", a, _not()]
		return a

	func _not() -> Variant:
		if _peek("id", "not"):
			pos += 1
			if not _enter():
				return null
			var v: Variant = ["not", _not()]
			depth -= 1
			return v
		return _compare()

	func _compare() -> Variant:
		var a: Variant = _concat()
		while true:
			if _peek("id", "in"):
				pos += 1
				a = ["in", a, _concat()]
			elif _peek("op") and toks[pos].v in ["==", "!=", "<", "<=", ">", ">="]:
				var op: String = _take().v
				a = [op, a, _concat()]
			else:
				break
		return a

	func _concat() -> Variant:
		var a: Variant = _additive()
		while _peek("op", ".."):
			pos += 1
			a = ["..", a, _additive()]
		return a

	func _additive() -> Variant:
		var a: Variant = _term()
		while _peek("op", "+") or _peek("op", "-"):
			var op: String = _take().v
			a = [op, a, _term()]
		return a

	func _term() -> Variant:
		var a: Variant = _unary()
		while _peek("op", "*") or _peek("op", "/") or _peek("op", "%"):
			var op: String = _take().v
			a = [op, a, _unary()]
		return a

	# -2 ^ 2 is -(2 ^ 2): ^ binds tighter than unary minus, as in Lua.
	func _unary() -> Variant:
		if _peek("op", "-"):
			pos += 1
			if not _enter():
				return null
			var v: Variant = ["neg", _unary()]
			depth -= 1
			return v
		return _power()

	func _power() -> Variant:
		var a: Variant = _postfix()
		if _peek("op", "^"):
			pos += 1
			if not _enter():
				return null
			a = ["^", a, _unary()]   # right-associative
			depth -= 1
		return a

	func _postfix() -> Variant:
		var a: Variant = _primary()
		while _peek("op", "[") or _peek("op", "."):
			if _peek("op", "."):
				pos += 1
				if pos >= toks.size() or toks[pos].t != "id":
					error = "a field name after '.'"
					return null
				a = ["index", a, ["lit", str(_take().v)]]
				continue
			pos += 1
			if not _enter():
				return null
			var k: Variant = _ternary()
			depth -= 1
			if not _expect("]"):
				return null
			a = ["index", a, k]
		return a

	func _primary() -> Variant:
		if pos >= toks.size():
			if error == "":
				error = "unexpected end"
			return null
		var t: Dictionary = _take()
		match t.t:
			"num", "str":
				return ["lit", t.v]
			"path":
				var parts: Array = []
				for p in (t.v as String).split("."):
					parts.append(p)
				if not paths.has(t.v):
					paths.append(t.v)
				return ["path", parts]
			"id":
				match t.v:
					"true": return ["lit", true]
					"false": return ["lit", false]
					"null": return ["lit", null]
				if _peek("op", "("):
					pos += 1
					var args := []
					if not _peek("op", ")"):
						while true:
							if not _enter():
								return null
							args.append(_ternary())
							depth -= 1
							if _peek("op", ","):
								pos += 1
								continue
							break
					if not _expect(")"):
						return null
					return ["call", t.v, args]
				error = "unknown name '%s' (paths start with @)" % t.v
				return null
			"op":
				if t.v == "(":
					if not _enter():
						return null
					var inner: Variant = _ternary()
					depth -= 1
					if not _expect(")"):
						return null
					return inner
				if t.v == "[":
					var items := []
					if not _peek("op", "]"):
						while true:
							if not _enter():
								return null
							items.append(_ternary())
							depth -= 1
							if _peek("op", ","):
								pos += 1
								continue
							break
					if not _expect("]"):
						return null
					return ["call", "__list", items]
		if error == "":
			error = "unexpected '%s'" % str(t.v)
		return null
