class_name JsonDoc
extends RefCounted
## What every JSON document type (.hexmap, .encounter) needs: stable
## serialisation so saves diff well, ids, and deep copies.


## Serialise with keys sorted at every level and whole floats written as
## ints, so a load/save cycle changes nothing and diffs stay small.
static func stringify(doc: Dictionary) -> String:
	return JSON.stringify(sorted(doc), "  ", false) + "\n"


## Parse text into a Dictionary. Returns {} and fills `error` on failure.
static func parse(text: String, error: Array = []) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		error.append("line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		error.append("not a JSON object")
		return {}
	return json.data


## Recursively sort dictionary keys. Cell keys ("q,r") sort as strings,
## which is fine: stable is what matters.
static func sorted(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		var keys := (v as Dictionary).keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for k in keys:
			out[k] = sorted(v[k])
		return out
	if v is Array:
		var out := []
		for e in v:
			out.append(sorted(e))
		return out
	# JSON.parse gives every number back as a float; write whole numbers as
	# ints so a load/save cycle does not turn "v": 1 into "v": 1.0 forever.
	if v is float and is_finite(v) and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	return v


static func uuid() -> String:
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = randi() & 0xff
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


static func new_id(prefix: String) -> String:
	return "%s_%08x" % [prefix, randi()]


## Deep copy of nested dictionaries and arrays.
static func deep(v: Variant) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v


## Structural equality after normalisation (ints vs whole floats, key order).
static func same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(sorted(a)) == JSON.stringify(sorted(b))


## Merge `changes` into `target` in place: a null value removes the key.
## Returns the previous values as the inverse change set.
static func merge(target: Dictionary, changes: Dictionary) -> Dictionary:
	var before := {}
	for k in changes:
		before[k] = deep(target[k]) if target.has(k) else null
		if changes[k] == null:
			target.erase(k)
		else:
			target[k] = deep(changes[k])
	return before


## ISO 8601, UTC, "2026-09-19T18:04:00": what the format docs show.
static func now() -> String:
	return Time.get_datetime_string_from_system(true, false)


## A document's text with its "modified" stamps blanked, for comparing two
## documents that should be the same apart from when they were touched.
static func sans_modified(text: String) -> String:
	var re := RegEx.new()
	re.compile('"modified": "[^"]*"')
	return re.sub(text, '"modified": ""', true)
