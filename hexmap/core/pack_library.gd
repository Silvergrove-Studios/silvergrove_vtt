class_name PackLibrary
extends RefCounted
## Finds content packs, reads their manifests, and hands out textures at the
## density the caller is drawing at. See docs/pack-format.md.
##
## Packs are read straight off disk (FileAccess / Image.load_from_file), not
## through Godot's importer, so any folder anywhere can be a pack and no
## `.import` files are needed. SVGs are rasterised per density bucket and
## cached; rasters are loaded once.

signal loaded

const DENSITY_BUCKETS: Array[int] = [32, 64, 128, 256, 512, 1024, 2048]

## pack id -> manifest Dictionary (with "_dir" added: absolute directory).
var packs: Dictionary = {}
## Problems found while loading, for the UI to show.
var warnings: PackedStringArray = []
## "ref@variant@bucket" -> Texture2D
var _textures: Dictionary = {}
var _placeholder: Dictionary = {}
var _extra_dirs: PackedStringArray = []


func search_dirs() -> PackedStringArray:
	var dirs := PackedStringArray()
	dirs.append(ProjectSettings.globalize_path("res://packs"))
	dirs.append(ProjectSettings.globalize_path("user://packs"))
	var beside := OS.get_executable_path().get_base_dir().path_join("packs")
	if not dirs.has(beside):
		dirs.append(beside)
	for d in _extra_dirs:
		if not dirs.has(d):
			dirs.append(d)
	return dirs


func set_extra_dirs(dirs: PackedStringArray) -> void:
	_extra_dirs = dirs


func reload() -> void:
	packs.clear()
	warnings.clear()
	_textures.clear()
	for root in search_dirs():
		if not DirAccess.dir_exists_absolute(root):
			continue
		# A search dir may itself be a pack, or hold packs.
		if FileAccess.file_exists(root.path_join("pack.json")):
			_load_pack(root)
			continue
		var da := DirAccess.open(root)
		if da == null:
			continue
		for sub in da.get_directories():
			var dir := root.path_join(sub)
			if FileAccess.file_exists(dir.path_join("pack.json")):
				_load_pack(dir)
	loaded.emit()


func _load_pack(dir: String) -> void:
	var text := FileAccess.get_file_as_string(dir.path_join("pack.json"))
	var json := JSON.new()
	if json.parse(text) != OK:
		warnings.append("%s: pack.json line %d: %s" % [dir, json.get_error_line(), json.get_error_message()])
		return
	var m = json.data
	if not (m is Dictionary) or m.get("format", "") != "silvergrove.pack":
		warnings.append("%s: not a silvergrove.pack manifest" % dir)
		return
	var id := str(m.get("id", ""))
	if id == "":
		warnings.append("%s: pack has no id" % dir)
		return
	if packs.has(id):
		warnings.append("%s: duplicate pack id '%s' (already loaded from %s)" % [dir, id, packs[id]["_dir"]])
		return
	m["_dir"] = dir
	for k in ["terrains", "props", "walls", "lights", "tokens"]:
		if not m.has(k):
			m[k] = []
	packs[id] = m


func pack_ids() -> PackedStringArray:
	var ids := PackedStringArray(packs.keys())
	ids.sort()
	return ids


func pack_version(pack_id: String) -> String:
	return str(packs.get(pack_id, {}).get("pack_version", "0.0.0"))


## Split "pack:asset" into [pack, asset]; [] if malformed.
static func split_ref(ref: String) -> PackedStringArray:
	var i := ref.find(":")
	if i <= 0:
		return PackedStringArray()
	return PackedStringArray([ref.substr(0, i), ref.substr(i + 1)])


## The manifest entry for an asset ref in the given collection
## ("terrains", "props", "walls", "lights", "tokens"), or {} if unknown.
func asset(collection: String, ref: String) -> Dictionary:
	var parts := split_ref(ref)
	if parts.is_empty():
		return {}
	var p: Dictionary = packs.get(parts[0], {})
	for a in p.get(collection, []):
		if a.get("id", "") == parts[1]:
			return a
	return {}


