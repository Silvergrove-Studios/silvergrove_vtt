extends TestCase
## Hex grid maths.


func test_axial_world_roundtrip() -> void:
	for orient in [HexGrid.Orient.POINTY, HexGrid.Orient.FLAT]:
		for off in [HexGrid.Offset.ODD, HexGrid.Offset.EVEN]:
			var g := HexGrid.new(orient, off, 12, 9)
			for cell in g.all_cells():
				var c := g.cell_center(cell)
				check(g.world_to_axial(c) == cell, "centre roundtrip %s %s %s" % [orient, off, cell])
				# A point near a corner still lands in the right cell.
				var corners := g.cell_corners(cell)
				for k in corners:
					var p: Vector2 = c.lerp(k, 0.9)
					check(g.world_to_axial(p) == cell, "near-corner roundtrip %s %s %s" % [orient, off, cell])


func test_offset_roundtrip() -> void:
	for orient in [HexGrid.Orient.POINTY, HexGrid.Orient.FLAT]:
		for off in [HexGrid.Offset.ODD, HexGrid.Offset.EVEN]:
			var g := HexGrid.new(orient, off, 7, 5)
			for row in g.rows:
				for col in g.columns:
					var a := g.offset_to_axial(col, row)
					check(g.axial_to_offset(a) == Vector2i(col, row), "offset roundtrip %s %s (%d,%d)" % [orient, off, col, row])
					check(g.in_bounds(a), "in bounds")
			check(not g.in_bounds(g.offset_to_axial(-1, 0)), "out of bounds left")
			check(not g.in_bounds(g.offset_to_axial(g.columns, 0)), "out of bounds right")


func test_layout_matches_foundry_convention() -> void:
	# Pointy, odd: cell (0,0) bounding box at origin; row 1 is shifted right.
	var g := HexGrid.new(HexGrid.Orient.POINTY, HexGrid.Offset.ODD, 4, 4)
	var c00 := g.cell_center(g.offset_to_axial(0, 0))
	check(near(c00.x, 0.5) and near(c00.y, HexGrid.R), "pointy origin cell centre %s" % c00)
	var c01 := g.cell_center(g.offset_to_axial(0, 1))
	check(near(c01.x, 1.0), "odd row shifted right: %s" % c01)
	check(near(c01.y, HexGrid.R * 2.5), "row pitch is 1.5R: %s" % c01)
	var s := g.map_size()
	check(near(s.x, 4.5) and near(s.y, 2.0 * HexGrid.R + 3 * 1.5 * HexGrid.R), "pointy map size %s" % s)
	check(g.foundry_grid_type() == 2, "HEXODDR")
	# Flat, even: column 0 is shifted down.
	var f := HexGrid.new(HexGrid.Orient.FLAT, HexGrid.Offset.EVEN, 4, 4)
	var f00 := f.cell_center(f.offset_to_axial(0, 0))
	check(near(f00.x, HexGrid.R) and near(f00.y, 1.0), "flat/even origin cell shifted down %s" % f00)
	var f10 := f.cell_center(f.offset_to_axial(1, 0))
	check(near(f10.y, 0.5), "flat/even column 1 not shifted %s" % f10)
	check(f.foundry_grid_type() == 5, "HEXEVENQ")


func test_corners_are_unit_hex() -> void:
	var g := HexGrid.new()
	var pts := g.cell_corners(Vector2i.ZERO)
	check(pts.size() == 6, "six corners")
	var c := g.cell_center(Vector2i.ZERO)
	for p in pts:
		check(near(p.distance_to(c), HexGrid.R), "corner at circumradius")
	# Flat-to-flat width is exactly 1.
	var xs := []
	for p in pts:
		xs.append(p.x)
	xs.sort()
	check(near(xs[-1] - xs[0], 1.0), "flat-to-flat width 1 (pointy)")


func test_distance_and_line() -> void:
	check(HexGrid.axial_distance(Vector2i(0, 0), Vector2i(3, -1)) == 3, "distance")
	var l := HexGrid.line(Vector2i(0, 0), Vector2i(3, -1))
	check(l.size() == 4 and l[0] == Vector2i(0, 0) and l[-1] == Vector2i(3, -1), "line endpoints %s" % [l])
	check(HexGrid.spiral(Vector2i.ZERO, 1).size() == 7, "radius-1 spiral has 7 cells")
	check(HexGrid.spiral(Vector2i.ZERO, 2).size() == 19, "radius-2 spiral has 19 cells")


func test_snap_to_corner() -> void:
	var g := HexGrid.new()
	var corner := g.cell_corners(Vector2i(2, 1))[3]
	var snapped := g.snap_to_corner(corner + Vector2(0.03, -0.02))
	check(snapped.distance_to(corner) < 1e-6, "snaps to nearest corner")
