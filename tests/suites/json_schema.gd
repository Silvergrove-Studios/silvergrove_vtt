extends TestCase
## JsonSchema: the validator plugins' data goes through. Table-driven:
## each case is [schema, value, expected error count or a path the error
## must be at].


func _j(text: String) -> Variant:
	var json := JSON.new()
	var err := json.parse(text)
	check(err == OK, "test JSON parses: " + text)
	return json.data


func _case(schema: String, value: String, expect: Variant, label := "") -> void:
	var errors := JsonSchema.check(_j(schema), _j(value))
	var name := label if label != "" else "%s ⟵ %s" % [schema, value]
	if expect is int:
		check(errors.size() == expect, "%s: %d error(s) expected, got %s" % [name, expect, errors])
	else:
		var found := false
		for e in errors:
			if e.path == str(expect):
				found = true
		check(found, "%s: an error at %s, got %s" % [name, expect, errors])


func test_schema_types_and_scalars() -> void:
	_case('{"type":"string"}', '"a"', 0)
	_case('{"type":"string"}', '1', 1)
	_case('{"type":"number"}', '1.5', 0)
	_case('{"type":"integer"}', '2', 0, "2.0 from JSON is an integer")
	_case('{"type":"integer"}', '2.5', 1)
	_case('{"type":"boolean"}', 'true', 0)
	_case('{"type":"boolean"}', '1', 1, "1 is not a boolean")
	_case('{"type":"null"}', 'null', 0)
	_case('{"type":["string","null"]}', 'null', 0, "a type list")
	_case('{"type":["string","null"]}', '3', 1)
	_case('{"type":"object"}', '{}', 0)
	_case('{"type":"array"}', '{}', 1)
	_case('{"enum":["a","b",1]}', '"b"', 0)
	_case('{"enum":["a","b",1]}', '1', 0)
	_case('{"enum":["a","b",1]}', '"c"', 1)
	_case('{"const":{"x":[1,2]}}', '{"x":[1,2]}', 0, "const compares by content")
	_case('{"const":{"x":[1,2]}}', '{"x":[1,3]}', 1)
	_case('{"minimum":0,"maximum":10}', '10', 0)
	_case('{"minimum":0,"maximum":10}', '11', 1)
	_case('{"exclusiveMinimum":0}', '0', 1)
	_case('{"exclusiveMaximum":5}', '4.9', 0)
	_case('{"multipleOf":0.5}', '2.5', 0)
	_case('{"multipleOf":3}', '7', 1)
	_case('{"minLength":2,"maxLength":3}', '"ab"', 0)
	_case('{"minLength":2,"maxLength":3}', '"abcd"', 1)
	_case('{"pattern":"^[a-z]+$"}', '"abc"', 0)
	_case('{"pattern":"^[a-z]+$"}', '"ab1"', 1)
	_case('{"format":"date-time"}', '"2026-09-20T18:00:00Z"', 0)
	_case('{"format":"date-time"}', '"yesterday"', 1)
	_case('{"format":"id"}', '"sample.ordered"', 0)
	_case('{"format":"id"}', '"1bad"', 1)
	_case('{"format":"color"}', '"#4f9cf6"', 0)
	_case('{"format":"color"}', '"blue"', 1)
	_case('{"format":"made-up"}', '"anything"', 0, "unknown formats are annotations")


func test_schema_objects() -> void:
	var actor := '{"type":"object","required":["id","name"],"properties":{"id":{"type":"string","format":"id"},"name":{"type":"string","minLength":1},"level":{"type":"integer","minimum":1,"default":1},"tags":{"type":"array","items":{"type":"string"},"uniqueItems":true}},"additionalProperties":false}'
	_case(actor, '{"id":"a1","name":"Hero","level":3,"tags":["x","y"]}', 0, "a good actor")
	_case(actor, '{"id":"a1"}', "/name")
	_case(actor, '{"id":"a1","name":"","level":3}', "/name")
	_case(actor, '{"id":"a1","name":"H","level":0}', "/level")
	_case(actor, '{"id":"a1","name":"H","level":1.5}', "/level")
	_case(actor, '{"id":"a1","name":"H","extra":1}', "/extra")
	_case(actor, '{"id":"a1","name":"H","tags":["x","x"]}', "/tags/1")
	_case(actor, '{"id":"a1","name":"H","tags":[1]}', "/tags/0")
	_case('{"additionalProperties":{"type":"number"}}', '{"a":1,"b":"no"}', "/b")
	_case('{"patternProperties":{"^ext_":{"type":"object"}}}', '{"ext_x":{},"other":1}', 0)
	_case('{"patternProperties":{"^ext_":{"type":"object"}}}', '{"ext_x":1}', "/ext_x")
	_case('{"propertyNames":{"pattern":"^[a-z]+$"}}', '{"ok":1,"Bad":2}', "/Bad")
	_case('{"minProperties":1}', '{}', 1)
	_case('{"maxProperties":1}', '{"a":1,"b":2}', 1)
	_case('{"dependentRequired":{"credit":["billing"]}}', '{"credit":1}', "/billing")
	_case('{"dependentRequired":{"credit":["billing"]}}', '{"credit":1,"billing":1}', 0)
	_case('{"properties":{"a/b":{"type":"number"}}}', '{"a/b":"x"}', "/a~1b", "slashes in keys are escaped in paths")


