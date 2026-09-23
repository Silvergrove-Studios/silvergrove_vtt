class_name CampaignPackage
extends RefCounted
## A campaign package (`.campaignpkg`): a campaign someone assembled —
## the adventure, its maps, the content it adds, the rules it was tested
## with — as one file to download. A package is a **template and stays
## one**: nothing the table does writes to it. Starting a campaign from
## it copies it into an instance folder, and that copy is what is played,
## imported into and saved. Editing a package means working on an
## instance and exporting a new package from it.
##
## docs/campaign-packages.md is the design.

const FORMAT := "silvergrove.campaignpkg"
const VERSION := 1
const EXT := "campaignpkg"


## What a package says about itself, without instancing it:
## {ok, why, manifest, id, name, package_version, description, authors,
##  license, requires, tested_with, bundles_rules, entries: n}
static func read(path: String) -> Dictionary:
	var out := {"ok": false, "why": "", "manifest": {}, "id": "", "name": "", "package_version": "", "description": "",
		"authors": [], "license": "", "requires": {}, "tested_with": {}, "bundles_rules": false, "entries": 0, "path": path}
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		out.why = "%s is not a package this build reads" % path.get_file()
		return out
	var names := zr.get_files()
	if not Array(names).has("package.json"):
		zr.close()
		out.why = "%s has no package.json" % path.get_file()
		return out
	var err := []
	var m := JsonDoc.parse(zr.read_file("package.json").get_string_from_utf8(), err)
	zr.close()
	if m.is_empty():
		out.why = "%s: %s" % [path.get_file(), ", ".join(PackedStringArray(err))]
		return out
	if str(m.get("format", FORMAT)) != FORMAT or int(m.get("version", VERSION)) > VERSION:
		out.why = "%s is not a package this build reads" % path.get_file()
		return out
	out.manifest = m
	out.id = str(m.get("id", path.get_file().get_basename()))
	out.name = str(m.get("name", out.id))
	out.package_version = str(m.get("package_version", ""))
	out.description = str(m.get("description", ""))
	out.authors = m.get("authors", [])
	out.license = str(m.get("license", ""))
	out.requires = m.get("requires", {}) if m.get("requires") is Dictionary else {}
	out.tested_with = m.get("tested_with", {}) if m.get("tested_with") is Dictionary else {}
	out.bundles_rules = Array(names).any(func(n: String) -> bool: return str(n).begins_with("rules/"))
	out.entries = names.size()
	out.ok = true
	return out


## What this table cannot satisfy, in plain words. `installed` is
## {plugin id: version}; a package that bundles its rules needs none.
static func unmet(info: Dictionary, installed: Dictionary, app_version: String) -> Array:
	var out := []
	var req: Dictionary = info.get("requires", {})
	var app_need := str(req.get("app", ""))
	if app_need != "" and not _version_ok(app_version, app_need):
		out.append("needs Hexmap %s (this is %s)" % [app_need, app_version])
	if bool(info.get("bundles_rules", false)):
		return out
	for p in req.get("plugins", []):
		if not (p is Dictionary):
			continue
		# (a package that carries its rules never gets here)
		var pid := str(p.get("id", ""))
		var want := str(p.get("version", ""))
		if not installed.has(pid):
			out.append("needs the %s ruleset%s, which is not installed" % [pid, (" " + want) if want != "" else ""])
		elif want != "" and not _version_ok(str(installed[pid]), want):
			out.append("needs the %s ruleset %s (this table has %s)" % [pid, want, str(installed[pid])])
	return out


