extends SceneTree
## godot --headless -s tools/gen_pack_art.gd — (re)generate the three example
## packs under packs/: pack.json manifests and deliberately plain SVG
## placeholder art (flat colours, simple shapes, a seeded scatter of detail).
## Real art replaces the SVGs in place; the manifests need not change.

const HEX_H := 115.47   # height of a pointy-top hex 100 wide

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	for pack in [_woodland(), _swamp(), _dungeons()]:
		_write_pack(pack)
	print("packs generated")
	quit(0)


# ============================================================ pack definitions ==

func _woodland() -> Dictionary:
	return {
		"id": "woodland", "name": "Woodland", "pack_version": "0.1.0",
		"description": "Temperate forest floors, trees, camps and clearings. Placeholder art.",
		"terrains": [
			_t("grass", "Grass", "#5b8c3a", "tufts", 3),
			_t("tall_grass", "Tall grass", "#6f9a3c", "tufts_dense", 2),
			_t("forest_floor", "Forest floor", "#4a5a2c", "leaves", 3),
			_t("undergrowth", "Undergrowth", "#3f6b2e", "tufts_dense", 2, ["dense"]),
			_t("dirt_path", "Dirt path", "#8b6b45", "dots", 2),
			_t("rocky_ground", "Rocky ground", "#7d7a70", "pebbles", 2),
			_t("shallow_stream", "Shallow stream", "#4f86a8", "ripples", 2, ["water"]),
			_t("clearing_flowers", "Flower clearing", "#6e9a48", "flowers", 2),
		],
		"props": [
			_p("oak_large", "Large oak", "tree", [2.2, 2.2], [0.5, 0.55], "overhead", {"canopy": "#2f6b2a", "trunk": "#4a3320"}, {"move": true, "sight": false}, 3.0),
			_p("oak", "Oak", "tree", [1.4, 1.4], [0.5, 0.55], "overhead", {"canopy": "#357a30", "trunk": "#4a3320"}, {"move": true, "sight": false}, 2.5),
			_p("pine", "Pine", "pine", [1.2, 1.2], [0.5, 0.5], "overhead", {"canopy": "#2a5a30", "trunk": "#3e2a18"}, {"move": true, "sight": false}, 3.0),
			_p("birch", "Birch", "tree", [1.1, 1.1], [0.5, 0.55], "overhead", {"canopy": "#7fae5a", "trunk": "#d8d8d0"}, {"move": true, "sight": false}, 2.5),
			_p("bush", "Bush", "blob", [0.7, 0.7], [0.5, 0.5], "objects", {"fill": "#3e7a33"}, {"move": false, "sight": true}, 0.6),
			_p("fallen_log", "Fallen log", "log", [1.6, 0.5], [0.5, 0.5], "objects", {"fill": "#6b4a2a"}, {"move": true, "sight": false}, 0.4),
			_p("stump", "Stump", "stump", [0.5, 0.5], [0.5, 0.5], "objects", {"fill": "#7a5a35"}, {"move": true, "sight": false}, 0.3),
			_p("boulder", "Boulder", "rock", [0.9, 0.8], [0.5, 0.6], "objects", {"fill": "#7d7a70"}, {"move": true, "sight": false}, 0.7),
			_p("boulder_small", "Small boulder", "rock", [0.5, 0.45], [0.5, 0.6], "objects", {"fill": "#8a877c"}, {"move": false, "sight": false}, 0.3),
			_p("campfire", "Campfire", "fire", [0.6, 0.6], [0.5, 0.5], "objects", {"fill": "#ff8a2a"}, {"move": false, "sight": false}, 0.3,
				{"bright": 1.5, "dim": 3.0, "color": "#ffa040", "intensity": 1.0, "animation": "torch"}),
			_p("tent", "Tent", "tent", [1.3, 1.3], [0.5, 0.55], "objects", {"fill": "#a8926a"}, {"move": true, "sight": true}, 1.0),
			_p("mushroom_ring", "Mushroom ring", "ring", [1.0, 1.0], [0.5, 0.5], "ground", {"fill": "#d8c8a8"}, {"move": false, "sight": false}, 0.1),
			_p("wooden_fence", "Fence section", "planks", [1.0, 0.2], [0.5, 0.5], "objects", {"fill": "#8b6b45"}, {"move": true, "sight": false}, 0.5),
			_p("hunters_snare", "Hunter's snare", "ring", [0.4, 0.4], [0.5, 0.5], "ground", {"fill": "#5a4a3a"}, {"move": false, "sight": false}, 0.05),
			_p("stream_stones", "Stepping stones", "pebbles", [1.0, 0.5], [0.5, 0.5], "ground", {"fill": "#8a877c"}, {"move": false, "sight": false}, 0.05),
		],
		"walls": [
			_w("wooden_fence", "Wooden fence", "#8b6b45", 0.08, "fence"),
			_w("hedge", "Hedge", "#3e7a33", 0.22, "wall"),
			_w("log_barricade", "Log barricade", "#6b4a2a", 0.18, "wall"),
			_w("stream_bank", "Stream bank", "#4f86a8", 0.06, "terrain"),
		],
		"lights": [
			_l("campfire", "Campfire", 1.5, 3.0, "#ffa040", "torch"),
			_l("lantern", "Lantern", 1.0, 2.0, "#ffd080", "flicker"),
			_l("moonbeam", "Moonbeam", 0.0, 2.0, "#a0c0ff", "none"),
		],
	}


