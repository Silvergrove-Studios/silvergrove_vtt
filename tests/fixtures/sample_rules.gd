class_name SampleRules
extends RefCounted
## An original, deliberately small ruleset written against the kernel in
## GDScript: the Phase 1 fixture. Six numbers, a defence, initiative, a
## d20 with three outcomes, a "shaken" condition, hit points as a pool.
## Not a game anyone plays; a probe for the API. Phase 2 rewrites it in
## Lua as `sample.ordered`.
##
## actor.ext.sample: { level, stats: {agi, str, wit} }
## derived.sample:   defence (typed), initiative (typed), attack (typed), hp_max

const ID := "sample"
const POLICY := {"status": "best", "circumstance": "best"}

## Weak: the kernel keeps this ruleset alive (it is the `owner`), not the
## other way round.
var _kernel: WeakRef
var kernel: RulesKernel:
	get: return _kernel.get_ref() if _kernel != null else null


func install(k: RulesKernel) -> void:
	_kernel = weakref(k)
	k.register_ruleset(ID, {"owner": self, "derive": derive, "policy": POLICY, "fields": {"level_label": "\"Level \" .. (@actor.ext.sample.level ?? 1)"}})
	k.hooks.on("before_roll", before_roll, ID)
	k.hooks.on("after_roll", after_roll, ID)


## Pure: the view in, the numbers out.
func derive(view: Dictionary) -> Dictionary:
	var ext: Dictionary = view.get("ext", {}).get(ID, {})
	var stats: Dictionary = ext.get("stats", {})
	var agi := float(stats.get("agi", 0))
	var strength := float(stats.get("str", 0))
	var level := int(ext.get("level", 1))
	return {
		"defence": TypedNumber.make([{"label": "base", "type": "base", "value": 10}, {"label": "agility", "type": "ability", "value": agi}], POLICY),
		"initiative": TypedNumber.make([{"label": "agility", "type": "ability", "value": agi}], POLICY),
		"attack": TypedNumber.make([{"label": "strength", "type": "ability", "value": strength}], POLICY),
		"hp_max": 6 + level * 4 + strength,
	}


## A shaken attacker rolls at -2 (status; the best status counts, so two
## sources of -2 are still -2); attack rolls carry the actor's attack parts.
func before_roll(p: Dictionary) -> Dictionary:
	var actor_id := str(p.ctx.get("actor", ""))
	if actor_id == "":
		return p
	if p.ctx.get("kind", "") == "attack":
		var d: Dictionary = kernel.state.encounter.actor(actor_id).get("derived", {}).get(ID, {})
		for part in d.get("attack", {}).get("parts", []):
			p.spec.parts.append(part)
	for fx in kernel.effects_on_actor(actor_id):
		if str(fx.get("key", "")) == "shaken":
			p.spec.parts.append({"label": "shaken", "type": "status", "value": -2, "source": str(fx.id)})
	if p.ctx.get("forbidden", false):
		p.veto = "the sample rules forbid this roll"
	return p


## Success at or above the DC, a natural 20 is a critical.
func after_roll(p: Dictionary) -> Dictionary:
	var faces: Array = p.result.groups.get("main", {}).get("faces", [])
	if p.ctx.has("dc"):
		p.result.outcome = "success" if float(p.result.total) >= float(p.ctx.dc) else "failure"
		if faces.size() == 1 and int(faces[0]) == 20:
			p.result.outcome = "critical"
	return p


## The one action: an attack roll against the target's defence, damage on
## a hit, all as one undo step with the rolls in the log.
func strike(attacker: String, target: String) -> Dictionary:
	var k := kernel
	var dc := TypedNumber.value(k.state.encounter.actor(target).get("derived", {}).get(ID, {}).get("defence", 10))
	var attack := k.roll("1d20", {"actor": attacker, "kind": "attack", "dc": dc}, "Strike")
	if attack.is_empty():
		return {"ok": false, "why": k.last_veto}
	var out := {"ok": true, "attack": attack, "outcome": str(attack.result.outcome), "damage": 0}
	if attack.result.outcome == "failure":
		return out
	var dmg := k.roll("1d8", {"actor": attacker, "kind": "damage"}, "Damage")
	var amount := float(dmg.result.total) * (2 if attack.result.outcome == "critical" else 1)
	out.damage = amount
	var spend := Resources.spend(k.state, "actor:" + target, ID, "hp", amount)
	if spend.is_empty():
		var rec := Resources.get_record(k.state, "actor:" + target, ID, "hp")
		spend = Resources.set_event("actor:" + target, ID, "hp", {"kind": "pool", "current": 0, "max": rec.get("max", 0), "recharge": "rest"})
	k.commit([spend], "Damage", {"by": ID, "roll": int(k.log.seq) - 1})
	return out
