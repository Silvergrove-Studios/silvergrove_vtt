<!--
  Table settings: how much the app does at this table (a level, and
  "Customized" once anything differs from it), and every ruleset setting
  sorted by the question it answers — a section back to the level with a
  press, a level switch that says what it will change before it does,
  settings that wait for the next fight marked, a search, and the house
  rules. Each change is kept as it's made (one step of the Table's undo;
  Undo here takes back the newest). The Table has the same window.
-->
<script lang="ts">
  import Modal from '../common/Modal.svelte';
  import { dmOp, game, notice, submit } from '../lib/game.svelte';
  import {
    badgeWords,
    changeWords,
    levelChanges,
    levelTitle,
    noticeWords,
    prefWhenWords,
    registryOf,
    sectionReset,
    sections,
    valueWords,
    type Level,
    type Pref,
    type Setting,
  } from '../lib/tablesettings';

  let { onclose }: { onclose: () => void } = $props();

  const reg = $derived(registryOf(game.dm));
  let search = $state('');
  // the level a press asked for: what it changes is shown before it does
  let asking = $state<Level | null>(null);
  const preview = $derived(reg && asking ? levelChanges(reg, asking) : []);
  const shown = $derived(reg ? sections(reg, search) : []);
  // the house rules as typed here, until kept (null: as the table has them)
  let house = $state<string | null>(null);
  let busy = $state(false);

  function ask(level: Level): void {
    if (!reg) return;
    asking = level === reg.level && reg.level_set && !reg.customized ? null : level;
  }

  async function dm(op: string, fields: Record<string, unknown>, said: string): Promise<boolean> {
    busy = true;
    const r = await submit({ kind: 'dm', op, ...fields });
    busy = false;
    if (r.ok && said) notice(said);
    return r.ok;
  }

  async function switchLevel(): Promise<void> {
    if (!asking) return;
    const to = asking;
    if (await dm('table_level', { level: to }, `This table runs at ${levelTitle(reg, to)} now`)) asking = null;
  }

  function set(s: Setting, value: unknown): void {
    dmOp('rules_setting', { plugin: s.plugin, key: s.key, value });
    notice(`${s.title}: ${valueWords(s, value)}`);
  }

  function nextFightWords(): string {
    return reg?.fight ? 'waits for the next fight' : 'takes effect at the next fight';
  }

  // the players' own choices: the preferences a search leaves (by their words or a player's name)
  const prefsShown = $derived.by(() => {
    const all = reg?.prefs ?? [];
    const words = search.toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return all;
    const names = (reg?.players ?? []).map((p) => p.name).join(' ');
    return all.filter((p) => words.every((w) => `${p.title} ${p.description} players preferences ${names}`.toLowerCase().includes(w)));
  });
  const offeredPrefs = $derived(prefsShown.filter((p) => p.offered));

  function setPref(player: string, name: string, p: Pref, value: unknown): void {
    dmOp('player_pref', { player, plugin: p.plugin, key: p.key, value });
    notice(`${name}: ${p.title}, ${valueWords(p, value)}`);
  }
</script>

