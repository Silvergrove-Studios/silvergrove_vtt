-- sample.ordered: the reference ruleset. Six stats, a defence, initiative,
-- a d20 against a difficulty with three outcomes, conditions as effects,
-- hit points as a pool, armour as a slot track, and three actions.
local hm = hexmap
local ID = hm.id

-- ------------------------------------------------------------- schema --
-- What an actor's data for this ruleset must look like.
hm.schema.define("actor", {
	type = "object",
	required = { "level", "stats" },
	properties = {
		level = { type = "integer", minimum = 1, maximum = 20 },
		stats = {
			type = "object",
			required = { "agi", "str", "wit" },
			properties = {
				agi = { type = "integer", minimum = -5, maximum = 10 },
				str = { type = "integer", minimum = -5, maximum = 10 },
				wit = { type = "integer", minimum = -5, maximum = 10 },
			},
			additionalProperties = false,
		},
		armour = { type = "integer", minimum = 0, maximum = 5 },
		traits = { type = "array", items = { type = "string" } },
	},
	additionalProperties = false,
})

-- --------------------------------------------------------- conditions --
-- Data, not code: the kernel applies `changes` to the derived numbers.
local CONDITIONS = {
	shaken = { label = "Shaken", stack = "highest", changes = { { path = "defence", mode = "add", value = -2, type = "status" } } },
	prone = { label = "Prone", stack = "none", changes = { { path = "defence", mode = "add", value = -2, type = "status" }, { path = "speed", mode = "multiply", value = 0.5 } } },
	blessed = { label = "Blessed", stack = "highest", changes = { { path = "attack", mode = "add", expr = "@value", type = "status" } } },
}

local function condition(key, on, value, duration)
	local c = CONDITIONS[key]
	if c == nil then error("no condition '" .. tostring(key) .. "'") end
	return hm.effects.apply({
		on = on, key = key, label = c.label, value = value or 1,
		stack = c.stack, changes = c.changes, duration = duration or { kind = "until_cleared" },
	})
end

-- ---------------------------------------------------------------- derive --
hm.derive(function(view)
	local d = view.ext[ID] or { level = 1, stats = { agi = 0, str = 0, wit = 0 } }
	local s = d.stats
	local armour = d.armour or 0
	return {
		defence = hm.num({ { label = "base", type = "base", value = 10 }, { label = "agility", type = "ability", value = s.agi }, { label = "armour", type = "item", value = armour } }),
		initiative = hm.num({ { label = "agility", type = "ability", value = s.agi }, { label = "wits", type = "ability", value = s.wit } }),
		attack = hm.num({ { label = "strength", type = "ability", value = s.str } }),
		hp_max = 6 + d.level * 4 + s.str,
		speed = 6,
		label = "Level " .. tostring(d.level),
	}
end)

-- ----------------------------------------------------------------- turns --
-- Ordered turns from the derived initiative, highest first, one action a
-- turn; a strike spends it.
hm.turns.register({
	shape = "ordered", name = "Initiative", description = "Highest initiative first; one action a turn.",
	initiative = "initiative", tie_break = "highest", budgets = { actions = 1 },
})

-- ----------------------------------------------------------------- views --
hm.ui.register("sheet", {
	type = "column",
	children = {
		{ type = "text", bind = "/derived/label", style = "dim" },
		{ type = "row", children = {
			{ type = "number", label = "Defence", bind = "/derived/defence" },
			{ type = "number", label = "Initiative", bind = "/derived/initiative" },
			{ type = "number", label = "Attack", bind = "/derived/attack" },
		} },
		{ type = "pool", label = "Hit points", bind = "/resources/hp" },
		{ type = "track", label = "Armour", bind = "/resources/armour" },
		{ type = "effects", label = "Conditions", bind = "/effects" },
		{ type = "glyphs", label = "an unknown widget type, for the test" },
	},
})

-- ----------------------------------------------------------------- hooks --
-- Attack rolls carry the attacker's attack parts and every condition that
-- bears on rolls.
hm.on("before_roll", function(p)
	local actor = p.ctx.actor
	if actor == nil then return p end
	if p.ctx.kind == "attack" then
		local d = hm.derived(actor)
		for _, part in ipairs((d.attack or {}).parts or {}) do
			table.insert(p.spec.parts, part)
		end
	end
	if hm.effects.has("actor:" .. actor, "shaken") then
		table.insert(p.spec.parts, { label = "shaken", type = "status", value = -2 })
	end
	if p.ctx.forbidden then p.veto = "sample.ordered forbids this roll" end
	return p
end)

-- Success at or above the difficulty; a natural critical_on is a critical.
hm.on("after_roll", function(p)
	if p.ctx.dc == nil then return p end
	local faces = ((p.result.groups or {}).main or {}).faces or {}
	p.result.outcome = (p.result.total >= p.ctx.dc) and "success" or "failure"
	if #faces == 1 and faces[1] >= hm.settings.get("critical_on", 20) then
		p.result.outcome = "critical"
	end
	return p
end)