## Make a campaign of one's own from a package: everything copied into
## `dest` (a folder of its own), the campaign named and given a fresh id,
## the package's play state left behind. {ok, why, path, name}.
static func instance(pkg_path: String, dest: String, p_name := "") -> Dictionary:
	var out := {"ok": false, "why": "", "path": "", "name": ""}
	var info := read(pkg_path)
	if not info.ok:
		out.why = str(info.why)
		return out
	var zr := ZIPReader.new()
	if zr.open(pkg_path) != OK:
		out.why = "cannot open %s" % pkg_path.get_file()
		return out
	var campaign_file := str(info.manifest.get("campaign", "campaign.json"))
	var names := zr.get_files()
	if not Array(names).has(campaign_file):
		zr.close()
		out.why = "%s names %s, which is not in it" % [str(info.name), campaign_file]
		return out
	if DirAccess.make_dir_recursive_absolute(dest) != OK:
		zr.close()
		out.why = "cannot make %s" % dest
		return out
	var wanted := p_name.strip_edges() if p_name.strip_edges() != "" else str(info.name)
	var slug := _slug(wanted)
	var campaign_path := dest.path_join("%s.campaign" % slug)
	for n in names:
		if n.ends_with("/") or n.contains("..") or n == "package.json":
			continue
		var rel := n
		if n == campaign_file:
			rel = "%s.campaign" % slug
		var path := dest.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			zr.close()
			out.why = "cannot write %s" % path
			return out
		f.store_buffer(zr.read_file(n))
		f.close()
	zr.close()
	# the copy becomes this table's campaign: its own id and name, no play behind it
	var err := []
	var c := Campaign.load_file(campaign_path, err)
	if c == null:
		out.why = "the package's campaign could not be read: %s" % ", ".join(PackedStringArray(err))
		return out
	c.doc.id = JsonDoc.uuid()
	c.doc.name = wanted
	c.doc.runtime = {}
	c.doc.sessions = []
	c.doc.clock = {"session": 0, "day": int(c.clock.get("day", 1)), "minute": int(c.clock.get("minute", 0))}
	c.doc.package = {"id": str(info.id), "version": str(info.package_version), "name": str(info.name),
		"tested_with": JsonDoc.deep(info.tested_with)}
	if bool(info.bundles_rules):
		c.doc.rules_dir = "rules"
	var save_err := c.save(campaign_path)
	if save_err != OK:
		out.why = "cannot write %s" % campaign_path
		return out
	out.path = campaign_path
	out.name = wanted
	out.ok = true
	return out


## Write a package from a campaign: the document without its play state,
## its maps, its packs, and **the rulesets it plays** — a package carries
## everything it needs, so a table that has installed nothing can start
## it. A ruleset travels whole, its own licence file included.
## opts: {id, package_version, authors, license, url, description,
## keep_players, plugin_dirs (where installed rulesets are),
## bundle_rules = false only for a package that deliberately leans on an
## installed ruleset}.
static func export_from(campaign: Campaign, dest_path: String, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "why": "", "path": dest_path, "files": 0}
	if campaign == null or campaign.path == "":
		out.why = "save the campaign first"
		return out
	var zp := ZIPPacker.new()
	DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
	if zp.open(dest_path) != OK:
		out.why = "cannot write %s" % dest_path
		return out
	var doc: Dictionary = JsonDoc.deep(campaign.doc)
	doc.runtime = {}
	doc.sessions = []
	doc.erase("package")
	if not bool(opts.get("keep_players", false)):
		doc.players = []
		var keep := {}
		for aid in doc.actors:
			if str(doc.actors[aid].get("kind", "")) != "pc":
				keep[aid] = doc.actors[aid]
		doc.actors = keep
		doc.resources = {}
	# the rulesets this campaign plays, copied in whole (their packs and licences with them)
	var bundle := bool(opts.get("bundle_rules", true))
	var rules_from := {}
	if bundle:
		rules_from = _rule_dirs(campaign, opts.get("plugin_dirs", []))
		var missing := []
		for p in campaign.plugins:
			if p is Dictionary and not rules_from.has(str(p.get("id", ""))):
				missing.append(str(p.get("id", "")))
		if not missing.is_empty():
			zp.close()
			DirAccess.remove_absolute(dest_path)
			out.why = "the %s ruleset is not here to put in the package (install it, or export without its rules)" % ", ".join(PackedStringArray(missing))
			return out
	var manifest := {"format": FORMAT, "version": VERSION,
		"id": str(opts.get("id", _slug(campaign.name))), "name": campaign.name,
		"package_version": str(opts.get("package_version", "1.0.0")),
		"authors": opts.get("authors", [str(campaign.doc.get("meta", {}).get("author", ""))]).filter(func(a: Variant) -> bool: return str(a) != ""),
		"license": str(opts.get("license", "")), "url": str(opts.get("url", "")),
		"description": str(opts.get("description", campaign.doc.get("meta", {}).get("description", ""))),
		"requires": opts.get("requires", {"app": ">=%s" % _major(App.version()), "plugins": _plugin_requirements(campaign)}),
		"tested_with": {"app": App.version(), "plugins": _plugin_versions(campaign)},
		"bundles_rules": bundle and not rules_from.is_empty(),
		"campaign": "campaign.json"}
	var n := 0
	zp.start_file("package.json")
	zp.write_file(JsonDoc.stringify(manifest).to_utf8_buffer())
	zp.close_file()
	n += 1
	zp.start_file("campaign.json")
	zp.write_file(JsonDoc.stringify(doc).to_utf8_buffer())
	zp.close_file()
	n += 1
	# everything the campaign names, by its own relative paths
	var files := PackedStringArray()
	for m in campaign.maps:
		if m is Dictionary and str(m.get("path", "")) != "" and not str(m.path).is_absolute_path():
			files.append(str(m.path))
	for sub in ["packs", "handouts"]:
		_walk(campaign.base_dir().path_join(sub), sub, files)
	for rel in files:
		var src := campaign.resolve(rel)
		if not FileAccess.file_exists(src):
			continue
		zp.start_file(rel)
		zp.write_file(FileAccess.get_file_as_bytes(src))
		zp.close_file()
		n += 1
	# the rulesets, from wherever this table has them
	for pid in rules_from:
		var from := str(rules_from[pid])
		var within := PackedStringArray()
		_walk(from, "", within)
		for rel in within:
			var src := from.path_join(rel)
			if not FileAccess.file_exists(src):
				continue
			zp.start_file("rules/%s/%s" % [pid, rel])
			zp.write_file(FileAccess.get_file_as_bytes(src))
			zp.close_file()
			n += 1
	zp.close()
	out.files = n
	out.ok = true
	return out


