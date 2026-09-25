<!--
  A searchable list to choose from: a bound list (strings, or records with
  an id and a name) or a compendium collection fetched a page at a time.
  Choosing sends on_pick with @pick (or, with multi, @picks on Done).
-->
<script lang="ts">
  import { viewUi } from './context';
  import { fillIntent, optionId, optionLabel, valueOf, type Dict, clone } from './viewlib';

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
      const query: Dict = node.query && typeof node.query === 'object' ? clone(node.query) : {};
      if (text) query.text = text;
      query.per_page = Number(node.per_page ?? 25);
      if (node.fields) query.fields = node.fields;
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
      items = all.filter((it) => !text || optionLabel(it).toLowerCase().includes(text));
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
          <button type="button" class="opt" onclick={() => pick(it)}>{optionLabel(it)}</button>
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
</style>
