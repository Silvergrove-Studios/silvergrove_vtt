<!--
  A fight in the theatre of the mind, where a map would be: "Who's in the
  fight" — each creature's name, what this screen may know of its health
  (a player's only what the table shows them), its conditions where this
  screen sees them, the order and whose turn it is. A pick waits here, not
  on a map: a target is chosen from the list (several, or the darts, as on
  a map), an area's creatures are named from it, and "No target: just roll"
  stays. The DM's list has the hidden too, each creature's hit points, and
  a tap opens one's stat block beside it; what the DM adds (creatures with
  no token to put down) comes in `extra`.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { MindRow } from '../lib/mind';

  interface Props {
    rows: MindRow[];
    /** the DM's list */
    gm?: boolean;
    /** a pick waiting: what it says, what has been chosen, how many it takes, and No target */
    pick?: { words: string; status: string; many: number; each: string; noTarget: boolean } | null;
    /** those chosen so far ("token:<id>"; for darts, one entry a dart) */
    picked?: string[];
    /** why a creature can't be the pick's ("dead"), by target; one not here can't be chosen at all */
    why?: Record<string, string>;
    /** the DM's: the creature chosen (its stat block beside) */
    selected?: string;
    onSelect?: (id: string) => void;
    onChoose?: (target: string) => void;
    onUnchoose?: (target: string) => void;
    onDone?: () => void;
    onCancel?: () => void;
    onNoTarget?: () => void;
    /** more at the foot of it (the DM's Add to the fight) */
    extra?: Snippet;
  }

  let { rows, gm = false, pick = null, picked = [], why = {}, selected = '', onSelect, onChoose, onUnchoose, onDone, onCancel, onNoTarget, extra }: Props = $props();
  const times = (target: string) => picked.filter((x) => x === target).length;
  const inOrder = $derived(rows.some((r) => r.order >= 0));
</script>