<Modal title="Table settings" wide {onclose}>
  {#if !reg}
    <p class="dim">Open a campaign first: table settings are the campaign’s.</p>
  {:else}
    <!-- (there's no Save: a playtest's DM wondered whether a change had stuck) -->
    <p class="dim small lead">How much the app does at this table, and what it checks, asks and shows. Each change is kept as you make it; characters made after it follow it.</p>
    <div class="levelrow">
      <div class="levels" role="group" aria-label="Level">
        {#each reg.levels as l (l.id)}
          <button
            type="button"
            class="lv"
            class:on={asking ? asking === l.id : l.id === reg.level}
            aria-pressed={l.id === reg.level}
            title={`${l.title}: ${l.tagline}\n• ${l.lines.join('\n• ')}`}
            onclick={() => ask(l.id)}>{l.title}</button
          >
        {/each}
      </div>
      <span class="badge" class:custom={reg.customized} data-testid="level-badge">{badgeWords(reg)}</span>
    </div>
    {#if asking}
      <div class="preview" role="region" aria-label="What switching changes">
        <p><strong>Switch to {levelTitle(reg, asking)}?</strong> <span class="dim">{reg.levels.find((l) => l.id === asking)?.tagline}</span></p>
        {#if preview.length}
          <p class="count">{changeWords(preview).split(':')[0]}:</p>
          <ul class="changes">
            {#each preview as c (c.id)}
              <li>
                <span>{c.title}</span>
                <span class="fromto">{c.fromWords} → <strong>{c.toWords}</strong></span>
                {#if c.nextFight}<span class="tag">{nextFightWords()}</span>{/if}
              </li>
            {/each}
          </ul>
        {:else}
          <p class="count">{changeWords(preview)}</p>
        {/if}
        <div class="btns">
          <button type="button" class="accent" disabled={busy} onclick={switchLevel}>Switch to {levelTitle(reg, asking)}</button>
          <button type="button" class="quiet" onclick={() => (asking = null)}>Cancel</button>
        </div>
      </div>
    {/if}
    <div class="searchrow">
      <input type="search" placeholder="Search the settings" aria-label="Search the settings" bind:value={search} />
      {#if reg.undo}
        <button type="button" class="quiet" disabled={busy} title={`Take back: ${reg.undo}`} onclick={() => dm('table_undo', {}, `Taken back: ${reg?.undo}`)}>Undo: {reg.undo}</button>
      {/if}
    </div>
    {#each shown as sec (sec.question.id)}
      {@const rs = sectionReset(reg, sec)}
      <section aria-labelledby={`q-${sec.question.id}`}>
        <header>
          <div class="what">
            <h3 id={`q-${sec.question.id}`}>{sec.question.title}</h3>
            <span class="dim small">{sec.question.description}</span>
          </div>
          {#if rs.follows}
            <button
              type="button"
              class="quiet reset"
              disabled={!rs.differs || busy}
              title={rs.differs ? `This section’s settings as ${levelTitle(reg, reg.level)} has them` : `Already as ${levelTitle(reg, reg.level)} has it`}
              onclick={() => dm('table_reset', { question: sec.question.id }, `${sec.question.title}: as ${levelTitle(reg, reg.level)} has it`)}
              >Reset to {levelTitle(reg, reg.level)}</button
            >
          {/if}
        </header>
        <ul>
          {#if sec.question.id === 'space' && sec.own}
            <li>
              <div class="what"><span class="title">Fights are played</span><span class="dim small">{reg.spaces.find((s) => s.id === reg.space)?.words}</span></div>
              <div class="control">
                <select aria-label="Where fights happen" value={reg.space} onchange={(e) => dmOp('table_set', { space: (e.currentTarget as HTMLSelectElement).value })}>
                  {#each reg.spaces as s (s.id)}<option value={s.id}>{s.title}</option>{/each}
                </select>
              </div>
            </li>
          {/if}
          {#each sec.settings as s (s.id)}
            <li class:differs={s.differs}>
              <div class="what">
                <span class="title">{s.title}</span>
                {#if s.description}<span class="dim small">{s.description}</span>{/if}
                <span class="tags">
                  {#if s.next_fight}<span class="tag">{nextFightWords()}</span>{/if}
                  {#if s.notice}<span class="dim small">{noticeWords(s.notice)}</span>{/if}
                  {#if s.differs && s.level_value !== undefined}<span class="dim small">· {levelTitle(reg, reg.level)} has it {valueWords(s, s.level_value)}</span>{/if}
                  {#if reg.plugins.length > 1}<span class="dim small">· {s.plugin_name}</span>{/if}
                </span>
              </div>
              <div class="control">
                {#if Array.isArray(s.enum)}
                  <select aria-label={s.title} value={JSON.stringify(s.value)} onchange={(e) => set(s, JSON.parse((e.currentTarget as HTMLSelectElement).value))}>
                    {#each s.enum as v, i (JSON.stringify(v))}
                      <option value={JSON.stringify(v)}>{(s.labels ?? [])[i] ?? String(v)}</option>
                    {/each}
                  </select>
                {:else if s.type === 'boolean'}
                  <label class="switch">
                    <input type="checkbox" aria-label={s.title} checked={s.value === true} onchange={(e) => set(s, (e.currentTarget as HTMLInputElement).checked)} />
                    <span>{s.value === true ? 'On' : 'Off'}</span>
                  </label>
                {:else if s.type === 'string'}
                  <input type="text" aria-label={s.title} value={String(s.value ?? '')} onchange={(e) => set(s, (e.currentTarget as HTMLInputElement).value)} />
                {:else}
                  <input
                    type="number"
                    aria-label={s.title}
                    min={s.minimum}
                    max={s.maximum}
                    step={s.type === 'integer' ? 1 : 'any'}
                    value={Number(s.value ?? 0)}
                    onchange={(e) => set(s, Number((e.currentTarget as HTMLInputElement).value))}
                  />
                {/if}
              </div>
            </li>
          {/each}
          {#if sec.question.id === 'table' && sec.own}
            <li class="house">
              <label class="what" for="house-rules"><span class="title">House rules</span><span class="dim small">What your table does its own way, in your words. Players read them in How this table runs.</span></label>
              <textarea id="house-rules" rows="4" value={house ?? reg.house_rules} oninput={(e) => (house = (e.currentTarget as HTMLTextAreaElement).value)}></textarea>
              <div class="btns">
                <button
                  type="button"
                  disabled={house === null || house === reg.house_rules || busy}
                  onclick={async () => {
                    if (await dm('table_set', { house_rules: house ?? '' }, 'House rules kept')) house = null;
                  }}>Keep the house rules</button
                >
              </div>
            </li>
          {/if}
        </ul>
      </section>
    {:else}
      <p class="dim">No setting says “{search}”.</p>
    {/each}
    {#if prefsShown.length}
      <!-- what each player chose for themselves, where the table lets them: theirs from
           their ⋯ menu (My preferences), and yours to change -->
      <section aria-labelledby="q-prefs" data-testid="players-prefs">
        <header>
          <div class="what">
            <h3 id="q-prefs">Players’ preferences</h3>
            <span class="dim small">What each player chooses for themselves, where the table lets them: from their ⋯ menu (My preferences), and yours to change.</span>
          </div>
        </header>
        {#if !offeredPrefs.length}
          <p class="dim small">The players choose none of these at this table now.</p>
        {:else if !(reg.players ?? []).length}
          <p class="dim small">No player has joined yet.</p>
        {/if}
        <ul>
          {#each offeredPrefs.length ? (reg.players ?? []) : [] as pl (pl.id)}
            {#each offeredPrefs as p (p.id)}
              {@const v = pl.values?.[p.id] ?? p.default}
              <li>
                <div class="what">
                  <span class="title">{pl.name}: {p.title}</span>
                  <span class="dim small">{pl.own?.[p.id] ? 'Their choice' : 'As the table has it, until they choose'}</span>
                </div>
                <div class="control">
                  {#if Array.isArray(p.enum)}
                    <select aria-label={`${pl.name}: ${p.title}`} value={JSON.stringify(v)} onchange={(e) => setPref(pl.id, pl.name, p, JSON.parse((e.currentTarget as HTMLSelectElement).value))}>
                      {#each p.enum as c, i (JSON.stringify(c))}
                        <option value={JSON.stringify(c)}>{(p.labels ?? [])[i] ?? String(c)}</option>
                      {/each}
                    </select>
                  {:else if p.type === 'boolean'}
                    <label class="switch">
                      <input type="checkbox" aria-label={`${pl.name}: ${p.title}`} checked={v === true} onchange={(e) => setPref(pl.id, pl.name, p, (e.currentTarget as HTMLInputElement).checked)} />
                      <span>{v === true ? 'On' : 'Off'}</span>
                    </label>
                  {/if}
                </div>
              </li>
            {/each}
          {/each}
          {#each prefsShown.filter((p) => !p.offered) as p (p.id)}
            <li class="kept"><span class="dim small">{p.title}: not the players’ to choose now.{prefWhenWords(p) ? ` To let them: ${prefWhenWords(p)}.` : ''}</span></li>
          {/each}
        </ul>
      </section>
    {/if}
  {/if}
  {#snippet actions()}
    <button type="button" class="accent" onclick={onclose}>Done</button>
  {/snippet}
</Modal>

<style>
  .lead {
    margin: 0 0 12px;
  }
  .small {
    font-size: 0.85rem;
  }
  .levelrow {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 14px;
    align-items: center;
    margin-bottom: 12px;
  }
  .levels {
    display: inline-flex;
    flex-wrap: wrap;
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 3px;
    gap: 2px;
  }
  .lv {
    border: 0;
    border-radius: 999px;
    background: transparent;
    min-height: 32px;
    padding: 4px 14px;
  }
  .lv.on {
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 650;
  }
  .badge {
    font-size: 0.85rem;
    color: var(--muted);
  }
  .badge.custom {
    color: var(--accent);
    font-weight: 600;
  }
  .preview {
    border: 1px solid var(--accent-soft);
    background: var(--accent-bg);
    border-radius: var(--radius);
    padding: 10px 14px;
    margin-bottom: 12px;
  }
  .preview p {
    margin: 0 0 6px;
  }
  .count {
    font-weight: 600;
  }
  .changes {
    margin: 0 0 8px;
    padding-left: 1.1em;
  }
  .changes li {
    margin: 2px 0;
  }
  .fromto {
    margin-left: 6px;
    color: var(--muted);
  }
  .fromto strong {
    color: var(--text);
  }
  .tag {
    display: inline-block;
    font-size: 0.75rem;
    padding: 1px 8px;
    border-radius: 999px;
    border: 1px solid var(--accent-soft);
    color: var(--accent);
    margin-right: 6px;
  }
  .btns {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }
  .searchrow {
    display: flex;
    gap: 8px;
    align-items: center;
    margin-bottom: 8px;
  }
  .searchrow input {
    flex: 1;
    min-width: 0;
  }
  section {
    margin-top: 14px;
  }
  header {
    display: flex;
    gap: 12px;
    align-items: flex-start;
    justify-content: space-between;
    border-bottom: 1px solid var(--border);
    padding-bottom: 6px;
  }
  h3 {
    font-size: 1.1rem;
  }
  .reset {
    flex: none;
    border: 1px solid var(--border);
    font-size: 0.85rem;
    min-height: 30px;
    padding: 2px 10px;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }
  section > ul > li {
    display: flex;
    gap: 16px;
    align-items: center;
    justify-content: space-between;
    padding: 10px 0;
    border-bottom: 1px solid var(--border-soft);
  }
  li.differs .title::after {
    content: ' •';
    color: var(--accent);
  }
  li.house {
    flex-direction: column;
    align-items: stretch;
    gap: 6px;
  }
  .what {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .title {
    line-height: 1.35;
  }
  .tags {
    display: flex;
    flex-wrap: wrap;
    gap: 2px 6px;
    align-items: center;
  }
  .control {
    flex: none;
  }
  select {
    max-width: 24em;
  }
  input[type='number'] {
    width: 6em;
  }
  .switch {
    display: inline-flex;
    gap: 8px;
    align-items: center;
  }
  textarea {
    width: 100%;
  }
  @media (max-width: 560px) {
    section > ul > li {
      flex-direction: column;
      align-items: stretch;
      gap: 6px;
    }
  }
</style>
