class_name TestSuite
extends RefCounted
## The unit tests' runner, one object any driver can use: tests/run_tests.gd
## (`./run.sh test`, headless) and the app's own self-test mode, which runs
## the same suites inside a build on a phone, a simulator or an exported
## desktop app (`--selftest`, or a `user://selftest` marker file). The
## tests live in tests/suites/*.gd (TestCase subclasses); each test_*
## method asserts with check() and run_all() reports through `say`.

var tree: SceneTree
var root: Window
## Where a line of output goes: print by default; the self-test also
## writes it to a file.
var say: Callable = func(line: String) -> void: print(line)
var _fails := 0
var _count := 0
var fails: int:
	get: return _fails
var count: int:
	get: return _count
## Tests that could not run here ("skipped: …"), for the report.
var skipped: PackedStringArray = []


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	root = tree.root


## The suites, in the order they run. Each is a TestCase subclass under
## tests/suites/ whose test_* methods are the tests. An explicit list, not
## a directory scan: exported builds do not list res:// reliably.
const SUITES := ["hex_grid", "document", "json_schema", "expr", "pdf", "exporters", "packs_tools", "layers_lighting",
	"ui", "ui_views", "shell", "encounter", "table", "player", "net", "fuzz", "rules_kernel", "rules_lua", "rules_plugins", "rules_turns", "rules_views", "rules_content", "rules_map", "rules_campaign", "rules_perf", "rules_sandbox"]


## Run every test_* method of every suite (or those whose names contain
## `filter`). Tests may await frames, so this is a coroutine.
func run_all(filter := "") -> void:
	for suite_name in SUITES:
		var script: GDScript = load("res://tests/suites/%s.gd" % suite_name)
		if script == null:
			check(false, "suite %s failed to load" % suite_name)
			continue
		var case: TestCase = script.new()
		case.suite = self
		for m in case.get_method_list():
			var n: String = m.name
			if not n.begins_with("test_"):
				continue
			if filter != "" and not n.contains(filter) and not suite_name.contains(filter):
				continue
			say.call("-- " + n)
			await case.call(n)
	say.call("%d checks, %d failed%s" % [_count, _fails, "" if skipped.is_empty() else " (%d skipped)" % skipped.size()])


func check(cond: bool, msg: String) -> void:
	_count += 1
	if not cond:
		_fails += 1
		say.call("  FAIL: " + msg)


func skip(why: String) -> void:
	skipped.append(why)
	say.call("  (skipped: %s)" % why)


func near(a: float, b: float, eps := 1e-6) -> bool:
	return absf(a - b) <= eps


## The example maps and encounters: inside the project, or pushed to
## user://examples on a device where res:// is a compiled pack.
static func examples_dir() -> String:
	if not OS.has_feature("template"):
		var local := ProjectSettings.globalize_path("res://examples")
		if FileAccess.file_exists(local.path_join("ruined_chapel.hexmap")):
			return local   # the project on disk: the editor, ./run.sh test
	# In a build, res:// is the pack; globalize_path gives nothing usable.
	if FileAccess.file_exists("res://examples/ruined_chapel.hexmap"):
		return "res://examples"
	return ProjectSettings.globalize_path("user://examples")   # pushed to a device


static func example(file: String) -> String:
	return examples_dir().path_join(file)


## Scratch output that survives the run (the PDF for an external check).
static func out_dir() -> String:
	var d := ProjectSettings.globalize_path("user://out" if OS.has_feature("template") else "res://out")
	DirAccess.make_dir_recursive_absolute(d)
	return d


# ------------------------------------------------------------------- hex grid --


# ------------------------------------------------------------- remote join --

## Join a Table that is really running somewhere — on the host beside an
## emulator, on a laptop across the wifi from a phone on USB — and play a
## move. Not a test_* (there is no table in the unit run); the self-test
## runs it when user://selftest_join names an address, and
## tools/android_join_test.sh drives that.
func join_remote(address: String, port: int, timeout_s := 20.0) -> void:
	var packs := PackLibrary.new()
	packs.reload()
	var s := NetSession.new(address, port, packs, "join test")
	var told := []
	s.status.connect(func(t: String) -> void: told.append(t))
	var closed := []
	s.closed.connect(func(r: String) -> void: closed.append(r))
	check(s.connect_to_host() == OK, "connect_to_host(%s:%d)" % [address, port])
	var pump := func(done: Callable, why: String) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < timeout_s * 1000.0:
			s.poll()
			if done.call():
				return true
			if not closed.is_empty():
				say.call("  closed while waiting for %s: %s" % [why, closed])
				return false
			OS.delay_msec(20)
		say.call("  timed out waiting for %s (told: %s)" % [why, told])
		return false
	check(pump.call(func() -> bool: return s.state != null, "the welcome"), "welcomed by the table at %s:%d" % [address, port])
	if s.state == null:
		return
	say.call("  table: '%s', %d scenes, %d players, turns %s" % [s.state.encounter.name, s.state.encounter.scenes.size(), s.state.encounter.players.size(), s.state.encounter.turns.get("mode", "?")])
	check(pump.call(func() -> bool: return s.maps_ready(), "the maps"), "maps streamed")
	check(pump.call(func() -> bool: return s.assets_pending() == 0, "pack files"), "pack files streamed (or already here)")
	check(s.state.map_for(s.scene_id()) != null, "the shown scene has its map")
	if s.state.encounter.players.is_empty():
		check(false, "the table has no players to join as")
		s.leave()
		return
	var pid := str(s.state.encounter.players[0].id)
	s.join(pid)
	check(pump.call(func() -> bool: return s.joined, "the join"), "joined as %s" % s.player_name())
	var mine := s.my_tokens()
	say.call("  %d tokens of mine on the scene; %s" % [mine.size(), s.turn_summary()])
	if not mine.is_empty():
		var tk: Dictionary = mine[0]
		var from := Vision.token_pos(tk)
		var g := s.state.map_for(s.scene_id()).grid
		var to := g.cell_center(g.world_to_axial(from) + Vector2i(1, 0))
		var why := s.request({"t": "token.set", "scene": s.scene_id(), "id": str(tk.id), "changes": {"pos": [to.x, to.y]}})
		if why == "":
			check(pump.call(func() -> bool: return Vision.token_pos(s.state.token(s.scene_id(), str(tk.id))) == to, "the move to echo back"), "a move went to the table and came back")
			# And back again, to leave the table as it was.
			s.request({"t": "token.set", "scene": s.scene_id(), "id": str(tk.id), "changes": {"pos": [from.x, from.y]}})
			pump.call(func() -> bool: return Vision.token_pos(s.state.token(s.scene_id(), str(tk.id))) == from, "the move back")
		else:
			say.call("  move refused locally (%s) — fine, the table's turn mode says so" % why)
			check(true, "refusal reason given")
	s.leave()
