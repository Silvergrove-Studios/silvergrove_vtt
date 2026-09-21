-- sample.focus: the second reference ruleset. No initiative — a spotlight
-- that Players ask for and the GM grants, and that a roll can hand to the
-- GM. Two named dice (bright and dark d10s) give a four-way outcome; dark
-- outcomes feed a GM pool the GM spends to spotlight adversaries. Abilities
-- are cards in a hand and a vault; swapping costs strain. Hit points are a
-- slot track. A countdown ticks on dark outcomes.
local hm = hexmap
local ID = hm.id

hm.schema.define("actor", {
	type = "object",
	required = { "traits" },
	properties = {
		traits = { type = "object", properties = { nerve = { type = "integer" }, grace = { type = "integer" }, wit = { type = "integer" } } },
		hand = { type = "array", items = { type = "string" } },
		vault = { type = "array", items = { type = "string" } },
		adversary = { type = "boolean" },
		thresholds = { type = "object", properties = { major = { type = "integer" }, severe = { type = "integer" } } },
	},
})

-- Cards: data. A card has a name, a trait it rolls with, a recall cost
-- (strain to bring it from the vault) and what it does when played.
local CARDS = {
	dash = { label = "Dash", trait = "grace", recall = 1, effect = { key = "quick", label = "Quick", changes = { { path = "evade", mode = "add", value = 2, type = "status" } }, duration = { kind = "scene" } } },
	rally = { label = "Rally", trait = "nerve", recall = 2, heal = 2 },
	trick = { label = "Trick", trait = "wit", recall = 1, effect = { key = "dazed", label = "Dazed", changes = { { path = "evade", mode = "add", value = -2, type = "status" } }, duration = { kind = "turn_end" }, target = true } },
}

local function ref_of(actor_id) return "actor:" .. actor_id end

-- --------------------------------------------------------------- derive --
hm.derive(function(view)
	local d = view.ext[ID] or { traits = {} }
	local t = d.traits or {}
	return {
		evade = hm.num({ { label = "base", type = "base", value = 8 }, { label = "grace", type = "trait", value = t.grace or 0 } }),
		thresholds = d.thresholds or { major = 4, severe = 8 },
		hand = d.hand or {},
		vault = d.vault or {},
		is_adversary = d.adversary == true,
	}
end)

-- ------------------------------------------------------------------ map --
-- Distances are bands, not numbers: what matters is whether you are
-- close enough, and the table tells you in words.
-- edge-to-edge distances in hexes: adjacent is 0, one hex between is 1
hm.map.bands({ { name = "melee", max = 0.5 }, { name = "very_close", max = 2.5 }, { name = "close", max = 5.5 }, { name = "far", max = 11.5 }, { name = "very_far", max = 1e9 } })
local BAND_ORDER = { melee = 1, very_close = 2, close = 3, far = 4, very_far = 5 }

-- Throw something at a target within Close: an action roll, and a
-- highlight on the table showing the throw's reach.
hm.actions.register("throw", {
	label = "Throw", target = "actor",
	run = function(ctx)
		local mine, theirs = hm.tokens(ctx.actor), hm.tokens(ctx.target)
		if #mine == 0 or #theirs == 0 then error("throw needs both on the map") end
		local scene = mine[1].scene or ctx.scene
		local d = hm.map.distance(scene, "token:" .. mine[1].id, "token:" .. theirs[1].id)
		if BAND_ORDER[d.band] > BAND_ORDER.close then error("too far to throw: " .. d.band) end
		local reach = hm.map.template(scene, { shape = "band", at = "token:" .. mine[1].id, band = "close" })
		hm.commit(hm.map.highlight(scene, reach.cells, "#ffd166", "Close"), "Reach")
		local a = hm.actor(ctx.actor)
		local value = (a.ext[ID].traits or {}).grace or 0
		local entry = hm.dice.roll({ named = { bright = "1d10", dark = "1d10" }, parts = { { label = "grace", type = "trait", value = value } }, kind = "action" },
			{ actor = ctx.actor, kind = "action", dc = 10 + BAND_ORDER[d.band] }, "Throw")
		hm.commit(hm.map.highlight(scene, nil), "Reach")
		return { band = d.band, outcome = entry.result.outcome }
	end,
})

