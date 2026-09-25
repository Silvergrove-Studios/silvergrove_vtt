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
	# a damaged package is not started
	var whole := verify(pkg_path)
	if not whole.ok:
		out.why = "the package is damaged: %s" % str(whole.why)
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
	# never over a campaign already there
	var existing := DirAccess.open(dest)
	if existing != null and (not existing.get_files().is_empty() or not existing.get_directories().is_empty()):
		zr.close()
		out.why = "there is already a campaign in %s" % dest
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
	# (a package from before strip_play may still carry its author's)
	strip_play(c.doc)
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


## What a group's play left in a campaign that is theirs and no one
## else's: the players' notes, what the DM showed them (journal handouts
## with a `ref`), and what the sessions banked (entries stamped with a
## `session`); a note's record of the session it was handed out in. What
## the author prepared stays.
static func strip_play(doc: Dictionary) -> void:
	doc.player_notes = []
	var kept := []
	for j in doc.get("journal", []):
		if not (j is Dictionary):
			continue
		if j.has("session") or (str(j.get("kind", "")) == "handout" and str(j.get("ref", "")) != ""):
			continue
		var e: Dictionary = JsonDoc.deep(j)
		e.erase("handed")
		kept.append(e)
	doc.journal = kept


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
	strip_play(doc)
	doc.erase("package")
	# the author's own authoring and play are not the package's
	doc.erase("source_of")
	doc.erase("package_updates")
	for e in doc.get("encounters", []):
		if e is Dictionary:
			e.erase("live")
			e.played = []
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
	# the art its maps are drawn with: carried in the campaign's art/, and it
	# must be art its makers allow to be passed on
	var art_dir := campaign.base_dir().path_join("art")
	var art := {}
	var da := DirAccess.open(art_dir)
	if da != null:
		for sub in da.get_directories():
			var mp := art_dir.path_join(sub).path_join("pack.json")
			if not FileAccess.file_exists(mp):
				continue
			var err := []
			var m := JsonDoc.parse(FileAccess.get_file_as_string(mp), err)
			var ok := PackLibrary.redistributable(m)
			if not ok.ok:
				zp.close()
				DirAccess.remove_absolute(dest_path)
				out.why = "the art pack '%s' cannot go in a package: %s" % [str(m.get("id", sub)), str(ok.why)]
				return out
			art[str(m.get("id", sub))] = {"version": str(m.get("pack_version", "")), "license": str(m.get("license", ""))}
	var manifest := {"format": FORMAT, "version": VERSION,
		"id": str(opts.get("id", _slug(campaign.name))), "name": campaign.name,
		"package_version": str(opts.get("package_version", "1.0.0")),
		"authors": opts.get("authors", [str(campaign.doc.get("meta", {}).get("author", ""))]).filter(func(a: Variant) -> bool: return str(a) != ""),
		"license": str(opts.get("license", "")), "url": str(opts.get("url", "")),
		"description": str(opts.get("description", campaign.doc.get("meta", {}).get("description", ""))),
		# the app it was made with, to the minor version: an older one may not read what it relies on
		"requires": opts.get("requires", {"app": ">=%s" % _minor_floor(App.version()), "plugins": _plugin_requirements(campaign)}),
		"tested_with": {"app": App.version(), "plugins": _plugin_versions(campaign)},
		"bundles_rules": bundle and not rules_from.is_empty(),
		"changelog": opts.get("changelog", []),
		"art": art,
		"campaign": "campaign.json"}
	var n := 0
	# every file's SHA-256, written into package.json last: a package that
	# was damaged (or altered) on its way to a DM is caught before it starts
	var hashes := {}
	var put := func(rel: String, bytes: PackedByteArray) -> void:
		zp.start_file(rel)
		zp.write_file(bytes)
		zp.close_file()
		hashes[rel] = sha256(bytes)
	put.call("campaign.json", JsonDoc.stringify(doc).to_utf8_buffer())
	n += 1
	# everything the campaign names, by its own relative paths
	var files := PackedStringArray()
	for m in campaign.maps:
		if m is Dictionary and str(m.get("path", "")) != "" and not str(m.path).is_absolute_path():
			files.append(str(m.path))
	for sub in ["packs", "art", "handouts"]:
		_walk(campaign.base_dir().path_join(sub), sub, files)
	for rel in files:
		var src := campaign.resolve(rel)
		if not FileAccess.file_exists(src):
			continue
		put.call(rel, FileAccess.get_file_as_bytes(src))
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
			put.call("rules/%s/%s" % [pid, rel], FileAccess.get_file_as_bytes(src))
			n += 1
	manifest.files = hashes
	manifest.digest = digest_of(hashes)
	zp.start_file("package.json")
	zp.write_file(JsonDoc.stringify(manifest).to_utf8_buffer())
	zp.close_file()
	n += 1
	zp.close()
	out.files = n
	out.digest = manifest.digest
	out.ok = true
	return out


