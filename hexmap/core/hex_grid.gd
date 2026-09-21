class_name HexGrid
extends RefCounted
## The grid — hex or square. Everything the rest of the app needs to know
## about where cells are lives here; nothing else does trigonometry. The
## class keeps its name from when every grid was a hex grid; `shape` says
## which it is, and every question below is answered for both.
##
## Units: one "hex unit" is the grid size — the flat-to-flat width of a hex
## (twice the inradius), or the side of a square. That is the number a
## physical map is described by ("1-inch hexes", "1-inch squares") and the
## number Foundry calls `grid.size`, so scaling to pixels or points is a
## single multiplication everywhere else.
##
## Cells are addressed in axial coordinates (q, r) internally and stored that
## way in files. Offset coordinates (col, row) exist for the map bounds, for
## importers/exporters that want them, and for the status bar. On a square
## grid the two are the same thing: q is the column, r the row.
##
## Orient POINTY: hexes sit in horizontal rows, alternate rows are shifted
## right by half a hex ("odd-r"/"even-r"). FLAT: vertical columns, alternate
## columns shifted down ("odd-q"/"even-q"). `offset` says which parity is
## shifted. This is exactly Foundry's HEXODDR / HEXEVENR / HEXODDQ / HEXEVENQ.
## Squares ignore both.
##
## Distances: `steps(a, b)` counts cell steps — hex steps on a hex grid,
## Chebyshev (a diagonal is one step) on squares, with `diagonals(a, b)`
## saying how many of those steps were diagonal so a ruleset can price them
## as it likes (5-10-5, every diagonal 5, Euclidean).

enum Orient { POINTY, FLAT }
enum Offset { ODD, EVEN }
enum Shape { HEX, SQUARE }

const SQRT3 := 1.7320508075688772
## Circumradius of a hex whose flat-to-flat width is 1.
const R := 1.0 / SQRT3
## Inradius (half the flat-to-flat width).
const I := 0.5

const AXIAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const SQUARE_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1),
]
const SQUARE_DIAGONALS: Array[Vector2i] = [
	Vector2i(1, -1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

var shape: Shape = Shape.HEX
var orientation: Orient = Orient.POINTY
var offset: Offset = Offset.ODD
## Map bounds, in offset coordinates.
var columns: int = 20
var rows: int = 14
## What one hex means in the game: `distance` `units` (5 ft, 1 m, 2 km...).
var distance: float = 5.0
var units: String = "ft"


func _init(p_orient := Orient.POINTY, p_offset := Offset.ODD, p_columns := 20, p_rows := 14, p_shape := Shape.HEX) -> void:
	shape = p_shape
	orientation = p_orient
	offset = p_offset
	columns = p_columns
	rows = p_rows


static func square(p_columns := 20, p_rows := 14) -> HexGrid:
	return HexGrid.new(Orient.POINTY, Offset.ODD, p_columns, p_rows, Shape.SQUARE)


func is_square() -> bool:
	return shape == Shape.SQUARE


## How many corners a cell has.
func corner_count() -> int:
	return 4 if shape == Shape.SQUARE else 6


# ------------------------------------------------------------- serialisation --

func to_dict() -> Dictionary:
	return {
		"shape": "square" if shape == Shape.SQUARE else "hex",
		"orientation": "pointy" if orientation == Orient.POINTY else "flat",
		"offset": "odd" if offset == Offset.ODD else "even",
		"columns": columns,
		"rows": rows,
		"distance": distance,
		"units": units,
	}


static func from_dict(d: Dictionary) -> HexGrid:
	var g := HexGrid.new()
	g.shape = Shape.SQUARE if str(d.get("shape", "hex")) == "square" else Shape.HEX
	g.orientation = Orient.FLAT if str(d.get("orientation", "pointy")) == "flat" else Orient.POINTY
	g.offset = Offset.EVEN if str(d.get("offset", "odd")) == "even" else Offset.ODD
	g.columns = int(d.get("columns", 20))
	g.rows = int(d.get("rows", 14))
	g.distance = float(d.get("distance", 5.0))
	g.units = str(d.get("units", "ft"))
	return g


func duplicate_grid() -> HexGrid:
	return HexGrid.from_dict(to_dict())


# ------------------------------------------------------------------ geometry --

## Centre of a cell, in hex units. Cell (col 0, row 0) has its bounding box's
## top-left corner at the origin, which is what Foundry and Tiled assume too.
func axial_to_world(q: int, r: int) -> Vector2:
	if shape == Shape.SQUARE:
		return Vector2(q + 0.5, r + 0.5)
	if orientation == Orient.POINTY:
		var x := (q + r * 0.5) + I
		var y := r * 1.5 * R + R
		if offset == Offset.EVEN:
			x += I
		return Vector2(x, y)
	else:
		var x := q * 1.5 * R + R
		var y := (r + q * 0.5) + I
		if offset == Offset.EVEN:
			y += I
		return Vector2(x, y)


func cell_center(cell: Vector2i) -> Vector2:
	return axial_to_world(cell.x, cell.y)


## The cell under a point (hex units). Inverse of axial_to_world with cube
## rounding, so it is exact at the centres and fair at the edges.
func world_to_axial(p: Vector2) -> Vector2i:
	if shape == Shape.SQUARE:
		return Vector2i(floori(p.x), floori(p.y))
	var fq: float
	var fr: float
	if orientation == Orient.POINTY:
		var x := p.x - I - (I if offset == Offset.EVEN else 0.0)
		var y := p.y - R
		fr = y / (1.5 * R)
		fq = x - fr * 0.5
	else:
		var x := p.x - R
		var y := p.y - I - (I if offset == Offset.EVEN else 0.0)
		fq = x / (1.5 * R)
		fr = y - fq * 0.5
	return _cube_round(fq, fr)


static func _cube_round(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var q := roundi(fq)
	var r := roundi(fr)
	var s := roundi(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)


## The corners of a cell (six, or four on squares), clockwise on screen,
## in hex units.
func cell_corners(cell: Vector2i) -> PackedVector2Array:
	return corners_at(cell_center(cell))


func corners_at(c: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if shape == Shape.SQUARE:
		pts.resize(4)
		pts[0] = c + Vector2(-I, -I)
		pts[1] = c + Vector2(I, -I)
		pts[2] = c + Vector2(I, I)
		pts[3] = c + Vector2(-I, I)
		return pts
	pts.resize(6)
	var start := -30.0 if orientation == Orient.POINTY else 0.0
	for i in 6:
		var a := deg_to_rad(start + 60.0 * i)
		pts[i] = c + Vector2(cos(a), sin(a)) * R
	return pts


## Nearest hex corner to a point; walls like to snap here.
func snap_to_corner(p: Vector2) -> Vector2:
	var best := p
	var best_d := INF
	var cell := world_to_axial(p)
	for n in [cell] + neighbors(cell):
		for c in cell_corners(n):
			var d := c.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = c
	return best


## Nearest cell centre. Props and lights snap here (centres are what you
## want most of the time).
func snap_to_center(p: Vector2) -> Vector2:
	return cell_center(world_to_axial(p))


## The cells sharing an edge with this one; on squares, `diagonals` adds
## the four that share only a corner.
func neighbors(cell: Vector2i, diagonals := false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if shape == Shape.SQUARE:
		for d in SQUARE_DIRECTIONS:
			out.append(cell + d)
		if diagonals:
			for d in SQUARE_DIAGONALS:
				out.append(cell + d)
		return out
	for d in AXIAL_DIRECTIONS:
		out.append(cell + d)
	return out


## Steps between two cells: hex steps, or Chebyshev on squares (a diagonal
## step counts one).
func steps(a: Vector2i, b: Vector2i) -> int:
	if shape == Shape.SQUARE:
		return maxi(absi(a.x - b.x), absi(a.y - b.y))
	return axial_distance(a, b)


## How many of the steps between two cells are diagonal: 0 on a hex grid.
func diagonals(a: Vector2i, b: Vector2i) -> int:
	if shape == Shape.SQUARE:
		return mini(absi(a.x - b.x), absi(a.y - b.y))
	return 0


## Hex steps between two axial cells (a hex grid's distance).
static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## Cells within `radius` steps of `center` (inclusive), for brushes: a hex
## of hexes, or a (2r+1)² block of squares.
func spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if shape == Shape.SQUARE:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				out.append(center + Vector2i(dx, dy))
		return out
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			out.append(center + Vector2i(dq, dr))
	return out


## Cells along a straight line from a to b (inclusive), for drag painting.
func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := steps(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		out.append(a)
		return out
	for i in n + 1:
		var t := float(i) / n
		var fq := lerpf(a.x, b.x, t)
		var fr := lerpf(a.y, b.y, t)
		if shape == Shape.SQUARE:
			out.append(Vector2i(roundi(fq + 1e-6), roundi(fr + 1e-6)))
		else:
			out.append(_cube_round(fq + 1e-6, fr + 1e-6))
	return out


# ---------------------------------------------------------- offset coordinates --

func axial_to_offset(cell: Vector2i) -> Vector2i:
	if shape == Shape.SQUARE:
		return cell
	var q := cell.x
	var r := cell.y
	if orientation == Orient.POINTY:
		# odd-r: col = q + (r - (r&1)) / 2 ; even-r: col = q + (r + (r&1)) / 2
		var col := q + ((r - (r & 1)) >> 1 if offset == Offset.ODD else (r + (r & 1)) >> 1)
		return Vector2i(col, r)
	else:
		var row := r + ((q - (q & 1)) >> 1 if offset == Offset.ODD else (q + (q & 1)) >> 1)
		return Vector2i(q, row)


func offset_to_axial(col: int, row: int) -> Vector2i:
	if shape == Shape.SQUARE:
		return Vector2i(col, row)
	if orientation == Orient.POINTY:
		var q := col - ((row - (row & 1)) >> 1 if offset == Offset.ODD else (row + (row & 1)) >> 1)
		return Vector2i(q, row)
	else:
		var r := row - ((col - (col & 1)) >> 1 if offset == Offset.ODD else (col + (col & 1)) >> 1)
		return Vector2i(col, r)


func in_bounds(cell: Vector2i) -> bool:
	var o := axial_to_offset(cell)
	return o.x >= 0 and o.y >= 0 and o.x < columns and o.y < rows


## Every cell of the map, row-major in offset order.
func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in rows:
		for col in columns:
			out.append(offset_to_axial(col, row))
	return out


## Bounding box of the whole map, in hex units, anchored at the origin.
func map_size() -> Vector2:
	if shape == Shape.SQUARE:
		return Vector2(columns, rows)
	if orientation == Orient.POINTY:
		var w := columns + (I if rows > 1 else 0.0)
		var h := 2.0 * R + (rows - 1) * 1.5 * R
		return Vector2(w, h)
	else:
		var w := 2.0 * R + (columns - 1) * 1.5 * R
		var h := rows + (I if columns > 1 else 0.0)
		return Vector2(w, h)


## Foundry's CONST.GRID_TYPES value for this grid.
func foundry_grid_type() -> int:
	if shape == Shape.SQUARE:
		return 1                                  # SQUARE
	if orientation == Orient.POINTY:
		return 2 if offset == Offset.ODD else 3   # HEXODDR / HEXEVENR
	return 4 if offset == Offset.ODD else 5       # HEXODDQ / HEXEVENQ


## Tiled's staggeraxis / staggerindex for this grid (hex only; squares
## are Tiled's orthogonal orientation).
func tiled_stagger() -> Dictionary:
	if shape == Shape.SQUARE:
		return {}
	return {
		"staggeraxis": "y" if orientation == Orient.POINTY else "x",
		"staggerindex": "odd" if offset == Offset.ODD else "even",
	}