func _swamp() -> Dictionary:
	return {
		"id": "swamp", "name": "Swamp", "pack_version": "0.1.0",
		"description": "Marsh, bog, murky water and what lives on it. Placeholder art.",
		"terrains": [
			_t("marsh_grass", "Marsh grass", "#5f7a3a", "tufts", 3),
			_t("reeds", "Reeds", "#6c8a3e", "tufts_dense", 2, ["dense"]),
			_t("murky_water", "Murky water", "#3f5f4f", "ripples", 2, ["water"]),
			_t("deep_water", "Deep water", "#2b4a48", "ripples", 2, ["water", "deep"]),
			_t("mud", "Mud", "#5e4a35", "dots", 2),
			_t("peat", "Peat", "#4c3d2e", "leaves", 2),
			_t("moss_stone", "Mossy stone", "#58705a", "pebbles", 2),
			_t("rotting_boardwalk", "Rotting boardwalk", "#6b563d", "planks", 2),
		],
		"props": [
			_p("mangrove", "Mangrove", "tree", [1.8, 1.8], [0.5, 0.6], "overhead", {"canopy": "#3b6b3a", "trunk": "#4a3a2a"}, {"move": true, "sight": false}, 2.5),
			_p("dead_tree", "Dead tree", "dead_tree", [1.3, 1.3], [0.5, 0.6], "overhead", {"fill": "#5a4a3a"}, {"move": true, "sight": false}, 2.5),
			_p("cypress_knees", "Cypress knees", "pebbles", [0.8, 0.5], [0.5, 0.5], "objects", {"fill": "#6a5a45"}, {"move": false, "sight": false}, 0.3),
			_p("lily_pads", "Lily pads", "pads", [1.0, 1.0], [0.5, 0.5], "ground", {"fill": "#4f8a4a"}, {"move": false, "sight": false}, 0.02),
			_p("sunken_boat", "Sunken boat", "boat", [1.6, 0.7], [0.5, 0.5], "objects", {"fill": "#5a4630"}, {"move": true, "sight": false}, 0.3),
			_p("witch_hut", "Witch's hut", "hut", [2.5, 2.5], [0.5, 0.55], "objects", {"fill": "#4a3a2a", "roof": "#6a5a40"}, {"move": true, "sight": true}, 2.0),
			_p("rickety_dock", "Rickety dock", "planks", [2.0, 0.8], [0.5, 0.5], "ground", {"fill": "#6b563d"}, {"move": false, "sight": false}, 0.1),
			_p("will_o_wisp", "Will-o'-wisp", "wisp", [0.4, 0.4], [0.5, 0.5], "overhead", {"fill": "#a0ffd0"}, {"move": false, "sight": false}, 1.0,
				{"bright": 0.5, "dim": 1.5, "color": "#a0ffd0", "intensity": 0.8, "animation": "pulse"}),
			_p("bog_gas", "Bog gas", "blob", [1.0, 1.0], [0.5, 0.5], "overhead", {"fill": "#9ab07a", "opacity": 0.5}, {"move": false, "sight": false}, 0.5),
			_p("mossy_stone", "Mossy stone", "rock", [0.7, 0.6], [0.5, 0.6], "objects", {"fill": "#58705a"}, {"move": true, "sight": false}, 0.5),
			_p("hanging_moss", "Hanging moss", "blob", [1.2, 0.6], [0.5, 0.3], "overhead", {"fill": "#7a9a5a", "opacity": 0.8}, {"move": false, "sight": false}, 0.5),
			_p("frog_totem", "Frog totem", "totem", [0.5, 0.5], [0.5, 0.6], "objects", {"fill": "#6a7a4a"}, {"move": true, "sight": false}, 1.2),
			_p("skull_pile", "Skull pile", "pebbles", [0.6, 0.5], [0.5, 0.5], "objects", {"fill": "#d8d0c0"}, {"move": false, "sight": false}, 0.2),
		],
		"walls": [
			_w("boardwalk_rail", "Boardwalk rail", "#6b563d", 0.06, "fence"),
			_w("palisade", "Palisade", "#5a4630", 0.16, "wall"),
			_w("thicket", "Thicket", "#3b6b3a", 0.25, "terrain"),
			_w("water_edge", "Water's edge", "#3f5f4f", 0.05, "invisible"),
		],
		"lights": [
			_l("wisp", "Wisp light", 0.5, 1.5, "#a0ffd0", "pulse"),
			_l("bog_fire", "Bog fire", 1.0, 2.5, "#80ff90", "flicker"),
			_l("hut_lantern", "Hut lantern", 1.0, 2.0, "#ffd080", "flicker"),
		],
	}


