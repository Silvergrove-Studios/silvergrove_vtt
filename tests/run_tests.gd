extends SceneTree
## godot --headless -s tests/run_tests.gd [-- <filter>] — run the unit
## tests (tests/test_suite.gd) with no window. The run fails if any check
## fails. The same suite runs inside a build as the app's self-test mode.

var _ran := false


## Tests run on the first frame, not from _init(): by then the root Window
## is inside the tree, so Controls added under it get _ready() and paths.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var suite := TestSuite.new(self)
	await suite.run_all(args[0] if args.size() > 0 else "")
	quit(1 if suite.fails > 0 else 0)
