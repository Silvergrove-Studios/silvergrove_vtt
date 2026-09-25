<!--
  A form from a field list (PropertyForm): each field its label and its
  control. Values start as the host's form would have them (a number 0 or
  its minimum, a choice its first option, …) so a form sent untouched says
  what the Godot one would. A field may take its choices from a compendium
  `collection` (fetched here) or `from` the data (worked out before).
-->
<script lang="ts">
  import FieldInput from './FieldInput.svelte';
  import { viewUi } from './context';
  import { optionValue, type Dict } from './viewlib';

  let { fields, values = $bindable({}), onchange }: { fields: Dict[]; values?: Dict; onchange?: (key: string, v: any) => void } = $props();

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
      default:
        return String(v ?? f.default ?? '');
    }
  }

  /** The fields as drawn: a collection's choices once they have come. */
  const drawn = $derived(
    fields
      .filter((f) => f && typeof f === 'object' && 'key' in f)
      .map((f) => (f.collection ? { ...f, type: 'enum', options: loaded[f.key] ?? [], loading: !loaded[f.key] } : f)),
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
      if (!f?.collection || loaded[f.key]) continue;
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
    <div class="row" class:wide={f.type === 'list' || f.type === 'text'}>
      <label for={undefined} class="label" title={f.tooltip ?? ''}>{f.label ?? f.key}</label>
      <div class="control">
        <FieldInput field={f} bind:value={values[f.key]} commit={(v) => onchange?.(f.key, v)} />
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