-- ---------------------------------------------------------------- turns --
hm.turns.register({ shape = "focus", name = "Spotlight", description = "The focus moves by fiction; the GM grants it, dark rolls take it." })

-- ---------------------------------------------------------------- views --
-- The sheet a player sees on their phone, and the status everyone sees.
-- Data only: what to show and which intent a tap sends.
hm.ui.register("sheet", {
	type = "column",
	children = {
		{ type = "row", children = {
			{ type = "number", label = "Evade", bind = "/derived/evade" },
			{ type = "text", expr = "'Thresholds ' .. (@derived.thresholds.major ?? 4) .. ' / ' .. (@derived.thresholds.severe ?? 8)", style = "dim" },
		} },
		{ type = "track", label = "Hits", bind = "/resources/hp" },
		{ type = "track", label = "Strain", bind = "/resources/strain" },
		{ type = "track", label = "Armour", bind = "/resources/armour" },
		{ type = "section", title = "Hand", children = {
			{ type = "cards", bind = "/derived/hand", on_tap = { kind = "action", plugin = hm.id, action = "play", ctx = { actor = "$/actor/id", card = "$/card_id", target = "$/actor/id" } } },
		} },
		{ type = "section", title = "Vault", children = {
			{ type = "cards", bind = "/derived/vault", on_tap = { kind = "action", plugin = hm.id, action = "recall", ctx = { actor = "$/actor/id", card = "$/card_id" } }, empty = "empty" },
		} },
		{ type = "action_bar", actions = {
			{ type = "button", label = "Act (nerve)", intent = { kind = "action", plugin = hm.id, action = "act", ctx = { actor = "$/actor/id", trait = "nerve", dc = 10 } } },
			{ type = "button", label = "Act (grace)", intent = { kind = "action", plugin = hm.id, action = "act", ctx = { actor = "$/actor/id", trait = "grace", dc = 10 } } },
			{ type = "button", label = "Act (wit)", intent = { kind = "action", plugin = hm.id, action = "act", ctx = { actor = "$/actor/id", trait = "wit", dc = 10 } } },
		} },
		{ type = "effects", label = "Effects", bind = "/effects" },
	},
})
hm.ui.register("status", {
	type = "column",
	children = {
		{ type = "text", expr = "'GM pool: ' .. (@state.pool ?? 0)", style = "header" },
		{ type = "list", bind = "/tracks", item = { type = "tracker", bind = "/item" } },
	},
})
hm.ui.register("gm", {
	type = "column",
	children = {
		{ type = "text", expr = "'Pool ' .. (@state.pool ?? 0) .. ' · focus ' .. (@turns.focus ?? '')" },
		{ type = "list", bind = "/actors", item = { type = "text", expr = "@item.name .. ': evade ' .. (@item.derived.evade.total ?? '?')" } },
	},
})

-- --------------------------------------------------------------- rolls --
-- Every action roll is bright d10 + dark d10 + trait against a difficulty.
-- Bright ≥ dark on a success: "bright"; otherwise "dark". Doubles are a
-- "shine" (a critical) whatever the total.
hm.on("after_roll", function(p)
	if p.ctx.kind ~= "action" then return p end
	local g = p.result.groups
	local bright, dark = (g.bright or {}).total or 0, (g.dark or {}).total or 0
	local ok = p.result.total >= (p.ctx.dc or 10)
	if bright == dark then p.result.outcome = "shine"
	elseif ok and bright > dark then p.result.outcome = "success_bright"
	elseif ok then p.result.outcome = "success_dark"
	elseif bright > dark then p.result.outcome = "failure_bright"
	else p.result.outcome = "failure_dark" end
	p.result.tone = (p.result.outcome == "shine" or bright > dark) and "bright" or "dark"
	return p
end)

