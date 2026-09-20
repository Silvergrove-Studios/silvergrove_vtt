class_name JsonSchema
extends RefCounted
## A JSON Schema validator (draft 2020-12, the working subset) for the data
## plugins declare: actors, effects, compendium records, view schemas, pack
## manifests. Values are what JsonDoc.parse gives — Dictionaries, Arrays,
## Strings, floats, bools, null — so "integer" means a number with no
## fraction. Errors are {path, message} with a JSON-pointer-like path, so
## a form can point at the field.
##
## Supported keywords: type (one or several), enum, const; properties,
## required, additionalProperties, patternProperties, propertyNames,
## minProperties, maxProperties, dependentRequired; items, prefixItems,
## minItems, maxItems, uniqueItems, contains, minContains, maxContains;
## minimum, maximum, exclusiveMinimum, exclusiveMaximum, multipleOf;
## minLength, maxLength, pattern, format (date-time, date, id, color);
## allOf, anyOf, oneOf, not, if/then/else; $ref to "#/…" pointers within
## the root and to registered schema ids; $defs / definitions.
## Ignored (documentation for forms): title, description, default,
## examples, deprecated, readOnly, $schema, $id, $comment, ui.

var root: Dictionary
var id := ""

## Schemas other schemas may $ref by id ("actor", "effect", a URL…).
static var _registry: Dictionary = {}
static var _regex_cache: Dictionary = {}


func _init(schema: Dictionary, p_id := "") -> void:
	root = schema
	id = p_id if p_id != "" else str(schema.get("$id", ""))


## Make a schema available to $ref by id.
static func register(p_id: String, schema: Dictionary) -> JsonSchema:
	var s := JsonSchema.new(schema, p_id)
	_registry[p_id] = s
	return s


static func registered(p_id: String) -> JsonSchema:
	return _registry.get(p_id)


static func clear_registry() -> void:
	_registry.clear()


## Validate in one call. Empty array = valid. A boolean schema is allowed.
static func check(schema: Variant, value: Variant) -> Array:
	if schema is bool:
		return [] if schema else [{"path": "", "message": "not allowed"}]
	return JsonSchema.new(schema).validate(value)


## Errors for `value` against this schema; empty when it conforms.
func validate(value: Variant) -> Array:
	var errors := []
	_validate(root, value, "", errors)
	return errors


## The first error as one line, or "".
func first_error(value: Variant) -> String:
	var e := validate(value)
	return "" if e.is_empty() else "%s: %s" % [e[0].path if e[0].path != "" else "/", e[0].message]


# ---------------------------------------------------------------------------

func _err(errors: Array, path: String, message: String) -> void:
	errors.append({"path": path, "message": message})


func _validate(schema: Variant, value: Variant, path: String, errors: Array) -> void:
	if schema is bool:
		if not schema:
			_err(errors, path, "not allowed")
		return
	if not (schema is Dictionary):
		return
	var s: Dictionary = schema
	if s.has("$ref"):
		var target: Variant = _resolve(str(s["$ref"]))
		if target == null:
			_err(errors, path, "unresolvable $ref %s" % s["$ref"])
		else:
			target.owner._validate(target.schema, value, path, errors)
		# 2020-12: other keywords beside $ref still apply
	if s.has("type") and not _type_ok(s["type"], value):
		_err(errors, path, "expected %s, got %s" % [_type_name(s["type"]), _actual_type(value)])
		return
	if s.has("enum") and not _in_list(s["enum"], value):
		_err(errors, path, "must be one of %s" % [s["enum"]])
	if s.has("const") and not _json_equal(s["const"], value):
		_err(errors, path, "must be %s" % [s["const"]])
	if value is Dictionary:
		_validate_object(s, value, path, errors)
	elif value is Array:
		_validate_array(s, value, path, errors)
	elif value is String:
		_validate_string(s, value, path, errors)
	elif value is float or value is int:
		_validate_number(s, value, path, errors)
	if s.has("allOf"):
		for sub in s["allOf"]:
			_validate(sub, value, path, errors)
	if s.has("anyOf"):
		var ok := false
		for sub in s["anyOf"]:
			var e := []
			_validate(sub, value, path, e)
			if e.is_empty():
				ok = true
				break
		if not ok:
			_err(errors, path, "matches none of the alternatives")
	if s.has("oneOf"):
		var n := 0
		for sub in s["oneOf"]:
			var e := []
			_validate(sub, value, path, e)
			if e.is_empty():
				n += 1
		if n != 1:
			_err(errors, path, "must match exactly one alternative (matched %d)" % n)
	if s.has("not"):
		var e := []
		_validate(s["not"], value, path, e)
		if e.is_empty():
			_err(errors, path, "must not match the excluded schema")
	if s.has("if"):
		var e := []
		_validate(s["if"], value, path, e)
		if e.is_empty():
			if s.has("then"):
				_validate(s["then"], value, path, errors)
		elif s.has("else"):
			_validate(s["else"], value, path, errors)


