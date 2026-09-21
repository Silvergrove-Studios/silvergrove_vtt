-- sample.house: house rules over sample.ordered. Loaded after it (it
-- depends on it), it replaces the base ruleset's after_roll — the
-- manifest's `overrides` — so a roll is classified here instead, and adds
-- a before_roll of its own that runs after the base one.
local hm = hexmap

-- Criticals from critical_from (19 by default) up; a natural 1 is a fumble.
hm.on("after_roll", function(p)
	if p.ctx.dc == nil then return p end
	local faces = ((p.result.groups or {}).main or {}).faces or {}
	p.result.outcome = (p.result.total >= p.ctx.dc) and "success" or "failure"
	if #faces == 1 then
		if faces[1] >= hm.settings.get("critical_from", 19) then p.result.outcome = "critical" end
		if faces[1] == 1 then p.result.outcome = "fumble" end
	end
	p.result.house = true
	return p
end)

-- Attacks in the dark are harder: the base ruleset's parts stay, this adds one.
hm.on("before_roll", function(p)
	if p.ctx.kind == "attack" and p.ctx.dark then
		table.insert(p.spec.parts, { label = "darkness", type = "circumstance", value = -2 })
	end
	return p
end)

-- The base ruleset's own hook: a hard hit (6 or more) also shakes the
-- target. hm.hooks.run in sample.ordered's strike is where this lands.
hm.on("sample.ordered.after_damage", function(p)
	if p.amount >= 6 then
		table.insert(p.events, { t = "log.add", entry = { id = "n_hard_" .. tostring(p.roll), kind = "note", text = "a hard hit", audience = "all" } })
		p.note = "hard hit"
	end
	return p
end)

-- A fumble costs the attacker their footing: a ruling worth writing down.
hm.actions.register("fumble", {
	label = "Resolve a fumble", target = "actor",
	run = function(ctx)
		hm.log(hm.actor(ctx.actor).name .. " fumbles and drops prone", "all")
		return { prone = true }
	end,
})
