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

  // what the search looks through, as one string: every view the table sends
  // is a new list, and the search ran again on each
  const colls = $derived(((game.view.collections as string[]) ?? []).join('\n'));

  $effect(() => {
    const text = q.trim();
    const list = colls ? colls.split('\n') : [];
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
    for (const coll of list) {
      comp(coll, { query: { text, per_page: 8, fields: ['name'] } }).then((reply) => {
        if (mine !== seq) return;
        for (const e of (reply.page?.entries as Dict[]) ?? []) found.push({ collection: coll, id: String(e.id ?? ''), name: String(e.name ?? e.id ?? '') });
        results = [...found].sort((x, y) => score(x.name) - score(y.name));
      });
    }
  });
</script>

<!-- the search box has the keyboard as the card opens (a playtest's player
     typed "cover" into it and the word went into the chat box beneath), is
     named for what it does, and Enter opens the first of what it found -->
<Modal title={entry ? String(entry.data.entry?.name ?? 'Look up') : 'Look up'} wide {onclose}>
  <div class="lookup">
    <!-- svelte-ignore a11y_autofocus -->
    <input
      type="search"
      aria-label="Look up"
      placeholder="A spell, a creature, an item, a condition…"
      bind:value={q}
      autofocus={!at}
      onkeydown={(e) => {
        if (e.key === 'Enter' && results.length) {
          e.preventDefault();
          open(results[0].collection, results[0].id);
          q = '';
        }
      }}
    />
    {#if results.length}
      <!-- (each one a button that looks like one: a playtest's player took the
           plain rows for text and clicked around them) -->
      <ul class="results" aria-label="Found">
        {#each results as r (r.collection + '/' + r.id)}
          <li>
            <button type="button" class="result" onclick={() => { open(r.collection, r.id); q = ''; }}>
              <span class="name">{r.name}</span>
              <span class="dim kind">{r.collection.replace(/_/g, ' ')}</span>
              <span class="go" aria-hidden="true">Open ›</span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
    {#if error}<p class="dim">{error}</p>{/if}
    {#if entry}
      <article class="card">
        <View node={cardSchema(game.view.cards ?? {}, entry.collection)} ctx={{ ...entry.data, role: game.role === 'dm' ? 'gm' : 'player' }} />
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
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
    max-height: 280px;
    overflow: auto;
  }
  .result {
    width: 100%;
    display: flex;
    align-items: baseline;
    gap: 10px;
    text-align: left;
    background: var(--panel-2);
    border: 1px solid var(--border);
  }
  .result:hover:not(:disabled) {
    border-color: var(--accent-soft);
  }
  .result .name {
    color: var(--accent);
    font-weight: 600;
    text-decoration: underline;
    text-decoration-color: var(--accent-soft);
    text-underline-offset: 3px;
  }
  .result .kind {
    flex: 1;
    min-width: 0;
    font-size: 0.88rem;
  }
  .result .go {
    color: var(--muted);
    font-size: 0.85rem;
    white-space: nowrap;
  }
  .card {
    padding: 4px 2px;
  }
</style>
