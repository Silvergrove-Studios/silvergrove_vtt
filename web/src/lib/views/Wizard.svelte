<!--
  One step at a time, with Back and Next; the last step's button submits
  every step's values together ($values).
-->
<script lang="ts">
  import Form from './Form.svelte';
  import { viewUi } from './context';
  import { fillIntent, putValue, withOptions, type Dict } from './viewlib';
  import { markdown } from '../markdown';

  let { node, ctx }: { node: Dict; ctx: Dict } = $props();
  const ui = viewUi();
  let at = $state(0);
  let values = $state<Dict>({});
  const steps = $derived((Array.isArray(node.steps) ? node.steps : []) as Dict[]);
  const step = $derived((steps[at] ?? {}) as Dict);
  const fields = $derived(((step.fields as Dict[]) ?? []).filter((f) => f && typeof f === 'object' && 'key' in f).map((f) => withOptions(f, ctx)));
  const last = $derived(at >= steps.length - 1);

  function next(): void {
    if (!last) {
      at += 1;
      return;
    }
    ui.intent(putValue(fillIntent(node.submit ?? {}, ctx), $state.snapshot(values), '$values'));
  }
</script>

<div class="wizard">
  {#if steps.length === 0}
    <h4>{node.label ?? ''}</h4>
  {:else}
    <div class="head">
      <h4>{node.label ? `${node.label}: ` : ''}{step.title ?? ''}</h4>
      <span class="dim">{at + 1} of {steps.length}</span>
    </div>
    {#if step.text}<div class="prose">{@html markdown(String(step.text))}</div>{/if}
    {#key at}
      <Form {fields} bind:values />
    {/key}
    <div class="nav">
      <button type="button" disabled={at === 0} onclick={() => (at = Math.max(0, at - 1))}>{node.back_label ?? 'Back'}</button>
      <button type="button" class="accent" onclick={next}>{last ? (node.submit_label ?? 'Submit') : (node.next_label ?? 'Next')}</button>
    </div>
  {/if}
</div>

<style>
  .wizard {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 8px;
  }
  .nav {
    display: flex;
    justify-content: space-between;
    gap: 8px;
  }
</style>
