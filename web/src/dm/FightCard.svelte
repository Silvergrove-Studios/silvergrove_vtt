<!--
  A fight, prepared: its name, the battle map it's on, its creatures (how
  many, hidden at first or seen), the DM's notes, and Start. The
  adventure's own fights and the DM's (a playtest's DM could start only
  the adventure's, and couldn't bring in the mastiff the party found).
-->
<script lang="ts">
  import { comp, dmOp, game, type Dict } from '../lib/game.svelte';
  import { pictureUrl } from '../lib/art';

  let { fightId, onclose, onopen }: { fightId: string; onclose?: () => void; onopen?: (ref: string) => void } = $props();

  const dm = $derived(game.dm);
  const fight = $derived(((dm.encounters as Dict[]) ?? []).find((e) => String(e.id) === fightId));
  const live = $derived(!!fight?.live && typeof fight.live === 'object' && Object.keys(fight.live).length > 0);
  const maps = $derived(((dm.maps as Dict[]) ?? []).filter((m) => m.role !== 'regional'));
  const lines = $derived(((fight?.creatures as Dict[]) ?? []).filter((c) => c && typeof c === 'object'));
  // the pictures of its creatures, by name (a playtest's DM found the Warden's only after the game)
  const pictures = $derived.by((): Dict[] => {
    const names = lines.map((c) => String(c.name ?? c.entry ?? '').toLowerCase().replace(/\s+\d+$/, '')).filter((n) => n.length > 2);
    return ((dm.pictures as Dict[]) ?? []).filter((p) => {
      const pn = String(p.name ?? '').toLowerCase().replace(/^the\s+/, '');
      return names.some((n) => pn.includes(n) || n.includes(pn));
    });
  });
  const fromPlace = $derived(((dm.places as Dict[]) ?? []).find((p) => p.kind === 'encounter' && String(p.target ?? '') === fightId));
  // the creatures the rules put on a map, in the campaign's rules version
  const creatureFilter = $derived.by((): Dict => {
    for (const acts of Object.values((game.view.actions ?? {}) as Dict)) {
      const f = (acts as Dict)?.spawn?.query?.filter;
      if (f && typeof f === 'object') return f as Dict;
    }
    return {};
  });

  let q = $state('');
  let found = $state<Dict[]>([]);
  let count = $state(1);
  let hidden = $state(true);
  let starting = $state(false);
  let seq = 0;
  $effect(() => {
    const text = q.trim();
    const mine = ++seq;
    if (text.length < 2) {
      found = [];
      return;
    }
    comp('creatures', { query: { text, per_page: 8, fields: ['name', 'cr', 'type'], filter: creatureFilter } }).then((reply) => {
      if (mine === seq) found = (reply.page?.entries as Dict[]) ?? [];
    });
  });

  let timer: ReturnType<typeof setTimeout> | undefined;
  function setLater(field: string, value: string): void {
    clearTimeout(timer);
    timer = setTimeout(() => dmOp('fight_set', { encounter: fightId, [field]: value }), 700);
  }

  function setLines(next: Dict[]): void {
    dmOp('fight_set', { encounter: fightId, creatures: next });
  }

  function add(e: Dict): void {
    dmOp('fight_add', { encounter: fightId, collection: 'creatures', entry: String(e.id), name: String(e.name ?? e.id), count, hidden });
    q = '';
    found = [];
  }

  function cr(v: unknown): string {
    const n = Number(v);
    return n === 0.125 ? '1/8' : n === 0.25 ? '1/4' : n === 0.5 ? '1/2' : String(v ?? '');
  }

  function remove(): void {
    if (confirm(`Delete “${fight?.name ?? 'this fight'}”? Its creatures and notes go with it.`)) {
      dmOp('fight_delete', { encounter: fightId });
      onclose?.();
    }
  }
</script>