func _dungeons() -> Dictionary:
	return {
		"id": "dungeons_and_castles", "name": "Dungeons & Castles", "pack_version": "0.1.0",
		"description": "Stone floors, walls, doors, furniture and fixtures for interiors. Placeholder art.",
		"terrains": [
			_t("flagstone", "Flagstone", "#6e6a63", "flagstones", 3),
			_t("cobblestone", "Cobblestone", "#75716a", "pebbles_dense", 2),
			_t("rough_stone", "Rough stone", "#5a5652", "cracks", 2),
			_t("dirt_floor", "Dirt floor", "#6b5a45", "dots", 2),
			_t("wooden_floor", "Wooden floor", "#7a5a3a", "planks", 2),
			_t("rubble", "Rubble", "#6b655c", "rubble", 2, ["difficult"]),
			_t("pit", "Pit", "#141414", "solid", 1, ["hazard"]),
			_t("stairs", "Stairs", "#6e6a63", "stairs", 1),
			_t("carpet_red", "Red carpet", "#7a2a2a", "border", 1),
			_t("moat_water", "Moat water", "#3f5f7a", "ripples", 2, ["water"]),
			_t("grass_courtyard", "Courtyard grass", "#5b8c3a", "tufts", 2),
		],
		"props": [
			_p("wooden_door", "Wooden door", "door", [1.0, 0.25], [0.5, 0.5], "objects", {"fill": "#6b4a2a"}, {"move": true, "sight": true}, 1.0),
			_p("portcullis", "Portcullis", "bars", [1.0, 0.25], [0.5, 0.5], "objects", {"fill": "#4a4a50"}, {"move": true, "sight": false}, 1.0),
			_p("table", "Table", "table", [1.4, 0.8], [0.5, 0.5], "objects", {"fill": "#7a5a3a"}, {"move": true, "sight": false}, 0.4),
			_p("end_table", "End table", "table", [0.4, 0.4], [0.5, 0.5], "objects", {"fill": "#7a5a3a"}, {"move": false, "sight": false}, 0.35),
			_p("chair", "Chair", "chair", [0.45, 0.45], [0.5, 0.5], "objects", {"fill": "#6b4a2a"}, {"move": false, "sight": false}, 0.5),
			_p("throne", "Throne", "chair", [0.8, 0.8], [0.5, 0.5], "objects", {"fill": "#8a6a2a"}, {"move": true, "sight": false}, 0.9),
			_p("bed", "Bed", "bed", [1.0, 1.8], [0.5, 0.5], "objects", {"fill": "#6b4a2a", "cover": "#8a3a3a"}, {"move": true, "sight": false}, 0.3),
			_p("chest", "Chest", "box", [0.7, 0.5], [0.5, 0.5], "objects", {"fill": "#6b4a2a", "band": "#b09040"}, {"move": true, "sight": false}, 0.3),
			_p("barrel", "Barrel", "barrel", [0.5, 0.5], [0.5, 0.5], "objects", {"fill": "#7a5a3a"}, {"move": true, "sight": false}, 0.5),
			_p("crate", "Crate", "box", [0.6, 0.6], [0.5, 0.5], "objects", {"fill": "#8a6a45", "band": "#6b4a2a"}, {"move": true, "sight": false}, 0.4),
			_p("bookshelf", "Bookshelf", "shelf", [1.0, 0.4], [0.5, 0.5], "objects", {"fill": "#5a3a1a"}, {"move": true, "sight": true}, 1.2),
			_p("weapon_rack", "Weapon rack", "shelf", [1.0, 0.3], [0.5, 0.5], "objects", {"fill": "#4a3a2a"}, {"move": true, "sight": false}, 1.0),
			_p("altar", "Altar", "altar", [1.2, 0.7], [0.5, 0.5], "objects", {"fill": "#8a8578"}, {"move": true, "sight": false}, 0.5),
			_p("pillar", "Pillar", "pillar", [0.6, 0.6], [0.5, 0.5], "objects", {"fill": "#8a8578"}, {"move": true, "sight": true}, 2.0),
			_p("statue", "Statue", "statue", [0.7, 0.7], [0.5, 0.6], "objects", {"fill": "#9a968a"}, {"move": true, "sight": false}, 1.4),
			_p("brazier", "Brazier", "fire", [0.6, 0.6], [0.5, 0.5], "objects", {"fill": "#ff8a2a", "base": "#4a4a50"}, {"move": true, "sight": false}, 0.6,
				{"bright": 1.5, "dim": 3.0, "color": "#ff9040", "intensity": 1.0, "animation": "flicker"}),
			_p("torch_sconce", "Torch sconce", "torch", [0.3, 0.3], [0.5, 0.5], "objects", {"fill": "#ffa040"}, {"move": false, "sight": false}, 0.2,
				{"bright": 1.0, "dim": 2.0, "color": "#ffa040", "intensity": 1.0, "animation": "torch"}),
			_p("candelabra", "Candelabra", "torch", [0.4, 0.4], [0.5, 0.5], "objects", {"fill": "#ffe0a0"}, {"move": false, "sight": false}, 0.4,
				{"bright": 0.5, "dim": 1.5, "color": "#ffe0a0", "intensity": 0.8, "animation": "flicker"}),
			_p("cauldron", "Cauldron", "barrel", [0.6, 0.6], [0.5, 0.5], "objects", {"fill": "#2a2a30"}, {"move": true, "sight": false}, 0.5),
			_p("trapdoor", "Trapdoor", "door", [0.8, 0.8], [0.5, 0.5], "ground", {"fill": "#5a4630"}, {"move": false, "sight": false}, 0.0),
			_p("rug", "Rug", "rug", [1.6, 1.0], [0.5, 0.5], "ground", {"fill": "#7a2a2a", "band": "#c0a040"}, {"move": false, "sight": false}, 0.0),
			_p("bones", "Bones", "pebbles", [0.6, 0.4], [0.5, 0.5], "ground", {"fill": "#e0d8c8"}, {"move": false, "sight": false}, 0.05),
			_p("well", "Well", "ring", [1.0, 1.0], [0.5, 0.5], "objects", {"fill": "#7a766a"}, {"move": true, "sight": false}, 0.6),
			_p("fountain", "Fountain", "fountain", [1.5, 1.5], [0.5, 0.5], "objects", {"fill": "#8a8578", "water": "#4f86a8"}, {"move": true, "sight": false}, 0.8),
			_p("banner", "Banner", "banner", [0.4, 1.2], [0.5, 0.1], "overhead", {"fill": "#7a2a2a", "band": "#c0a040"}, {"move": false, "sight": false}, 1.5),
		],
		"walls": [
			_w("stone_wall", "Stone wall", "#8a8578", 0.15, "wall"),
			_w("brick_wall", "Brick wall", "#8a5a4a", 0.15, "wall"),
			_w("wooden_partition", "Wooden partition", "#7a5a3a", 0.1, "wall"),
			_w("iron_bars", "Iron bars", "#4a4a50", 0.06, "window"),
			_w("arrow_slit", "Arrow slit", "#8a8578", 0.15, "window"),
			_w("secret_door", "Secret door", "#8a8578", 0.15, "secret"),
			_w("battlement", "Battlement", "#8a8578", 0.2, "wall"),
			_w("ledge", "Ledge", "#6e6a63", 0.04, "fence"),
		],
		"lights": [
			_l("torch", "Torch", 1.0, 2.0, "#ffa040", "torch"),
			_l("brazier", "Brazier", 1.5, 3.0, "#ff9040", "flicker"),
			_l("candle", "Candle", 0.3, 1.0, "#ffe0a0", "flicker"),
			_l("magical_glow", "Magical glow", 1.0, 2.0, "#80a0ff", "pulse"),
			_l("sunlight_shaft", "Sunlight shaft", 2.0, 3.0, "#fff4d0", "none"),
		],
	}


# ------------------------------------------------------------- entry builders --

func _t(id: String, name: String, color: String, deco: String, variants: int, tags: Array = []) -> Dictionary:
	var files: Array = []
	var square: Array = []
	for v in variants:
		files.append("terrain/%s_%d.svg" % [id, v + 1])
		square.append("terrain/%s_sq_%d.svg" % [id, v + 1])
	return {"id": id, "name": name, "color": color, "textures_hex": files, "textures_square": square, "tags": tags, "_deco": deco}


