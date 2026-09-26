<!--
  Numbers for named stats (a character's six abilities), made the way the
  table plays: a point buy (− / + within the points, never out of range),
  a fixed array or rolled numbers (each given to one ability; picking one
  another ability has swaps them), or typed. Each stat says what it is
  for; the class's key ones are marked and a suggestion fills them in. A
  background's +2/+1 (or +1/+1/+1) is chosen below, with the final scores
  and their modifiers. The value: {method, base, bonus, final}.
-->
<script lang="ts">
  import { viewUi } from './context';
  import { fillIntent, type Dict } from './viewlib';
  import {
    canLower,
    canRaise,
    costOf,
    finalScores,
    modifier,
    pointBuy,
    pool,
    scoresValue,
    signed,
    spent,
    startingBase,
    suggestedBase,
    startingBonus,
    stats,
    type ScoresValue,
  } from './fieldcheck';

  let { field, value = $bindable(), ctx = {} }: { field: Dict; value: any; ctx?: Dict } = $props();
  const ui = viewUi();

  const list = $derived(stats(field));
  const method = $derived(String(field.method ?? 'manual'));
  const pb = $derived(pointBuy(field));
  const nums = $derived(pool(field));
  const primary = $derived(((field.primary as string[]) ?? []).map(String));
  const who = $derived(String(field.who ?? ''));
  const among = $derived((((field.bonus as Dict)?.among as string[]) ?? []).map(String).filter(Boolean));
  const hasBonus = $derived(among.length >= 2);
  let rolling = $state(false);
  let explain = $state(false);

  const current = $derived((value && typeof value === 'object' ? value : null) as ScoresValue | null);
  const base = $derived(current?.base ?? {});
  const bonus = $derived(current?.bonus ?? {});
  const final = $derived(finalScores(field, base, bonus));
  const left = $derived(method === 'point_buy' ? pb.budget - spent(base, pb) : 0);
  const pattern = $derived(Object.values(bonus).filter((v) => Number(v) > 0).length === 3 ? 'three' : 'two');

  function set(b: Record<string, number | null>, bo: Record<string, number>): void {
    value = scoresValue(field, b, bo);
  }

  // a fresh start when there is none that fits: another method, the rolls
  // just made, a background whose three abilities are others
  $effect(() => {
    const v = current;
    const ids = list.map((s) => s.id);
    // an array's or the rolls' numbers: each given at most as often as it is there, or not yet
    const fromPool = () => {
      if (!nums) return false;
      const left = counts(nums);
      for (const id of ids) {
        const x = v?.base?.[id];
        if (x === null || x === undefined) continue;
        if (!left.get(Number(x))) return false;
        left.set(Number(x), left.get(Number(x))! - 1);
      }
      return true;
    };
    const fits =
      v &&
      v.method === method &&
      (method === 'array' || method === 'rolled' ? fromPool() : ids.every((id) => Number.isInteger(Number(v.base?.[id])) && v.base?.[id] !== null));
    if (!fits) {
      if (method === 'rolled' && !nums) {
        if (v) value = null;
        return;
      }
      set(startingBase(field), hasBonus ? startingBonus(field) : {});
      return;
    }
    // (until the background's record has come — a reload — its three are not known: the bonus waits)
    if (hasBonus && Object.keys(v.bonus ?? {}).some((k) => !among.includes(k))) set(v.base, startingBonus(field));
    if (!field.bonus && Object.keys(v.bonus ?? {}).length) set(v.base, {});
    if (hasBonus && Object.keys(v.bonus ?? {}).length === 0) set(v.base, startingBonus(field));
  });

  function step(id: string, d: number): void {
    const b = { ...base };
    if (d > 0 && !canRaise(id, b, pb)) return;
    if (d < 0 && !canLower(id, b, pb)) return;
    b[id] = Number(b[id]) + d;
    set(b, bonus);
  }

  function counts(ns: number[]): Map<number, number> {
    const m = new Map<number, number>();
    for (const n of ns) m.set(n, (m.get(n) ?? 0) + 1);
    return m;
  }

  /** How many of `n` are not given to any ability yet. */
  function free(n: number): number {
    let c = counts(nums ?? []).get(n) ?? 0;
    for (const st of list) if (base[st.id] !== null && base[st.id] !== undefined && Number(base[st.id]) === n) c -= 1;
    return c;
  }

  /** Who has every `n` there is, when none is free: choosing it swaps with them. */
  function holder(id: string, n: number): string {
    if (free(n) > 0) return '';
    return list.find((st) => st.id !== id && base[st.id] !== null && Number(base[st.id]) === n)?.name ?? '';
  }

  /** Give a number to an ability (or none): when every one of that number is
   * given, the ability that had it takes this one's (or none). */
  function give(id: string, n: number | null): void {
    const b = { ...base };
    const was = b[id] ?? null;
    if (n !== null && was !== n && free(n) <= 0) {
      const other = list.find((st) => st.id !== id && b[st.id] !== null && Number(b[st.id]) === n);
      if (other) b[other.id] = was;
    }
    b[id] = n;
    set(b, bonus);
  }

  function typed(id: string, raw: string): void {
    const m = (field.manual as Dict) ?? {};
    const lo = Number(m.min ?? 1);
    const hi = Number(m.max ?? 30);
    const n = Math.max(lo, Math.min(hi, Math.trunc(Number(raw) || lo)));
    set({ ...base, [id]: n }, bonus);
  }

  // the class's suggestion is the player's to ask for, never put in unasked
  function suggest(): void {
    set(suggestedBase(field), bonus);
  }

  function reset(): void {
    set(startingBase(field), bonus);
  }

  function roll(): void {
    const intent = (field.rolled as Dict)?.roll;
    if (!intent) return;
    rolling = true;
    ui.intent(fillIntent(intent, ctx));
    setTimeout(() => (rolling = false), 4000);
  }

  function setPattern(p: 'two' | 'three'): void {
    if (p === 'three') set(base, Object.fromEntries(among.map((a) => [a, 1])));
    else set(base, startingBonus(field));
  }

  function plus(n: 2 | 1, id: string): void {
    const b: Record<string, number> = {};
    const two = n === 2 ? id : Object.keys(bonus).find((k) => bonus[k] === 2);
    let one = n === 1 ? id : Object.keys(bonus).find((k) => bonus[k] === 1);
    if (one === two) one = among.find((a) => a !== two);
    if (two) b[two] = 2;
    if (one) b[one] = 1;
    set(base, b);
  }

  const nameOf = (id: string) => list.find((s) => s.id === id)?.name ?? id;
  const aOrAn = (w: string) => `${'aeiouAEIOU'.includes(w.charAt(0)) ? 'an' : 'a'} ${w}`;
</script>

<div class="scores">
  <div class="how">
    {#if method === 'point_buy'}
      <div class="budget">
        <span><strong>{pb.budget} points</strong> to spend on your scores (8 to 15)</span>
        <span class="left" class:done={left === 0}>{left === 0 ? 'All spent ✓' : `${left} left`}</span>
      </div>
      <div class="bar" aria-hidden="true"><span style:width={`${Math.max(0, Math.min(100, ((pb.budget - left) / pb.budget) * 100))}%`}></span></div>
    {:else if method === 'array'}
      <p>Give each of these numbers to one ability: <strong>{(nums ?? []).join(', ')}</strong>.</p>
    {:else if method === 'rolled'}
      {#if nums}
        <p>You rolled <strong>{[...nums].sort((a, b) => b - a).join(', ')}</strong>. Give each number to one ability.</p>
      {:else}
        <p>Roll four six-sided dice six times, keeping the three highest each time. The table rolls for you, where everyone sees.</p>
        <button type="button" class="accent" disabled={rolling} onclick={roll}>{rolling ? 'Rolling…' : 'Roll my scores'}</button>
      {/if}
    {:else}
      <p>Type each score.</p>
    {/if}
    {#if (method !== 'rolled' || nums) && list.length}
      <div class="tools">
        {#if field.suggest && who}<button type="button" onclick={suggest}>Suggested for {aOrAn(who)}</button>{/if}
        {#if method === 'point_buy' || method === 'array' || (method === 'rolled' && nums)}<button type="button" class="quiet" onclick={reset}>Start again</button>{/if}
      </div>
    {/if}
  </div>

  {#if method !== 'rolled' || nums}
    <p class="legend" aria-hidden="true"><span>Score</span><span>After your background: score · modifier</span></p>
    <ul class="stats">
      {#each list as s (s.id)}
        {@const has = base[s.id] !== null && base[s.id] !== undefined}
        {@const b = Number(base[s.id] ?? 0)}
        {@const f = final[s.id] === null || final[s.id] === undefined ? null : Number(final[s.id])}
        {@const key = primary.includes(s.id)}
        <li class:key>
          <div class="about">
            <div class="name">
              <strong>{s.name}</strong>
              {#if key}<span class="badge">Key for {who ? aOrAn(who) : 'your class'}</span>{/if}
            </div>
            {#if s.text}<p class="what">{s.text}</p>{/if}
            {#if s.uses}<p class="uses">{s.uses}</p>{/if}
          </div>
          <div class="set">
            {#if method === 'point_buy'}
              <div class="stepper">
                <button type="button" aria-label={`Lower ${s.name}`} disabled={!canLower(s.id, base, pb)} onclick={() => step(s.id, -1)}>−</button>
                <span class="n">{b}</span>
                <button type="button" aria-label={`Raise ${s.name}`} disabled={!canRaise(s.id, base, pb)} onclick={() => step(s.id, 1)}>+</button>
              </div>
              <span class="cost">{costOf(b, pb)} pt{costOf(b, pb) === 1 ? '' : 's'}</span>
            {:else if nums}
              <select aria-label={s.name} class:unset={!has} value={has ? String(b) : ''} onchange={(e) => { const raw = (e.currentTarget as HTMLSelectElement).value; give(s.id, raw === '' ? null : Number(raw)); }}>
                <option value="">—</option>
                {#each [...new Set(nums)].sort((x, y) => y - x) as n (n)}
                  {@const who = has && b === n ? '' : holder(s.id, n)}
                  <option value={String(n)}>{who ? `${n} · swap with ${who}` : String(n)}</option>
                {/each}
              </select>
            {:else}
              <input type="number" inputmode="numeric" aria-label={s.name} min={(field.manual as Dict)?.min ?? 1} max={(field.manual as Dict)?.max ?? 30} value={b} onchange={(e) => typed(s.id, (e.currentTarget as HTMLInputElement).value)} />
            {/if}
            <span class="result" title="The score after your background, and its modifier">
              {#if Number(bonus[s.id] ?? 0) > 0}<span class="plus">+{bonus[s.id]}</span>{/if}
              <span class="final">{f === null ? '—' : f}</span>
              <span class="mod">{f === null ? '' : signed(modifier(f))}</span>
            </span>
          </div>
        </li>
      {/each}
    </ul>

    {#if hasBonus}
      <div class="bonus">
        <p><strong>Your background{field.bonus?.source ? ` (${field.bonus.source})` : ''}</strong> raises {among.map(nameOf).join(', ').replace(/, ([^,]*)$/, ' or $1')}: +2 to one and +1 to another, or +1 to all three.</p>
        <div class="choices" role="radiogroup" aria-label="How your background raises your abilities">
          <button type="button" role="radio" aria-checked={pattern === 'two'} class:on={pattern === 'two'} onclick={() => setPattern('two')}>+2 and +1</button>
          <button type="button" role="radio" aria-checked={pattern === 'three'} class:on={pattern === 'three'} onclick={() => setPattern('three')}>+1 to all three</button>
        </div>
        {#if pattern === 'two'}
          {#each [2, 1] as n (n)}
            <div class="choices" role="radiogroup" aria-label={`+${n} to`}>
              <span class="lead">+{n} to</span>
              {#each among as a (a)}
                <button type="button" role="radio" aria-checked={Number(bonus[a] ?? 0) === n} class:on={Number(bonus[a] ?? 0) === n} onclick={() => plus(n as 2 | 1, a)}>{nameOf(a)}</button>
              {/each}
            </div>
          {/each}
        {/if}
      </div>
    {/if}
  {/if}

  <button type="button" class="quiet explain" aria-expanded={explain} onclick={() => (explain = !explain)}>{explain ? '▾' : '▸'} What do these numbers mean?</button>
  {#if explain}
    <div class="prose small">
      <p>Each ability has a <strong>score</strong>. At the start most are between 8 and 15; 10 or 11 is an ordinary person. What you use in play is the <strong>modifier</strong> beside it (a 14 or 15 gives +2): it is added to your d20 whenever you use that ability — to hit, to resist, to try something hard.</p>
      <p>Your class's key abilities are marked: put your best numbers there. Constitution helps every character (more hit points).</p>
    </div>
  {/if}
</div>

<style>
  .scores {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .how p {
    margin: 0 0 6px;
  }
  .budget {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 8px;
    flex-wrap: wrap;
  }
  .left {
    font-weight: 700;
    color: var(--accent);
    white-space: nowrap;
  }
  .left.done {
    color: #8fd18f;
  }
  .bar {
    height: 6px;
    border-radius: 3px;
    background: var(--panel-2);
    overflow: hidden;
    margin-top: 6px;
  }
  .bar span {
    display: block;
    height: 100%;
    background: var(--accent);
    transition: width 0.15s;
  }
  .tools {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-top: 8px;
  }
  .legend {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    margin: 0 4px -6px;
    font-size: 0.72rem;
    font-weight: 650;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--muted);
  }
  .legend span:first-child {
    visibility: hidden;
  }
  .stats {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .stats li {
    display: flex;
    gap: 10px;
    justify-content: space-between;
    align-items: center;
    padding: 10px 12px;
    border-radius: 12px;
    background: var(--panel-2);
    border: 1px solid var(--border);
  }
  .stats li.key {
    border-color: var(--accent);
    box-shadow: inset 3px 0 0 var(--accent);
  }
  .about {
    min-width: 0;
    flex: 1;
  }
  .name {
    display: flex;
    gap: 8px;
    align-items: baseline;
    flex-wrap: wrap;
  }
  .badge {
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--accent);
  }
  .what {
    margin: 2px 0 0;
    font-size: 0.88rem;
  }
  .uses {
    margin: 2px 0 0;
    font-size: 0.8rem;
    color: var(--muted);
  }
  .set {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 4px;
    flex: none;
  }
  .stepper {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .stepper button {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    padding: 0;
    font-size: 1.2rem;
    line-height: 1;
  }
  .stepper .n {
    min-width: 2ch;
    text-align: center;
    font-size: 1.2rem;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .cost {
    font-size: 0.75rem;
    color: var(--muted);
  }
  select.unset {
    color: var(--muted);
    border-style: dashed;
  }
  select,
  input[type='number'] {
    width: 5.5em;
    font-size: 1.05rem;
  }
  .result {
    display: flex;
    gap: 6px;
    align-items: baseline;
    font-variant-numeric: tabular-nums;
  }
  .plus {
    font-size: 0.78rem;
    font-weight: 700;
    color: #8fd18f;
  }
  .final {
    font-weight: 700;
  }
  .mod {
    min-width: 2.4ch;
    text-align: right;
    color: var(--accent);
    font-weight: 700;
  }
  .bonus {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 12px;
    border-radius: 12px;
    border: 1px dashed var(--border);
  }
  .bonus p {
    margin: 0;
  }
  .choices {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
    align-items: center;
  }
  .choices .lead {
    min-width: 3.2em;
    color: var(--muted);
    font-weight: 600;
  }
  .choices button.on {
    background: var(--accent-bg);
    border-color: var(--accent);
    color: var(--heading);
  }
  .explain {
    align-self: flex-start;
  }
  .small {
    font-size: 0.9rem;
  }
</style>