<section class="mind" aria-label="Who's in the fight">
  <header>
    <h2>Who's in the fight</h2>
    <p class="dim small">
      {gm ? 'In the theatre of the mind: no map. Where everyone is, and so range, sight, movement and who is in reach, is yours to judge.' : 'In the theatre of the mind: no map. The DM says where everyone is.'}
    </p>
  </header>
  {#if pick}
    <div class="pickbar" role="group" aria-label="Choose from the list">
      <p class="words" role="status">{pick.words}</p>
      {#if pick.status}<p class="status">{pick.status}</p>{/if}
      <div class="actions">
        {#if pick.noTarget}<button type="button" class="quiet" onclick={() => onNoTarget?.()}>No target: just roll</button>{/if}
        <button type="button" class="quiet" onclick={() => onCancel?.()}>Cancel</button>
        <button type="button" class="accent" disabled={picked.length === 0} onclick={() => onDone?.()}>Done</button>
      </div>
    </div>
  {/if}
  <ol class="rows" aria-label="The creatures in the fight">
    {#each rows as r (r.id)}
      {@const n = times(r.target)}
      {@const can = pick ? r.target in why && !why[r.target] : false}
      <li class="row" class:current={r.current} class:dead={r.dead} class:on={selected === r.id} class:chosen={n > 0}>
        <div class="who">
          {#if inOrder}<span class="init" title="Its place in the order">{r.init || (r.order >= 0 ? String(r.order + 1) : '')}</span>{/if}
          {#if gm && onSelect}
            <button type="button" class="name linkish" onclick={() => onSelect?.(r.id)} title="Its stat block">{r.name}{#if r.label}<span class="label"> ({r.label})</span>{/if}</button>
          {:else}
            <span class="name">{r.name}{#if r.label}<span class="label"> ({r.label})</span>{/if}</span>
          {/if}
          {#if r.party}<span class="tag">{r.mine ? 'you' : 'party'}</span>{/if}
          {#if r.hidden}<span class="tag hid">hidden</span>{/if}
          {#if r.current}<span class="tag turn">its turn</span>{/if}
        </div>
        <div class="state">
          {#if r.marks}<span class="mark" class:bad={r.marks !== 'Bloodied'}>{r.marks}</span>{/if}
          {#if r.hp}<span class="hp" title="Hit points">{r.hp} hp</span>{/if}
          {#each r.effects as e (e)}<span class="badge">{e}</span>{/each}
          {#if r.note}<span class="dim small">{r.note}</span>{/if}
          {#if r.seen}<span class="dim small seen">players see: {r.seen}</span>{/if}
        </div>
        {#if pick}
          <div class="choose">
            {#if can}
              <button type="button" class:accent={n > 0} aria-pressed={n > 0} onclick={() => onChoose?.(r.target)}>
                {n > 0 ? (pick.each ? `Chosen ×${n}` : 'Chosen') : `Choose ${r.name}`}
              </button>
              {#if pick.each && n > 0}<button type="button" class="quiet" aria-label={`One ${pick.each} fewer at ${r.name}`} onclick={() => onUnchoose?.(r.target)}>−</button>{/if}
            {:else if why[r.target]}
              <span class="dim small why">{why[r.target]}</span>
            {/if}
          </div>
        {/if}
      </li>
    {:else}
      <li class="dim empty">Nobody yet.</li>
    {/each}
  </ol>
  {#if extra}{@render extra()}{/if}
</section>

<style>
  .mind {
    height: 100%;
    overflow-y: auto;
    padding: 14px 14px 32px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    background:
      radial-gradient(900px 400px at 50% -10%, rgba(184, 156, 255, 0.08), transparent 60%),
      var(--bg);
  }
  header h2 {
    font-size: 1.25rem;
  }
  header p {
    margin: 4px 0 0;
  }
  .small {
    font-size: 0.85rem;
  }
  .pickbar {
    position: sticky;
    top: 0;
    z-index: 2;
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 12px;
    background: var(--panel-2);
    border: 1px solid var(--accent-soft);
    border-radius: 12px;
    box-shadow: var(--shadow);
  }
  .pickbar p {
    margin: 0;
  }
  .words {
    font-weight: 600;
  }
  .status {
    font-size: 0.92rem;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 6px;
  }
  .rows {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .row {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 4px 10px;
    align-items: center;
    padding: 8px 10px;
    border: 1px solid var(--border-soft);
    border-radius: 10px;
    background: var(--panel);
  }
  .row.current {
    border-color: rgba(255, 215, 90, 0.55);
    background: color-mix(in srgb, rgba(255, 215, 90, 0.1) 100%, var(--panel));
  }
  .row.on {
    box-shadow: inset 0 0 0 1px rgba(255, 255, 77, 0.5);
  }
  .row.chosen {
    border-color: var(--accent);
  }
  .row.dead {
    opacity: 0.6;
  }
  .who {
    display: flex;
    align-items: baseline;
    gap: 8px;
    flex-wrap: wrap;
    min-width: 0;
  }
  .init {
    min-width: 22px;
    text-align: right;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .name {
    font-weight: 600;
  }
  .linkish {
    background: none;
    border: 0;
    padding: 0;
    min-height: 0;
    color: var(--heading);
    text-align: left;
  }
  .label {
    font-weight: 500;
    color: var(--muted);
    font-size: 0.9em;
  }
  .tag {
    font-size: 0.75rem;
    color: var(--muted);
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 0 7px;
  }
  .tag.hid {
    border-style: dashed;
  }
  .tag.turn {
    color: #ffd75a;
    border-color: rgba(255, 215, 90, 0.5);
  }
  .state {
    grid-column: 1 / -1;
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
    align-items: center;
  }
  .mark {
    font-size: 0.8rem;
    font-weight: 600;
    color: #ffb4a8;
  }
  .mark.bad {
    color: var(--danger);
  }
  .hp {
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
    color: var(--muted);
  }
  .badge {
    font-size: 0.75rem;
    padding: 1px 8px;
    border-radius: 999px;
    background: var(--panel-3);
  }
  .choose {
    grid-column: 2;
    grid-row: 1;
    display: flex;
    gap: 4px;
    align-items: center;
  }
  .why {
    font-style: italic;
  }
  .empty {
    padding: 8px;
  }
</style>
