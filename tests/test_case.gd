class_name TestCase
extends RefCounted
## A group of tests: subclasses under tests/suites/ define test_* methods
## and assert through the runner (`suite`, a TestSuite). The helpers here
## are the fixtures more than one suite needs.

var suite: TestSuite

var tree: SceneTree:
	get: return suite.tree
var root: Window:
	get: return suite.root
var say: Callable:
	get: return suite.say


func check(cond: bool, msg: String) -> void:
	suite.check(cond, msg)


func skip(why: String) -> void:
	suite.skip(why)


func near(a: float, b: float, eps := 1e-6) -> bool:
	return absf(a - b) <= eps


static func examples_dir() -> String:
	return TestSuite.examples_dir()


static func example(file: String) -> String:
	return TestSuite.example(file)


static func out_dir() -> String:
	return TestSuite.out_dir()


# -------------------------------------------------------------- fixtures --

func _ctx() -> EditorContext:
	var ctx := EditorContext.new()
	ctx.packs = PackLibrary.new()
	ctx.packs.reload()
	ctx.history = History.new()
	ctx.map = HexMap.create("T", HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 10, 8))
	ctx.commands = Commands.new(ctx.map, ctx.history)
	ctx.canvas = MapCanvas.new()
	ctx.canvas.map = ctx.map
	ctx.canvas.packs = ctx.packs
	ctx.canvas.ppx = 256.0
	return ctx


func _chapel() -> HexMap:
	return HexMap.load_file(example("ruined_chapel.hexmap"))


## Example files may have an autosave sidecar from someone's session; the
## windows would offer to restore it instead of opening the example.
func _example(file: String) -> String:
	var p := example(file)
	DirAccess.remove_absolute(p + ".autosave")
	return p


## A small encounter on the chapel: one scene, a party token at the west
## door, one goblin. Returns [state, scene_id, party_token_id, goblin_id].
func _small_encounter() -> Array:
	var m := _chapel()
	var st := EncounterState.new(Encounter.create("Test"))
	st.attach_map(m)
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	st.apply({"t": "scene.add", "scene": sc})
	var g := m.grid
	var hero := Encounter.new_token("Hero", g.cell_center(g.offset_to_axial(3, 7)), {"owner": "pl_1", "vision": {"radius": 6}})
	var gob := Encounter.new_token("Goblin", g.cell_center(g.offset_to_axial(9, 7)), {"hidden": true})
	st.apply({"t": "token.add", "scene": sc.id, "token": hero})
	st.apply({"t": "token.add", "scene": sc.id, "token": gob})
	return [st, sc.id, hero.id, gob.id]


## A TableContext on the example encounter, with a canvas but no window.
func _table_ctx() -> TableContext:
	var ctx := TableContext.new()
	ctx.app = App.new("user://test_prefs_table.json")
	var e := Encounter.load_file(example("chapel_ambush.encounter"))
	ctx.set_encounter(e)
	ctx.state.resolve_maps()
	ctx.canvas = MapCanvas.new()
	ctx.canvas.packs = ctx.app.packs
	ctx.canvas.set_scene(ctx.state, ctx.scene_id)
	ctx.zoom = 1.0
	return ctx


func _door_of(ctx: TableContext) -> Dictionary:
	for w in ctx.map().level_by_id("ground").walls:
		if w.get("door", "none") == "door":
			return w
	return {}
