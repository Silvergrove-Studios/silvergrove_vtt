class_name MapRenderer
extends RefCounted
## Renders a region of a map to an Image at any density, off screen, using
## the same MapCanvas the editor shows. Big renders are done in tiles so no
## single viewport exceeds what the GPU is happy with.
##
## Needs a live renderer: this does not work under --headless. The CLI
## exporter opens a small window for the duration instead.

const MAX_TILE := 4096

## Options: level (int), show_grid, show_walls, show_lights, show_notes,
## show_hidden (bools), darkness (float), grid_color (Color), texture_ppx.
static func render(host: Node, map: HexMap, packs: PackLibrary, ppx: float, region_hex: Rect2, opts: Dictionary = {}) -> Image:
	var origin_px := region_hex.position * ppx
	var size_px := Vector2i((region_hex.size * ppx).ceil())
	size_px.x = maxi(size_px.x, 1)
	size_px.y = maxi(size_px.y, 1)
	var result := Image.create(size_px.x, size_px.y, false, Image.FORMAT_RGBA8)

	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var canvas := MapCanvas.new()
	canvas.map = map
	canvas.packs = packs
	canvas.level_index = int(opts.get("level", 0))
	canvas.ppx = ppx
	canvas.texture_ppx = float(opts.get("texture_ppx", ppx))
	canvas.show_grid = bool(opts.get("show_grid", true))
	canvas.show_walls = bool(opts.get("show_walls", false))
	canvas.show_lights = bool(opts.get("show_lights", false))
	canvas.show_notes = bool(opts.get("show_notes", false))
	canvas.show_hidden = bool(opts.get("show_hidden", false))
	canvas.darkness = float(opts.get("darkness", 0.0))
	if opts.has("grid_color"):
		canvas.grid_color_override = opts.grid_color
	vp.add_child(canvas)
	host.add_child(vp)

	var ty := 0
	while ty < size_px.y:
		var th := mini(MAX_TILE, size_px.y - ty)
		var tx := 0
		while tx < size_px.x:
			var tw := mini(MAX_TILE, size_px.x - tx)
			vp.size = Vector2i(tw, th)
			canvas.position = -(origin_px + Vector2(tx, ty))
			canvas.refresh()
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var tile := vp.get_texture().get_image()
			tile.convert(Image.FORMAT_RGBA8)
			result.blit_rect(tile, Rect2i(0, 0, tw, th), Vector2i(tx, ty))
			tx += tw
		ty += th

	host.remove_child(vp)
	vp.queue_free()
	return result


## Convenience: the whole map at `ppx`.
static func render_map(host: Node, map: HexMap, packs: PackLibrary, ppx: float, opts: Dictionary = {}) -> Image:
	return await render(host, map, packs, ppx, Rect2(Vector2.ZERO, map.grid.map_size()), opts)


## Flatten transparency onto a colour (paper white for print).
static func flatten(img: Image, background: Color) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(background)
	var src := img.duplicate()
	src.convert(Image.FORMAT_RGBA8)
	out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)
	out.convert(Image.FORMAT_RGB8)
	return out
