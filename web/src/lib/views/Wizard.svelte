<!--
  One step at a time, with Back and Next; the last step's button submits
  every step's values together ($values).

  A step or a field may have an `if`, and a field's properties may be
  `{expr = "…"}`: both see the view's data and `@values` (the answers so
  far) and `@chosen` (for an answer picked from a compendium or a list of
  records, that record — the class chosen, with its skill choices and
  spell counts). Next waits until the step's fields are right (a name
  typed, the points spent, the skills chosen) and says what is missing.
  The step and the answers are kept in this browser until the wizard is
  done, so a phone that drops the page while in another app comes back to
  where it was.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import Form from './Form.svelte';
  import { viewUi } from './context';
  import { fillIntent, putValue, shown, withOptions, type Dict } from './viewlib';
  import { fieldProblem, resolve, type Choice } from './fieldcheck';
  import { markdown } from '../markdown';

  let { node, ctx }: { node: Dict; ctx: Dict } = $props();
  const ui = viewUi();
  const KEEP_MS = 24 * 60 * 60 * 1000;

  const steps = $derived((Array.isArray(node.steps) ? node.steps : []).filter((s: unknown) => s && typeof s === 'object') as Dict[]);
  const storeKey = $derived(`hexmap.wizard/${String(ctx.me ?? '')}/${String(node.label ?? '')}/${steps.map((s) => String(s.title ?? '')).join('|')}`);

  function load(key: string): { at: number; values: Dict } | null {
    try {
      const raw = localStorage.getItem(key);
      if (!raw) return null;
      const v = JSON.parse(raw) as { at: number; values: Dict; t: number };
      if (!v || typeof v !== 'object' || Date.now() - Number(v.t ?? 0) > KEEP_MS) return null;
      return { at: Number(v.at) || 0, values: v.values && typeof v.values === 'object' ? v.values : {} };
    } catch {
      return null;
    }
  }

  // (read once, as the wizard opens: where it was left)
  const kept = untrack(() => load(storeKey));
  let at = $state(kept?.at ?? 0);
  let values = $state<Dict>(kept?.values ?? {});
  let chosen = $state<Dict>({});
  let options = $state<Record<string, Choice[] | null>>({});
  let sending = $state(false);
  let top: HTMLDivElement | undefined = $state();
  const asked = new Map<string, string>();

  const wctx = $derived({ ...ctx, values, chosen });
  const visible = $derived(steps.filter((s) => shown(s, wctx)));
  const index = $derived(Math.max(0, Math.min(at, visible.length - 1)));
  const step = $derived((visible[index] ?? {}) as Dict);
  const last = $derived(index >= visible.length - 1);

  function fieldsOf(s: Dict): Dict[] {
    return ((s.fields as Dict[]) ?? []).filter((f) => f && typeof f === 'object' && 'key' in f).map((f) => withOptions(resolve(f, wctx), wctx));
  }

  const fields = $derived(fieldsOf(step));
  const problem = $derived.by(() => {
    for (const f of fields) {
      if (!shown(f, wctx)) continue;
      const p = fieldProblem(f, values[f.key], options[f.key] ?? null);
      if (p) return p;
    }
    return '';
  });

  // keep the step and the answers
  $effect(() => {
    const snap = { at: index, values: $state.snapshot(values), t: Date.now() };
    try {
      localStorage.setItem(storeKey, JSON.stringify(snap));
    } catch {
      /* private mode, or full */
    }
  });

  // the record behind each answer picked from a compendium or from records
  $effect(() => {
    for (const s of steps) {
      for (const f of (s.fields as Dict[]) ?? []) {
        if (!f || typeof f !== 'object' || !('key' in f)) continue;
        const key = String(f.key);
        const v = values[key];
        if (typeof v !== 'string' || v === '') {
          if (key in chosen) delete chosen[key];
          continue;
        }
        if (f.collection && f.type !== 'choose') {
          const want = `${f.collection}/${v}`;
          if (asked.get(key) === want) continue;
          asked.set(key, want);
          ui.comp(String(f.collection), { id: v }).then((reply) => {
            if (asked.get(key) === want && reply.entry) chosen[key] = reply.entry;
          });
        } else {
          const recs = options[key] ?? (Array.isArray(f.options) ? (f.options as Dict[]) : null);
          const rec = recs?.find((o) => o && typeof o === 'object' && String(o.id ?? '') === v);
          if (rec && chosen[key]?.id !== rec.id) chosen[key] = rec;
        }
      }
    }
  });

  function goto(i: number): void {
    at = Math.max(0, Math.min(i, visible.length - 1));
    queueMicrotask(() => top?.scrollIntoView({ block: 'start', behavior: 'smooth' }));
  }

  /** The answers of the steps and fields that apply (a spell step a fighter never saw is left out). */
  function answers(): Dict {
    const out: Dict = {};
    for (const s of visible) for (const f of fieldsOf(s)) if (shown(f, wctx)) out[f.key] = $state.snapshot(values[f.key]);
    return out;
  }

  function next(): void {
    if (problem) return;
    if (!last) {
      goto(index + 1);
      return;
    }
    sending = true;
    ui.intent(putValue(fillIntent(node.submit ?? {}, ctx), answers(), '$values'));
    setTimeout(() => (sending = false), 3000);
  }
</script>

<div class="wizard" bind:this={top}>
  {#if visible.length === 0}
    <h4>{node.label ?? ''}</h4>
  {:else}
    <div class="head">
      <h4>{step.title ?? ''}</h4>
      <span class="dim">Step {index + 1} of {visible.length}</span>
    </div>
    <div class="dots" aria-hidden="true">
      {#each visible as s, i (i)}<span class:on={i === index} class:done={i < index} title={String(s.title ?? '')}></span>{/each}
    </div>
    {#if step.text}<div class="prose">{@html markdown(String(step.text))}</div>{/if}
    {#key `${index}/${String(step.title ?? '')}`}
      <Form {fields} bind:values bind:options ctx={wctx} />
    {/key}
    {#if problem}<p class="problem" role="status">{problem}</p>{/if}
    <div class="nav">
      <button type="button" disabled={index === 0} onclick={() => goto(index - 1)}>{node.back_label ?? 'Back'}</button>
      <button type="button" class="accent" disabled={!!problem || sending} onclick={next}>{last ? (sending ? 'Sending…' : (node.submit_label ?? 'Submit')) : (node.next_label ?? 'Next')}</button>
    </div>
  {/if}
</div>

<style>
  .wizard {
    display: flex;
    flex-direction: column;
    gap: 10px;
    scroll-margin-top: 12px;
  }
  .head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 8px;
  }
  .head h4 {
    font-family: var(--font-display);
    font-size: 1.25rem;
    margin: 0;
  }
  .dots {
    display: flex;
    gap: 6px;
  }
  .dots span {
    flex: 1;
    height: 4px;
    border-radius: 2px;
    background: var(--panel-2);
  }
  .dots span.done {
    background: color-mix(in srgb, var(--accent) 45%, transparent);
  }
  .dots span.on {
    background: var(--accent);
  }
  .problem {
    margin: 0;
    font-size: 0.9rem;
    color: var(--accent);
  }
  .nav {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    position: sticky;
    bottom: 0;
    padding: 8px 0 2px;
    background: linear-gradient(to top, var(--panel) 70%, transparent);
  }
  .nav button {
    min-width: 7em;
    min-height: 44px;
  }
</style>