{#if !fight}
  <p class="dim">Making the fight…</p>
{:else}
  <div class="fightcard">
    {#if live}
      <div class="state live">
        <strong>The fight is on.</strong>
        <span class="dim">Run it from the bar over the map; add a creature from its card (Put it on the map).</span>
      </div>
    {/if}
    <label class="edit">Name <input type="text" value={fight.name ?? ''} oninput={(e) => setLater('name', e.currentTarget.value)} /></label>
    <label class="edit">
      The map it's on
      <select value={String(fight.map ?? '')} disabled={live} onchange={(e) => dmOp('fight_set', { encounter: fightId, map: e.currentTarget.value })}>
        {#each maps as m (m.id)}<option value={String(m.id)}>{m.name}</option>{/each}
      </select>
    </label>

    <section>
      <h3>Creatures</h3>
      {#each lines as c, i (i)}
        <div class="line">
          <span class="name">{c.name ?? c.entry}</span>
          <span class="dim">{c.hidden === false ? 'seen' : 'hidden at first'}</span>
          <div class="count" role="group" aria-label={`How many ${c.name ?? c.entry}`}>
            <button type="button" class="quiet" aria-label="One fewer" disabled={Number(c.count ?? 1) <= 1 || live} onclick={() => setLines(lines.map((x, j) => (j === i ? { ...x, count: Number(x.count ?? 1) - 1 } : x)))}>−</button>
            <span class="n">{c.count ?? 1}</span>
            <button type="button" class="quiet" aria-label="One more" disabled={Number(c.count ?? 1) >= 20 || live} onclick={() => setLines(lines.map((x, j) => (j === i ? { ...x, count: Number(x.count ?? 1) + 1 } : x)))}>+</button>
          </div>
          <button type="button" class="quiet" disabled={live} onclick={() => setLines(lines.filter((_, j) => j !== i))}>Take out</button>
        </div>
      {:else}
        <p class="dim">None yet: find some below.</p>
      {/each}
    </section>

    {#if pictures.length}
      <section>
        <h3>Their pictures</h3>
        <div class="pics">
          {#each pictures as p (p.ref)}
            <button type="button" class="quiet pic" onclick={() => onopen?.(`picture:${p.ref}`)}>
              {#if pictureUrl(String(p.ref))}<img src={pictureUrl(String(p.ref))} alt="" />{/if}
              <span>{p.name}</span>
            </button>
          {/each}
        </div>
      </section>
    {/if}

    {#if !live}
      <section class="adding">
        <h3>Add creatures</h3>
        <input type="search" placeholder="A creature: goblin, wolf, mastiff…" bind:value={q} aria-label="Find a creature" />
        <div class="opts">
          <label>How many <input type="number" min="1" max="20" bind:value={count} /></label>
          <label><input type="checkbox" bind:checked={hidden} /> hidden until you reveal them</label>
        </div>
        {#each found as e (e.id)}
          <button type="button" class="quiet found" onclick={() => add(e)}>
            <span>{e.name}</span><span class="dim">CR {cr(e.cr)}{e.type ? ` · ${e.type}` : ''}</span><span class="accentword">Add {count}</span>
          </button>
        {/each}
      </section>
    {/if}

    <label class="edit">Notes for you <textarea rows="4" value={fight.notes ?? ''} oninput={(e) => setLater('notes', e.currentTarget.value)}></textarea></label>

    <div class="actions">
      {#if live}
        <button type="button" onclick={() => dmOp('end_fight')}>End the fight</button>
      {:else}
        <!-- (one press: a fight takes a moment to set up, and a second press started it twice) -->
        <button type="button" class="accent" disabled={starting || !lines.length} onclick={() => { starting = true; dmOp('launch', { encounter: fightId }); setTimeout(() => (starting = false), 5000); }}>
          {starting ? 'Starting…' : 'Start the fight'}
        </button>
        {#if !lines.length}<span class="dim">Add a creature first.</span>{/if}
        {#if !fromPlace}<button type="button" class="quiet danger" onclick={remove}>Delete the fight</button>{/if}
      {/if}
    </div>
    {#if fromPlace}<p class="dim">The adventure starts it at {fromPlace.name}; so does Start here.</p>{/if}
  </div>
{/if}

<style>
  .fightcard {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .state.live {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 10px 12px;
    border-radius: 10px;
    background: color-mix(in srgb, #e36b5b 16%, var(--panel));
  }
  .edit {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  h3 {
    font-size: 1rem;
    margin: 0 0 6px;
  }
  .line {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 0;
    border-bottom: 1px solid var(--border-soft);
    flex-wrap: wrap;
  }
  .line .name {
    flex: 1;
    min-width: 8em;
    font-weight: 600;
  }
  .count {
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .count .n {
    min-width: 1.6em;
    text-align: center;
    font-variant-numeric: tabular-nums;
  }
  .adding {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .opts {
    display: flex;
    gap: 14px;
    flex-wrap: wrap;
    align-items: center;
  }
  .opts input[type='number'] {
    width: 4.5em;
  }
  .found {
    display: flex;
    gap: 10px;
    align-items: baseline;
    text-align: left;
    width: 100%;
  }
  .found span:first-child {
    flex: 1;
  }
  .accentword {
    color: var(--accent);
    font-weight: 600;
  }
  .pics {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }
  .pic {
    display: flex;
    flex-direction: column;
    gap: 4px;
    align-items: center;
    width: 120px;
    padding: 6px;
  }
  .pic img {
    width: 100%;
    aspect-ratio: 1;
    object-fit: cover;
    border-radius: 8px;
  }
  .actions {
    display: flex;
    gap: 10px;
    align-items: center;
    flex-wrap: wrap;
  }
</style>
