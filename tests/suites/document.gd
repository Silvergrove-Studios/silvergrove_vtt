extends TestCase
## Map documents and history.


func test_map_json_roundtrip() -> void:
	var m := HexMap.create("Test", HexGrid.new(HexGrid.Orient.FLAT, HexGrid.Offset.EVEN, 5, 4))
	var lvl := m.level(0)
	lvl["terrain"]["0,0"] = {"t": "woodland:grass", "v": 1, "rot": 0, "z": 0}
	lvl["props"].append({"id": "p_1", "asset": "woodland:oak_large", "pos": [1.25, 2.5], "rot": 15.0, "scale": 1.0})
	var text := m.to_json()
	var err := []
	var m2 := HexMap.from_json(text, err)
	check(m2 != null, "parses back: %s" % [err])
	if m2 == null:
		return
	check(m2.grid.orientation == HexGrid.Orient.FLAT and m2.grid.offset == HexGrid.Offset.EVEN, "grid preserved")
	check(m2.level(0)["terrain"]["0,0"]["t"] == "woodland:grass", "terrain preserved")
	check(m2.level(0)["props"][0]["pos"][0] == 1.25, "prop position preserved")
	check(m2.to_json() == text, "stable serialisation")
	var bad := HexMap.from_json("{\"format\": \"nope\"}", err)
	check(bad == null, "rejects foreign documents")


func test_history() -> void:
	var h := History.new()
	var v := [0]
	h.commit("set 1", func(): v[0] = 1, func(): v[0] = 0)
	h.commit("set 2", func(): v[0] = 2, func(): v[0] = 1)
	check(v[0] == 2, "commits run redo")
	h.undo()
	check(v[0] == 1, "undo one")
	h.undo()
	check(v[0] == 0, "undo two")
	check(not h.can_undo(), "stack empty")
	h.redo()
	h.redo()
	check(v[0] == 2 and not h.can_redo(), "redo both")
	h.begin_group()
	h.commit("a", func(): v[0] = 10, func(): v[0] = 2)
	h.commit("b", func(): v[0] = 11, func(): v[0] = 10)
	h.end_group("stroke")
	check(v[0] == 11, "group applied")
	h.undo()
	check(v[0] == 2, "group undone as one step: %d" % v[0])