func _p(id: String, name: String, kind: String, size: Array, anchor: Array, layer: String, colors: Dictionary, blocks: Dictionary, height: float, light = null) -> Dictionary:
	return {"id": id, "name": name, "texture": "props/%s.svg" % id, "size": size, "anchor": anchor, "layer": layer,
		"blocks": blocks, "height": height, "light": light, "tags": [kind], "_kind": kind, "_colors": colors}


func _w(id: String, name: String, color: String, width: float, preset: String) -> Dictionary:
	return {"id": id, "name": name, "color": color, "width": width, "preset": preset}


func _l(id: String, name: String, bright: float, dim: float, color: String, animation: String) -> Dictionary:
	return {"id": id, "name": name, "bright": bright, "dim": dim, "color": color, "intensity": 1.0, "animation": animation}


# ------------------------------------------------------------------- writing --

func _write_pack(pack: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path("res://packs").path_join(pack.id)
	DirAccess.make_dir_recursive_absolute(dir.path_join("terrain"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("props"))
	var manifest := {
		"format": "silvergrove.pack", "version": 1,
		"id": pack.id, "name": pack.name, "pack_version": pack.pack_version,
		"authors": ["Silvergrove Studios"], "license": "MIT. Placeholder art generated by tools/gen_pack_art.gd.",
		"description": pack.description,
		"terrains": [], "props": [], "walls": pack.walls, "lights": pack.lights,
	}
	for t in pack.terrains:
		for v in t.textures_hex.size():
			_save(dir.path_join(t.textures_hex[v]), _terrain_svg(t.color, t._deco, "%s/%s/%d" % [pack.id, t.id, v]))
		for v in t.get("textures_square", []).size():
			# the same scatter, seeded alike, framed as a square
			_save(dir.path_join(t.textures_square[v]), _terrain_svg(t.color, t._deco, "%s/%s/%d" % [pack.id, t.id, v], true))
		var clean: Dictionary = t.duplicate()
		clean.erase("_deco")
		manifest.terrains.append(clean)
	for p in pack.props:
		_save(dir.path_join(p.texture), _prop_svg(p._kind, p.size, p._colors, "%s/%s" % [pack.id, p.id]))
		var clean: Dictionary = p.duplicate()
		clean.erase("_kind")
		clean.erase("_colors")
		manifest.props.append(clean)
	_save(dir.path_join("pack.json"), JSON.stringify(manifest, "  ", false) + "\n")
	print("wrote pack ", pack.id, ": ", manifest.terrains.size(), " terrains, ", manifest.props.size(), " props")


func _save(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _seed(key: String) -> void:
	_rng.seed = hash(key)


func _n(v: float) -> String:
	return "%.1f" % v


# --------------------------------------------------------------- terrain art --

const HEX_POINTS := "50,0 100,28.87 100,86.6 50,115.47 0,86.6 0,28.87"


## The art for one cell: a pointy hexagon in a 100 × 115.47 box, or — for
## `square` — the middle 100 × 100 of the same scatter, filled edge to
## edge, so a terrain looks alike on either grid.
func _terrain_svg(color: String, deco: String, key: String, square := false) -> String:
	_seed(key)
	var base := Color(color)
	var s := PackedStringArray()
	if square:
		s.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="256" height="256">')
		s.append('<defs><clipPath id="cell"><rect x="0" y="0" width="100" height="100"/></clipPath></defs>')
		s.append('<rect x="0" y="0" width="100" height="100" fill="%s"/>' % color)
		s.append('<g clip-path="url(#cell)"><g transform="translate(0 -7.735)">')
	else:
		s.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 115.47" width="256" height="296">')
		s.append('<defs><clipPath id="hex"><polygon points="%s"/></clipPath></defs>' % HEX_POINTS)
		s.append('<polygon points="%s" fill="%s"/>' % [HEX_POINTS, color])
		s.append('<g clip-path="url(#hex)">')
	# Gentle mottling so neighbouring cells do not read as one flat sheet.
	for i in 4:
		var c := base.lightened(_rng.randf_range(-0.08, 0.08))
		s.append('<circle cx="%s" cy="%s" r="%s" fill="%s" opacity="0.5"/>' % [_n(_rng.randf_range(0, 100)), _n(_rng.randf_range(0, 115)), _n(_rng.randf_range(20, 45)), _h(c)])
	match deco:
		"tufts", "tufts_dense":
			var dark := _h(base.darkened(0.25))
			var count := 14 if deco == "tufts" else 26
			for i in count:
				var x := _rng.randf_range(4, 96)
				var y := _rng.randf_range(6, 110)
				var h := _rng.randf_range(4, 9)
				s.append('<path d="M%s %s q-2 -%s -3 -%s M%s %s q0 -%s 0 -%s M%s %s q2 -%s 3 -%s" stroke="%s" stroke-width="1.2" fill="none" stroke-linecap="round"/>' % [
					_n(x), _n(y), _n(h * 0.6), _n(h), _n(x), _n(y), _n(h * 0.7), _n(h * 1.2), _n(x), _n(y), _n(h * 0.6), _n(h), dark])
		"leaves":
			for i in 16:
				var c := base.lightened(_rng.randf_range(0.05, 0.25)).lerp(Color("#a06030"), _rng.randf_range(0.0, 0.5))
				s.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s" transform="rotate(%s %s %s)"/>' % [
					_n(_rng.randf_range(4, 96)), _n(_rng.randf_range(4, 111)), _n(_rng.randf_range(2, 4)), _n(_rng.randf_range(1, 2)), _h(c),
					_n(_rng.randf_range(0, 180)), _n(50), _n(57)])
		"dots":
			for i in 22:
				s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(_rng.randf_range(2, 98)), _n(_rng.randf_range(2, 113)), _n(_rng.randf_range(0.6, 1.8)), _h(base.darkened(_rng.randf_range(0.1, 0.3)))])
		"pebbles", "pebbles_dense":
			var count := 12 if deco == "pebbles" else 30
			for i in count:
				var c := base.lightened(_rng.randf_range(-0.15, 0.15))
				s.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s" stroke="%s" stroke-width="0.6"/>' % [
					_n(_rng.randf_range(4, 96)), _n(_rng.randf_range(4, 111)), _n(_rng.randf_range(3, 7)), _n(_rng.randf_range(2, 5)), _h(c), _h(base.darkened(0.3))])
		"ripples":
			var light := _h(base.lightened(0.18))
			for i in 7:
				var y := 8 + i * 15 + _rng.randf_range(-3, 3)
				var x0 := _rng.randf_range(-10, 10)
				s.append('<path d="M%s %s q12 -4 24 0 t24 0 t24 0 t24 0 t24 0" stroke="%s" stroke-width="1.4" fill="none" opacity="0.7"/>' % [_n(x0), _n(y), light])
		"flowers":
			var dark := _h(base.darkened(0.25))
			for i in 10:
				var x := _rng.randf_range(4, 96)
				var y := _rng.randf_range(6, 110)
				s.append('<path d="M%s %s q0 -4 0 -7" stroke="%s" stroke-width="1" fill="none"/>' % [_n(x), _n(y), dark])
			for i in 12:
				var c: Color = [Color("#f0e060"), Color("#f08080"), Color("#e0e0f0"), Color("#c080e0")][_rng.randi() % 4]
				s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(_rng.randf_range(4, 96)), _n(_rng.randf_range(4, 111)), _n(_rng.randf_range(1.2, 2.2)), _h(c)])
		"planks":
			var dark := _h(base.darkened(0.35))
			var light := _h(base.lightened(0.08))
			var y := 0.0
			var k := 0
			while y < 116:
				var h := _rng.randf_range(9, 14)
				s.append('<rect x="-5" y="%s" width="110" height="%s" fill="%s"/>' % [_n(y), _n(h - 1.2), light if k % 2 == 0 else color])
				s.append('<line x1="-5" y1="%s" x2="105" y2="%s" stroke="%s" stroke-width="1.2"/>' % [_n(y + h - 0.6), _n(y + h - 0.6), dark])
				var jx := _rng.randf_range(10, 90)
				s.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="1"/>' % [_n(jx), _n(y), _n(jx), _n(y + h - 1.2), dark])
				y += h
				k += 1
		"flagstones":
			var dark := _h(base.darkened(0.4))
			var cols := 4
			var rows := 5
			for r in rows:
				for c in cols:
					var x := c * 26.0 - 4 + _rng.randf_range(-3, 3)
					var y := r * 24.0 - 2 + _rng.randf_range(-3, 3)
					var w := 24.0 + _rng.randf_range(-4, 4)
					var h := 22.0 + _rng.randf_range(-4, 4)
					var fill := _h(base.lightened(_rng.randf_range(-0.1, 0.1)))
					s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="3" fill="%s" stroke="%s" stroke-width="1.5"/>' % [_n(x), _n(y), _n(w), _n(h), fill, dark])
		"cracks":
			var dark := _h(base.darkened(0.45))
			for i in 6:
				var x := _rng.randf_range(5, 95)
				var y := _rng.randf_range(5, 110)
				var d := "M%s %s" % [_n(x), _n(y)]
				for k in 4:
					x += _rng.randf_range(-14, 14)
					y += _rng.randf_range(-14, 14)
					d += " L%s %s" % [_n(x), _n(y)]
				s.append('<path d="%s" stroke="%s" stroke-width="%s" fill="none" stroke-linejoin="round"/>' % [d, dark, _n(_rng.randf_range(0.8, 1.6))])
		"rubble":
			var dark := _h(base.darkened(0.35))
			for i in 18:
				var x := _rng.randf_range(4, 96)
				var y := _rng.randf_range(4, 111)
				var r := _rng.randf_range(3, 8)
				var pts := PackedStringArray()
				for k in 5:
					var a := TAU * k / 5.0 + _rng.randf_range(-0.3, 0.3)
					pts.append("%s,%s" % [_n(x + cos(a) * r * _rng.randf_range(0.6, 1.0)), _n(y + sin(a) * r * _rng.randf_range(0.6, 1.0))])
				s.append('<polygon points="%s" fill="%s" stroke="%s" stroke-width="0.8"/>' % [" ".join(pts), _h(base.lightened(_rng.randf_range(-0.1, 0.15))), dark])
		"stairs":
			var dark := _h(base.darkened(0.45))
			var light := _h(base.lightened(0.12))
			for i in 6:
				var y := 8 + i * 17
				s.append('<rect x="-5" y="%s" width="110" height="15" fill="%s"/>' % [_n(y), light if i % 2 == 0 else color])
				s.append('<line x1="-5" y1="%s" x2="105" y2="%s" stroke="%s" stroke-width="2"/>' % [_n(y), _n(y), dark])
		"border":
			if square:
				s.append('<rect x="9" y="16.7" width="82" height="82" fill="none" stroke="%s" stroke-width="3"/>' % _h(base.lightened(0.35)))
			else:
				s.append('<polygon points="50,10 91,33.6 91,81.8 50,105.4 9,81.8 9,33.6" fill="none" stroke="%s" stroke-width="3"/>' % _h(base.lightened(0.35)))
		"solid":
			pass
	s.append('</g>')
	if square:
		s.append('</g>')
		s.append('<rect x="0.5" y="0.5" width="99" height="99" fill="none" stroke="%s" stroke-width="1" opacity="0.5"/>' % _h(base.darkened(0.35)))
	else:
		s.append('<polygon points="%s" fill="none" stroke="%s" stroke-width="1" opacity="0.5"/>' % [HEX_POINTS, _h(base.darkened(0.35))])
	s.append('</svg>')
	return "\n".join(s) + "\n"