func terrain(ref: String) -> Dictionary: return asset("terrains", ref)
func prop(ref: String) -> Dictionary: return asset("props", ref)
func wall_style(ref: String) -> Dictionary: return asset("walls", ref)
func light_preset(ref: String) -> Dictionary: return asset("lights", ref)
func token_art(ref: String) -> Dictionary: return asset("tokens", ref)


## All assets of a collection across packs, each with "_ref" and "_pack" set.
func all(collection: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pid in pack_ids():
		for a in packs[pid].get(collection, []):
			var d: Dictionary = a.duplicate()
			d["_ref"] = "%s:%s" % [pid, a.get("id", "")]
			d["_pack"] = pid
			out.append(d)
	return out


# ------------------------------------------------------------------- textures --

static func bucket_for(ppx: float) -> int:
	for b in DENSITY_BUCKETS:
		if b >= ppx:
			return b
	return DENSITY_BUCKETS[-1]


## Texture for a terrain variant at roughly `ppx` pixels per hex.
func terrain_texture(ref: String, variant: int, ppx: float) -> Texture2D:
	var t := terrain(ref)
	var files: Array = t.get("textures", [])
	if files.is_empty():
		return placeholder(Color(t.get("color", "#ff00ff")))
	var file: String = files[posmod(variant, files.size())]
	# A hex-fit texture is about one hex wide; a square one tiles, so
	# rasterise it around one hex too.
	return _texture(split_ref(ref)[0], file, 1.25 * ppx, "%s@%d" % [ref, variant])


## Texture for a prop at roughly `ppx` pixels per hex; sized by its footprint.
func prop_texture(ref: String, ppx: float) -> Texture2D:
	var p := prop(ref)
	var file := str(p.get("texture", ""))
	if file == "":
		return placeholder(Color.MAGENTA)
	var size: Array = p.get("size", [1, 1])
	return _texture(split_ref(ref)[0], file, float(size[0]) * ppx, ref)


## Texture for a token's art, sized to fill `size` hexes at `ppx`; null when
## the ref is unknown so the caller draws its plain disc instead.
func token_texture(ref: String, ppx: float, size := 1.0) -> Texture2D:
	var t := token_art(ref)
	var file := str(t.get("texture", ""))
	if file == "":
		return null
	return _texture(split_ref(ref)[0], file, size * ppx, ref)


func wall_texture(ref: String, ppx: float) -> Texture2D:
	var w := wall_style(ref)
	var file := str(w.get("texture", ""))
	if file == "":
		return null
	return _texture(split_ref(ref)[0], file, ppx, ref)


func _texture(pack_id: String, file: String, target_px: float, key: String) -> Texture2D:
	var bucket := bucket_for(target_px)
	var ck := "%s@%d" % [key, bucket]
	if _textures.has(ck):
		return _textures[ck]
	var p: Dictionary = packs.get(pack_id, {})
	var path: String = str(p.get("_dir", "")).path_join(file)
	var img := _load_image(path, bucket)
	var tex: Texture2D
	if img == null:
		warnings.append("missing texture: " + path)
		tex = placeholder(Color.MAGENTA)
	else:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_textures[ck] = tex
	return tex


static func _load_image(path: String, target_px: int) -> Image:
	if not FileAccess.file_exists(path):
		return null
	if path.get_extension().to_lower() == "svg":
		var buf := FileAccess.get_file_as_bytes(path)
		var probe := Image.new()
		if probe.load_svg_from_buffer(buf, 1.0) != OK or probe.get_width() == 0:
			return null
		var scale := float(target_px) / maxf(1.0, float(probe.get_width()))
		if absf(scale - 1.0) < 0.01:
			return probe
		var img := Image.new()
		if img.load_svg_from_buffer(buf, clampf(scale, 0.05, 64.0)) != OK:
			return null
		return img
	var img := Image.load_from_file(path)
	return img


## A flat swatch, for missing art. Cached per colour.
func placeholder(color: Color) -> Texture2D:
	var k := color.to_html()
	if _placeholder.has(k):
		return _placeholder[k]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(color)
	# Diagonal hatch so it is obviously not real art.
	for i in 64:
		img.set_pixel(i, i, color.darkened(0.4))
		img.set_pixel(i, 63 - i, color.darkened(0.4))
	var tex := ImageTexture.create_from_image(img)
	_placeholder[k] = tex
	return tex
