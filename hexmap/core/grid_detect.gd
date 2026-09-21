class_name GridDetect
extends RefCounted
## Finds the printed grid on a battle-map image: how many pixels one cell
## is, and where the lines fall. Grid lines are the strongest *periodic*
## edges in the picture, so the column-wise sum of horizontal contrast
## (and the row-wise sum of vertical contrast) is a signal whose period
## is the cell size and whose phase is the origin; autocorrelation finds
## the period, a phase scan the origin. Works for square grids drawn as
## lines (most published maps); a gridless painting comes back with a low
## confidence and the user drags two corners instead.

const MAX_SIDE := 2048
const MIN_PERIOD := 6


## {ppc, ox, oy, confidence, error}: pixels per cell, the image pixel a
## grid corner falls on (0 ≤ ox, oy < ppc), and 0–1 confidence (below
## about 0.15 there is no grid to speak of).
static func detect(img: Image) -> Dictionary:
	if img == null or img.get_width() < 2 * MIN_PERIOD or img.get_height() < 2 * MIN_PERIOD:
		return {"ppc": 0.0, "ox": 0.0, "oy": 0.0, "confidence": 0.0, "error": "image too small"}
	var work := img.duplicate() as Image
	work.convert(Image.FORMAT_RGBA8)
	var scale := 1.0
	var longest := maxi(work.get_width(), work.get_height())
	if longest > MAX_SIDE:
		scale = float(longest) / MAX_SIDE
		work.resize(int(work.get_width() / scale), int(work.get_height() / scale), Image.INTERPOLATE_BILINEAR)
	var w := work.get_width()
	var h := work.get_height()
	# luminance, then contrast between neighbours along each axis
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for y in h:
		for x in w:
			var c := work.get_pixel(x, y)
			lum[y * w + x] = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	var cols := PackedFloat32Array()
	cols.resize(w)
	var rows := PackedFloat32Array()
	rows.resize(h)
	for y in h:
		for x in w:
			var v := lum[y * w + x]
			if x + 1 < w:
				cols[x] += absf(lum[y * w + x + 1] - v)
			if y + 1 < h:
				rows[y] += absf(lum[(y + 1) * w + x] - v)
	var px := _period(cols)
	var py := _period(rows)
	if px.period <= 0 and py.period <= 0:
		return {"ppc": 0.0, "ox": 0.0, "oy": 0.0, "confidence": 0.0, "error": "no grid found"}
	# the two axes should agree; take the better one when they do not
	var period: float
	var conf: float
	if px.period > 0 and py.period > 0 and absf(px.period - py.period) <= 0.06 * maxf(px.period, py.period):
		period = (px.period + py.period) * 0.5
		conf = (px.confidence + py.confidence) * 0.5
	elif px.confidence >= py.confidence:
		period = px.period
		conf = px.confidence
	else:
		period = py.period
		conf = py.confidence
	# contrast between x and x+1 belongs to x + 0.5: the line itself
	var ox := fmod(_phase(cols, period) + 0.5, period) if px.period > 0 else 0.0
	var oy := fmod(_phase(rows, period) + 0.5, period) if py.period > 0 else 0.0
	return {"ppc": period * scale, "ox": ox * scale, "oy": oy * scale, "confidence": conf, "error": ""}


## The period of a profile by normalised autocorrelation: the lag with the
## strongest correlation, refined to sub-pixel by its neighbours.
## {period, confidence}; period 0 when nothing periodic stands out.
static func _period(profile: PackedFloat32Array) -> Dictionary:
	var n := profile.size()
	var mean := 0.0
	for v in profile:
		mean += v
	mean /= maxf(1.0, n)
	var d := PackedFloat32Array()
	d.resize(n)
	var energy := 0.0
	for i in n:
		d[i] = profile[i] - mean
		energy += d[i] * d[i]
	if energy <= 1e-9:
		return {"period": 0.0, "confidence": 0.0}
	var best_lag := 0
	var best := 0.0
	var corr := PackedFloat32Array()
	var max_lag := n / 3
	corr.resize(max_lag + 1)
	# prefix sums of the squares, for the energy of each overlap
	var sq := PackedFloat32Array()
	sq.resize(n + 1)
	for i in n:
		sq[i + 1] = sq[i] + d[i] * d[i]
	for lag in range(MIN_PERIOD, max_lag + 1):
		var s := 0.0
		for i in n - lag:
			s += d[i] * d[i + lag]
		# normalised by the two overlapping halves' energies, so long lags
		# are not favoured for having fewer terms
		var e1 := sq[n - lag]
		var e2 := sq[n] - sq[lag]
		var c := s / maxf(1e-9, sqrt(e1 * e2))
		corr[lag] = c
		if c > best:
			best = c
			best_lag = lag
	if best_lag == 0 or best < 0.12:
		return {"period": 0.0, "confidence": maxf(0.0, best)}
	# every multiple of the true period correlates about as well; the
	# period is the shortest lag that peaks nearly as high as the best
	for lag in range(MIN_PERIOD, best_lag):
		if corr[lag] >= best * 0.8 and _is_peak(corr, lag):
			best_lag = lag
			best = corr[lag]
			break
	var period := float(best_lag)
	if best_lag > MIN_PERIOD and best_lag < max_lag:
		# parabolic refinement around the peak
		var l := corr[best_lag - 1]
		var r := corr[best_lag + 1]
		var denom := l - 2.0 * best + r
		if absf(denom) > 1e-9:
			period += 0.5 * (l - r) / denom
	return {"period": period, "confidence": clampf(best, 0.0, 1.0)}


