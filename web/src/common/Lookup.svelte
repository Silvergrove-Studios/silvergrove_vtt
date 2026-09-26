<!--
  Look something up: a search across every collection at the table, what
  matched, and the entry as a card (the ruleset's, or a generic one).
  Opened by a sheet's lookup button or by the search box.
-->
<script lang="ts">
  import Modal from './Modal.svelte';
  import View from '../lib/views/View.svelte';
  import { comp, game } from '../lib/game.svelte';
  import { cardData, cardSchema, type Dict } from '../lib/views/viewlib';

  let { at = null, onclose }: { at?: { collection: string; id: string } | null; onclose: () => void } = $props();

  let q = $state('');
  let results = $state<{ collection: string; id: string; name: string }[]>([]);
  let entry = $state<{ collection: string; data: Dict } | null>(null);
  let error = $state('');
  let seq = 0;

  function open(collection: string, id: string): void {
    error = '';
    comp(collection, { id }).then((reply) => {
      if (reply.entry) entry = { collection, data: cardData(reply.entry, game.role === 'dm' ? 'gm' : 'player', game.me) };
      else error = String(reply.error ?? 'not found');
    });
  }

  $effect(() => {
    if (at) open(at.collection, at.id);
  });

  $effect(() => {
    const text = q.trim();
    const mine = ++seq;
    if (text.length < 2) {
      results = [];
      return;
    }
    const found: typeof results = [];
    // the best names first, whichever collection answers first: "Advantage/Disadvantage"
    // before the conditions that mention it (a playtest's new player searched
    // "advantage" and saw only those)
    const t = text.toLowerCase();
    const score = (name: string): number => {
      const n = name.toLowerCase();
      if (n === t) return 0;
      if (n.startsWith(t)) return 1;
      if (n.split(/[^a-z0-9']+/).some((w) => w.startsWith(t))) return 2;
      return 3;
    };
    for (const coll of (game.view.collections as string[]) ?? []) {
      comp(coll, { query: { text, per_page: 8, fields: ['name'] } }).then((reply) => {
        if (mine !== seq) return;
        for (const e of (reply.page?.entries as Dict[]) ?? []) found.push({ collection: coll, id: String(e.id ?? ''), name: String(e.name ?? e.id ?? '') });
        results = [...found].sort((x, y) => score(x.name) - score(y.name));
      });
    }
  });
</script>

<Modal title={entry ? String(entry.data.entry?.name ?? 'Look up') : 'Look up'} wide {onclose}>
  <div class="lookup">
    <input type="search" placeholder="A spell, a creature, an item, a condition…" bind:value={q} />
    {#if results.length}
      <ul class="results">
        {#each results as r (r.collection + '/' + r.id)}
          <li><button type="button" class="quiet" onclick={() => { open(r.collection, r.id); q = ''; }}>{r.name}<span class="dim"> · {r.collection.replace(/_/g, ' ')}</span></button></li>
        {/each}
      </ul>
    {/if}
    {#if error}<p class="dim">{error}</p>{/if}
    {#if entry}
      <article class="card">
        <View node={cardSchema(game.view.cards ?? {}, entry.collection)} ctx={entry.data} />
      </article>
    {/if}
  </div>
</Modal>

<style>
  .lookup {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .results {
    list-style: none;
    margin: 0;
    padding: 4px;
    border: 1px solid var(--border);
    border-radius: 10px;
    max-height: 240px;
    overflow: auto;
  }
  .results button {
    width: 100%;
    text-align: left;
  }
  .card {
    padding: 4px 2px;
  }
</style>