## Where each ruleset the campaign plays can be copied from: the
## campaign's own copy first, then the dirs this table installs into.
static func _rule_dirs(campaign: Campaign, plugin_dirs: Array) -> Dictionary:
	var out := {}
	var want := []
	for p in campaign.plugins:
		if p is Dictionary and str(p.get("id", "")) != "":
			want.append(str(p.id))
	if want.is_empty():
		return out
	var carried := campaign.resolve(str(campaign.doc.get("rules_dir", "rules")))
	for m in PluginHost.discover([carried] + Array(plugin_dirs)):
		var id := str(m.get("id", ""))
		# a plugin a wanted one depends on travels too
		if want.has(id) or Array(m.get("depends", [])).any(func(d: Variant) -> bool: return want.has(str(d))):
			out[id] = str(m.get("__dir", ""))
	# and what those depend on, one more pass (a base under a layer under a layer)
	for m in PluginHost.discover([carried] + Array(plugin_dirs)):
		for dep in m.get("depends", []):
			if out.has(str(m.get("id", ""))) and not out.has(str(dep)):
				for d in PluginHost.discover([carried] + Array(plugin_dirs)):
					if str(d.get("id", "")) == str(dep):
						out[str(dep)] = str(d.get("__dir", ""))
	return out


## Files under `dir`, as paths relative to the campaign (or to `under`).
static func _walk(dir: String, prefix: String, into: PackedStringArray, under := "") -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not n.begins_with("."):
			if da.current_is_dir():
				_walk(dir.path_join(n), prefix.path_join(n), into, under)
			else:
				into.append(prefix.path_join(n))
		n = da.get_next()
	da.list_dir_end()


static func _plugin_requirements(campaign: Campaign) -> Array:
	var out := []
	for p in campaign.plugins:
		if p is Dictionary and str(p.get("id", "")) != "":
			var r := {"id": str(p.id)}
			if str(p.get("version", "")) != "":
				r.version = ">=%s" % str(p.version)
			out.append(r)
	return out


static func _plugin_versions(campaign: Campaign) -> Dictionary:
	var out := {}
	for p in campaign.plugins:
		if p is Dictionary and str(p.get("id", "")) != "":
			out[str(p.id)] = str(p.get("version", ""))
	return out


## Does `have` satisfy `need` (">=1.2.0", "1.2.0", or "*")?
static func _version_ok(have: String, need: String) -> bool:
	var want := need.strip_edges()
	if want == "" or want == "*":
		return true
	var op := ">="
	if want.begins_with(">="):
		want = want.substr(2).strip_edges()
	elif want.begins_with("="):
		op = "="
		want = want.substr(1).strip_edges()
	var cmp := _compare(have, want)
	return cmp >= 0 if op == ">=" else cmp == 0


## -1, 0, 1 comparing dotted versions ("2.0.0" vs "1.9.3"); non-numbers sort last.
static func _compare(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() and str(pa[i]).is_valid_int() else 0
		var y := int(pb[i]) if i < pb.size() and str(pb[i]).is_valid_int() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


static func _major(v: String) -> String:
	return "%s.0.0" % v.split(".")[0]


static func _slug(s: String) -> String:
	var out := ""
	for ch in s.strip_edges().to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if out != "" else "campaign"