func _validate_object(s: Dictionary, v: Dictionary, path: String, errors: Array) -> void:
	var props: Dictionary = s.get("properties", {})
	for r in s.get("required", []):
		if not v.has(r):
			_err(errors, path + "/" + str(r), "required")
	if s.has("minProperties") and v.size() < int(s["minProperties"]):
		_err(errors, path, "needs at least %d properties" % int(s["minProperties"]))
	if s.has("maxProperties") and v.size() > int(s["maxProperties"]):
		_err(errors, path, "allows at most %d properties" % int(s["maxProperties"]))
	var dep: Dictionary = s.get("dependentRequired", {})
	for k in dep:
		if v.has(k):
			for r in dep[k]:
				if not v.has(r):
					_err(errors, path + "/" + str(r), "required when %s is present" % k)
	var patterns: Dictionary = s.get("patternProperties", {})
	for key in v:
		var k := str(key)
		var sub := path + "/" + _escape(k)
		var matched := false
		if props.has(k):
			matched = true
			_validate(props[k], v[key], sub, errors)
		for pat in patterns:
			if _regex(str(pat)).search(k) != null:
				matched = true
				_validate(patterns[pat], v[key], sub, errors)
		if s.has("propertyNames"):
			var e := []
			_validate(s["propertyNames"], k, sub, e)
			if not e.is_empty():
				_err(errors, sub, "property name not allowed")
		if not matched and s.has("additionalProperties"):
			var ap: Variant = s["additionalProperties"]
			if ap is bool:
				if not ap:
					_err(errors, sub, "unknown property")
			else:
				_validate(ap, v[key], sub, errors)


func _validate_array(s: Dictionary, v: Array, path: String, errors: Array) -> void:
	if s.has("minItems") and v.size() < int(s["minItems"]):
		_err(errors, path, "needs at least %d items" % int(s["minItems"]))
	if s.has("maxItems") and v.size() > int(s["maxItems"]):
		_err(errors, path, "allows at most %d items" % int(s["maxItems"]))
	var prefix: Array = s.get("prefixItems", [])
	for i in v.size():
		var sub := "%s/%d" % [path, i]
		if i < prefix.size():
			_validate(prefix[i], v[i], sub, errors)
		elif s.has("items"):
			_validate(s["items"], v[i], sub, errors)
	if bool(s.get("uniqueItems", false)):
		for i in v.size():
			for j in range(i + 1, v.size()):
				if _json_equal(v[i], v[j]):
					_err(errors, "%s/%d" % [path, j], "duplicate item")
					break
	if s.has("contains"):
		var n := 0
		for item in v:
			var e := []
			_validate(s["contains"], item, path, e)
			if e.is_empty():
				n += 1
		var lo := int(s.get("minContains", 1))
		var hi := int(s.get("maxContains", -1))
		if n < lo:
			_err(errors, path, "needs at least %d matching item(s)" % lo)
		if hi >= 0 and n > hi:
			_err(errors, path, "allows at most %d matching item(s)" % hi)