# ------------------------------------------------------------------ prop art --

func _prop_svg(kind: String, size: Array, colors: Dictionary, key: String) -> String:
	_seed(key)
	var aspect := float(size[1]) / float(size[0])
	var w := 100.0
	var h := 100.0 * aspect
	var fill := str(colors.get("fill", "#808080"))
	var s := PackedStringArray()
	s.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%d" height="%d">' % [_n(w), _n(h), 256, int(256 * aspect)])
	var shadow := '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="#000" opacity="0.25"/>'
	match kind:
		"tree":
			var canopy := Color(str(colors.get("canopy", "#2f6b2a")))
			s.append(shadow % [_n(w * 0.5), _n(h * 0.58), _n(w * 0.46), _n(h * 0.42)])
			for i in 9:
				var a := TAU * i / 9.0
				var r := w * _rng.randf_range(0.28, 0.36)
				s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(w * 0.5 + cos(a) * w * 0.17), _n(h * 0.5 + sin(a) * h * 0.17), _n(r), _h(canopy.lightened(_rng.randf_range(-0.1, 0.12)))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(w * 0.5), _n(h * 0.5), _n(w * 0.3), _h(canopy.lightened(0.15))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(w * 0.5), _n(h * 0.55), _n(w * 0.05), str(colors.get("trunk", "#4a3320"))])
		"pine":
			var canopy := Color(str(colors.get("canopy", "#2a5a30")))
			s.append(shadow % [_n(w * 0.5), _n(h * 0.55), _n(w * 0.45), _n(h * 0.42)])
			for ring in [0.46, 0.34, 0.22]:
				var pts := PackedStringArray()
				for i in 12:
					var a := TAU * i / 12.0
					var r: float = w * ring * (1.0 if i % 2 == 0 else 0.72)
					pts.append("%s,%s" % [_n(w * 0.5 + cos(a) * r), _n(h * 0.5 + sin(a) * r)])
				s.append('<polygon points="%s" fill="%s"/>' % [" ".join(pts), _h(canopy.lightened((0.46 - ring) * 0.6))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(w * 0.5), _n(h * 0.5), _n(w * 0.04), str(colors.get("trunk", "#3e2a18"))])
		"dead_tree":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.6), _n(w * 0.3), _n(h * 0.25)])
			for i in 7:
				var a := TAU * i / 7.0 + _rng.randf_range(-0.2, 0.2)
				var l := w * _rng.randf_range(0.25, 0.45)
				s.append('<path d="M%s %s l%s %s l%s %s" stroke="%s" stroke-width="%s" fill="none" stroke-linecap="round"/>' % [
					_n(w * 0.5), _n(h * 0.6), _n(cos(a) * l * 0.6), _n(sin(a) * l * 0.6), _n(cos(a + 0.4) * l * 0.4), _n(sin(a + 0.4) * l * 0.4), fill, _n(_rng.randf_range(3, 6))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(w * 0.5), _n(h * 0.6), _n(w * 0.09), fill])
		"blob":
			var op := float(colors.get("opacity", 1.0))
			for i in 6:
				s.append('<circle cx="%s" cy="%s" r="%s" fill="%s" opacity="%s"/>' % [_n(w * _rng.randf_range(0.3, 0.7)), _n(h * _rng.randf_range(0.3, 0.7)), _n(w * _rng.randf_range(0.22, 0.32)), _h(Color(fill).lightened(_rng.randf_range(-0.1, 0.1))), _n(op)])
		"log":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.62), _n(w * 0.47), _n(h * 0.35)])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"/>' % [_n(w * 0.04), _n(h * 0.2), _n(w * 0.92), _n(h * 0.6), _n(h * 0.3), fill])
			s.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"/>' % [_n(w * 0.06), _n(h * 0.5), _n(w * 0.05), _n(h * 0.28), _h(Color(fill).lightened(0.35))])
			for i in 4:
				var x := w * _rng.randf_range(0.2, 0.9)
				s.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="1.5"/>' % [_n(x), _n(h * 0.28), _n(x + w * 0.08), _n(h * 0.72), _h(Color(fill).darkened(0.3))])
		"stump":
			s.append('<circle cx="50" cy="50" r="44" fill="%s"/>' % _h(Color(fill).darkened(0.25)))
			s.append('<circle cx="50" cy="50" r="36" fill="%s"/>' % _h(Color(fill).lightened(0.3)))
			for r in [28, 20, 12, 5]:
				s.append('<circle cx="50" cy="50" r="%d" fill="none" stroke="%s" stroke-width="1.5"/>' % [r, _h(Color(fill).darkened(0.2))])
		"rock":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.7), _n(w * 0.45), _n(h * 0.25)])
			var pts := PackedStringArray()
			for i in 8:
				var a := TAU * i / 8.0
				pts.append("%s,%s" % [_n(w * 0.5 + cos(a) * w * _rng.randf_range(0.36, 0.46)), _n(h * 0.5 + sin(a) * h * _rng.randf_range(0.34, 0.45))])
			s.append('<polygon points="%s" fill="%s" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % [" ".join(pts), fill, _h(Color(fill).darkened(0.35))])
			s.append('<polygon points="%s,%s %s,%s %s,%s" fill="%s" opacity="0.6"/>' % [_n(w * 0.35), _n(h * 0.3), _n(w * 0.6), _n(h * 0.25), _n(w * 0.5), _n(h * 0.45), _h(Color(fill).lightened(0.3))])
		"fire":
			var base_c := str(colors.get("base", "#6a6a60"))
			for i in 8:
				var a := TAU * i / 8.0
				s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(w * 0.5 + cos(a) * w * 0.4), _n(h * 0.5 + sin(a) * h * 0.4), _n(w * 0.09), base_c])
			s.append('<circle cx="50" cy="50" r="30" fill="%s" opacity="0.9"/>' % fill)
			s.append('<circle cx="50" cy="50" r="18" fill="#ffd060"/>')
			s.append('<circle cx="50" cy="50" r="8" fill="#fff8d0"/>')
		"torch":
			s.append('<circle cx="50" cy="50" r="40" fill="%s" opacity="0.35"/>' % fill)
			s.append('<circle cx="50" cy="50" r="22" fill="%s" opacity="0.8"/>' % fill)
			s.append('<circle cx="50" cy="50" r="10" fill="#fff8d0"/>')
		"tent":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.62), _n(w * 0.46), _n(h * 0.36)])
			s.append('<polygon points="%s,%s %s,%s %s,%s %s,%s" fill="%s" stroke="%s" stroke-width="2"/>' % [
				_n(w * 0.08), _n(h * 0.22), _n(w * 0.92), _n(h * 0.22), _n(w * 0.8), _n(h * 0.88), _n(w * 0.2), _n(h * 0.88), fill, _h(Color(fill).darkened(0.3))])
			s.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="3"/>' % [_n(w * 0.5), _n(h * 0.22), _n(w * 0.5), _n(h * 0.88), _h(Color(fill).darkened(0.35))])
		"ring":
			var count := 10
			for i in count:
				var a := TAU * i / count
				s.append('<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="1"/>' % [_n(w * 0.5 + cos(a) * w * 0.38), _n(h * 0.5 + sin(a) * h * 0.38), _n(w * 0.07), fill, _h(Color(fill).darkened(0.4))])
		"planks":
			var n := maxi(3, int(w / (h * 0.35)))
			for i in n:
				var x := w * i / n
				s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s" stroke="%s" stroke-width="1"/>' % [_n(x + 0.5), _n(h * 0.05), _n(w / n - 1.0), _n(h * 0.9), _h(Color(fill).lightened(_rng.randf_range(-0.08, 0.08))), _h(Color(fill).darkened(0.35))])
		"pebbles":
			for i in 7:
				s.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s" stroke="%s" stroke-width="1"/>' % [_n(w * _rng.randf_range(0.15, 0.85)), _n(h * _rng.randf_range(0.2, 0.8)), _n(w * _rng.randf_range(0.08, 0.16)), _n(h * _rng.randf_range(0.1, 0.2)), _h(Color(fill).lightened(_rng.randf_range(-0.1, 0.1))), _h(Color(fill).darkened(0.4))])
		"pads":
			for i in 6:
				var cx := w * _rng.randf_range(0.2, 0.8)
				var cy := h * _rng.randf_range(0.2, 0.8)
				var r := w * _rng.randf_range(0.1, 0.18)
				s.append('<path d="M%s %s L%s %s A%s %s 0 1 1 %s %s Z" fill="%s" stroke="%s" stroke-width="1"/>' % [_n(cx), _n(cy), _n(cx + r), _n(cy - r * 0.3), _n(r), _n(r), _n(cx + r), _n(cy + r * 0.3), _h(Color(fill).lightened(_rng.randf_range(-0.1, 0.1))), _h(Color(fill).darkened(0.35))])
		"boat":
			s.append('<path d="M%s %s Q%s %s %s %s Q%s %s %s %s Z" fill="%s" stroke="%s" stroke-width="2"/>' % [
				_n(w * 0.03), _n(h * 0.5), _n(w * 0.5), _n(h * -0.2), _n(w * 0.97), _n(h * 0.5), _n(w * 0.5), _n(h * 1.2), _n(w * 0.03), _n(h * 0.5), fill, _h(Color(fill).darkened(0.35))])
			for x in [0.3, 0.5, 0.7]:
				s.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="2"/>' % [_n(w * x), _n(h * 0.2), _n(w * x), _n(h * 0.8), _h(Color(fill).darkened(0.3))])
		"hut":
			var roof := str(colors.get("roof", "#6a5a40"))
			s.append(shadow % [_n(w * 0.5), _n(h * 0.62), _n(w * 0.48), _n(h * 0.4)])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % [_n(w * 0.15), _n(h * 0.2), _n(w * 0.7), _n(h * 0.7), fill])
			s.append('<polygon points="%s,%s %s,%s %s,%s %s,%s" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.08), _n(h * 0.15), _n(w * 0.92), _n(h * 0.15), _n(w * 0.85), _n(h * 0.85), _n(w * 0.15), _n(h * 0.85), roof, _h(Color(roof).darkened(0.35))])
			s.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="3"/>' % [_n(w * 0.5), _n(h * 0.15), _n(w * 0.5), _n(h * 0.85), _h(Color(roof).darkened(0.4))])
		"wisp":
			s.append('<circle cx="50" cy="50" r="45" fill="%s" opacity="0.25"/>' % fill)
			s.append('<circle cx="50" cy="50" r="28" fill="%s" opacity="0.6"/>' % fill)
			s.append('<circle cx="50" cy="50" r="12" fill="#ffffff"/>')
		"totem":
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="8" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.25), _n(h * 0.1), _n(w * 0.5), _n(h * 0.8), fill, _h(Color(fill).darkened(0.35))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="#f0e060"/>' % [_n(w * 0.38), _n(h * 0.3), _n(w * 0.06)])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="#f0e060"/>' % [_n(w * 0.62), _n(h * 0.3), _n(w * 0.06)])
		"door":
			s.append('<rect x="2" y="%s" width="%s" height="%s" rx="2" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(h * 0.1), _n(w - 4), _n(h * 0.8), fill, _h(Color(fill).darkened(0.4))])
			s.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.5), _n(h * 0.1), _n(w * 0.5), _n(h * 0.9), _h(Color(fill).darkened(0.4))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="#c0a040"/>' % [_n(w * 0.42), _n(h * 0.5), _n(minf(w, h) * 0.06)])
		"bars":
			s.append('<rect x="2" y="%s" width="%s" height="%s" fill="%s" opacity="0.4"/>' % [_n(h * 0.3), _n(w - 4), _n(h * 0.4), fill])
			for i in 7:
				var x := w * (0.08 + 0.14 * i)
				s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % [_n(x), _n(h * 0.05), _n(w * 0.04), _n(h * 0.9), fill])
		"table":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.6), _n(w * 0.48), _n(h * 0.45)])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="4" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.04), _n(h * 0.06), _n(w * 0.92), _n(h * 0.88), fill, _h(Color(fill).darkened(0.35))])
			for i in 3:
				var y := h * (0.3 + 0.2 * i)
				s.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="1"/>' % [_n(w * 0.08), _n(y), _n(w * 0.92), _n(y), _h(Color(fill).darkened(0.2))])
		"chair":
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="4" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.15), _n(h * 0.2), _n(w * 0.7), _n(h * 0.65), fill, _h(Color(fill).darkened(0.35))])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="3" fill="%s"/>' % [_n(w * 0.15), _n(h * 0.08), _n(w * 0.7), _n(h * 0.16), _h(Color(fill).darkened(0.3))])
		"bed":
			var cover := str(colors.get("cover", "#8a3a3a"))
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="4" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.04), _n(h * 0.02), _n(w * 0.92), _n(h * 0.96), fill, _h(Color(fill).darkened(0.35))])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="3" fill="%s"/>' % [_n(w * 0.1), _n(h * 0.25), _n(w * 0.8), _n(h * 0.7), cover])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="4" fill="#e8e0d0"/>' % [_n(w * 0.15), _n(h * 0.06), _n(w * 0.7), _n(h * 0.14)])
		"box":
			var band := str(colors.get("band", "#b09040"))
			s.append(shadow % [_n(w * 0.5), _n(h * 0.6), _n(w * 0.48), _n(h * 0.45)])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="3" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.05), _n(h * 0.08), _n(w * 0.9), _n(h * 0.84), fill, _h(Color(fill).darkened(0.35))])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % [_n(w * 0.05), _n(h * 0.44), _n(w * 0.9), _n(h * 0.12), band])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % [_n(w * 0.44), _n(h * 0.08), _n(w * 0.12), _n(h * 0.84), band])
		"barrel":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.6), _n(w * 0.45), _n(h * 0.4)])
			s.append('<circle cx="50" cy="50" r="42" fill="%s" stroke="%s" stroke-width="2"/>' % [fill, _h(Color(fill).darkened(0.4))])
			s.append('<circle cx="50" cy="50" r="30" fill="none" stroke="%s" stroke-width="3"/>' % _h(Color(fill).darkened(0.3)))
			s.append('<circle cx="50" cy="50" r="6" fill="%s"/>' % _h(Color(fill).darkened(0.3)))
		"shelf":
			s.append('<rect x="2" y="%s" width="%s" height="%s" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(h * 0.05), _n(w - 4), _n(h * 0.9), fill, _h(Color(fill).darkened(0.4))])
			var x := w * 0.06
			while x < w * 0.92:
				var bw := w * _rng.randf_range(0.04, 0.08)
				var c: Color = [Color("#8a3a3a"), Color("#3a5a8a"), Color("#4a7a3a"), Color("#c0a040"), Color("#6a4a7a")][_rng.randi() % 5]
				s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % [_n(x), _n(h * 0.15), _n(bw - 1), _n(h * 0.7), _h(c)])
				x += bw
		"altar":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.62), _n(w * 0.48), _n(h * 0.42)])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="3" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.04), _n(h * 0.08), _n(w * 0.92), _n(h * 0.84), fill, _h(Color(fill).darkened(0.4))])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % [_n(w * 0.12), _n(h * 0.2), _n(w * 0.76), _n(h * 0.6), _h(Color(fill).lightened(0.15))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="#c0a040"/>' % [_n(w * 0.5), _n(h * 0.5), _n(h * 0.14)])
		"pillar":
			s.append(shadow % [_n(w * 0.52), _n(h * 0.55), _n(w * 0.46), _n(h * 0.46)])
			s.append('<circle cx="50" cy="50" r="44" fill="%s" stroke="%s" stroke-width="2"/>' % [fill, _h(Color(fill).darkened(0.4))])
			s.append('<circle cx="50" cy="50" r="30" fill="%s"/>' % _h(Color(fill).lightened(0.15)))
		"statue":
			s.append(shadow % [_n(w * 0.5), _n(h * 0.65), _n(w * 0.42), _n(h * 0.3)])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" rx="4" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.15), _n(h * 0.3), _n(w * 0.7), _n(h * 0.6), fill, _h(Color(fill).darkened(0.4))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="2"/>' % [_n(w * 0.5), _n(h * 0.45), _n(w * 0.2), _h(Color(fill).lightened(0.2)), _h(Color(fill).darkened(0.4))])
		"rug":
			var band := str(colors.get("band", "#c0a040"))
			s.append('<rect x="2" y="2" width="%s" height="%s" rx="3" fill="%s"/>' % [_n(w - 4), _n(h - 4), fill])
			s.append('<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-width="3"/>' % [_n(w * 0.08), _n(h * 0.1), _n(w * 0.84), _n(h * 0.8), band])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="2"/>' % [_n(w * 0.5), _n(h * 0.5), _n(h * 0.22), band])
		"fountain":
			var water := str(colors.get("water", "#4f86a8"))
			s.append('<circle cx="50" cy="50" r="47" fill="%s" stroke="%s" stroke-width="2"/>' % [fill, _h(Color(fill).darkened(0.4))])
			s.append('<circle cx="50" cy="50" r="38" fill="%s"/>' % water)
			s.append('<circle cx="50" cy="50" r="12" fill="%s" stroke="%s" stroke-width="2"/>' % [fill, _h(Color(fill).darkened(0.4))])
			s.append('<circle cx="50" cy="50" r="24" fill="none" stroke="%s" stroke-width="1.5" opacity="0.7"/>' % _h(Color(water).lightened(0.3)))
		"banner":
			var band := str(colors.get("band", "#c0a040"))
			s.append('<rect x="%s" y="0" width="%s" height="%s" fill="%s"/>' % [_n(w * 0.1), _n(w * 0.8), _n(h * 0.06), band])
			s.append('<polygon points="%s,%s %s,%s %s,%s %s,%s %s,%s" fill="%s" stroke="%s" stroke-width="2"/>' % [
				_n(w * 0.15), _n(h * 0.05), _n(w * 0.85), _n(h * 0.05), _n(w * 0.85), _n(h * 0.85), _n(w * 0.5), _n(h * 0.98), _n(w * 0.15), _n(h * 0.85), fill, _h(Color(fill).darkened(0.35))])
			s.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [_n(w * 0.5), _n(h * 0.4), _n(w * 0.2), band])
		_:
			s.append('<rect x="4" y="4" width="%s" height="%s" fill="%s" stroke="#000" stroke-width="2"/>' % [_n(w - 8), _n(h - 8), fill])
	s.append('</svg>')
	return "\n".join(s) + "\n"


func _h(c: Color) -> String:
	return "#" + c.to_html(false)
