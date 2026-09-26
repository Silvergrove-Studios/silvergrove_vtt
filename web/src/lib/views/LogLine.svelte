<!--
  One line of the log: a roll (its total, the dice, the outcome), a line
  of chat, a note, something shown, a ruling.
-->
<script lang="ts">
  import { num, type Dict } from './viewlib';
  import { playerName } from '../game.svelte';
  import { natural } from '../rolls';

  let { entry, actors = {} }: { entry: Dict; actors?: Dict } = $props();
  const kind = $derived(String(entry.kind ?? ''));
  const r = $derived((entry.result ?? {}) as Dict);
  const who = $derived(entry.actor ? String(actors?.[entry.actor]?.name ?? '') : '');
  const dice = $derived(((r.dice as Dict[]) ?? []).filter((d) => d && typeof d === 'object'));
  const mod = $derived(Number(r.modifier ?? 0));
  // a natural 20 or 1 looked like any other roll (a playtest's DM announced them by hand)
  const nat = $derived(kind === 'roll' ? natural(entry) : null);
  // why the roll had advantage or disadvantage (the ruleset keeps it on the
  // roll's spec): a playtest's DM couldn't tell why an attack had disadvantage
  const edge = $derived.by(() => {
    const spec = (entry.spec ?? {}) as Dict;
    const a = String(spec.why_adv ?? '');
    const d = String(spec.why_dis ?? '');
    if (a && d) return `Advantage (${a}) and disadvantage (${d}) cancel out`;
    if (a) return `Advantage: ${a}`;
    if (d) return `Disadvantage: ${d}`;
    return '';
  });
</script>

{#if kind === 'roll'}
  <div class="line roll">
    <div class="what">
      {#if who}<span class="who">{who}</span>{/if}
      <span class="label">{entry.label ?? 'Roll'}</span>
      {#if entry.audience && entry.audience !== 'all'}<span class="tag">secret</span>{/if}
    </div>
    <div class="result">
      <span class="dice">
        {#each dice as d}
          <span class="die" class:dropped={!d.kept} class:nat20={nat === 20 && d.kept && Number(d.sides) === 20 && Number(d.face) === 20} class:nat1={nat === 1 && d.kept && Number(d.sides) === 20 && Number(d.face) === 1} title={`d${d.sides}`}>{d.face}</span>
        {/each}
        {#if mod !== 0}<span class="mod">{mod > 0 ? '+' : '−'}{num(Math.abs(mod))}</span>{/if}
      </span>
      <span class="total">{num(r.total ?? 0)}</span>
    </div>
    {#if r.outcome || nat}
      <div class="outcome">
        {#if nat === 20}<span class="nat crit">Natural 20!</span>{:else if nat === 1}<span class="nat fumble">Natural 1</span>{/if}
        {r.outcome ?? ''}
      </div>
    {/if}
    {#if edge}<div class="edge">{edge}</div>{/if}
  </div>
{:else if kind === 'chat'}
  <div class="line chat">
    <span class="who">{playerName(String(entry.from ?? ''))}</span>
    {#if Array.isArray(entry.to) && entry.to.length}<span class="to">to {entry.to.join(', ')}{String(entry.audience ?? '').startsWith('private:') ? ' (private)' : ''}</span>{/if}
    <span class="text">{entry.text}</span>
  </div>
{:else if kind === 'note'}
  <div class="line note dim">{entry.text}</div>
{:else if kind === 'handout'}
  <div class="line handout"><strong>{entry.title ? `${entry.title}: ` : ''}</strong>{entry.text ?? ''}</div>
{:else if kind === 'ruling'}
  <div class="line ruling dim">Ruling: {entry.text}</div>
{:else}
  <div class="line dim">{entry.text ?? entry.label ?? kind}</div>
{/if}

<style>
  /* what was typed on several lines stays on them (a playtest's DM had his
     line breaks squashed into spaces) */
  .chat .text,
  .note,
  .handout {
    white-space: pre-wrap;
  }
  .edge {
    font-size: 0.8rem;
    color: var(--muted);
  }
  .line {
    padding: 6px 0;
    border-bottom: 1px solid var(--border-soft);
    line-height: 1.35;
    overflow-wrap: anywhere;
  }
  .who {
    font-weight: 600;
    margin-right: 6px;
  }
  .to {
    color: var(--muted);
    font-size: 0.85em;
    margin-right: 6px;
  }
  .roll .what {
    display: flex;
    gap: 6px;
    align-items: baseline;
    flex-wrap: wrap;
  }
  .roll .label {
    color: var(--text);
  }
  .tag {
    font-size: 0.75em;
    padding: 1px 6px;
    border-radius: 999px;
    background: var(--hover);
    color: var(--muted);
  }
  .result {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-top: 4px;
  }
  .dice {
    display: flex;
    gap: 4px;
    flex-wrap: wrap;
    align-items: center;
  }
  .die {
    min-width: 26px;
    height: 26px;
    padding: 0 4px;
    display: inline-grid;
    place-items: center;
    border-radius: 7px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    font-variant-numeric: tabular-nums;
    font-size: 0.9em;
  }
  .die.dropped {
    opacity: 0.4;
    text-decoration: line-through;
  }
  .die.nat20 {
    border-color: var(--accent);
    color: var(--accent);
    font-weight: 700;
  }
  .die.nat1 {
    border-color: var(--danger, #d9534f);
    color: var(--danger, #d9534f);
    font-weight: 700;
  }
  .nat {
    font-weight: 700;
    margin-right: 6px;
  }
  .nat.crit {
    color: var(--accent);
  }
  .nat.fumble {
    color: var(--danger, #d9534f);
  }
  .mod {
    color: var(--muted);
  }
  .total {
    font-family: var(--font-display);
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--accent);
    font-variant-numeric: tabular-nums;
  }
  .outcome {
    color: var(--muted);
    font-size: 0.9em;
  }
</style>