# ---------------------------------------------------------- authoring --

## Release the package this campaign is the working copy of: the next
## version (a patch by default), the notes added to its changelog, written
## to the file it was released to before. A campaign that is not yet the
## source of a package becomes one: it keeps the package it came from's id
## and continues its versions, or takes its own name as id at 1.0.0.
## {ok, why, path, version}.
static func release(campaign: Campaign, notes: String, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "why": "", "path": "", "version": ""}
	if campaign == null or campaign.path == "":
		out.why = "save the campaign first"
		return out
	var src: Dictionary = campaign.doc.get("source_of", {}) if campaign.doc.get("source_of") is Dictionary else {}
	var came_from: Dictionary = campaign.doc.get("package", {}) if campaign.doc.get("package") is Dictionary else {}
	var id := str(src.get("id", came_from.get("id", _slug(campaign.name))))
	var version := str(opts.get("version", ""))
	if version == "":
		var last := str(src.get("version", came_from.get("version", "")))
		version = bump(last, str(opts.get("bump", "patch"))) if last != "" else "1.0.0"
	var path := str(opts.get("path", src.get("path", "")))
	if path == "":
		out.why = "say where the package goes the first time"
		return out
	var changelog: Array = (src.get("changelog", []) as Array).duplicate(true)
	changelog.append({"version": version, "date": Time.get_date_string_from_system(), "notes": notes.strip_edges()})
	var o: Dictionary = opts.duplicate()
	o.id = id
	o.package_version = version
	o.changelog = changelog
	var r := export_from(campaign, path, o)
	if not r.ok:
		out.why = str(r.why)
		return out
	campaign.doc.source_of = {"id": id, "name": campaign.name, "version": version, "path": path, "changelog": changelog, "digest": str(r.get("digest", ""))}
	campaign.touch()
	campaign.save()
	out.path = path
	out.version = version
	out.ok = true
	return out


## "1.2.3" → the next version by `part` ("major", "minor", "patch").
static func bump(v: String, part := "patch") -> String:
	var p := v.split(".")
	var nums := [int(p[0]) if p.size() > 0 and p[0].is_valid_int() else 0, int(p[1]) if p.size() > 1 and p[1].is_valid_int() else 0,
		int(p[2]) if p.size() > 2 and p[2].is_valid_int() else 0]
	match part:
		"major": nums = [nums[0] + 1, 0, 0]
		"minor": nums = [nums[0], nums[1] + 1, 0]
		_: nums[2] += 1
	return "%d.%d.%d" % nums


# ------------------------------------------------------------ updates --

## A newer version of the package this campaign came from, in `dir`, or {}.
static func newer_for(campaign: Campaign, dir: String) -> Dictionary:
	var came: Dictionary = campaign.doc.get("package", {}) if campaign != null and campaign.doc.get("package") is Dictionary else {}
	if came.is_empty():
		return {}
	var best := {}
	var da := DirAccess.open(dir)
	if da == null:
		return {}
	for f in da.get_files():
		if not f.ends_with("." + EXT):
			continue
		var info := read(dir.path_join(f))
		if not info.ok or str(info.id) != str(came.get("id", "")):
			continue
		var have := str(best.get("package_version", came.get("version", "")))
		if _compare(str(info.package_version), have) > 0:
			best = info
	return best


