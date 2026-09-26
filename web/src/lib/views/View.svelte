<!--
  A ruleset's view — the JSON a plugin registered — drawn over its data,
  as the host's ViewRenderer draws it (hexmap/ui/views/view_renderer.gd).
  The page never runs plugin code: the view says what to show and which
  intent a control sends; the Table decides what it means. Unknown types
  show as text, so a newer plugin still reads.
-->
<script lang="ts">
  import View from './View.svelte';
  import Form from './Form.svelte';
  import Picker from './Picker.svelte';
  import Wizard from './Wizard.svelte';
  import LogLine from './LogLine.svelte';
  import FieldInput from './FieldInput.svelte';
  import { viewUi } from './context';
  import { markdown } from '../markdown';
  import { assetArt } from '../art';
  import { breakdown, fillIntent, num, putValue, shown, textOf, valueOf, withOptions, type Dict, clone } from './viewlib';
  import { Expr, truthy } from '../expr';
  import { resolve } from './fieldcheck';

  let { node, ctx, depth = 0 }: { node: any; ctx: Dict; depth?: number } = $props();
  const ui = viewUi();
  const n = $derived((node && typeof node === 'object' && !Array.isArray(node) ? node : null) as Dict | null);
  const type = $derived(String(n?.type ?? ''));
  const visible = $derived(n != null && depth <= 24 && shown(n, ctx));
  let tab = $state(0);
  let formValues = $state<Dict>({});
  let fieldValue = $state<any>(undefined);

  function send(tpl: unknown, sub: Dict = ctx): void {
    const payload = fillIntent(tpl, sub);
    if (payload && typeof payload === 'object' && String(payload.pick ?? '') !== '') ui.pick(payload);
    else ui.intent(payload);
  }

  /** A property that is a literal, or a node's value ({expr}, {bind}, {text}). */
  function prop(node: Dict, key: string): string {
    const v = node[key];
    if (v && typeof v === 'object' && !Array.isArray(v)) return textOf(valueOf(v, ctx, 'text'));
    return v === undefined || v === null ? '' : String(v);
  }

  function items(v: any): any[] {
    if (Array.isArray(v)) return v;
    if (v && typeof v === 'object') return Object.values(v);
    return [];
  }

  // what a button costs, in words (a playtest's player read "Dash [1 actions]")
  const COST_WORDS: Record<string, [string, string]> = { actions: ['action', 'actions'], bonus: ['bonus action', 'bonus actions'], reactions: ['reaction', 'reactions'] };
  function costWords(k: string, v: unknown): string {
    const w = COST_WORDS[k];
    return w ? `${num(v)} ${Number(v) === 1 ? w[0] : w[1]}` : `${num(v)} ${k}`;
  }

  function buttonLabel(b: Dict): string {
    let s = textOf(valueOf(b, ctx, 'label'));
    if (b.cost && typeof b.cost === 'object' && Object.keys(b.cost).length) s += `  [${Object.entries(b.cost).map(([k, v]) => costWords(k, v)).join(', ')}]`;
    return s;
  }

  function enabled(b: Dict): boolean {
    if (!('intent' in b)) return false;
    return !('enabled' in b) || truthy(Expr.evaluate(String(b.enabled), ctx));
  }

  function prompted(rec: Dict): Dict {
    const form: Dict = rec.form && typeof rec.form === 'object' ? rec.form : {};
    return {
      label: String(form.title ?? rec.title ?? 'A question'),
      fields: Array.isArray(form.fields) ? form.fields : [],
      values: rec.default ?? {},
      submit: { kind: 'answer', prompt: String(rec.id ?? ''), answer: '$values' },
      submit_label: String(form.submit ?? 'Answer'),
      // a button for each choice ([{id, label, intent?}]) instead of one
      // "Answer": a roll the DM asked for is the player's own click
      choices: Array.isArray(form.choices) ? form.choices.filter((c: unknown) => c && typeof c === 'object') : null,
      prompt: String(rec.id ?? ''),
    };
  }

  // one tap per card: the choice goes, and the buttons wait for the card to close
  let chose = $state('');
  function choose(f: Dict, c: Dict): void {
    if (chose === f.prompt) return;
    chose = String(f.prompt);
    const values = $state.snapshot(formValues);
    if (c.intent && typeof c.intent === 'object') ui.intent(putValue(fillIntent(c.intent, ctx), values, '$values'));
    else ui.intent({ kind: 'answer', prompt: f.prompt, answer: { ...values, choice: String(c.id ?? '') } });
  }

  function formFields(f: Dict): Dict[] {
    // a field's `if` and its {expr} properties, as a wizard's are (what a new
    // level asks: a bard's Expertise, a ranger's languages)
    return ((f.fields as Dict[]) ?? []).filter((x) => x && typeof x === 'object' && 'key' in x && shown(x, ctx)).map((x) => withOptions(resolve(x, ctx), ctx));
  }

  // a form sent waits for the table: done, it starts over from its own values
  // (unless it `keep`s them) and says so beside its button for a moment;
  // refused, what was typed stays (a playtest's DM saw "Give something of your
  // own" still filled in after Give it, and couldn't tell it had worked)
  let sending = $state(false);
  let said = $state('');
  let saidTimer: ReturnType<typeof setTimeout> | undefined;
  async function submitForm(f: Dict): Promise<void> {
    const payload = putValue(fillIntent(f.submit ?? {}, ctx), $state.snapshot(formValues), '$values');
    if (!ui.submit) {
      ui.intent(payload);
      return;
    }
    sending = true;
    const r = await ui.submit(payload);
    sending = false;
    if (!r.ok) return;
    if (!f.keep) formValues = f.values && typeof f.values === 'object' ? clone(f.values) : {};
    said = String(f.done ?? 'Done ✓');
    clearTimeout(saidTimer);
    saidTimer = setTimeout(() => (said = ''), 4000);
  }
  $effect(() => () => clearTimeout(saidTimer));

  // a form's starting values, once for each form drawn here (a tab switch
  // draws another in this place: it starts from its own)
  let seededFor = '';
  $effect.pre(() => {
    if (!n || (type !== 'prompt' && type !== 'form' && type !== 'field')) return;
    const key = JSON.stringify(n);
    if (key === seededFor) return;
    seededFor = key;
    const src = type === 'prompt' ? prompted((valueOf(n, ctx) as Dict) ?? {}).values : type === 'form' ? n.values : null;
    if (src && typeof src === 'object') for (const [k, v] of Object.entries(clone(src))) formValues[k] = v;
    if (type === 'field') fieldValue = n.bind ? clone(valueOf({ bind: n.bind }, ctx)) : n.value;
  });

  // a field follows its value as the table changes it (the DM gives gold, a
  // level raises a score), not only as it was when drawn
  let boundWas: string | undefined;
  $effect(() => {
    if (type !== 'field' || !n?.bind) return;
    const v = valueOf({ bind: n.bind }, ctx);
    const s = JSON.stringify(v ?? null);
    if (s !== boundWas) {
      boundWas = s;
      fieldValue = clone(v);
    }
  });

  function trackBoxes(rec: Dict): { mark: 'marked' | 'open' | 'crossed' }[] {
    const total = Number(rec.max ?? 0) + Number(rec.extra ?? 0);
    const marked = Number(rec.marked ?? 0);
    const crossed: number[] = Array.isArray(rec.crossed) ? rec.crossed : [];
    const out: { mark: 'marked' | 'open' | 'crossed' }[] = [];
    let seen = 0;
    for (let i = 0; i < total; i++) {
      if (crossed.includes(i)) out.push({ mark: 'crossed' });
      else out.push({ mark: seen++ < marked ? 'marked' : 'open' });
    }
    return out;
  }

  function imageUrl(ref: string): string {
    return assetArt('tokens', ref).url || ui.picture(ref);
  }