local function pool()
	return (hm.state.get("encounter").pool or 0)
end

local function pool_set(n)
	return hm.state.set("encounter", "", { pool = math.max(0, math.min(hm.settings.get("pool_max", 12), n)) })
end

-- ---------------------------------------------------------------- hooks --
-- When the focus moves to an adversary the GM pays one from the pool
-- (a plugin can veto: no pool, no spotlight).
hm.on("focus_changed", function(p)
	if p.to and p.to:sub(1, 6) == "actor:" then
		local a = hm.actor(p.to:sub(7))
		if a and (a.ext[ID] or {}).adversary and p.by ~= ID then
			local n = pool()
			if n <= 0 then p.veto = "the GM has no pool to spend" return p end
			table.insert(p.events, pool_set(n - 1))
		end
	end
	return p
end)

-- A rest clears strain and gives the GM one pool.
hm.on("rest", function(p)
	table.insert(p.events, pool_set(pool() + 1))
	return p
end)

-- --------------------------------------------------------------- actions --
-- Act: roll the two dice with a trait. A dark outcome feeds the pool and
-- hands the focus to the GM; a bright one keeps it with the players.
hm.actions.register("act", {
	label = "Act", target = "none",
	run = function(ctx)
		local a = hm.actor(ctx.actor)
		if a == nil then error("act needs an actor") end
		local trait = ctx.trait or "nerve"
		local value = (a.ext[ID].traits or {})[trait] or 0
		local spec = { named = { bright = "1d10", dark = "1d10" }, parts = { { label = trait, type = "trait", value = value } }, kind = "action" }
		local entry
		if ctx.help then
			-- a helper joins: open the roll, take the help die, resolve
			local id = hm.dice.open(spec, { actor = ctx.actor, kind = "action", dc = ctx.dc or 10 }, "Act", "all", 30)
			hm.dice.contribute(id, ctx.help.by, "help", ctx.help.expr or "1d6")
			entry = hm.dice.resolve(id)
		else
			entry = hm.dice.roll(spec, { actor = ctx.actor, kind = "action", dc = ctx.dc or 10 }, "Act")
		end
		local out = { outcome = entry.result.outcome, tone = entry.result.tone, total = entry.result.total }
		if out.tone == "dark" then
			hm.commit(pool_set(pool() + 1), "Pool")
			local turns = hm.turns.current()
			if turns.running and turns.strategy == "focus" and turns.focus ~= "gm" then
				hm.turns.set_focus("gm", ID)
			end
		end
		return out
	end,
})

