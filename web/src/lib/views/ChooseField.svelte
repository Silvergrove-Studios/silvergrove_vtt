<!--
  Some of a list of described options: skills, spells, an equipment
  package. The options are the field's own records ({id, name, text, tag,
  sub}) or a compendium collection's entries (the viewer's own audience),
  less those `allowed` leaves out; those `fixed` are had already (ticked,
  locked, not counted). A counter says how many are left to choose and
  nothing past the limit can be picked. `single`: one of them (a string).
-->
<script lang="ts">
  import { viewUi } from './context';
  import { Expr } from '../expr';
  import { markdown } from '../markdown';
  import { matchWords, type Dict } from './viewlib';
  import { allowedIds, chooseBounds, choiceList, fixedIds, picked, toggle, type Choice } from './fieldcheck';

  let { field, value = $bindable(), options = $bindable() }: { field: Dict; value: any; options?: Choice[] | null } = $props();
  const ui = viewUi();

  let fetched = $state<Choice[] | null>(null);
  let fetchedKey = '';
  let q = $state('');
  let open = $state<string>('');

  // a collection's entries, fetched again when the query changes (another class chosen)
  $effect(() => {
    if (!field.collection) return;
    const query: Dict = field.query && typeof field.query === 'object' ? field.query : {};
    const want = ['name', 'text', ...(((field.fields as string[]) ?? []) as string[])];
    const req: Dict = { per_page: Number(field.limit ?? 400), page: 1, fields: want, sort: String(query.sort ?? field.sort ?? 'name') };
    if (query.filter && typeof query.filter === 'object') req.filter = query.filter;
    if (query.text) req.text = String(query.text);
    const key = `${field.collection}|${JSON.stringify(req)}`;
    if (key === fetchedKey) return;
    fetchedKey = key;
    fetched = null;
    ui.comp(String(field.collection), { query: req }).then((reply) => {
      if (key !== fetchedKey) return;
      fetched = ((reply.page?.entries as Dict[]) ?? []).map((e) => {
        const sub = field.sub ? Expr.evaluateText(String(field.sub), { item: e }) : '';
        return { ...e, id: String(e.id ?? ''), name: String(e.name ?? e.id ?? ''), sub, text: String(e.text ?? '') } as Choice;
      });
    });
  });

  const all = $derived(field.collection ? fetched : choiceList(field.options));
  const allowed = $derived(allowedIds(field));
  const fixed = $derived(fixedIds(field));
  const offered = $derived((all ?? []).filter((o) => !fixed.includes(o.id) && (!allowed || allowed.includes(o.id))));
  const had = $derived((all ?? []).filter((o) => fixed.includes(o.id)));
  const ids = $derived(picked(field, value));
  const bounds = $derived(chooseBounds(field));
  const full = $derived(!field.single && ids.length >= bounds[1]);
  // (the words typed, in any order, each the start of a word: "hooded lan" finds "Lantern, Hooded")
  const shownList = $derived(q.trim() ? offered.filter((o) => matchWords(`${o.name} ${o.sub ?? ''} ${o.tag ?? ''}`, q)) : offered);

  // what the options are, for the wizard's check
  $effect(() => {
    options = all ? [...had, ...offered] : null;
  });

  // a pick that is no longer on offer (another class chosen) goes
  $effect(() => {
    if (!all) return;
    const ok = new Set(offered.map((o) => o.id));
    const keep = ids.filter((id) => ok.has(id));
    if (keep.length !== ids.length) value = field.single ? (keep[0] ?? '') : keep;
  });

  function tap(o: Choice): void {
    value = toggle(field, value, o.id);
  }

  function preview(t: string): string {
    const s = t.replace(/\s+/g, ' ').trim();
    return s.length > 180 ? s.slice(0, 177).replace(/\s\S*$/, '') + '…' : s;
  }

  const counter = $derived.by(() => {
    if (field.single) return ids.length ? '' : 'Choose one';
    const [lo, hi] = bounds;
    if (lo === hi) {
      const n = lo - ids.length;
      return n > 0 ? `Choose ${lo} · ${n} left` : `${lo} chosen ✓`;
    }
    return hi === Infinity ? `${ids.length} chosen` : `${ids.length} of up to ${hi}`;
  });
</script>

