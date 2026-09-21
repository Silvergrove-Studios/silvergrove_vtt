extends TestCase
## Expr: the expression language plugins put in data. Table-driven, plus
## a fuzz run for termination.

const CTX := {
	"actor": {"level": 3, "name": "Hero", "stats": {"agi": 2, "str": -1}, "tags": ["elf", "ranger"], "prone": false, "hp": {"max": 24, "cur": 9}},
	"target": {"size": "large", "cover": null},
	"n": 7, "half": 0.5, "s": "Sword of Dawn", "list": [1, 2, 3],
}


func _is(source: String, expect: Variant, label := "") -> void:
	var v: Variant = Expr.evaluate(source, CTX)
	var ok := false
	if expect is float or expect is int:
		ok = (v is float or v is int) and is_equal_approx(float(v), float(expect))
	elif expect is bool:
		ok = v is bool and v == expect
	else:
		ok = v == expect
	check(ok, "%s%s → %s (got %s)" % [label + ": " if label != "" else "", source, expect, v])


func _bad(source: String, label := "") -> void:
	var e := Expr.parse(source)
	check(not e.is_valid() and e.error != "", "%s%s is a parse error (%s)" % [label + ": " if label != "" else "", source, e.error])


func test_expr_arithmetic_and_precedence() -> void:
	_is("1 + 2 * 3", 7)
	_is("(1 + 2) * 3", 9)
	_is("2 ^ 3 ^ 2", 512, "right-assoc power")
	_is("-2 ^ 2", -4, "unary minus binds looser than ^")
	_is("7 % 3", 1)
	_is("7 / 2", 3.5)
	_is("@n * @half", 3.5)
	_is("@actor.level * 2 + 1", 7)
	_is("@actor.stats.agi + @actor.stats.str", 1)
	_is("1 / 0", null, "division by zero is null")
	_is("floor(7 / 2) + ceil(0.2) + round(2.5) + abs(-3)", 3 + 1 + 3 + 3)
	_is("min(4, 2, 9)", 2)
	_is("max(@list)", 3, "max of a list")
	_is("clamp(@n, 0, 5)", 5)
	_is("sum(@list) + len(@list) + len(@actor.tags) + len(@s)", 6 + 3 + 2 + 13)
	_is("sign(-9)", -1)


func test_expr_paths_strings_and_logic() -> void:
	_is("@actor.name", "Hero")
	_is("@actor.tags[1]", "ranger")
	_is("@actor.tags[5]", null, "out of range is null")
	_is("@actor.missing.deeper", null, "missing is null, not an error")
	_is('@actor.stats["agi"]', 2)
	_is("@actor.tags[0] .. \"/\" .. @actor.level", "elf/3", "concatenation formats numbers")
	_is("@actor.stats[\"ag\" .. \"i\"] + 1", 3, "a computed index")
	_is("@actor[\"stats\"].agi", 2, "a field after a computed index")
	_is("@actor.hp[\"c\" .. \"ur\"] + @actor.hp.max", 33, "chained")
	_is("\"Level \" .. @half", "Level 0.5")
	_is("str(@list)", "[1,2,3]")
	_is("upper(@s) == \"SWORD OF DAWN\"", true)
	_is("lower(\"AbC\")", "abc")
	_is("contains(@s, \"Dawn\") and starts(@s, \"Sword\") and ends(@s, \"n\")", true)
	_is("\"of\" in @s", true, "substring membership")
	_is("\"elf\" in @actor.tags", true)
	_is("\"orc\" in @actor.tags", false)
	_is("has(@actor, \"prone\")", true)
	_is("has(@actor.tags, \"ranger\")", true)
	_is("join(@list, \"-\")", "1-2-3")
	_is("@target.size == \"large\" and not @actor.prone", true)
	_is("@actor.prone or @n > 5", true)
	_is("not @actor.prone", true)
	_is("null == null and 1 == 1.0 and [1, 2] == @list[0] .. \"\" .. \"\" == \"1\"", false, "list literals and equality")
	_is("[1, 2, 3] == @list", true)
	_is("true == 1", false, "booleans are not numbers")
	_is("@target.cover ?? \"none\"", "none")
	_is("@actor.level ?? 99", 3)
	_is("@actor.hp.cur <= @actor.hp.max / 2 ? \"bloodied\" : \"fine\"", "bloodied")
	_is("@n > 5 ? (@n > 6 ? \"big\" : \"mid\") : \"small\"", "big", "nested ternary")
	_is("@actor.name ? \"named\" : \"nameless\"", "named", "a string is truthy (not a GDScript comparison error)")
	_is("@actor.missing ? 1 : 2", 2, "null is falsy")
	_is("0 ? 1 : 2", 1, "zero is truthy, as in Lua")
	_is("\"b\" > \"a\"", true, "string ordering")
	_is("1 < \"a\"", null, "mixed comparison is an error → null")
	_is("num(\"12.5\") + num(true)", 13.5)
	_is("num(\"x\")", null)
	_is("@actor.level > 2 and @actor.stats.agi >= 2 and \"ranger\" in @actor.tags", true, "a typical predicate")


func test_expr_errors_and_deps() -> void:
	_bad("1 +")
	_bad("(1 + 2")
	_bad("foo")
	_bad("@")
	_bad("@a..b")
	_bad("1 2")
	_bad("\"unterminated")
	_bad("f(1,")
	_bad("? 1 : 2")
	_bad("1 ? 2")
	_bad("#")
	var e := Expr.parse("@actor.level + @actor.stats.agi * @n + max(@list) + @actor.level")
	check(e.is_valid() and e.deps() == ["actor.level", "actor.stats.agi", "n", "list"], "deps lists each path once: %s" % [e.deps()])
	var f := Expr.parse("unknown_fn(1)")
	check(f.is_valid() and f.eval({}) == null and f.error.contains("unknown function"), "unknown functions fail at eval: " + f.error)
	var g := Expr.parse("abs(\"x\")")
	check(g.eval({}) == null and g.error != "", "wrong argument types fail softly: " + g.error)
	check(Expr.evaluate_text("@a.b", {}) == "" and Expr.evaluate_text("1 + 1", {}) == "2", "evaluate_text")
	var deep := "(".repeat(60) + "1" + ")".repeat(60)
	var d := Expr.parse(deep)
	check(not d.is_valid() and d.error.contains("deep"), "nesting is bounded: " + d.error)


func test_expr_fuzz_terminates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260920
	var atoms := ["1", "2.5", "@n", "@actor.level", "@list", "@s", "\"x\"", "true", "null", "min", "len", "sum", "str",
		"+", "-", "*", "/", "%", "^", "..", "==", "!=", "<", ">=", "and", "or", "not", "in", "??", "?", ":", "(", ")", "[", "]", ",", " ", "@", "\"", "'", "#"]
	var parsed := 0
	var evaluated := 0
	var t0 := Time.get_ticks_msec()
	for i in 3000:
		var parts := PackedStringArray()
		for j in rng.randi_range(1, 14):
			parts.append(atoms[rng.randi_range(0, atoms.size() - 1)])
		var src := " ".join(parts)
		var e := Expr.parse(src)
		if e.is_valid():
			parsed += 1
			var v: Variant = e.eval(CTX)
			if v != null:
				evaluated += 1
		else:
			check(e.error != "", "an invalid parse says why: " + src)
	check(parsed > 50 and evaluated > 20, "the fuzz found live expressions (parsed %d, evaluated %d)" % [parsed, evaluated])
	check(Time.get_ticks_msec() - t0 < 5000, "3000 random expressions in under 5 s (%d ms)" % (Time.get_ticks_msec() - t0))