## What moving this campaign onto a newer version of its package would
## change — never applied by itself. {from, to, changelog: [entries since],
## maps: {added, changed}, packs: {added, changed}, art: {added, changed},
## encounters: {added}, rules: [{id, from, to}]}.
static func update_report(campaign: Campaign, pkg_path: String) -> Dictionary:
	var info := read(pkg_path)
	var came: Dictionary = campaign.doc.get("package", {}) if campaign.doc.get("package") is Dictionary else {}
	var out := {"ok": info.ok, "why": str(info.get("why", "")), "from": str(came.get("version", "")), "to": str(info.get("package_version", "")),
		"name": str(info.get("name", "")), "changelog": [], "maps": {"added": [], "changed": []}, "packs": {"added": [], "changed": []},
		"art": {"added": [], "changed": []}, "encounters": {"added": []}, "rules": []}
	if not info.ok:
		return out
	for entry in info.manifest.get("changelog", []):
		if entry is Dictionary and _compare(str(entry.get("version", "")), str(out.from)) > 0:
			out.changelog.append(entry)
	var listed: Dictionary = info.manifest.get("files", {}) if info.manifest.get("files") is Dictionary else {}
	var seen := {}
	for rel in listed:
		var parts := str(rel).split("/")
		if parts.size() < 2:
			continue
		var kind: String = {"maps": "maps", "packs": "packs", "art": "art"}.get(parts[0], "")
		if kind == "":
			continue
		var key := parts[1] if kind != "maps" else str(rel).substr(5)
		var local := campaign.base_dir().path_join(str(rel))
		var state := ""
		if not FileAccess.file_exists(local):
			state = "added" if not DirAccess.dir_exists_absolute(campaign.base_dir().path_join(parts[0]).path_join(parts[1])) or kind == "maps" else "changed"
		elif sha256(FileAccess.get_file_as_bytes(local)) != str(listed[rel]):
			state = "changed"
		if state == "" or seen.has(kind + "/" + key):
			continue
		seen[kind + "/" + key] = true
		(out[kind][state] as Array).append(key)
	# prepared encounters the new version adds
	var zr := ZIPReader.new()
	if zr.open(pkg_path) == OK:
		var err := []
		var doc := JsonDoc.parse(zr.read_file(str(info.manifest.get("campaign", "campaign.json"))).get_string_from_utf8(), err)
		for e in doc.get("encounters", []):
			if e is Dictionary and campaign.encounter_entry(str(e.get("id", ""))).is_empty():
				out.encounters.added.append(str(e.get("name", e.get("id", ""))))
		# the rulesets it carries, against the campaign's own
		for n in zr.get_files():
			var parts := n.split("/")
			if parts.size() == 3 and parts[0] == "rules" and parts[2] == "manifest.json":
				var m := JsonDoc.parse(zr.read_file(n).get_string_from_utf8(), err)
				var mine := campaign.base_dir().path_join("rules").path_join(parts[1]).path_join("manifest.json")
				var have: Dictionary = JsonDoc.parse(FileAccess.get_file_as_string(mine), err) if FileAccess.file_exists(mine) else {}
				if str(have.get("version", "")) != str(m.get("version", "")):
					out.rules.append({"id": parts[1], "from": str(have.get("version", "")), "to": str(m.get("version", ""))})
		zr.close()
	return out


## Bring a newer version's content into this campaign, as the DM chose:
## `content` — maps, content packs, art, and the prepared encounters it
## adds (the campaign's play, and encounters it has played, are left as
## they are); `rules` — the rulesets the package carries replace the
## campaign's own. {ok, why, applied: [what moved]}.
static func apply_update(campaign: Campaign, pkg_path: String, content := true, rules := false) -> Dictionary:
	var out := {"ok": false, "why": "", "applied": []}
	var whole := verify(pkg_path)
	if not whole.ok:
		out.why = "the package is damaged: %s" % str(whole.why)
		return out
	var info := read(pkg_path)
	var zr := ZIPReader.new()
	if zr.open(pkg_path) != OK:
		out.why = "cannot open it"
		return out
	var base := campaign.base_dir()
	for n in zr.get_files():
		if n.ends_with("/") or n.contains(".."):
			continue
		var top := n.get_slice("/", 0)
		if (content and top in ["maps", "packs", "art", "handouts"]) or (rules and top == "rules"):
			var path := base.path_join(n)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				continue
			f.store_buffer(zr.read_file(n))
			f.close()
	if content:
		var err := []
		var doc := JsonDoc.parse(zr.read_file(str(info.manifest.get("campaign", "campaign.json"))).get_string_from_utf8(), err)
		for m in doc.get("maps", []):
			if m is Dictionary and campaign.map_entry(str(m.get("id", ""))).is_empty():
				campaign.maps.append(m)
				out.applied.append("map %s" % str(m.get("name", m.get("id", ""))))
		for p in doc.get("packs", []):
			if p is Dictionary and not campaign.packs.any(func(x: Dictionary) -> bool: return str(x.get("id", "")) == str(p.get("id", ""))):
				campaign.packs.append(p)
				out.applied.append("content %s" % str(p.get("id", "")))
		for e in doc.get("encounters", []):
			if e is Dictionary and campaign.encounter_entry(str(e.get("id", ""))).is_empty():
				var fresh: Dictionary = JsonDoc.deep(e)
				fresh.erase("live")
				fresh.played = []
				campaign.encounters.append(fresh)
				out.applied.append("encounter %s" % str(e.get("name", e.get("id", ""))))
		campaign.doc.package.version = str(info.package_version)
		campaign.doc.package.tested_with = JsonDoc.deep(info.tested_with)
	if rules:
		out.applied.append("rules as tested with %s %s" % [str(info.name), str(info.package_version)])
	zr.close()
	var updates: Array = campaign.doc.get("package_updates", [])
	updates.append({"to": str(info.package_version), "content": content, "rules": rules, "at": JsonDoc.now(), "session": int(campaign.clock.get("session", 0))})
	campaign.doc.package_updates = updates
	campaign.touch()
	campaign.save()
	out.ok = true
	return out


