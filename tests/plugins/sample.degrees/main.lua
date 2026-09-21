-- sample.degrees: the third reference ruleset. Every check has four
-- degrees of success (±10 from the difficulty, a natural 20 or 1 shifts
-- one step); conditions carry a value that ticks down; three actions a
-- turn with a mounting penalty on repeated attacks; and a shipped
-- compendium of creatures and feats that actors are made from.
local hm = hexmap
local ID = hm.id

-- ---------------------------------------------------------------- schemas --
local STATS = { type = "object", required = { "might", "agility", "mind" }, properties = {
	might = { type = "integer", minimum = -5, maximum = 8 }, agility = { type = "integer", minimum = -5, maximum = 8 }, mind = { type = "integer", minimum = -5, maximum = 8 } } }
local RANKS = { type = "object", properties = {
	perception = { type = "integer", minimum = 0, maximum = 4 }, stealth = { type = "integer", minimum = 0, maximum = 4 }, athletics = { type = "integer", minimum = 0, maximum = 4 } } }

hm.schema.define("actor", {
	type = "object", required = { "level", "stats" },
	properties = { level = { type = "integer", minimum = 1, maximum = 20 }, stats = STATS, ranks = RANKS, ac_base = { type = "integer", minimum = 5, maximum = 30 },
		feats = { type = "array", items = { type = "string" } }, source = { type = "string" } },
})
-- The shape of a creature entry in the compendium (shipped or homebrew).
hm.schema.define("creatures", {
	type = "object", required = { "id", "name", "level", "stats" },
	properties = { id = { type = "string" }, name = { type = "string" }, level = { type = "integer", minimum = 0, maximum = 25 },
		kind = { type = "string", enum = { "humanoid", "animal", "giant", "undead", "fey", "other" } },
		traits = { type = "array", items = { type = "string" } }, stats = STATS, ranks = RANKS,
		ac_base = { type = "integer", minimum = 5, maximum = 30 }, hp = { type = "integer", minimum = 1 }, text = { type = "string", format = "text" } },
})
hm.schema.define("feats", {
	type = "object", required = { "id", "name", "level" },
	properties = { id = { type = "string" }, name = { type = "string" }, level = { type = "integer", minimum = 1, maximum = 20 },
		kind = { type = "string", enum = { "general", "skill", "class" } }, traits = { type = "array", items = { type = "string" } }, text = { type = "string", format = "text" } },
})

-- ------------------------------------------------------------------ derive --
local function prof(rank, level)
	if rank == 0 then return 0 end
	return rank * 2 + level
end

hm.derive(function(view)
	local d = view.ext[ID] or { level = 1, stats = { might = 0, agility = 0, mind = 0 } }
	local s, r = d.stats, d.ranks or {}
	local L = d.level
	local feats = {}
	for _, f in ipairs(d.feats or {}) do feats[f] = true end
	local perception = hm.num({ { label = "mind", type = "attribute", value = s.mind }, { label = "proficiency", type = "proficiency", value = prof(r.perception or 0, L) },
		(feats["keen-eyes"] and { label = "keen eyes", type = "circumstance", value = 1 } or { label = "", type = "untyped", value = 0 }) })
	return {
		ac = hm.num({ { label = "base", type = "base", value = d.ac_base or 10 }, { label = "agility", type = "attribute", value = s.agility } }),
		perception = perception,
		stealth = hm.num({ { label = "agility", type = "attribute", value = s.agility }, { label = "proficiency", type = "proficiency", value = prof(r.stealth or 0, L) } }),
		athletics = hm.num({ { label = "might", type = "attribute", value = s.might }, { label = "proficiency", type = "proficiency", value = prof(r.athletics or 0, L) } }),
		attack = hm.num({ { label = "might", type = "attribute", value = s.might }, { label = "proficiency", type = "proficiency", value = 2 + L } }),
		hp_max = (d.hp or (8 + L * 6)) ,
		label = "Level " .. tostring(L),
		feats = d.feats or {},
	}
end)

-- ------------------------------------------------------------------- turns --
hm.turns.register({ shape = "ordered", name = "Perception order", description = "Highest perception first; three actions and a reaction each turn.",
	initiative = "perception", tie_break = "highest", budgets = { actions = 3, reactions = 1 } })

-- Slowed costs actions at the start of the turn; the attack count resets.
hm.on("turn_start", function(p)
	if not p.actor or p.actor == "" then return p end
	table.insert(p.events, { t = "ext.set", scope = "token", scene = "", id = "", plugin = ID, changes = {} })
	table.remove(p.events)
	for _, fx in ipairs(hm.effects.on("actor:" .. p.actor, "slowed")) do
		local ev = hm.turns.consume(p.ref, "actions", fx.value or 1)
		if ev then table.insert(p.events, ev) end
	end
	table.insert(p.events, hm.state.set("encounter", "", { ["attacks/" .. p.actor] = 0 }))
	return p
end)