-- --------------------------------------------------------------- actions --
-- Strike: an attack roll against the target's defence; on a hit, damage,
-- with the target's owner asked whether to spend armour first.
hm.actions.register("strike", {
	label = "Strike", cost = { actions = 1 }, target = "actor",
	run = function(ctx)
		local target = hm.actor(ctx.target)
		if target == nil then error("strike needs a target actor") end
		-- in ordered turns, a strike costs the action
		local turns = hm.turns.current()
		if turns.running and turns.strategy == "ordered" then
			local ref = "token:" .. (ctx.token or "")
			if ctx.token and turns.counters[ref] then
				local spend = hm.turns.consume(ref, "actions", 1)
				if spend == nil then error("no action left this turn") end
				hm.commit(spend, "Action")
			end
		end
		-- on a map, a strike needs the target within reach (one hex)
		if ctx.token and ctx.scene then
			local theirs = hm.tokens(ctx.target)
			if #theirs > 0 then
				local d = hm.map.distance(ctx.scene, "token:" .. ctx.token, "token:" .. theirs[1].id)
				if d.edge > 1 then error(string.format("out of reach (%.1f hexes away)", d.edge)) end
			end
		end
		local dc = hm.value((hm.derived(ctx.target) or {}).defence)
		local attack = hm.dice.roll("1d20", { actor = ctx.actor, kind = "attack", dc = dc }, "Strike")
		local out = { outcome = attack.result.outcome, damage = 0 }
		if out.outcome == "failure" then return out end
		local dmg = hm.dice.roll("1d8", { actor = ctx.actor, kind = "damage" }, "Damage")
		local amount = dmg.result.total
		if out.outcome == "critical" then amount = amount * 2 end
		local armour = hm.resources.get("actor:" .. ctx.target, "armour")
		if armour ~= nil and armour.marked < armour.max and target.owner ~= nil and target.owner ~= "" then
			local answer = hm.prompt(target.owner, {
				title = "Spend armour?",
				fields = { { key = "spend", type = "bool", label = "Mark an armour slot to reduce the hit by " .. hm.settings.get("armour_reduces", 2) } },
			}, { default = { spend = false }, deadline = 30 })
			if answer and answer.spend then
				hm.commit(hm.resources.mark("actor:" .. ctx.target, "armour", 1), "Armour")
				amount = math.max(0, amount - hm.settings.get("armour_reduces", 2))
			end
		end
		out.damage = amount
		local ev = hm.resources.spend("actor:" .. ctx.target, "hp", amount)
		if ev == nil then
			local hp = hm.resources.get("actor:" .. ctx.target, "hp") or { max = 0 }
			ev = hm.resources.set("actor:" .. ctx.target, "hp", hm.resources.pool(0, hp.max, "rest"))
			out.down = true
		end
		hm.commit(ev, "Damage", { roll = dmg.id })
		if out.down then
			hm.commit(condition("prone", "actor:" .. ctx.target), "Down")
		end
		return out
	end,
})

-- Apply a named condition to a token or actor.
hm.actions.register("condition", {
	label = "Condition", cost = { actions = 0 }, target = "ref",
	run = function(ctx)
		local events = condition(ctx.key, ctx.target, ctx.value, ctx.duration)
		if #events == 0 then return { applied = false } end
		hm.commit(events, CONDITIONS[ctx.key].label)
		return { applied = true }
	end,
})

-- Rest: pools and tracks with recharge "rest" refill, resting effects end.
hm.actions.register("rest", {
	label = "Rest", cost = { actions = 0 },
	run = function(ctx)
		local events = hm.resources.refill("rest")
		for _, ev in ipairs(hm.effects.expire({ kind = "rest" })) do table.insert(events, ev) end
		if #events > 0 then hm.commit(events, "Rest") end
		hm.log("The party rests.", "all")
		return { refilled = #events }
	end,
})

-- The starting resources for an actor, so the Table (or a test) can set
-- them up with one call.
hm.actions.register("setup", {
	label = "Set up resources", cost = { actions = 0 }, target = "actor",
	run = function(ctx)
		local d = hm.derived(ctx.actor)
		local a = hm.actor(ctx.actor)
		local armour = (a.ext[ID] or {}).armour or 0
		local events = { hm.resources.set("actor:" .. ctx.actor, "hp", hm.resources.pool(d.hp_max, d.hp_max, "rest")) }
		if armour > 0 then
			table.insert(events, hm.resources.set("actor:" .. ctx.actor, "armour", hm.resources.track(armour, 0, 0, {}, "rest")))
		end
		hm.commit(events, "Set up")
		return { hp = d.hp_max, armour = armour }
	end,
})