static func sha256(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


## One digest for a whole package: the SHA-256 of "path hash" lines, sorted.
static func digest_of(hashes: Dictionary) -> String:
	var keys := hashes.keys()
	keys.sort()
	var lines := PackedStringArray()
	for k in keys:
		lines.append("%s %s" % [str(k), str(hashes[k])])
	return sha256("\n".join(lines).to_utf8_buffer())


## Is the package whole? Every file its manifest lists is there with the
## same SHA-256, and nothing is there it does not list. {ok, why, checked}.
## A package from before checksums reports ok with `unchecked`. This
## catches damage in transit; it is not a signature — whoever changes a
## package can change its manifest too.
static func verify(path: String) -> Dictionary:
	var out := {"ok": false, "why": "", "checked": 0, "unchecked": false}
	var info := read(path)
	if not info.ok:
		out.why = str(info.why)
		return out
	var listed: Dictionary = info.manifest.get("files", {}) if info.manifest.get("files") is Dictionary else {}
	if listed.is_empty():
		out.ok = true
		out.unchecked = true
		return out
	if digest_of(listed) != str(info.manifest.get("digest", "")):
		out.why = "its list of files does not match its digest"
		return out
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		out.why = "cannot open it"
		return out
	for n in zr.get_files():
		if n.ends_with("/") or n == "package.json":
			continue
		if not listed.has(n):
			zr.close()
			out.why = "it holds %s, which its manifest does not list" % n
			return out
		if sha256(zr.read_file(n)) != str(listed[n]):
			zr.close()
			out.why = "%s is not what it was when the package was made" % n
			return out
		out.checked += 1
	zr.close()
	if int(out.checked) != listed.size():
		out.why = "%d file%s its manifest lists %s missing" % [listed.size() - int(out.checked), "" if listed.size() - int(out.checked) == 1 else "s", "is" if listed.size() - int(out.checked) == 1 else "are"]
		return out
	out.ok = true
	return out


## What is inside, and under which terms — shown to a DM before they start
## it: [{kind, id, name, version, license, attribution}].
static func contents(path: String) -> Array:
	var out := []
	var info := read(path)
	if not info.ok:
		return out
	out.append({"kind": "campaign", "id": str(info.id), "name": str(info.name), "version": str(info.package_version),
		"license": str(info.license), "attribution": ", ".join(PackedStringArray(info.authors))})
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return out
	for n in zr.get_files():
		var parts := n.split("/")
		var kind := ""
		if parts.size() == 3 and parts[0] == "rules" and parts[2] == "manifest.json":
			kind = "ruleset"
		elif parts.size() == 3 and parts[0] == "art" and parts[2] == "pack.json":
			kind = "art"
		elif parts.size() == 3 and parts[0] == "packs" and parts[2] == "pack.json":
			kind = "content"
		if kind == "":
			continue
		var err := []
		var m := JsonDoc.parse(zr.read_file(n).get_string_from_utf8(), err)
		var prov: Dictionary = m.get("provenance", {}) if m.get("provenance") is Dictionary else {}
		out.append({"kind": kind, "id": str(m.get("id", parts[1])), "name": str(m.get("name", parts[1])),
			"version": str(m.get("version", m.get("pack_version", ""))),
			"license": str(m.get("license", prov.get("license", ""))), "attribution": str(m.get("attribution", prov.get("attribution", "")))})
	zr.close()
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
		# the editor's own bookkeeping is not content
		if not n.begins_with(".") and not n.ends_with(".uid") and not n.ends_with(".import"):
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


static func _minor_floor(v: String) -> String:
	var p := v.split(".")
	return "%s.%s.0" % [p[0], p[1] if p.size() > 1 else "0"]


static func _slug(s: String) -> String:
	var out := ""
	for ch in s.strip_edges().to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if out != "" else "campaign"