<div class="choose">
  {#if counter}<div class="counter" class:done={counter.endsWith('✓')}>{counter}</div>{/if}
  {#if had.length}
    <ul class="opts">
      {#each had as o (o.id)}
        <li>
          <div class="opt had" aria-disabled="true">
            <span class="box on" aria-hidden="true">🔒</span>
            <span class="body">
              <span class="top"><strong>{o.name}</strong>{#if o.tag}<span class="tag">{o.tag}</span>{/if}<span class="from">{field.fixed_label ?? 'Yours already'}</span></span>
              {#if o.text}<span class="text">{preview(o.text)}</span>{/if}
            </span>
          </div>
        </li>
      {/each}
    </ul>
  {/if}
  {#if all === null}
    <p class="dim">Loading the choices…</p>
  {:else if offered.length === 0}
    <p class="dim">{field.empty ?? 'Nothing to choose here.'}</p>
  {:else}
    {#if field.search || offered.length > 12}
      <input type="search" placeholder="Find one…" bind:value={q} />
    {/if}
    <ul class="opts" role={field.single ? 'radiogroup' : 'group'} aria-label={field.label ?? field.key}>
      {#each shownList as o (o.id)}
        {@const on = ids.includes(o.id)}
        <li>
          <div class="row">
            <button type="button" class="opt" class:on class:dimmed={full && !on} role={field.single ? 'radio' : 'checkbox'} aria-checked={on} onclick={() => tap(o)}>
              <span class="box" class:on class:round={field.single} aria-hidden="true">{on ? '✓' : ''}</span>
              <span class="body">
                <span class="top"><strong>{o.name}</strong>{#if o.tag}<span class="tag">{o.tag}</span>{/if}</span>
                {#if o.sub}<span class="sub">{o.sub}</span>{/if}
                {#if o.text}
                  {#if open === o.id}<span class="text full prose">{@html markdown(String(o.text))}</span>{:else}<span class="text">{preview(String(o.text))}</span>{/if}
                {/if}
              </span>
            </button>
            {#if field.detail}
              <button type="button" class="more" aria-label={`Read ${o.name}`} onclick={() => ui.intent({ kind: 'lookup', collection: String(field.detail), id: o.id })}>?</button>
            {:else if o.text && preview(String(o.text)) !== String(o.text).replace(/\s+/g, ' ').trim()}
              <button type="button" class="more" aria-label={open === o.id ? 'Less' : `More about ${o.name}`} onclick={() => (open = open === o.id ? '' : o.id)}>{open === o.id ? '−' : '…'}</button>
            {/if}
          </div>
        </li>
      {/each}
    </ul>
    {#if full && !field.single}<p class="dim small">That's all you can choose — tap one to swap it for another.</p>{/if}
  {/if}
</div>

<style>
  .choose {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .counter {
    align-self: flex-start;
    font-weight: 700;
    color: var(--accent);
  }
  .counter.done {
    color: #8fd18f;
  }
  .opts {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .row {
    display: flex;
    gap: 6px;
    align-items: stretch;
  }
  .opt {
    flex: 1;
    display: flex;
    gap: 10px;
    align-items: flex-start;
    text-align: left;
    padding: 10px 12px;
    border-radius: 12px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    min-height: 48px;
    font: inherit;
    color: inherit;
  }
  .opt.on {
    border-color: var(--accent);
    background: var(--accent-bg);
  }
  .opt.dimmed {
    opacity: 0.55;
  }
  .opt.had {
    opacity: 0.85;
    border-style: dashed;
  }
  .box {
    flex: none;
    width: 22px;
    height: 22px;
    border-radius: 6px;
    border: 2px solid var(--muted);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 0.8rem;
    font-weight: 800;
    margin-top: 1px;
  }
  .box.round {
    border-radius: 50%;
  }
  .box.on {
    border-color: var(--accent);
    background: var(--accent);
    color: #1b1508;
  }
  .had .box {
    border: 0;
    background: none;
    font-size: 0.9rem;
  }
  .body {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .top {
    display: flex;
    gap: 8px;
    align-items: baseline;
    flex-wrap: wrap;
  }
  .tag {
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.05em;
    color: var(--muted);
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 0 7px;
  }
  .from {
    font-size: 0.78rem;
    color: #8fd18f;
  }
  .sub {
    font-size: 0.82rem;
    color: var(--accent);
  }
  .text {
    font-size: 0.86rem;
    color: var(--muted);
  }
  .text.full {
    color: var(--text, inherit);
  }
  .more {
    flex: none;
    align-self: flex-start;
    width: 44px;
    height: 44px;
    border-radius: 12px;
    padding: 0;
  }
  .small {
    font-size: 0.85rem;
    margin: 0;
  }
</style>
