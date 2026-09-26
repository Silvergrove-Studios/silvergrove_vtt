class_name Lighting
extends RefCounted
## Light-versus-wall geometry for the editor's lighting preview: which wall
## segments block light, and the polygon a light at `origin` can reach
## within `radius`. Pure functions in hex units; unit-tested.
##
## VTTs do their own lighting from the exported walls; this exists so what
## you see while editing is honest about where a torch reaches.

## Segments from a level's walls that block `what` ("light" for lights,
## "sight" for vision): [{a, b, one_way, limited}] where one_way is 0 both /
## 1 left / 2 right (right-hand rule walking a -> b), and limited is a wall of
## sight mode "limited" (terrain: a stream bank, tall grass), seen across but
## not through: only the second one a ray crosses blocks it. Open doors never
## block.
static func blocking_segments(level: Dictionary, visible: Dictionary = {}, what := "light") -> Array:
	var out: Array = []
	for w in level.get("walls", []):
		if not visible.is_empty() and not visible.get(LayerTree.ref("walls", str(w.get("id", ""))), true):
			continue
		var blocks: Dictionary = w.get("blocks", {})
		if not bool(blocks.get(what, true)):
			continue
		if str(w.get("door", "none")) != "none" and str(w.get("state", "closed")) == "open":
			continue
		var pts: Array = w.get("points", [])
		var one_way := 0
		match w.get("one_way", null):
			"left": one_way = 1
			"right": one_way = 2
		# (light through a wall that blocks it but not sight is blocked whole,
		# as the Foundry export has it)
		var limited := str(w.get("sight_mode", "normal")) == "limited" and (what == "sight" or bool(blocks.get("sight", true)))
		for i in pts.size() - 1:
			out.append({
				"a": Vector2(float(pts[i][0]), float(pts[i][1])),
				"b": Vector2(float(pts[i + 1][0]), float(pts[i + 1][1])),
				"one_way": one_way,
				"limited": limited,
			})
	return out


## Only the segments that can matter for a light: within `radius` of origin.
static func nearby(segments: Array, origin: Vector2, radius: float) -> Array:
	var out: Array = []
	for s in segments:
		var q := Geometry2D.get_closest_point_to_segment(origin, s.a, s.b)
		if q.distance_to(origin) <= radius:
			out.append(s)
	return out


## Distance along the ray (origin, dir) to the nearest blocking segment, or
## INF. One-way segments block only rays arriving from their blocking side;
## limited ones only where the ray crosses its second (a playtest's players
## saw nothing across a stream: its bank hid the whole far side).
static func ray_hit(origin: Vector2, dir: Vector2, segments: Array, max_t: float) -> float:
	var best := INF
	var limited := PackedFloat32Array()
	for s in segments:
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var e := b - a
		var denom := dir.cross(e)
		if absf(denom) < 1e-9:
			continue
		var d := a - origin
		var t := d.cross(e) / denom
		var u := d.cross(dir) / denom
		if t <= 1e-6 or t >= best or t > max_t or u < -1e-6 or u > 1.0 + 1e-6:
			continue
		if s.one_way != 0:
			# Right-hand normal of a->b is (e.y, -e.x). "right" blocks rays
			# coming from the right side (travelling against the normal).
			var normal := Vector2(e.y, -e.x)
			var from_right := dir.dot(normal) < 0.0
			if (s.one_way == 2) != from_right:
				continue
		if bool(s.get("limited", false)):
			limited.append(t)
			continue
		best = t
	if limited.size() >= 2:
		limited.sort()
		var crossed := 0
		var last := -INF
		for t in limited:
			if t >= best:
				break
			# (where two segments of one wall meet, the ray crosses once)
			if t - last > 1e-4:
				crossed += 1
				last = t
				if crossed == 2:
					best = t
					break
	return best


## The region a light reaches: a star-shaped polygon around origin, points in
## angular order, clipped to `radius` and to the blocking segments. Rays go
## to every segment endpoint (nudged either side, so edges are sharp) plus a
## ring of `ring_rays` for the round parts.
## `cone_deg` < 360 limits the polygon to a cone facing `direction_deg`; the
## origin is then included as the first point so the shape closes at the light.
static func visibility_polygon(origin: Vector2, radius: float, segments: Array, ring_rays := 48, cone_deg := 360.0, direction_deg := 0.0) -> PackedVector2Array:
	var segs := nearby(segments, origin, radius)
	var packed := _pack(segs, origin)
	var cone := cone_deg < 359.999
	var half := deg_to_rad(cone_deg) / 2.0
	var facing := deg_to_rad(direction_deg)
	var angles := PackedFloat32Array()
	if cone:
		var n := maxi(4, int(ring_rays * cone_deg / 360.0))
		for i in n + 1:
			angles.append(facing - half + 2.0 * half * i / n)
	else:
		# Same [-PI, PI) range as Vector2.angle(), or the sort goes round twice.
		for i in ring_rays:
			angles.append(wrapf(TAU * i / ring_rays, -PI, PI))
	var eps := 0.0007
	for s in segs:
		for p in [s.a, s.b]:
			var a: float = (p - origin).angle()
			if cone:
				a = facing + angle_difference(facing, a)
				if absf(a - facing) > half:
					continue
			for da in [-eps, 0.0, eps]:
				angles.append(a + da if cone else wrapf(a + da, -PI, PI))
	angles.sort()
	var pts := PackedVector2Array()
	if cone:
		pts.append(origin)
	var last_angle := -INF
	for a in angles:
		if a - last_angle < 1e-7:
			continue
		last_angle = a
		var dir := Vector2(cos(a), sin(a))
		var t := _packed_hit(origin, dir, packed, radius, a)
		pts.append(origin + dir * minf(t, radius))
	return pts


