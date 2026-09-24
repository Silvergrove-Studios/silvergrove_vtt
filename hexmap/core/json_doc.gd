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


## Paths are JSON-pointer style, "ext/rules/stats/agi": keys may contain
## dots (plugin ids do), never slashes. Array steps are integer indices.
const PATH_SEP := "/"


## The value at a path, or `default` when any step is missing.
static func at_path(target: Variant, path: String, default: Variant = null) -> Variant:
	var v: Variant = target
	for part in path.split(PATH_SEP):
		if v is Dictionary and (v as Dictionary).has(part):
			v = v[part]
		elif v is Array and part.is_valid_int() and int(part) >= 0 and int(part) < (v as Array).size():
			v = v[int(part)]
		else:
			return default
	return v


## Set (or, with null, remove) the value at a path, creating intermediate
## dictionaries on the way in. Returns the previous value (null if none).
static func set_at_path(target: Dictionary, path: String, value: Variant) -> Variant:
	return set_at_path_ex(target, path, value).before


## set_at_path with the bookkeeping an exact inverse needs: `created` is
## the path of the topmost dictionary this call made (or ""), so undoing
## the set removes that, not just the leaf, and leaves no empty shells.
## An integer step walks into an existing array element (arrays are
## never created or grown on the way; a missing index is a no-op removal
## or an error for a set).
static func set_at_path_ex(target: Dictionary, path: String, value: Variant) -> Dictionary:
	var parts := path.split(PATH_SEP)
	var d: Variant = target
	var created := ""
	for i in parts.size() - 1:
		var k := parts[i]
		if d is Array:
			var idx := int(k) if k.is_valid_int() else -1
			if idx < 0 or idx >= (d as Array).size():
				return {"before": null, "created": ""}
			d = d[idx]
			continue
		if not ((d as Dictionary).get(k) is Dictionary or (d as Dictionary).get(k) is Array):
			if value == null:
				return {"before": null, "created": ""}
			d[k] = {}
			if created == "":
				created = PATH_SEP.join(parts.slice(0, i + 1))
		d = d[k]
	var last := parts[parts.size() - 1]
	if d is Array:
		var idx := int(last) if last.is_valid_int() else -1
		if idx < 0 or idx >= (d as Array).size():
			return {"before": null, "created": ""}
		var was: Variant = deep(d[idx])
		if value == null:
			(d as Array).remove_at(idx)
		else:
			d[idx] = deep(value)
		return {"before": was, "created": created}
	var before: Variant = deep(d[last]) if d.has(last) else null
	if value == null:
		d.erase(last)
	else:
		d[last] = deep(value)
	return {"before": before, "created": created}


## merge() for change sets whose keys may be paths: "a/b/c": 1 sets deep
## inside; a null removes. Returns the inverse change set: the previous
## value under the same key, or, where the set created dictionaries on the
## way, a removal of the topmost one it created.
static func merge_paths(target: Dictionary, changes: Dictionary) -> Dictionary:
	var before := {}
	for k in changes:
		var key := str(k)
		if key.contains(PATH_SEP):
			var r := set_at_path_ex(target, key, changes[k])
			if r.created != "":
				before[r.created] = null
			else:
				before[key] = r.before
		else:
			before[key] = deep(target[key]) if target.has(key) else null
			if changes[k] == null:
				target.erase(key)
			else:
				target[key] = deep(changes[k])
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


## Copy a file byte for byte. Unlike DirAccess.copy_absolute this reads
## through FileAccess, so a file inside the app's own package (res:// in an
## exported build, which on Android is inside the APK) copies whole instead
## of arriving empty. OK, or the error.
static func copy_file(from: String, to: String) -> Error:
	if not FileAccess.file_exists(from):
		return ERR_FILE_NOT_FOUND
	var bytes := FileAccess.get_file_as_bytes(from)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		return FileAccess.get_open_error()
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	return OK