static func _is_peak(corr: PackedFloat32Array, lag: int) -> bool:
	return lag > 0 and lag + 1 < corr.size() and corr[lag] >= corr[lag - 1] and corr[lag] >= corr[lag + 1]


## Where the lines fall: the offset in [0, period) whose comb of samples
## catches the most contrast.
static func _phase(profile: PackedFloat32Array, period: float) -> float:
	var n := profile.size()
	var best := 0.0
	var best_o := 0.0
	var steps := maxi(4, int(period * 4.0))
	for s in steps:
		var o := period * s / steps
		var sum := 0.0
		var x := o
		while x < n:
			sum += profile[int(x)]
			x += period
		if sum > best:
			best = sum
			best_o = o
	return best_o


# ------------------------------------------------------------ fitting --

## A backdrop record from a fit in image pixels: `ppc` pixels make one
## cell (x and y may differ on a stretched scan), and the image pixel
## (ox, oy) is a cell corner. The image's top-left lands at `pos` (up-left
## of the map's origin by less than a cell) and it spans `size` cells.
static func fit_from_pixels(img_size: Vector2i, backdrop: Dictionary, ppc_x: float, ppc_y: float, ox: float, oy: float) -> Dictionary:
	ppc_x = maxf(1e-6, ppc_x)
	ppc_y = maxf(1e-6, ppc_y)
	var out: Dictionary = backdrop.duplicate(true)
	var cx := fposmod(ox, ppc_x)
	var cy := fposmod(oy, ppc_y)
	out.pos = [snappedf(-cx / ppc_x, 0.0001), snappedf(-cy / ppc_y, 0.0001)]
	out.size = [snappedf(img_size.x / ppc_x, 0.0001), snappedf(img_size.y / ppc_y, 0.0001)]
	return out


## Two grid corners dragged on the map, `cols` cells apart across and
## `rows` down: the fit that puts lines through both. Points are in hex
## units on the current backdrop; the cell size comes from the span.
static func fit_from_corners(img_size: Vector2i, backdrop: Dictionary, a: Vector2, b: Vector2, cols: int, rows: int) -> Dictionary:
	var pa := to_image_px(backdrop, img_size, a)
	var pb := to_image_px(backdrop, img_size, b)
	var span := (pb - pa).abs()
	var ppc_x := span.x / maxi(1, cols)
	var ppc_y := span.y / maxi(1, rows) if rows > 0 and span.y > 1.0 else ppc_x
	var origin := Vector2(minf(pa.x, pb.x), minf(pa.y, pb.y))
	return fit_from_pixels(img_size, backdrop, ppc_x, ppc_y, origin.x, origin.y)


## A point in hex units → the backdrop image's pixel under it.
static func to_image_px(backdrop: Dictionary, img_size: Vector2i, p: Vector2) -> Vector2:
	var pos: Array = backdrop.get("pos", [0, 0])
	var size: Array = backdrop.get("size", [1, 1])
	return Vector2((p.x - float(pos[0])) / maxf(1e-6, float(size[0])) * img_size.x, (p.y - float(pos[1])) / maxf(1e-6, float(size[1])) * img_size.y)


## How many pixels of the backdrop make one cell now (x, y).
static func current_ppc(backdrop: Dictionary, img_size: Vector2i) -> Vector2:
	var size: Array = backdrop.get("size", [1, 1])
	return Vector2(img_size.x / maxf(1e-6, float(size[0])), img_size.y / maxf(1e-6, float(size[1])))