-- Frightened drops by one at the end of the turn (two with Steady).
hm.on("turn_end", function(p)
	if not p.actor or p.actor == "" then return p end
	local d = hm.derived(p.actor)
	local steady = false
	for _, f in ipairs(d.feats or {}) do if f == "steady" then steady = true end end
	for _, fx in ipairs(hm.effects.on("actor:" .. p.actor, "frightened")) do
		local v = (fx.value or 1) - (steady and 2 or 1)
		if v <= 0 then
			for _, ev in ipairs(hm.effects.remove(fx.id)) do table.insert(p.events, ev) end
		else
			table.insert(p.events, hm.effects.set(fx.id, { value = v, changes = { { path = "ac", mode = "add", value = 0 } } }))
		end
	end
	return p
end)

-- ------------------------------------------------------------------- rolls --
-- Frightened subtracts its value from every check; the attack penalty
-- mounts with each attack in a turn.
hm.on("before_roll", function(p)
	local actor = p.ctx.actor
	if not actor then return p end
	for _, fx in ipairs(hm.effects.on("actor:" .. actor, "frightened")) do
		table.insert(p.spec.parts, { label = "frightened", type = "status", value = -(fx.value or 1) })
	end
	if p.ctx.kind == "attack" then
		for _, part in ipairs((hm.derived(actor).attack or {}).parts or {}) do table.insert(p.spec.parts, part) end
		local n = ((hm.state.get("encounter").attacks or {})[actor]) or 0
		local map = hm.settings.get("map", { 0, -5, -10 })
		local penalty = map[math.min(n + 1, #map)]
		local quick = false
		for _, f in ipairs(hm.derived(actor).feats or {}) do if f == "quick-draw" then quick = true end end
		if quick and n == 0 then penalty = 0 end
		if penalty ~= 0 then table.insert(p.spec.parts, { label = "attack " .. (n + 1), type = "untyped", value = penalty }) end
	end
	return p
end)

-- Four degrees, with the natural 20 / 1 step.
hm.on("after_roll", function(p)
	local dc = p.ctx.dc
	if dc == nil then return p end
	local t = p.result.total
	local steps = { "critical_failure", "failure", "success", "critical_success" }
	local i = (t >= dc + 10) and 4 or ((t >= dc) and 3 or ((t > dc - 10) and 2 or 1))
	local faces = ((p.result.groups or {}).main or {}).faces or {}
	if #faces == 1 then
		if faces[1] == 20 then i = math.min(4, i + 1) end
		if faces[1] == 1 then i = math.max(1, i - 1) end
	end
	p.result.outcome = steps[i]
	p.result.degree = i
	return p
end)

-- ----------------------------------------------------------------- actions --
local function ref_of(a) return "actor:" .. a end

hm.actions.register("strike", {
	label = "Strike", cost = { actions = 1 }, target = "actor",
	run = function(ctx)
		local turns = hm.turns.current()
		if turns.running and ctx.token then
			local spend = hm.turns.consume("token:" .. ctx.token, "actions", 1)
			if spend == nil then error("no action left this turn") end
			hm.commit(spend, "Action")
		end
		local ac = hm.value((hm.derived(ctx.target) or {}).ac)
		-- cover from what stands between, when both are on the map
		local cover = "none"
		local mine, theirs = hm.tokens(ctx.actor), hm.tokens(ctx.target)
		if #mine > 0 and #theirs > 0 then
			local los = hm.map.los(mine[1].scene, "token:" .. mine[1].id, "token:" .. theirs[1].id)
			cover = los.cover
			if not los.clear then error("no line of sight to the target") end
			if cover == "partial" then ac = ac + 2 end
		end
		local attack = hm.dice.roll("1d20", { actor = ctx.actor, kind = "attack", dc = ac }, "Strike")
		attack.result.cover = cover
		local n = ((hm.state.get("encounter").attacks or {})[ctx.actor]) or 0
		hm.commit(hm.state.set("encounter", "", { ["attacks/" .. ctx.actor] = n + 1 }), "Attack count")
		local out = { outcome = attack.result.outcome, degree = attack.result.degree, damage = 0 }
		if out.degree >= 3 then
			local dmg = hm.dice.roll("1d8", { actor = ctx.actor, kind = "damage" }, "Damage")
			local amount = dmg.result.total + math.max(0, hm.value(hm.derived(ctx.actor).attack) - (2 + (hm.actor(ctx.actor).ext[ID].level or 1)))
			if out.degree == 4 then amount = amount * 2 end
			out.damage = amount
			local ev = hm.resources.spend(ref_of(ctx.target), "hp", amount)
			if ev == nil then
				local hp = hm.resources.get(ref_of(ctx.target), "hp") or { max = 0 }
				ev = hm.resources.set(ref_of(ctx.target), "hp", hm.resources.pool(0, hp.max, "rest"))
				out.down = true
			end
			hm.commit(ev, "Damage", { roll = dmg.id })
		elseif out.degree == 1 then
			hm.commit(hm.effects.apply({ on = ref_of(ctx.actor), key = "off-guard", label = "Off-guard", stack = "none",
				changes = { { path = "ac", mode = "add", value = -2, type = "status" } }, duration = { kind = "turn_start", of = ctx.token or ref_of(ctx.actor), turns = 1 } }), "Fumble")
		end
		return out
	end,
})

-- A valued condition from the compendium's list.
hm.actions.register("condition", {
	label = "Condition", cost = { actions = 0 }, target = "actor",
	run = function(ctx)
		local c = hm.comp.get("conditions", ctx.key)
		if c == nil then error("no condition '" .. tostring(ctx.key) .. "'") end
		local changes = {}
		if ctx.key == "off-guard" then changes = { { path = "ac", mode = "add", value = -2, type = "status" } } end
		local events = hm.effects.apply({ on = ref_of(ctx.target), key = ctx.key, label = c.name, value = c.valued and (ctx.value or 1) or nil,
			stack = c.valued and "highest" or "none", changes = changes, duration = { kind = "until_cleared" } })
		if #events == 0 then return { applied = false } end
		hm.commit(events, c.name)
		return { applied = true }
	end,
})

-- An actor from a compendium creature (shipped or homebrew alike), and a
-- token for it when a scene is given.
hm.actions.register("spawn", {
	label = "Add to the scene", target = "entry", collection = "creatures",
	run = function(ctx)
		local e = ctx.entry
		if e == nil or e.stats == nil then error("spawn needs a creature entry") end
		local id = "a_" .. e.id .. "_" .. tostring(hm.comp.count("creatures")) .. tostring(#hm.actors())
		local events = {
			{ t = "actor.add", actor = { id = id, kind = "npc", name = e.name, ext = { [ID] = { level = e.level, stats = e.stats, ranks = e.ranks or {}, ac_base = e.ac_base or 10, hp = e.hp, source = e.id } }, packs = hm.comp.versions() } },
			hm.resources.set(ref_of(id), "hp", hm.resources.pool(e.hp or 10, e.hp or 10, "rest")),
		}
		if ctx.scene and ctx.scene ~= "" then
			table.insert(events, { t = "token.add", scene = ctx.scene, token = { id = "t_" .. id, name = e.name, label = string.sub(e.name, 1, 1), art = "", color = "#c0392b",
				pos = { ctx.x or 0, ctx.y or 0 }, size = 1, rot = 0, elevation = 0, hidden = true, vision = { radius = 6 }, tags = {}, actor = id } })
		end
		hm.commit(events, "Spawn " .. e.name)
		return { actor = id }
	end,
})

-- A burst: everything in a circle around a place saves against it as one
-- step — a failure takes the damage, a critical failure double, a success
-- half, a critical success none. hm.bulk.roll does the per-target work.
hm.actions.register("burst", {
	label = "Burst", cost = { actions = 2 }, target = "ref",
	run = function(ctx)
		local area = hm.map.template(ctx.scene, { shape = "circle", at = ctx.at, radius = ctx.radius or 1, blocked_by_walls = true, include_self = true })
		hm.commit(hm.map.highlight(ctx.scene, area.cells, "#ff6b35", "Burst"), "Burst")
		local dmg = hm.dice.roll("2d6", { actor = ctx.actor, kind = "damage" }, "Burst").result.total
		local targets = {}
		for _, tid in ipairs(area.tokens) do
			local tk = hm.map.token(ctx.scene, tid)
			if tk and tk.actor and tk.actor ~= "" then table.insert(targets, ref_of(tk.actor)) end
		end
		local results = hm.bulk.roll(targets, "1d20", { kind = "save", dc = ctx.dc or 12 }, {
			critical_failure = { { kind = "resource", plugin = ID, name = "hp", delta = -dmg * 2 } },
			failure = { { kind = "resource", plugin = ID, name = "hp", delta = -dmg } },
			success = { { kind = "resource", plugin = ID, name = "hp", delta = -math.floor(dmg / 2) } },
			critical_success = {},
		}, "Burst")
		hm.commit(hm.map.highlight(ctx.scene, nil), "Burst")
		local hit = {}
		for _, r in ipairs(results) do table.insert(hit, { ref = r.ref, outcome = r.outcome }) end
		return { cells = #area.cells, hit = hit, damage = dmg }
	end,
})

-- "We ruled that…": a GM decision recorded with the rule it rests on.
hm.actions.register("rule", {
	label = "Record a ruling", target = "",
	run = function(ctx)
		local id = hm.ruling(ctx.text or "", { rule = ctx.rule, roll = ctx.roll, tags = ctx.tags or {} })
		return { id = id }
	end,
})

-- ------------------------------------------------------------ improvise --
-- "A level-4 brute, now": the benchmark tables of this ruleset, one form.
hm.improv.register("creature", {
	label = "Creature by level",
	params = {
		level = { type = "integer", minimum = 0, maximum = 20, default = 1, title = "Level" },
		role = { type = "string", enum = { "brute", "skirmisher", "caster" }, default = "brute", title = "Role" },
	},
	make = function(p)
		local level = tonumber(p.level) or 1
		local role = p.role or "brute"
		local stats = { might = 0, agility = 0, mind = 0 }
		local bump = math.floor(level / 3) + 1
		if role == "brute" then stats.might = bump + 1 stats.agility = 0 stats.mind = -1
		elseif role == "skirmisher" then stats.agility = bump + 1 stats.might = 0 stats.mind = 0
		else stats.mind = bump + 1 stats.might = -1 stats.agility = 0 end
		local hp = 8 + level * (role == "brute" and 10 or 7)
		return {
			kind = "npc",
			ext = { level = math.max(1, level), stats = stats, ac_base = 10 + math.floor(level / 2) + (role == "skirmisher" and 2 or 0), source = "improvised" },
			token = { color = role == "brute" and "#a83232" or (role == "skirmisher" and "#3273a8" or "#7a32a8"), size = (role == "brute" and level >= 6) and 2 or 1 },
			resources = { [ID] = { hp = { kind = "pool", current = hp, max = hp, recharge = "rest" } } },
		}
	end,
})

-- A zone of fire that burns for two rounds; whoever walks in takes damage.
hm.actions.register("fire_zone", {
	label = "Fire zone", cost = { actions = 2 }, target = "ref",
	run = function(ctx)
		local cells = hm.map.cells_within(ctx.scene, ctx.at, ctx.radius or 1)
		local region = hm.map.region("fire_" .. tostring(#cells) .. tostring(hm.clock.get().rests), cells, { "fire", "hazard" },
			{ label = "Fire", color = "#ff4500", duration = { kind = "rounds", rounds = 2 } })
		hm.commit(hm.map.region_add(ctx.scene, region), "Fire")
		return { region = region.id, cells = #cells }
	end,
})

hm.on("region_entered", function(p)
	local rec = p.record or {}
	local tags = rec.tags or {}
	local fire = false
	for _, tg in ipairs(tags) do if tg == "fire" then fire = true end end
	if fire and p.actor and p.actor ~= "" then
		local dmg = hm.dice.roll("1d6", { actor = p.actor, kind = "damage" }, "Fire")
		local ev = hm.resources.spend(ref_of(p.actor), "hp", dmg.result.total)
		if ev then table.insert(p.events, ev) end
		hm.log(hm.actor(p.actor).name .. " walks into the fire", "all")
	end
	return p
end)

-- Difficult ground costs a step of movement budget: a tagged region.
hm.on("token_moved", function(p)
	for _, tg in ipairs(hm.map.tags_at(p.scene, p.to)) do
		if tg == "wall_of_force" then p.veto = "the wall of force stops you" return p end
	end
	return p
end)

hm.actions.register("setup", {
	label = "Set up", target = "actor",
	run = function(ctx)
		local d = hm.derived(ctx.actor)
		hm.commit(hm.resources.set(ref_of(ctx.actor), "hp", hm.resources.pool(d.hp_max, d.hp_max, "rest")), "Set up")
		return { hp = d.hp_max }
	end,
})

-- ------------------------------------------------------------------- views --
hm.ui.register("sheet", {
	type = "column",
	children = {
		{ type = "text", bind = "/derived/label", style = "dim" },
		{ type = "row", children = {
			{ type = "number", label = "AC", bind = "/derived/ac" },
			{ type = "number", label = "Perception", bind = "/derived/perception" },
			{ type = "number", label = "Attack", bind = "/derived/attack" },
		} },
		{ type = "pool", label = "Hit points", bind = "/resources/hp" },
		{ type = "text", expr = "'Actions left: ' .. ((@turns.counters[\"token:\" .. (@tokens[0].id ?? \"\")].actions) ?? \"—\")", style = "dim" },
		{ type = "effects", label = "Conditions", bind = "/effects" },
		{ type = "list", bind = "/derived/feats", item = { type = "text", expr = "'Feat: ' .. @item" }, empty = "no feats" },
	},
})
