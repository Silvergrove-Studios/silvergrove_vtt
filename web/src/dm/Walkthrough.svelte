<!--
  The walkthrough for a campaign never set up (a new one, or an adventure
  just started): how this table runs, in five steps — where fights happen;
  how much the app does (four levels, three lines each on what the players
  will notice; Assisted offered first, for the DM to confirm or change);
  the table's questions, each with a line of its answer and a Change to
  open it; the rules options and the house rules; and a summary. Nothing
  changes until Done: then it is one change (the Table's undo has it), and
  the campaign is set up. The Table offers the same walkthrough.
-->
<script lang="ts">
  import Modal from '../common/Modal.svelte';
  import { game, notice, submit } from '../lib/game.svelte';
  import { draftFor, levelTitle, ownAnswers, questionLine, registryOf, valueWords, type Level, type Setting } from '../lib/tablesettings';

  let { onclose, ondone }: { onclose: () => void; ondone: (seeAll: boolean) => void } = $props();

  const reg = $derived(registryOf(game.dm));
  const STEPS = ['space', 'level', 'questions', 'rules', 'summary'] as const;
  const TITLES: Record<(typeof STEPS)[number], string> = {
    space: 'Where fights happen',
    level: 'How much the app does',
    questions: 'The table’s questions',
    rules: 'Rules options',
    summary: 'Your table',
  };
  let step = $state(0);
  const name = $derived(STEPS[step]);
  // the DM's answers: made once from the table as it came, nothing sent until Done
  let space = $state('maps');
  let level = $state<Level>('assisted');
  let values = $state<Record<string, unknown>>({});
  let house = $state('');
  let opened = $state('');
  let busy = $state(false);
  let started = false;
  $effect(() => {
    if (!reg || started) return;
    started = true;
    space = reg.spaces.some((s) => s.id === reg.space) ? reg.space : 'maps';
    house = reg.house_rules ?? '';
    level = reg.new_level ?? 'assisted';
    values = draftFor(reg, level);
  });

  const asked = $derived(reg ? reg.questions.filter((q) => q.level && q.settings.length) : []);
  const options = $derived(reg ? reg.questions.filter((q) => !q.level && q.settings.length) : []);
  const byId = $derived(new Map((reg?.settings ?? []).map((s) => [s.id, s])));

  function chooseLevel(l: Level): void {
    if (!reg) return;
    level = l;
    values = draftFor(reg, l, values);
  }

  function setValue(s: Setting, v: unknown): void {
    values = { ...values, [s.id]: v };
  }

  async function finish(seeAll: boolean): Promise<void> {
    if (!reg) return;
    busy = true;
    const r = await submit({ kind: 'dm', op: 'table_setup', level, space, house_rules: house, settings: ownAnswers(reg, level, values) });
    busy = false;
    if (!r.ok) return;
    notice(`The table is set up: ${levelTitle(reg, level)}`);
    ondone(seeAll);
  }
</script>

{#snippet control(s: Setting)}
  {@const v = values[s.id] ?? s.value}
  {#if Array.isArray(s.enum)}
    <select aria-label={s.title} value={JSON.stringify(v)} onchange={(e) => setValue(s, JSON.parse((e.currentTarget as HTMLSelectElement).value))}>
      {#each s.enum as c, i (JSON.stringify(c))}<option value={JSON.stringify(c)}>{(s.labels ?? [])[i] ?? String(c)}</option>{/each}
    </select>
  {:else if s.type === 'boolean'}
    <label class="switch"><input type="checkbox" aria-label={s.title} checked={v === true} onchange={(e) => setValue(s, (e.currentTarget as HTMLInputElement).checked)} /><span>{v === true ? 'On' : 'Off'}</span></label>
  {:else if s.type === 'string'}
    <input type="text" aria-label={s.title} value={String(v ?? '')} onchange={(e) => setValue(s, (e.currentTarget as HTMLInputElement).value)} />
  {:else}
    <input type="number" aria-label={s.title} min={s.minimum} max={s.maximum} step={s.type === 'integer' ? 1 : 'any'} value={Number(v ?? 0)} onchange={(e) => setValue(s, Number((e.currentTarget as HTMLInputElement).value))} />
  {/if}
{/snippet}

{#snippet row(s: Setting)}
  <li>
    <div class="what">
      <span>{s.title}</span>
      {#if s.description}<span class="dim small">{s.description}</span>{/if}
    </div>
    <div class="control">{@render control(s)}</div>
  </li>
{/snippet}

<Modal title="Set up this table" wide sticky {onclose}>
  {#if !reg}
    <p class="dim">Waiting for the table…</p>
  {:else}
    <p class="stepline"><span class="dim">Step {step + 1} of {STEPS.length} ·</span> <strong>{TITLES[name]}</strong></p>
    {#if name === 'space'}
      <p class="dim">Do your fights happen on maps with tokens, or in the theatre of the mind? The rolls work either way.</p>
      <div class="cards" role="radiogroup" aria-label="Where fights happen">
        {#each reg.spaces as s (s.id)}
          <button type="button" role="radio" aria-checked={space === s.id} class="card" class:on={space === s.id} onclick={() => (space = s.id)}>
            <span class="ctitle">{s.title}</span>
            <span class="dim">{s.words}</span>
          </button>
        {/each}
      </div>
    {:else if name === 'level'}
      <p class="dim">How much should the app do? You can change it, and any setting, at any time in Table settings.</p>
      <div class="cards levels" role="radiogroup" aria-label="How much the app does">
        {#each reg.levels as l (l.id)}
          <button type="button" role="radio" aria-checked={level === l.id} class="card" class:on={level === l.id} onclick={() => chooseLevel(l.id)}>
            <span class="ctitle">{l.title}</span>
            <span class="tagline">{l.tagline}</span>
            <ul>{#each l.lines as line (line)}<li>{line}</li>{/each}</ul>
          </button>
        {/each}
      </div>
    {:else if name === 'questions'}
      <p class="dim">What {levelTitle(reg, level)} answers to each of the table’s questions. Change any of them; the rest stay as the level has them.</p>
      {#each asked as q (q.id)}
        <section class="question" aria-label={q.title}>
          <div class="qhead">
            <div class="what">
              <h3>{q.title}</h3>
              <span class="line" title={questionLine(reg, q.id, values)}>{questionLine(reg, q.id, values)}</span>
            </div>
            <button type="button" class="quiet change" aria-expanded={opened === q.id} onclick={() => (opened = opened === q.id ? '' : q.id)}>{opened === q.id ? 'Done' : 'Change'}</button>
          </div>
          {#if opened === q.id}
            <ul class="settings">
              {#each q.settings as id (id)}
                {@const s = byId.get(id)}
                {#if s}{@render row(s)}{/if}
              {/each}
            </ul>
          {/if}
        </section>
      {:else}
        <p class="dim">The rules at this table ask nothing more.</p>
      {/each}
    {:else if name === 'rules'}
      <p class="dim">The rules you play by, whatever the level.</p>
      <ul class="settings">
        {#each options as q (q.id)}
          {#each q.settings as id (id)}
            {@const s = byId.get(id)}
            {#if s}{@render row(s)}{/if}
          {/each}
        {/each}
      </ul>
      <label class="house" for="wt-house">
        <span>House rules <span class="dim small">(optional): what your table does its own way. Players read them.</span></span>
        <textarea id="wt-house" rows="3" bind:value={house}></textarea>
      </label>
    {:else}
      {@const info = reg.levels.find((l) => l.id === level)}
      <p class="dim">Change any of this later in Table settings.</p>
      <dl class="summary" aria-label="Your table">
        <dt>Where fights happen</dt>
        <dd>{reg.spaces.find((s) => s.id === space)?.title}</dd>
        <dt>How much the app does</dt>
        <dd>
          <strong>{info?.title}</strong> — {info?.tagline}
          <ul>{#each info?.lines ?? [] as line (line)}<li>{line}</li>{/each}</ul>
        </dd>
        {#each [...asked, ...options] as q (q.id)}
          <dt>{q.title}</dt>
          <dd>
            {#each q.settings as id (id)}
              {@const s = byId.get(id)}
              {#if s}<span class="item">{s.title}: <strong>{valueWords(s, values[s.id] ?? s.value)}</strong></span>{/if}
            {/each}
          </dd>
        {/each}
        {#if house.trim()}
          <dt>House rules</dt>
          <dd class="pre">{house.trim()}</dd>
        {/if}
      </dl>
    {/if}
  {/if}
  {#snippet actions()}
    <button type="button" class="quiet notnow" onclick={onclose}>Not now</button>
    {#if step > 0}<button type="button" class="quiet" onclick={() => ((step -= 1), (opened = ''))}>Back</button>{/if}
    {#if name === 'summary'}
      <button type="button" disabled={busy || !reg} onclick={() => finish(true)}>See every setting</button>
      <button type="button" class="accent" disabled={busy || !reg} onclick={() => finish(false)}>Done</button>
    {:else}
      <button type="button" class="accent" disabled={!reg} onclick={() => ((step += 1), (opened = ''))}>Next</button>
    {/if}
  {/snippet}
</Modal>

<style>
  .stepline {
    margin: 0 0 6px;
  }
  .small {
    font-size: 0.85rem;
  }
  .cards {
    display: grid;
    gap: 10px;
    margin-top: 10px;
  }
  .cards.levels {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .card {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    text-align: left;
    padding: 12px 14px;
    border-radius: var(--radius);
    background: var(--panel-2);
    border: 1px solid var(--border);
  }
  .card.on {
    border-color: var(--accent);
    background: var(--accent-bg);
    box-shadow: 0 0 0 1px var(--accent) inset;
  }
  .ctitle {
    font-family: var(--font-display);
    font-size: 1.1rem;
    color: var(--heading);
  }
  .tagline {
    color: var(--accent);
    font-size: 0.9rem;
  }
  .card ul {
    margin: 4px 0 0;
    padding-left: 1.1em;
    font-size: 0.9rem;
  }
  .card li {
    margin: 2px 0;
  }
  .question {
    border-bottom: 1px solid var(--border-soft);
    padding: 10px 0;
  }
  .qhead {
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: space-between;
  }
  .what {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  h3 {
    font-size: 1.05rem;
  }
  /* one line, its whole text a hover away */
  .line {
    color: var(--muted);
    font-size: 0.88rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .change {
    flex: none;
    border: 1px solid var(--border);
  }
  .settings {
    list-style: none;
    margin: 6px 0 0;
    padding: 0;
  }
  .settings li {
    display: flex;
    gap: 16px;
    align-items: center;
    justify-content: space-between;
    padding: 8px 0;
    border-bottom: 1px solid var(--border-soft);
  }
  .control {
    flex: none;
  }
  select {
    max-width: 22em;
  }
  input[type='number'] {
    width: 6em;
  }
  .switch {
    display: inline-flex;
    gap: 8px;
    align-items: center;
  }
  .house {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 12px;
  }
  .summary {
    margin: 0;
    display: grid;
    grid-template-columns: minmax(10em, auto) 1fr;
    gap: 8px 16px;
  }
  .summary dt {
    color: var(--muted);
  }
  .summary dd {
    margin: 0;
  }
  .summary ul {
    margin: 4px 0 0;
    padding-left: 1.1em;
  }
  .item {
    display: block;
  }
  .pre {
    white-space: pre-wrap;
  }
  .notnow {
    margin-right: auto;
  }
  @media (max-width: 560px) {
    .cards.levels {
      grid-template-columns: 1fr;
    }
    .settings li {
      flex-direction: column;
      align-items: stretch;
      gap: 6px;
    }
    .summary {
      grid-template-columns: 1fr;
    }
  }
</style>
