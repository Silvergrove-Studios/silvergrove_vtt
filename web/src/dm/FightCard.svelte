<!--
  A fight, prepared: its name, the battle map it's on, its creatures (how
  many, hidden at first or seen), the DM's notes, and Start. The
  adventure's own fights and the DM's (a playtest's DM could start only
  the adventure's, and couldn't bring in the mastiff the party found).
  Where the table leaves it to each fight, Start says where: on its map, or
  in the theatre of the mind (no map needed); a table whose fights are all
  in the mind needs no map for any. Its own settings, for this fight alone
  (what it checks, whether the DM approves its outcomes, what the players
  see of its creatures' health), are the DM's here, as the table has them
  until changed.
-->
<script lang="ts">
  import { comp, dmOp, game, submit, type Dict } from '../lib/game.svelte';
  import { pictureUrl } from '../lib/art';
  import { fightSettings, registryOf, valueWords, type Setting } from '../lib/tablesettings';
  import Modal from '../common/Modal.svelte';
  import ActButton from '../lib/views/ActButton.svelte';

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
  // where fights happen at this table, and this one's own settings
  const reg = $derived(registryOf(dm));
  const tableSpace = $derived(String(reg?.space ?? 'maps'));
  const hasMap = $derived(String(fight?.map ?? '') !== '');
  const own = $derived((fight?.settings && typeof fight.settings === 'object' ? fight.settings : {}) as Record<string, unknown>);
  const perFight = $derived(fightSettings(reg));
  // a choice's options for one fight: as the table has it, or each of its own
  function fightOptions(st: Setting): { key: string; words: string; value: unknown }[] {
    const out = [{ key: 'table', words: `As the table (${valueWords(st, st.value)})`, value: null as unknown }];
    const values = Array.isArray(st.enum) ? st.enum : st.type === 'boolean' ? [true, false] : [];
    for (const v of values) out.push({ key: JSON.stringify(v), words: valueWords(st, v), value: v });
    return out;
  }
  function setOwn(st: Setting, key: string): void {
    const opt = fightOptions(st).find((o) => o.key === key);
    if (!opt) return;
    dmOp('fight_set', { encounter: fightId, settings: { [st.id]: opt.value } });
  }
  const ownCount = $derived(perFight.filter((st) => st.id in own).length);
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

  // (each press waits for the table and says it went: ActButton)
  function add(e: Dict): Promise<{ ok: boolean }> {
    return submit({ kind: 'dm', op: 'fight_add', encounter: fightId, collection: 'creatures', entry: String(e.id), name: String(e.name ?? e.id), count, hidden }).then((r) => {
      if (r.ok) {
        q = '';
        found = [];
      }
      return r;
    });
  }

  // Start the fight: busy until the table has it going, and the card gives way
  // to the fight's bar (a playtest's DM watched "Starting…" for three seconds
  // with nothing else moving, and nearly pressed again)
  async function start(space = ''): Promise<void> {
    if (starting) return;
    starting = true;
    const r = await submit({ kind: 'dm', op: 'launch', encounter: fightId, ...(space ? { space } : {}) });
    // (done: the fight's state is on its way; the bar takes over when it lands)
    setTimeout(() => (starting = false), r.ok ? 5000 : 0);
  }

  function cr(v: unknown): string {
    const n = Number(v);
    return n === 0.125 ? '1/8' : n === 0.25 ? '1/4' : n === 0.5 ? '1/2' : String(v ?? '');
  }

  // Delete asks in the table's own words (never the browser's bare OK)
  let deleting = $state(false);
  function remove(): void {
    deleting = false;
    dmOp('fight_delete', { encounter: fightId });
    onclose?.();
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
    {#if tableSpace === 'mind'}
      <!-- (every fight at this table is in the theatre of the mind: no map needed) -->
      <p class="dim mindline">Fought in the theatre of the mind: no map needed. Who's in it is a list on everyone's screen; range, sight and movement are yours to judge.</p>
    {:else}
    <label class="edit">
      The map it's on
      <select value={String(fight.map ?? '')} disabled={live} onchange={(e) => dmOp('fight_set', { encounter: fightId, map: e.currentTarget.value })}>
        <!-- (where fights may be in the theatre of the mind, one needs no map) -->
        {#if !hasMap || tableSpace === 'per_fight'}<option value="">No map: in the theatre of the mind</option>{/if}
        {#each maps as m (m.id)}<option value={String(m.id)}>{m.name}</option>{/each}
      </select>
    </label>
    {/if}
    {#if tableSpace !== 'mind' && hasMap}
    <!-- the light it is fought in: by day the players see all in their line
         of sight, in the dark only what lights and darkvision show -->
    <label class="edit">
      Light
      <select value={String(fight.light ?? '')} disabled={live} onchange={(e) => dmOp('fight_set', { encounter: fightId, light: e.currentTarget.value })}>
        <option value="">As the map</option>
        <option value="daylight">Daylight</option>
        <option value="dim">Dim</option>
        <option value="dark">Dark</option>
      </select>
      {#if live}<span class="dim small">Under way: change it in the map's bar (Light).</span>{/if}
    </label>
    {/if}

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
          <ActButton quiet class="foundbtn" act={() => add(e)}>
            <span class="found"><span>{e.name}</span><span class="dim">CR {cr(e.cr)}{e.type ? ` · ${e.type}` : ''}</span><span class="accentword">Add {count}</span></span>
          </ActButton>
        {/each}
      </section>
    {/if}

    <label class="edit">Notes for you <textarea rows="4" value={fight.notes ?? ''} oninput={(e) => setLater('notes', e.currentTarget.value)}></textarea></label>

    {#if perFight.length}
      <!-- for this fight alone: the table runs as Table settings say, this fight as set here
           (while it runs; Table settings says what differs) -->
      <details class="own">
        <summary>This fight's settings <span class="dim">— {ownCount ? `${ownCount} of its own` : 'as the table has them'}</span></summary>
        <p class="dim small">For this fight alone, while it runs. The rest of the table runs as Table settings say.</p>
        <ul>
          {#each perFight as st (st.id)}
            {@const mine = st.id in own}
            <li>
              <label>
                <span>{st.title}</span>
                <select aria-label={`${st.title}, this fight`} value={mine ? JSON.stringify(own[st.id]) : 'table'} onchange={(e) => setOwn(st, e.currentTarget.value)}>
                  {#each fightOptions(st) as o (o.key)}<option value={o.key}>{o.words}</option>{/each}
                </select>
              </label>
            </li>
          {/each}
        </ul>
      </details>
    {/if}

    <div class="actions">
      {#if live}
        <button type="button" onclick={() => dmOp('end_fight')}>End the fight</button>
      {:else}
        <!-- (one press: a fight takes a moment to set up, and a second press started it twice) -->
        {#if tableSpace === 'per_fight'}
          <!-- where the table leaves it to each fight: chosen as it starts -->
          {#if hasMap}
            <button type="button" class="accent" disabled={starting || !lines.length} aria-busy={starting ? 'true' : undefined} onclick={() => start('maps')}>
              {#if starting}Starting…<span class="spin" aria-hidden="true"></span>{:else}Start on its map{/if}
            </button>
          {/if}
          <button type="button" class={hasMap ? '' : 'accent'} disabled={starting || !lines.length} onclick={() => start('mind')}>
            {#if starting && !hasMap}Starting…<span class="spin" aria-hidden="true"></span>{:else}Start in the theatre of the mind{/if}
          </button>
        {:else}
          <button type="button" class="accent" disabled={starting || !lines.length || (tableSpace === 'maps' && !hasMap)} aria-busy={starting ? 'true' : undefined} onclick={() => start()}>
            {#if starting}Starting…<span class="spin" aria-hidden="true"></span>{:else}Start the fight{/if}
          </button>
          {#if tableSpace === 'maps' && !hasMap}<span class="dim">Choose the map it's on first.</span>{/if}
        {/if}
        {#if !lines.length}<span class="dim">Add a creature first.</span>{/if}
        {#if !fromPlace}<button type="button" class="quiet danger" onclick={() => (deleting = true)}>Delete the fight</button>{/if}
      {/if}
    </div>
    {#if fromPlace}<p class="dim">The adventure starts it at {fromPlace.name}; so does Start here.</p>{/if}
  </div>
  {#if deleting}
    <Modal title="Delete the fight?" onclose={() => (deleting = false)}>
      <p class="ask">“{fight.name ?? 'This fight'}” goes, with its creatures and your notes on it.</p>
      {#snippet actions()}
        <button type="button" class="quiet" onclick={() => (deleting = false)}>Keep it</button>
        <button type="button" class="danger" onclick={remove}>Delete the fight</button>
      {/snippet}
    </Modal>
  {/if}
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
  .small {
    font-size: 0.85rem;
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
  .adding :global(.foundbtn) {
    display: flex;
    align-items: baseline;
    width: 100%;
    text-align: left;
  }
  .found {
    flex: 1;
    display: flex;
    gap: 10px;
    align-items: baseline;
    text-align: left;
  }
  .ask {
    margin: 0;
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
  .mindline {
    margin: 0;
  }
  .own summary {
    cursor: pointer;
    font-weight: 600;
  }
  .own ul {
    list-style: none;
    margin: 6px 0 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .own label {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
  }
  .own select {
    max-width: 100%;
  }
</style>
