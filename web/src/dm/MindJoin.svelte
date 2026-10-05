<!--
  A creature into the fight in the theatre of the mind: found in the rules'
  creatures, so many of them, hidden or seen — no token to put down, no map
  to put it on. It rolls its initiative and takes its place in the order as
  one put on a map does; it goes with the fight's own when the fight ends.
-->
<script lang="ts">
  import { comp, game, submit, type Dict } from '../lib/game.svelte';
  import ActButton from '../lib/views/ActButton.svelte';

  let q = $state('');
  let found = $state<Dict[]>([]);
  let count = $state(1);
  let hidden = $state(false);
  let seq = 0;
  // the creatures the rules put in a fight, in the campaign's rules version
  const filter = $derived.by((): Dict => {
    for (const acts of Object.values((game.view.actions ?? {}) as Dict)) {
      const f = (acts as Dict)?.spawn?.query?.filter;
      if (f && typeof f === 'object') return f as Dict;
    }
    return {};
  });
  $effect(() => {
    const text = q.trim();
    const mine = ++seq;
    if (text.length < 2) {
      found = [];
      return;
    }
    comp('creatures', { query: { text, per_page: 8, fields: ['name', 'cr', 'type'], filter } }).then((reply) => {
      if (mine === seq) found = (reply.page?.entries as Dict[]) ?? [];
    });
  });

  function cr(v: unknown): string {
    const n = Number(v);
    return n === 0.125 ? '1/8' : n === 0.25 ? '1/4' : n === 0.5 ? '1/2' : String(v ?? '');
  }

  function join(e: Dict): Promise<{ ok: boolean }> {
    return submit({ kind: 'dm', op: 'fight_join', collection: 'creatures', entry: String(e.id), name: String(e.name ?? e.id), count, hidden }).then((r) => {
      if (r.ok) {
        q = '';
        found = [];
      }
      return r;
    });
  }
</script>

<section class="join" aria-label="Add to the fight">
  <h3>Add to the fight</h3>
  <input type="search" placeholder="A creature: goblin, wolf, mastiff…" bind:value={q} aria-label="Find a creature to add to the fight" />
  <div class="opts">
    <label>How many <input type="number" min="1" max="20" bind:value={count} /></label>
    <label><input type="checkbox" bind:checked={hidden} /> hidden until you reveal them</label>
  </div>
  {#each found as e (e.id)}
    <ActButton quiet class="foundbtn" act={() => join(e)}>
      <span class="found"><span>{e.name}</span><span class="dim">CR {cr(e.cr)}{e.type ? ` · ${e.type}` : ''}</span><span class="accentword">Add {count}</span></span>
    </ActButton>
  {/each}
</section>

<style>
  .join {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding-top: 10px;
    border-top: 1px solid var(--border-soft);
  }
  h3 {
    font-size: 1rem;
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
  .join :global(.foundbtn) {
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
  }
  .found span:first-child {
    flex: 1;
  }
  .accentword {
    color: var(--accent);
    font-weight: 600;
  }
</style>
