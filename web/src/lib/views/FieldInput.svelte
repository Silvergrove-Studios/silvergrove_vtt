<!--
  One control of a form, by the field's type (PropertyForm's types): a
  number, a switch, a choice, a colour, a line or a box of text, a pair of
  numbers, or a list of records each edited with its own small form.
  `value` follows every keystroke; `commit` is called when an edit is done
  (a choice made, a box left, Enter pressed).
-->
<script lang="ts">
  import Form from './Form.svelte';
  import ScoresField from './ScoresField.svelte';
  import ChooseField from './ChooseField.svelte';
  import { optionValue, optionLabel, type Dict } from './viewlib';
  import type { Choice } from './fieldcheck';

  let {
    field,
    value = $bindable(),
    commit,
    ctx = {},
    options = $bindable(),
  }: { field: Dict; value: any; commit?: (v: any) => void; ctx?: Dict; options?: Choice[] | null } = $props();

  const type = $derived(String(field.type ?? 'string'));
  const id = `f${Math.random().toString(36).slice(2, 9)}`;

  function clampNum(v: number): number {
    let x = Number.isFinite(v) ? v : 0;
    if (field.min !== undefined) x = Math.max(Number(field.min), x);
    if (field.max !== undefined) x = Math.min(Number(field.max), x);
    return type === 'int' ? Math.trunc(x) : x;
  }

  function addItem(): void {
    const list = Array.isArray(value) ? [...value] : [];
    list.push({});
    value = list;
    commit?.(value);
  }

  function removeItem(i: number): void {
    const list = Array.isArray(value) ? [...value] : [];
    list.splice(i, 1);
    value = list;
    commit?.(value);
  }
</script>

{#if type === 'scores'}
  <ScoresField {field} bind:value {ctx} />
{:else if type === 'choose'}
  <ChooseField {field} bind:value bind:options />
{:else if type === 'int' || type === 'float'}
  <span class="num">
    <input
      {id}
      type="number"
      inputmode={type === 'int' ? 'numeric' : 'decimal'}
      min={field.min}
      max={field.max}
      step={field.step ?? (type === 'int' ? 1 : 0.01)}
      value={value ?? 0}
      oninput={(e) => (value = clampNum(Number((e.currentTarget as HTMLInputElement).value)))}
      onchange={() => commit?.(value)}
    />
    {#if field.suffix}<span class="suffix">{field.suffix}</span>{/if}
  </span>
{:else if type === 'bool'}
  <input {id} type="checkbox" checked={value === true} onchange={(e) => { value = (e.currentTarget as HTMLInputElement).checked; commit?.(value); }} />
{:else if type === 'enum'}
  {#if (field.options ?? []).length === 0}
    <select {id} disabled><option>{field.loading ? 'Loading…' : 'Nothing to choose'}</option></select>
  {:else}
    <select {id} value={String(value ?? '')} onchange={(e) => { value = (e.currentTarget as HTMLSelectElement).value; commit?.(value); }}>
      {#each field.options as o (optionValue(o))}
        <option value={optionValue(o)}>{optionLabel(o)}</option>
      {/each}
    </select>
  {/if}
{:else if type === 'color'}
  <input {id} type="color" value={String(value ?? '#ffffff').slice(0, 7)} onchange={(e) => { value = (e.currentTarget as HTMLInputElement).value; commit?.(value); }} />
{:else if type === 'text'}
  <textarea {id} rows="4" value={String(value ?? '')} oninput={(e) => (value = (e.currentTarget as HTMLTextAreaElement).value)} onchange={() => commit?.(value)}></textarea>
{:else if type === 'vec2'}
  <span class="pair">
    {#each [0, 1] as axis}
      <input
        type="number"
        step={field.step ?? 0.01}
        value={Array.isArray(value) ? value[axis] : 0}
        oninput={(e) => {
          const v = Array.isArray(value) ? [...value] : [0, 0];
          v[axis] = Number((e.currentTarget as HTMLInputElement).value) || 0;
          value = v;
        }}
        onchange={() => commit?.(value)}
      />
    {/each}
  </span>
{:else if type === 'list'}
  <div class="list">
    {#each Array.isArray(value) ? value : [] as _item, i (i)}
      <div class="item">
        <Form fields={field.fields ?? []} bind:values={value[i]} onchange={() => commit?.(value)} />
        <button type="button" class="quiet" aria-label="Remove" onclick={() => removeItem(i)}>✕</button>
      </div>
    {/each}
    <button type="button" class="quiet add" onclick={addItem}>{field.add_label ?? 'Add'}</button>
  </div>
{:else}
  <input
    {id}
    type="text"
    value={String(value ?? '')}
    oninput={(e) => (value = (e.currentTarget as HTMLInputElement).value)}
    onchange={() => commit?.(value)}
    onkeydown={(e) => {
      if (e.key === 'Enter') commit?.(value);
    }}
  />
{/if}

<style>
  input[type='text'],
  input[type='number'],
  select,
  textarea {
    width: 100%;
    min-width: 0;
  }
  .num {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .suffix {
    color: var(--muted);
  }
  .pair {
    display: flex;
    gap: 6px;
  }
  .list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .item {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    padding: 8px;
    border: 1px solid var(--border);
    border-radius: 10px;
  }
  .item :global(.form) {
    flex: 1;
  }
  .add {
    align-self: flex-start;
  }
</style>
