<!--
  A searchable list to choose from: a bound list (strings, or records with
  an id and a name) or a compendium collection fetched a page at a time.
  Choosing sends on_pick with @pick (or, with multi, @picks on Done). The
  query's `{expr}` values are worked out from the data (a class's spells
  up to the level it casts); `sub` is a line under each name (an Expr over
  @item), `detail` a collection whose card a "?" opens.
-->
<script lang="ts">
  import { viewUi } from './context';
  import { fillIntent, matchWords, optionId, optionLabel, valueOf, type Dict, clone } from './viewlib';
  import { resolve } from './fieldcheck';
  import { Expr } from '../expr';

  let { node, ctx }: { node: Dict; ctx: Dict } = $props();
  const ui = viewUi();
  let q = $state('');
  let items = $state<any[]>([]);
  let status = $state('');
  let chosen = $state<string[]>([]);
  let seq = 0;
  const multi = $derived(Boolean(node.multi));

  function load(): void {
    const text = q.trim().toLowerCase();
    if (node.collection) {
      const query: Dict = node.query && typeof node.query === 'object' ? resolve(clone(node.query), ctx) : {};
      if (text) query.text = text;
      query.per_page = Number(node.per_page ?? 25);
      if (node.fields) query.fields = node.fields;
      if (node.sort) query.sort = node.sort;
      const mine = ++seq;
      status = 'Looking…';
      ui.comp(String(node.collection), { query }).then((reply) => {
        if (mine !== seq) return;
        if (reply.error) {
          status = String(reply.error);
          items = [];
          return;
        }
        const page = reply.page ?? {};
        items = (page.entries as any[]) ?? [];
        const total = Number(page.total ?? items.length);
        status = items.length === 0 ? (text ? 'Nothing matches' : String(node.empty ?? 'Nothing to pick')) : total > items.length ? `${items.length} of ${total} — narrow the search` : '';
      });
    } else {
      const raw = valueOf(node, ctx);
      let all: any[] = [];
      if (Array.isArray(raw)) all = raw;
      else if (raw && typeof raw === 'object') all = Object.entries(raw).map(([k, v]) => (v && typeof v === 'object' ? v : { id: k, name: String(v) }));
      items = all.filter((it) => matchWords(optionLabel(it), text));
      status = items.length === 0 ? (text ? 'Nothing matches' : String(node.empty ?? 'Nothing to pick')) : '';
    }
  }

  $effect(() => {
    void q;
    void ctx;
    load();
  });

  function pick(it: any): void {
    ui.intent(fillIntent(node.on_pick ?? {}, { ...ctx, pick: it, pick_id: optionId(it) }));
  }

  function done(): void {
    ui.intent(fillIntent(node.on_pick ?? {}, { ...ctx, picks: [...chosen] }));
  }

  function sub(it: any): string {
    return node.sub && it && typeof it === 'object' ? Expr.evaluateText(String(node.sub), { ...ctx, item: it }) : '';
  }

  function toggle(id: string): void {
    chosen = chosen.includes(id) ? chosen.filter((x) => x !== id) : [...chosen, id];
  }
</script>

<div class="picker">
  {#if node.label}<h4>{node.label}</h4>{/if}
  {#if node.search !== false}
    <input type="search" placeholder={node.placeholder ?? 'Search…'} bind:value={q} />
  {/if}
  <ul class="options" style:max-height={`${Number(node.height ?? 220)}px`}>
    {#each items as it, i (optionId(it) + ':' + i)}
      <li>
        {#if multi}
          <label class="opt">
            <input type="checkbox" checked={chosen.includes(optionId(it))} onchange={() => toggle(optionId(it))} />
            <span>{optionLabel(it)}</span>
          </label>
        {:else}
          <div class="row">
            <button type="button" class="opt" onclick={() => pick(it)}>
              <span class="name">{optionLabel(it)}</span>
              {#if node.sub}<span class="sub">{sub(it)}</span>{/if}
            </button>
            {#if node.detail}<button type="button" class="more" aria-label={`Read ${optionLabel(it)}`} onclick={() => ui.intent({ kind: 'lookup', collection: String(node.detail), id: optionId(it) })}>?</button>{/if}
          </div>
        {/if}
      </li>
    {/each}
  </ul>
  {#if status}<p class="dim">{status}</p>{/if}
  {#if multi}
    <button type="button" class="accent" onclick={done}>{node.done_label ?? 'Done'}</button>
  {/if}
</div>

<style>
  .picker {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .options {
    list-style: none;
    margin: 0;
    padding: 4px;
    overflow: auto;
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--field);
  }
  .opt {
    display: flex;
    gap: 8px;
    align-items: center;
    width: 100%;
    text-align: left;
    padding: 8px 10px;
    border: 0;
    border-radius: 8px;
    background: none;
    color: inherit;
    font: inherit;
    cursor: pointer;
  }
  .opt:hover {
    background: var(--hover);
  }
  .row {
    display: flex;
    gap: 4px;
    align-items: stretch;
  }
  .row .opt {
    flex: 1;
    flex-direction: column;
    align-items: flex-start;
    gap: 1px;
  }
  .sub {
    font-size: 0.8rem;
    color: var(--accent);
  }
  .more {
    flex: none;
    width: 40px;
    padding: 0;
    border-radius: 8px;
  }
</style>