</script>

{#if n == null || depth > 24}
  <p class="dim">{textOf(node)}</p>
{:else if visible}
  {#if type === 'column' || type === 'row'}
    <div class={type} style:gap={n.separation !== undefined ? `${n.separation}px` : undefined}>
      {#each (n.children as any[]) ?? [] as child}<View node={child} {ctx} depth={depth + 1} />{/each}
    </div>
  {:else if type === 'spacer'}
    <div style:height={`${Number(n.height ?? 8)}px`}></div>
  {:else if type === 'section'}
    <section class="section">
      <h3>{textOf(valueOf(n, ctx, 'title'))}</h3>
      {#each (n.children as any[]) ?? [] as child}<View node={child} {ctx} depth={depth + 1} />{/each}
    </section>
  {:else if type === 'tabs'}
    {@const tabs = ((n.tabs as Dict[]) ?? []).filter((t) => t && typeof t === 'object')}
    <div class="tabs">
      <div class="tabbar" role="tablist">
        {#each tabs as t, i}
          <button type="button" role="tab" aria-selected={tab === i} class:on={tab === i} onclick={() => (tab = i)}>{t.title ?? 'Tab'}</button>
        {/each}
      </div>
      {#if tabs[tab]}
        <div class="tabpage" role="tabpanel">
          {#each (tabs[tab].children as any[]) ?? [] as child}<View node={child} {ctx} depth={depth + 2} />{/each}
        </div>
      {/if}
    </div>
  {:else if type === 'text'}
    {@const s = textOf(valueOf(n, ctx, 'text'))}
    {#if n.rich}
      <div class="prose">{@html markdown(s)}</div>
    {:else if n.style === 'header'}
      <h4 class="header">{s}</h4>
    {:else}
      <p class:dim={n.style === 'dim'} class:mono={n.style === 'mono'}>{s}</p>
    {/if}
  {:else if type === 'number'}
    {@const v = valueOf(n, ctx)}
    <div class="stat">
      <span class="label">{n.label ?? ''}</span>
      <span class="value" title={breakdown(v)}>{textOf(v)}</span>
    </div>
  {:else if type === 'pool'}
    {@const rec = valueOf(n, ctx)}
    <div class="stat">
      <span class="label">{n.label ?? ''}</span>
      <span class="pool">
        {#if 'spend' in n}<button type="button" class="round" aria-label="Spend" onclick={() => send(n.spend)}>−</button>{/if}
        <span class="value">{rec && typeof rec === 'object' ? `${num(rec.current ?? 0)} / ${num(rec.max ?? 0)}` : '—'}</span>
        {#if 'gain' in n}<button type="button" class="round" aria-label="Gain" onclick={() => send(n.gain)}>+</button>{/if}
      </span>
    </div>
  {:else if type === 'track'}
    {@const rec = valueOf(n, ctx)}
    <div class="stat">
      <span class="label">{n.label ?? ''}</span>
      {#if rec && typeof rec === 'object'}
        <span class="boxes">
          {#each trackBoxes(rec) as b}
            {#if b.mark === 'crossed'}
              <span class="box crossed">✕</span>
            {:else}
              {@const key = b.mark === 'open' ? 'on_mark' : 'on_clear'}
              <button type="button" class="box" class:marked={b.mark === 'marked'} disabled={!(key in n)} aria-label={b.mark === 'open' ? 'Mark' : 'Clear'} onclick={() => send(n[key])}></button>
            {/if}
          {/each}
        </span>
      {:else}
        <span class="dim">—</span>
      {/if}
    </div>
  {:else if type === 'effects'}
    {@const list = items(valueOf(n, ctx)).filter((fx) => fx && typeof fx === 'object')}
    <div class="stat" class:bare={!n.label}>
      {#if n.label}<span class="label">{n.label}</span>{/if}
      <span class="badges">
        {#each list as fx}
          <span class="badge" title={String(fx.key ?? '')}>{fx.label ?? fx.key ?? '?'}{fx.value !== undefined && fx.value !== null ? ` ${num(fx.value)}` : ''}</span>
        {:else}
          <span class="dim">{n.empty ?? 'none'}</span>
        {/each}
      </span>
    </div>
  {:else if type === 'list'}
    {@const all = items(valueOf(n, ctx))}
    <div class="list">
      {#each all as item, index}
        <View node={n.item ?? { type: 'text', expr: 'str(@item)' }} ctx={{ ...ctx, item, index }} depth={depth + 1} />
      {/each}
      {#if all.length === 0 && n.empty}<p class="dim">{n.empty}</p>{/if}
    </div>
  {:else if type === 'cards'}
    {@const list = items(valueOf(n, ctx))}
    <div class="stat" class:bare={!n.label}>
      {#if n.label}<span class="label">{n.label}</span>{/if}
      <span class="cards">
        {#each list as card}
          {@const id = card && typeof card === 'object' ? String(card.id ?? '') : String(card)}
          <button type="button" class="card" title={card?.text ?? ''} disabled={!n.on_tap} onclick={() => send(n.on_tap, { ...ctx, card, card_id: id })}>
            {card && typeof card === 'object' ? (card.label ?? id) : id}
          </button>
        {:else}
          <span class="dim">{n.empty ?? 'no cards'}</span>
        {/each}
      </span>
    </div>
  {:else if type === 'button'}
    <button type="button" class:accent={n.accent} title={n.tooltip ?? ''} disabled={!enabled(n)} onclick={() => send(n.intent)}>{buttonLabel(n)}</button>
  {:else if type === 'action_bar'}
    <div class="actions">
      {#each ((n.actions as Dict[]) ?? []).filter((a) => a && typeof a === 'object' && shown(a, ctx)) as a}
        <button type="button" class:accent={a.accent} title={a.tooltip ?? ''} disabled={!enabled(a)} onclick={() => send(a.intent)}>{buttonLabel(a)}</button>
      {/each}
    </div>
  {:else if type === 'tracker'}
    {@const tr = valueOf(n, ctx)}
    {#if tr && typeof tr === 'object'}
      {@const mx = Number(tr.max ?? 0)}
      {@const filled = String(tr.direction ?? 'down') === 'up' ? Number(tr.value ?? 0) : mx - Number(tr.value ?? 0)}
      <div class="stat">
        <span class="label">{tr.name ?? ''}</span>
        <span class="boxes">
          {#each Array.from({ length: Math.max(0, mx) }) as _, i}<span class="box" class:marked={i < filled}></span>{/each}
          {#if tr.done}<span class="dim">{tr.on_done ?? 'done'}</span>{/if}
        </span>
      </div>
    {/if}
  {:else if type === 'prompt' || type === 'form'}
    {@const rec = type === 'prompt' ? valueOf(n, ctx) : null}
    {#if type === 'form' || (rec && typeof rec === 'object')}
      {@const f = type === 'prompt' ? prompted(rec) : n}
      <div class="form-box" class:prompt={type === 'prompt'}>
        {#if f.label}<h4>{f.label}</h4>{/if}
        <Form fields={formFields(f)} bind:values={formValues} />
        {#if f.choices && f.choices.length > 0}
          <div class="actions">
            {#each f.choices as c (String(c.id ?? c.label))}
              <button type="button" class="accent" disabled={chose === f.prompt} onclick={() => choose(f, c)}>{c.label ?? c.id}</button>
            {/each}
          </div>
        {:else}
          <div class="submit">
            <button type="button" class="accent" disabled={sending} onclick={() => submitForm(f)}>{f.submit_label ?? 'Submit'}</button>
            <span class="said" role="status">{said}</span>
          </div>
        {/if}
      </div>
    {/if}
  {:else if type === 'log'}
    {@const entries = items(valueOf(n, ctx)).filter((e) => e && typeof e === 'object')}
    <div class="log">
      {#each entries.slice(Math.max(0, entries.length - Number(n.limit ?? 12))) as entry (entry.id ?? JSON.stringify(entry))}
        <LogLine {entry} actors={ctx.actors} />
      {/each}
    </div>
  {:else if type === 'picker'}
    <Picker node={n} {ctx} />
  {:else if type === 'wizard'}
    <Wizard node={n} {ctx} />
  {:else if type === 'title'}
    {@const s = textOf(valueOf(n, ctx, 'text'))}
    {@const sub = prop(n, 'sub')}
    {@const iconRef = prop(n, 'icon')}
    {@const iconUrl = iconRef ? imageUrl(iconRef) : ''}
    <div class="titlebar">
      {#if iconUrl}<img class="icon" src={iconUrl} alt="" />{/if}
      <div class="titles">
        <h3 class="title">{s}</h3>
        {#if sub}<p class="sub">{sub}</p>{/if}
      </div>
    </div>
  {:else if type === 'facts'}
    <dl class="facts">
      {#each items(n.items) as it, i (i)}
        {#if it && typeof it === 'object' && shown(it, ctx)}
          {@const v = textOf(valueOf(it, ctx, 'text'))}
          {#if v !== ''}
            <div class="fact">
              <dt>{it.label ?? ''}</dt>
              <dd>{#if it.rich}<span class="prose">{@html markdown(v)}</span>{:else}{v}{/if}</dd>
            </div>
          {/if}
        {/if}
      {/each}
    </dl>
  {:else if type === 'tags'}
    <div class="tags">
      {#each items(n.items) as it, i (i)}
        {#if it && typeof it === 'object' && shown(it, ctx)}
          {@const v = textOf(valueOf(it, ctx, 'text'))}
          {#if v !== ''}<span class="tag" class:accent={it.tone === 'accent'}>{v}</span>{/if}
        {/if}
      {/each}
    </div>
  {:else if type === 'image'}
    {@const ref = textOf(valueOf(n, ctx, 'src'))}
    {@const url = ref ? imageUrl(ref) : ''}
    {#if url}
      <img class="image" src={url} alt="" style:height={`${Number(n.height ?? 96)}px`} />
    {:else}
      <p class="dim">{ref || '(no image)'}</p>
    {/if}
  {:else if type === 'field'}
    {@const field = withOptions({ key: 'value', label: String(n.label ?? ''), type: String(n.kind ?? 'string'), ...Object.fromEntries(['min', 'max', 'step', 'options', 'suffix', 'tooltip', 'fields', 'from'].filter((k) => k in n).map((k) => [k, n[k]])) }, ctx)}
    <div class="stat">
      <span class="label">{field.label}</span>
      <span class="control">
        <FieldInput {field} bind:value={fieldValue} commit={(v) => ui.intent(putValue(fillIntent(n.on_change ?? {}, ctx), v, '$value'))} />
      </span>
    </div>
  {:else}
    {@const v = valueOf(n, ctx)}
    <p class="dim">{type || '?'}: {v !== null && v !== undefined ? textOf(v) : JSON.stringify(n)}</p>
  {/if}
{/if}

<style>
  .column {
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-width: 0;
  }
  .row {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 12px;
    align-items: center;
    min-width: 0;
  }
  .row > :global(*) {
    flex: 1 1 auto;
    min-width: 0;
  }
  .section {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding-top: 6px;
  }
  .section > h3 {
    margin: 4px 0 0;
    font-family: var(--font-display);
    font-size: 1.05rem;
    font-weight: 600;
    letter-spacing: 0.01em;
    color: var(--heading);
    border-bottom: 1px solid var(--border);
    padding-bottom: 4px;
  }
  h4 {
    margin: 0;
    font-size: 1rem;
    font-weight: 650;
  }
  /* a sheet's or a card's name: the display face */
  .titlebar {
    display: flex;
    gap: 12px;
    align-items: center;
  }
  .titlebar .icon {
    width: 48px;
    height: 48px;
    flex: none;
    object-fit: contain;
    border-radius: 10px;
    background: var(--panel-2);
  }
  .titlebar .title {
    font-family: var(--font-display);
    font-size: 1.45rem;
    line-height: 1.15;
    margin: 0;
    color: var(--heading);
  }
  .titlebar .sub {
    margin: 2px 0 0;
    color: var(--accent);
    font-size: 0.92rem;
  }
  .facts {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 8px 16px;
    margin: 4px 0;
    padding: 10px 12px;
    border-radius: 12px;
    background: var(--panel-2);
    border: 1px solid var(--border-soft);
  }
  .fact dt {
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--muted);
  }
  .fact dd {
    margin: 2px 0 0;
  }
  .fact dd .prose :global(p) {
    margin: 0;
  }
  .tags {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
  }
  .tag {
    font-size: 0.78rem;
    font-weight: 650;
    padding: 2px 10px;
    border-radius: 999px;
    border: 1px solid var(--border);
    color: var(--muted);
  }
  .tag.accent {
    border-color: var(--accent);
    color: var(--accent);
  }
  .header {
    margin: 0;
    font-family: var(--font-display);
    font-size: 1.35rem;
    font-weight: 600;
    color: var(--heading);
    line-height: 1.2;
  }
  p {
    margin: 0;
    line-height: 1.45;
  }
  .mono {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.9em;
  }
  .stat {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    min-height: 32px;
  }
  .stat.bare {
    justify-content: flex-start;
  }
  .stat .label {
    color: var(--muted);
  }
  .stat .value {
    font-weight: 650;
    font-size: 1.05rem;
    font-variant-numeric: tabular-nums;
  }
  .stat .control {
    flex: 0 1 60%;
    min-width: 0;
  }
  .pool {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .round {
    width: 30px;
    height: 30px;
    padding: 0;
    border-radius: 999px;
  }
  .boxes {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    align-items: center;
  }
  .box {
    width: 20px;
    height: 20px;
    padding: 0;
    border-radius: 5px;
    border: 1.5px solid var(--muted);
    background: transparent;
    display: inline-grid;
    place-items: center;
    font-size: 12px;
    color: var(--muted);
  }
  .box.marked {
    background: var(--accent);
    border-color: var(--accent);
  }
  .box.crossed {
    opacity: 0.5;
  }
  .badges,
  .cards,
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .badge {
    padding: 3px 9px;
    border-radius: 999px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    font-size: 0.88em;
  }
  .card {
    min-width: 72px;
    min-height: 48px;
  }
  .list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  /* the tabs wrap onto a second row rather than scroll out of sight (on a
     playtest's phone "Features" showed as "Fe") */
  .tabbar {
    display: flex;
    flex-wrap: wrap;
    gap: 0 4px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 8px;
  }
  .tabbar button {
    border: 0;
    border-bottom: 2px solid transparent;
    border-radius: 0;
    background: none;
    padding: 8px 10px;
    color: var(--muted);
  }
  .tabbar button.on {
    color: var(--text);
    border-bottom-color: var(--accent);
  }
  .tabpage {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .form-box {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .form-box.prompt {
    padding: 12px;
    border-radius: 12px;
    border: 1px solid var(--accent-soft);
    background: var(--accent-bg);
  }
  .submit {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .said {
    color: var(--ok);
    font-weight: 600;
    font-size: 0.92rem;
  }
  .log {
    display: flex;
    flex-direction: column;
  }
  .image {
    width: 100%;
    object-fit: contain;
  }
</style>