func test_schema_arrays_and_combinators() -> void:
	_case('{"type":"array","minItems":1,"maxItems":2}', '[]', 1)
	_case('{"type":"array","minItems":1,"maxItems":2}', '[1,2,3]', 1)
	_case('{"prefixItems":[{"type":"string"},{"type":"number"}],"items":false}', '["a",1]', 0)
	_case('{"prefixItems":[{"type":"string"},{"type":"number"}],"items":false}', '["a",1,2]', "/2")
	_case('{"contains":{"const":"x"}}', '["a","x"]', 0)
	_case('{"contains":{"const":"x"},"minContains":2}', '["a","x"]', 1)
	_case('{"contains":{"const":"x"},"maxContains":1}', '["x","x"]', 1)
	_case('{"allOf":[{"type":"number"},{"minimum":5}]}', '7', 0)
	_case('{"allOf":[{"type":"number"},{"minimum":5}]}', '3', 1)
	_case('{"anyOf":[{"type":"string"},{"type":"number"}]}', '3', 0)
	_case('{"anyOf":[{"type":"string"},{"type":"number"}]}', 'true', 1)
	_case('{"oneOf":[{"type":"number"},{"minimum":5}]}', '3', 0, "exactly one")
	_case('{"oneOf":[{"type":"number"},{"minimum":5}]}', '7', 1, "both match")
	_case('{"not":{"type":"string"}}', '"a"', 1)
	_case('{"not":{"type":"string"}}', '1', 0)
	var cond := '{"properties":{"kind":{"type":"string"}},"if":{"properties":{"kind":{"const":"pool"}}},"then":{"required":["max"]},"else":{"required":["slots"]}}'
	_case(cond, '{"kind":"pool","max":3}', 0)
	_case(cond, '{"kind":"pool"}', "/max")
	_case(cond, '{"kind":"track","slots":3}', 0)
	_case(cond, '{"kind":"track"}', "/slots")
	_case('false', '1', 1, "a boolean schema")
	_case('true', '1', 0)


func test_schema_refs() -> void:
	JsonSchema.clear_registry()
	var root: Dictionary = _j('{"$defs":{"pos":{"type":"array","prefixItems":[{"type":"number"},{"type":"number"}],"minItems":2,"maxItems":2}},"type":"object","properties":{"at":{"$ref":"#/$defs/pos"},"to":{"$ref":"#/$defs/pos"}}}')
	var s := JsonSchema.new(root)
	check(s.validate({"at": [1, 2], "to": [3, 4]}).is_empty(), "local $ref resolves")
	var e := s.validate({"at": [1], "to": "x"})
	check(e.size() == 2 and e[0].path == "/at" and e[1].path == "/to", "errors through refs keep their paths: %s" % [e])
	check(not JsonSchema.new(_j('{"$ref":"#/$defs/nothing"}')).validate(1).is_empty(), "a bad pointer is an error, not a crash")
	JsonSchema.register("effect", _j('{"type":"object","required":["id"],"properties":{"id":{"type":"string"},"value":{"type":"integer"}}}'))
	var user := JsonSchema.new(_j('{"type":"array","items":{"$ref":"effect"}}'))
	check(user.validate([{"id": "shaken", "value": 2}]).is_empty(), "a registered schema by id")
	check(user.validate([{"value": 2}])[0].path == "/0/id", "…with paths")
	var deep := JsonSchema.new(_j('{"type":"object","properties":{"e":{"$ref":"effect#/properties/value"}}}'))
	check(deep.validate({"e": 1.5}).size() == 1, "id plus pointer")
	check(JsonSchema.new(_j('{"$ref":"unknown"}')).first_error({}) != "", "an unknown id reports")
	JsonSchema.clear_registry()


func test_schema_first_error_and_equality() -> void:
	var s := JsonSchema.new(_j('{"type":"object","properties":{"n":{"type":"integer"}}}'))
	check(s.first_error({"n": 1}) == "", "no error line when valid")
	check(s.first_error({"n": 1.5}).begins_with("/n: "), "the first error names the path")
	check(JsonSchema._json_equal(1, 1.0) and not JsonSchema._json_equal(true, 1) and JsonSchema._json_equal([1, {"a": null}], [1.0, {"a": null}]), "JSON equality")