## Angular bins for the segments a ray can cross: each segment is filed
## under every bin its angle from the origin spans.
const _BINS := 90


## Segments as packed arrays, filed by the angles they span from `origin`:
## a polygon casts hundreds of rays, and by day a token's sight reaches
## every wall on the map — a ray need only try the few in its direction.
static func _pack(segs: Array, origin: Vector2) -> Dictionary:
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	var flags := PackedInt32Array()   # one_way (0, 1, 2) + 4 when limited
	var bins := []
	for k in _BINS:
		bins.append(PackedInt32Array())
	var bw := TAU / _BINS
	for i in segs.size():
		var s: Dictionary = segs[i]
		a.append(s.a)
		b.append(s.b)
		flags.append(int(s.one_way) + (4 if bool(s.get("limited", false)) else 0))
		var ta: float = (s.a - origin).angle()
		var diff: float = angle_difference(ta, (s.b - origin).angle())
		var lo := ta if diff >= 0.0 else ta + diff
		# every bin from a hair before `lo` to a hair past lo + |diff|
		var k0 := int(floor((wrapf(lo - 1e-4, -PI, PI) + PI) / bw))
		for j in int(ceil((absf(diff) + 2e-4) / bw)) + 1:
			var k := (k0 + j) % _BINS
			var bin: PackedInt32Array = bins[k]
			bin.append(i)
			bins[k] = bin
	return {"a": a, "b": b, "flags": flags, "bins": bins}


## ray_hit over packed segments, the ones in the ray's direction: the same
## rules (one-way sides, a limited wall blocking at the second crossing).
static func _packed_hit(origin: Vector2, dir: Vector2, packed: Dictionary, max_t: float, angle: float) -> float:
	var sa: PackedVector2Array = packed.a
	var sb: PackedVector2Array = packed.b
	var flags: PackedInt32Array = packed.flags
	var near: PackedInt32Array = packed.bins[int(floor((wrapf(angle, -PI, PI) + PI) / (TAU / _BINS))) % _BINS]
	var best := INF
	var limited := PackedFloat32Array()
	for i in near:
		var a := sa[i]
		var e := sb[i] - a
		var denom := dir.cross(e)
		if absf(denom) < 1e-9:
			continue
		var d := a - origin
		var t := d.cross(e) / denom
		if t <= 1e-6 or t >= best or t > max_t:
			continue
		var u := d.cross(dir) / denom
		if u < -1e-6 or u > 1.0 + 1e-6:
			continue
		var f := flags[i]
		var one_way := f & 3
		if one_way != 0:
			var from_right := dir.dot(Vector2(e.y, -e.x)) < 0.0
			if (one_way == 2) != from_right:
				continue
		if f & 4:
			limited.append(t)
			continue
		best = t
	if limited.size() >= 2:
		limited.sort()
		var crossed := 0
		var last := -INF
		for t in limited:
			if t >= best:
				break
			if t - last > 1e-4:
				crossed += 1
				last = t
				if crossed == 2:
					best = t
					break
	return best


## The same polygon with every point pulled in to `inner` radius: the bright
## core of a light, still respecting the walls.
static func clamp_radius(origin: Vector2, polygon: PackedVector2Array, inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(polygon.size())
	for i in polygon.size():
		var v := polygon[i] - origin
		out[i] = origin + (v.limit_length(inner) if v.length() > inner else v)
	return out


## Fan triangles (origin, p[i], p[i+1]) as one triangle list, with UVs into a
## radial texture whose centre is the light and whose edge is `radius`.
## Returns {"vertices": PackedVector2Array, "uvs": PackedVector2Array}.
static func fan(origin: Vector2, radius: float, polygon: PackedVector2Array, scale := 1.0) -> Dictionary:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var n := polygon.size()
	if n < 3:
		return {"vertices": verts, "uvs": uvs}
	var uv_of := func(p: Vector2) -> Vector2:
		return (p - origin) / (2.0 * radius) + Vector2(0.5, 0.5)
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		verts.append(origin * scale)
		verts.append(a * scale)
		verts.append(b * scale)
		uvs.append(Vector2(0.5, 0.5))
		uvs.append(uv_of.call(a))
		uvs.append(uv_of.call(b))
	return {"vertices": verts, "uvs": uvs}


## Is `p` lit by a light at origin? (For tests and tooling.)
static func is_lit(origin: Vector2, radius: float, p: Vector2, segments: Array) -> bool:
	var v := p - origin
	var d := v.length()
	if d > radius or d < 1e-9:
		return d <= radius
	return ray_hit(origin, v / d, segments, d) >= d