func _validate_string(s: Dictionary, v: String, path: String, errors: Array) -> void:
	if s.has("minLength") and v.length() < int(s["minLength"]):
		_err(errors, path, "shorter than %d" % int(s["minLength"]))
	if s.has("maxLength") and v.length() > int(s["maxLength"]):
		_err(errors, path, "longer than %d" % int(s["maxLength"]))
	if s.has("pattern") and _regex(str(s["pattern"])).search(v) == null:
		_err(errors, path, "does not match %s" % s["pattern"])
	if s.has("format"):
		var f := str(s["format"])
		var ok := true
		match f:
			"date-time": ok = _regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?(Z|[+-]\\d{2}:?\\d{2})?$").search(v) != null
			"date": ok = _regex("^\\d{4}-\\d{2}-\\d{2}$").search(v) != null
			"id": ok = _regex("^[A-Za-z_][A-Za-z0-9_.-]*$").search(v) != null
			"color": ok = _regex("^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$").search(v) != null
			_: ok = true   # unknown formats are annotations
		if not ok:
			_err(errors, path, "not a valid %s" % f)


func _validate_number(s: Dictionary, v: Variant, path: String, errors: Array) -> void:
	var x := float(v)
	if s.has("minimum") and x < float(s["minimum"]):
		_err(errors, path, "below minimum %s" % s["minimum"])
	if s.has("maximum") and x > float(s["maximum"]):
		_err(errors, path, "above maximum %s" % s["maximum"])
	if s.has("exclusiveMinimum") and x <= float(s["exclusiveMinimum"]):
		_err(errors, path, "must be above %s" % s["exclusiveMinimum"])
	if s.has("exclusiveMaximum") and x >= float(s["exclusiveMaximum"]):
		_err(errors, path, "must be below %s" % s["exclusiveMaximum"])
	if s.has("multipleOf"):
		var m := float(s["multipleOf"])
		if m > 0.0 and not is_zero_approx(fmod(x, m)) and not is_equal_approx(fmod(x, m), m):
			_err(errors, path, "not a multiple of %s" % s["multipleOf"])


# ------------------------------------------------------------------ types --

static func _type_ok(t: Variant, v: Variant) -> bool:
	if t is Array:
		for one in t:
			if _type_ok(one, v):
				return true
		return false
	match str(t):
		"object": return v is Dictionary
		"array": return v is Array
		"string": return v is String
		"number": return v is float or v is int
		"integer": return v is int or (v is float and is_equal_approx(v, floor(v)))
		"boolean": return v is bool
		"null": return v == null
		"any": return true
	return false


static func _type_name(t: Variant) -> String:
	return " or ".join(PackedStringArray(t)) if t is Array else str(t)


static func _actual_type(v: Variant) -> String:
	if v == null: return "null"
	if v is Dictionary: return "object"
	if v is Array: return "array"
	if v is String: return "string"
	if v is bool: return "boolean"
	if v is float or v is int: return "number"
	return type_string(typeof(v))


static func _in_list(list: Array, v: Variant) -> bool:
	for item in list:
		if _json_equal(item, v):
			return true
	return false


## Equality as JSON sees it: 1 == 1.0, arrays and objects by content.
static func _json_equal(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is bool or b is bool:
		return a is bool and b is bool and a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _json_equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _json_equal(a[i], b[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


static func _regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var r := RegEx.new()
		r.compile(pattern)
		_regex_cache[pattern] = r
	return _regex_cache[pattern]


static func _escape(key: String) -> String:
	return key.replace("~", "~0").replace("/", "~1")


# ------------------------------------------------------------------- refs --

## {owner: JsonSchema, schema: Variant} for a $ref, or null.
func _resolve(ref: String) -> Variant:
	var owner: JsonSchema = self
	var pointer := ref
	if not ref.begins_with("#"):
		var hash := ref.find("#")
		var rid := ref if hash < 0 else ref.substr(0, hash)
		pointer = "#" if hash < 0 else ref.substr(hash)
		owner = _registry.get(rid)
		if owner == null:
			return null
	var node: Variant = owner.root
	if pointer == "#" or pointer == "":
		return {"owner": owner, "schema": node}
	for part in pointer.trim_prefix("#/").split("/"):
		var key := part.replace("~1", "/").replace("~0", "~")
		if node is Dictionary and node.has(key):
			node = node[key]
		elif node is Array and key.is_valid_int() and int(key) < node.size():
			node = node[int(key)]
		else:
			return null
	return {"owner": owner, "schema": node}
