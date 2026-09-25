<!--
  A form from a field list (PropertyForm): each field its label and its
  control. Values start as the host's form would have them (a number 0 or
  its minimum, a choice its first option, …) so a form sent untouched says
  what the Godot one would. A field may take its choices from a compendium
  `collection` (fetched here) or `from` the data (worked out before). With
  a `ctx` (a wizard's: its answers and the view's data), a field's `if`
  can hide it; `scores` and `choose` fields take the whole width.
-->
<script lang="ts">
  import FieldInput from './FieldInput.svelte';
  import { viewUi } from './context';
  import { optionValue, shown, type Dict } from './viewlib';
  import type { Choice } from './fieldcheck';

  let {
    fields,
    values = $bindable({}),
    onchange,
    ctx = null,
    options = $bindable(),
  }: { fields: Dict[]; values?: Dict; onchange?: (key: string, v: any) => void; ctx?: Dict | null; options?: Record<string, Choice[] | null> } = $props();

  const ui = viewUi();
  let loaded = $state<Record<string, Dict[]>>({});

  function initial(f: Dict, v: any): any {
    switch (String(f.type ?? 'string')) {
      case 'int':
      case 'float': {
        let x = Number(v ?? f.default ?? 0);
        if (!Number.isFinite(x)) x = 0;
        if (f.min !== undefined) x = Math.max(Number(f.min), x);
        if (f.max !== undefined) x = Math.min(Number(f.max), x);
        return f.type === 'int' ? Math.trunc(x) : x;
      }
      case 'bool':
        return v === true || v === 'true' || (v === undefined && f.default === true);
      case 'enum': {
        const opts: any[] = f.options ?? [];
        const s = String(v ?? f.default ?? '');
        return opts.some((o) => optionValue(o) === s) ? s : opts.length ? optionValue(opts[0]) : s;
      }
      case 'color':
        return String(v ?? f.default ?? '#ffffff');
      case 'vec2':
        return Array.isArray(v) ? v : [0, 0];
      case 'list':
        return Array.isArray(v) ? v.map((x) => (x && typeof x === 'object' ? x : {})) : [];
      case 'choose':
        return f.single ? String(v ?? f.default ?? '') : Array.isArray(v) ? v.map(String) : [];
      case 'scores':
        return v && typeof v === 'object' ? v : null;
      default:
        return String(v ?? f.default ?? '');
    }
  }

  /** The fields as drawn: a collection's choices once they have come. */
  const drawn = $derived(
    fields
      .filter((f) => f && typeof f === 'object' && 'key' in f && (!ctx || shown(f, ctx)))
      .map((f) => (f.collection && f.type !== 'choose' ? { ...f, type: 'enum', options: loaded[f.key] ?? [], loading: !loaded[f.key] } : f)),
  );

  // start every value off as the host's form would
  $effect.pre(() => {
    for (const f of drawn) {
      const v = initial(f, values[f.key]);
      if (JSON.stringify(v) !== JSON.stringify(values[f.key])) values[f.key] = v;
    }
  });

  // fields whose choices are a collection's entries, as this viewer may see them
  $effect(() => {
    for (const f of fields) {
      if (!f?.collection || f.type === 'choose' || loaded[f.key]) continue;
      const q: Dict = f.query && typeof f.query === 'object' ? f.query : {};
      const req: Dict = { text: String(q.text ?? ''), per_page: Number(f.limit ?? 200), page: 1, fields: ['name'], sort: String(q.sort ?? 'name') };
      if (q.filter && typeof q.filter === 'object') req.filter = q.filter;
      ui.comp(String(f.collection), { query: req }).then((reply) => {
        const opts: Dict[] = ((reply.page?.entries as Dict[]) ?? []).map((e) => ({ id: String(e.id ?? ''), name: String(e.name ?? e.id ?? '') }));
        if (f.optional) opts.unshift({ id: '', name: String(f.none_label ?? '—') });
        loaded[f.key] = opts;
      });
    }
  });
</script>

<div class="form">
  {#each drawn as f (f.key)}
    <div class="row" class:wide={f.type === 'list' || f.type === 'text' || f.type === 'scores' || f.type === 'choose'}>
      {#if f.label !== ''}<label for={undefined} class="label" class:strong={f.type === 'scores' || f.type === 'choose'} title={f.tooltip ?? ''}>{f.label ?? f.key}</label>{/if}
      {#if f.help}<p class="help">{f.help}</p>{/if}
      <div class="control">
        {#if options}
          <FieldInput field={f} bind:value={values[f.key]} bind:options={options[f.key]} ctx={ctx ?? {}} commit={(v) => onchange?.(f.key, v)} />
        {:else}
          <FieldInput field={f} bind:value={values[f.key]} ctx={ctx ?? {}} commit={(v) => onchange?.(f.key, v)} />
        {/if}
      </div>
    </div>
  {/each}
</div>

<style>
  .form {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .row {
    display: grid;
    grid-template-columns: minmax(90px, 38%) 1fr;
    gap: 10px;
    align-items: center;
  }
  .row.wide {
    grid-template-columns: 1fr;
    gap: 4px;
  }
  .label {
    color: var(--muted);
    font-size: 0.92rem;
  }
  .label.strong {
    color: var(--heading);
    font-weight: 650;
    font-size: 1rem;
  }
  .help {
    margin: 0;
    font-size: 0.86rem;
    color: var(--muted);
  }
  .control {
    min-width: 0;
  }
  @media (max-width: 420px) {
    .row {
      grid-template-columns: 1fr;
      gap: 4px;
    }
  }
</style>