-- Play a card from the hand: the effect it grants, or the healing it does.
hm.actions.register("play", {
	label = "Play a card", target = "actor",
	run = function(ctx)
		local a = hm.actor(ctx.actor)
		local card = CARDS[ctx.card]
		if card == nil then error("no card '" .. tostring(ctx.card) .. "'") end
		local hand = (a.ext[ID].hand or {})
		local found = false
		for _, c in ipairs(hand) do if c == ctx.card then found = true end end
		if not found then error(card.label .. " is not in the hand") end
		local events = {}
		if card.effect then
			local on = card.effect.target and ref_of(ctx.target) or ref_of(ctx.actor)
			for _, ev in ipairs(hm.effects.apply({ on = on, key = card.effect.key, label = card.effect.label, value = 1,
				changes = card.effect.changes, duration = card.effect.duration, stack = "highest" })) do table.insert(events, ev) end
		end
		if card.heal then
			local ev = hm.resources.clear(ref_of(ctx.actor), "hp", card.heal)
			if ev then table.insert(events, ev) end
		end
		hm.commit(events, card.label)
		return { played = ctx.card, effects = #events }
	end,
})

-- Move a card from the vault to the hand: costs strain (recall cost),
-- unless the actor just rested (the GM says so in ctx).
hm.actions.register("recall", {
	label = "Recall a card", target = "none",
	run = function(ctx)
		local a = hm.actor(ctx.actor)
		local card = CARDS[ctx.card]
		if card == nil then error("no card '" .. tostring(ctx.card) .. "'") end
		local d = a.ext[ID]
		local vault, hand = {}, {}
		local moved = false
		for _, c in ipairs(d.vault or {}) do
			if c == ctx.card and not moved then moved = true else table.insert(vault, c) end
		end
		if not moved then error(card.label .. " is not in the vault") end
		for _, c in ipairs(d.hand or {}) do table.insert(hand, c) end
		if #hand >= hm.settings.get("hand_size", 3) then error("the hand is full") end
		table.insert(hand, ctx.card)
		local events = { { t = "actor.set", id = ctx.actor, changes = { ["ext/" .. ID .. "/hand"] = hand, ["ext/" .. ID .. "/vault"] = vault } } }
		if not ctx.free then
			local strain = hm.resources.mark(ref_of(ctx.actor), "strain", card.recall)
			if strain == nil then error("too much strain to recall " .. card.label) end
			table.insert(events, strain)
		end
		hm.commit(events, "Recall " .. card.label)
		return { hand = hand, vault = vault }
	end,
})

-- Damage: thresholds decide how many boxes; the target's owner may spend
-- an armour box to drop one tier.
hm.actions.register("damage", {
	label = "Damage", target = "actor",
	run = function(ctx)
		local a = hm.actor(ctx.target)
		local d = hm.derived(ctx.target)
		local amount = ctx.amount or 0
		local th = d.thresholds
		local boxes = amount >= th.severe and 3 or (amount >= th.major and 2 or (amount > 0 and 1 or 0))
		local armour = hm.resources.get(ref_of(ctx.target), "armour")
		if boxes > 1 and armour and armour.marked < armour.max and a.owner and a.owner ~= "" then
			local ans = hm.prompt(a.owner, { title = "Spend armour?", fields = { { key = "spend", type = "bool", label = "Mark an armour box to take one box less" } } },
				{ default = { spend = false }, deadline = 20 })
			if ans and ans.spend then
				hm.commit(hm.resources.mark(ref_of(ctx.target), "armour", 1), "Armour")
				boxes = boxes - 1
			end
		end
		local ev = hm.resources.mark(ref_of(ctx.target), "hp", boxes)
		local down = false
		if ev == nil then
			local hp = hm.resources.get(ref_of(ctx.target), "hp")
			ev = hm.resources.set(ref_of(ctx.target), "hp", hm.resources.track(hp.max, hp.max + hp.extra - #hp.crossed, hp.extra, hp.crossed, "rest"))
			down = true
		end
		hm.commit(ev, "Damage")
		return { boxes = boxes, down = down }
	end,
})

-- Set up an actor's tracks and a scene countdown.
hm.actions.register("setup", {
	label = "Set up", target = "actor",
	run = function(ctx)
		local events = {
			hm.resources.set(ref_of(ctx.actor), "hp", hm.resources.track(6, 0, 0, {}, "rest")),
			hm.resources.set(ref_of(ctx.actor), "strain", hm.resources.track(6, 0, 0, {}, "rest")),
			hm.resources.set(ref_of(ctx.actor), "armour", hm.resources.track(ctx.armour or 1, 0, 0, {}, "rest")),
		}
		hm.commit(events, "Set up")
		return true
	end,
})

hm.actions.register("countdown", {
	label = "Start a countdown", target = "none",
	run = function(ctx)
		local track = hm.tracks.make(ctx.name or "Doom", ctx.steps or 3, "countdown",
			{ on = "roll_outcome", outcomes = { "failure_dark", "success_dark" }, amount = 1 }, "all", ctx.on_done or "It happens.")
		hm.commit(hm.tracks.add(track), "Countdown")
		return track.id
	end,
})

-- When a countdown finishes, the GM gains pool and the log says so.
hm.on("track_done", function(p)
	local tr = hm.tracks.get(p.track)
	if tr and tr.plugin == ID then
		table.insert(p.events, pool_set(pool() + 2))
		hm.log((tr.on_done or "") .. " (" .. tr.name .. ")", "all")
	end
	return p
end)
