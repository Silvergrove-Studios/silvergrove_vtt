<!--
  A player's screen, on a phone or a computer: nothing to install. Type
  your name (or tap it, if you have played here before) and you are in:
  the map through your characters' eyes, your character, the table, the
  talk and the dice, and your journal. What the DM shows you comes up over
  everything; a question for you comes up the same way.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import MapView from '../lib/map/MapView.svelte';
  import Chat from '../common/Chat.svelte';
  import Handout from '../common/Handout.svelte';
  import Lookup from '../common/Lookup.svelte';
  import Modal from '../common/Modal.svelte';
  import View from '../lib/views/View.svelte';
  import Character from './Character.svelte';
  import Journal from './Journal.svelte';
  import TablePane from './TablePane.svelte';
  import { comp, connect, game, handouts, intent, join, leave, myActors, notice, playerColors, rememberedName, request, type Dict } from '../lib/game.svelte';
  import { provideViewUi } from '../lib/views/context';
  import { pictureUrl } from '../lib/art';
  import { Grid } from '../lib/grid';
  import { pickTarget, pickWords, withTarget } from '../lib/map/pick';
  import { turnSummary } from '../lib/turns';

  type Tab = 'map' | 'character' | 'table' | 'chat' | 'journal';
  let tab = $state<Tab>('map');
  let name = $state(rememberedName());
  let wide = $state(false);
  let side = $state<Exclude<Tab, 'map'>>('character');
  let pick = $state<Dict | null>(null);
  let lookup = $state<{ collection: string; id: string } | null>(null);
  let lookingUp = $state(false);
  let showing = $state<Dict | null>(null);
  let asked = $state<string>('');
  let selected = $state('');
  let greeted = false;
  let primed = false;
  const seenHandouts = new Set<string>();
  const seenPrompts = new Set<string>();
  let seenChat = $state(0);

  provideViewUi({
    intent: (p) => {
      if (p?.kind === 'lookup') lookup = { collection: String(p.collection ?? ''), id: String(p.id ?? '') };
      else intent(p);
    },
    pick: (p) => {
      pick = p;
      if (!wide) tab = 'map';
    },
    comp,
    picture: pictureUrl,
  });

  const map = $derived(game.maps[String(game.scene.map ?? '')] ?? null);
  const turn = $derived(turnSummary(game.scene, game.me));
  const mine = $derived(myActors());
  const myTokens = $derived(((game.scene.tokens as Dict[]) ?? []).filter((t) => String(t.owner ?? '') === game.me));
  // what the map keeps in view: my token, or on the region the party's marker
  const followed = $derived(String(myTokens[0]?.id ?? ((game.scene.tokens as Dict[]) ?? []).find((t) => Array.isArray(t.tags) && t.tags.includes('party'))?.id ?? ''));
  const prompts = $derived(((game.view.prompts as Dict[]) ?? []).filter((p) => p && typeof p === 'object'));
  const promptIndex = $derived(prompts.findIndex((p) => String(p.id) === asked));
  const chatCount = $derived((((game.view.log as Dict[]) ?? []).filter((e) => e?.kind === 'chat' || e?.kind === 'roll')).length);

  // something the DM just showed: over everything (the ones there on joining are in the Journal)
  $effect(() => {
    const all = handouts();
    let newest: Dict | null = null;
    for (const h of all) {
      const id = String(h.id ?? h.ref ?? '');
      if (!seenHandouts.has(id)) {
        seenHandouts.add(id);
        if (primed) newest = h;
      }
    }
    if (game.view.actors) primed = true;
    if (newest) showing = newest;
  });

  // a question for me: at the front
  $effect(() => {
    for (const p of prompts) {
      const id = String(p.id ?? '');
      if (!seenPrompts.has(id)) {
        seenPrompts.add(id);
        asked = id;
      }
    }
  });

  // joined with no character: straight to where one is made
  $effect(() => {
    if (!greeted && game.view.actors) {
      greeted = true;
      if (mine.length === 0) {
        tab = 'character';
        side = 'character';
      }
    }
  });

  $effect(() => {
    if (tab === 'chat' || (wide && side === 'chat')) seenChat = chatCount;
  });

  // my turn: said, and felt on a phone
  let wasMine = false;
  $effect(() => {
    const mine = turn.mine && String(game.scene.turns?.mode ?? 'free') !== 'free';
    if (mine && !wasMine) {
      notice(turn.text);
      try {
        navigator.vibrate?.(180);
      } catch {
        /* not a phone */
      }
    }
    wasMine = mine;
  });

  onMount(() => {
    const mq = window.matchMedia('(min-width: 980px)');
    const fit = () => (wide = mq.matches);
    fit();
    mq.addEventListener('change', fit);
    void connect('player').then((ok) => {
      if (ok && name.trim()) join({ name: name.trim() });
    });
    return () => mq.removeEventListener('change', fit);
  });

  function joinAs(opts: { name?: string; player?: string }): void {
    if (opts.name !== undefined && !opts.name.trim()) {
      notice('Type your name first', 'error');
      return;
    }
    join(opts.name !== undefined ? { name: opts.name.trim() } : { player: opts.player });
  }

  function onTokenClick(t: Dict): void {
    if (pick) {
      resolvePick(t.pos ? { x: Number(t.pos[0]), y: Number(t.pos[1]) } : null);
      return;
    }
    selected = selected === t.id ? '' : String(t.id);
  }

  function onCellClick(_cell: unknown, at: { x: number; y: number }): void {
    if (pick) resolvePick(at);
    else selected = '';
  }

  function resolvePick(at: { x: number; y: number } | null): void {
    if (!pick || !at || !map) return;
    const target = pickTarget(new Grid(map.grid ?? {}), (game.scene.tokens as Dict[]) ?? [], pick, at, false);
    if (target === null) {
      notice('Nothing to pick there — try again, or Cancel', 'error');
      return;
    }
    intent(withTarget($state.snapshot(pick) as Dict, target, String(game.scene.id ?? '')));
    pick = null;
  }

  function onTokenDrop(t: Dict, pos: [number, number]): void {
    request({ t: 'token.set', scene: String(game.scene.id ?? ''), id: String(t.id), changes: { pos } });
  }

  const TABS: { key: Tab; label: string; icon: string }[] = [
    { key: 'map', label: 'Map', icon: 'M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3z M9 3v15 M15 6v15' },
    { key: 'character', label: 'Character', icon: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M4 21a8 8 0 0 1 16 0' },
    { key: 'table', label: 'Table', icon: 'M4 5h16v4H4z M4 11h16v8H4z M8 15h8' },
    { key: 'chat', label: 'Chat', icon: 'M4 5h16v11H9l-5 4z' },
    { key: 'journal', label: 'Journal', icon: 'M6 3h11a2 2 0 0 1 2 2v16H8a2 2 0 0 1-2-2z M6 19a2 2 0 0 1 2-2h11' },
  ];
</script>

{#if !game.joined}
  <main class="join">
    <div class="card">
      <p class="eyebrow">Hexmap</p>
      <h1>{game.table || 'A table'}</h1>
      {#if game.status === 'closed' && game.error && !game.config}
        <p class="error">{game.error}</p>
        <button type="button" class="accent" onclick={() => location.reload()}>Try again</button>
      {:else}
        <form onsubmit={(e) => { e.preventDefault(); joinAs({ name }); }}>
          <label for="name">Your name</label>
          <div class="line">
            <input id="name" type="text" autocomplete="nickname" placeholder="What the table calls you" bind:value={name} maxlength="40" />
            <button type="submit" class="accent" disabled={game.status !== 'open' || game.joining}>{game.joining ? 'Joining…' : 'Join'}</button>
          </div>
        </form>
        {#if game.players.length}
          <p class="dim small">Played here before? Tap your name.</p>
          <div class="names">
            {#each game.players as p (p.id)}
              <button type="button" class="chip" onclick={() => joinAs({ player: String(p.id) })}><span class="dot" style:background={String(p.color ?? '#999')}></span>{p.name}</button>
            {/each}
          </div>
        {/if}
        {#if game.error}<p class="error">{game.error}</p>{/if}
        {#if game.status !== 'open'}<p class="dim small">{game.status === 'closed' ? 'Lost the table — trying again…' : 'Finding the table…'}</p>{/if}
      {/if}
    </div>
  </main>
{:else}
  <main class="play" class:wide>
    <header class="bar">
      <div class="where">
        <span class="table">{game.table}</span>
        <span class="turn" class:mine={turn.mine}>{turn.text}</span>
      </div>
      <div class="me">
        {#if game.status !== 'open'}<span class="chip warn">Reconnecting…</span>{/if}
        <button type="button" class="quiet" onclick={() => (lookingUp = true)} aria-label="Look something up">Look up</button>
        <button type="button" class="quiet" onclick={() => { if (confirm('Leave the table? You can come back with your name.')) leave(); }}>Leave</button>
      </div>
    </header>

    <div class="body">
      <section class="mapwrap" class:hidden={!wide && tab !== 'map'}>
        <MapView
          {map}
          scene={game.scene}
          playerColors={playerColors()}
          {selected}
          activeToken={''}
          picking={pick ? pickWords(pick) : ''}
          centerOn={followed}
          follow={followed}
          canDrag={(t) => String(t.owner ?? '') === game.me}
          {onTokenClick}
          {onCellClick}
          {onTokenDrop}
          onCancelPick={() => (pick = null)}
        />
      </section>
      {#if wide}
        <aside class="side">
          <div class="sidetabs" role="tablist">
            {#each TABS.filter((t) => t.key !== 'map') as t (t.key)}
              <button type="button" role="tab" aria-selected={side === t.key} class:on={side === t.key} onclick={() => (side = t.key as typeof side)}>
                {t.label}{#if t.key === 'chat' && chatCount > seenChat}<span class="badge">{chatCount - seenChat}</span>{/if}{#if t.key === 'table' && prompts.length}<span class="badge">{prompts.length}</span>{/if}
              </button>
            {/each}
          </div>
          <div class="sidebody">
            {#if side === 'character'}<Character />{:else if side === 'table'}<TablePane />{:else if side === 'chat'}<Chat />{:else}<Journal />{/if}
          </div>
        </aside>
      {:else if tab !== 'map'}
        <section class="page">
          {#if tab === 'character'}<Character />{:else if tab === 'table'}<TablePane />{:else if tab === 'chat'}<Chat />{:else}<Journal />{/if}
        </section>
      {/if}
    </div>

    {#if !wide}
      <div class="tabs" role="tablist">
        {#each TABS as t (t.key)}
          <button type="button" role="tab" aria-selected={tab === t.key} class:on={tab === t.key} onclick={() => (tab = t.key)}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d={t.icon} /></svg>
            <span>{t.label}</span>
            {#if t.key === 'chat' && chatCount > seenChat}<span class="badge">{chatCount - seenChat}</span>{/if}
            {#if t.key === 'table' && prompts.length}<span class="badge">{prompts.length}</span>{/if}
          </button>
        {/each}
      </div>
    {/if}
  </main>

  {#if showing}
    <Handout handout={showing} onclose={() => (showing = null)} />
  {:else if promptIndex >= 0}
    <Modal title="The DM asks" onclose={() => (asked = '')}>
      <View node={{ type: 'prompt', bind: `/prompts/${promptIndex}` }} ctx={game.view} />
    </Modal>
  {/if}
  {#if lookup || lookingUp}
    <Lookup at={lookup} onclose={() => { lookup = null; lookingUp = false; }} />
  {/if}
{/if}

<style>
  .join {
    min-height: 100%;
    display: grid;
    place-items: center;
    padding: 24px 16px;
    background:
      radial-gradient(1200px 600px at 50% -10%, rgba(229, 165, 90, 0.14), transparent 60%),
      var(--bg);
  }
  .join .card {
    width: min(460px, 100%);
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .eyebrow {
    margin: 0;
    color: var(--accent);
    letter-spacing: 0.18em;
    text-transform: uppercase;
    font-size: 0.8rem;
    font-weight: 650;
  }
  .join h1 {
    font-size: clamp(2rem, 7vw, 2.8rem);
    line-height: 1.1;
  }
  .join form {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 10px;
  }
  .join label {
    color: var(--muted);
  }
  .line {
    display: flex;
    gap: 8px;
  }
  .line input {
    flex: 1;
    min-width: 0;
    min-height: 46px;
    font-size: 17px;
  }
  .line button {
    min-height: 46px;
    padding: 0 22px;
  }
  .names {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .names .chip {
    min-height: 38px;
    padding: 6px 14px;
    font-size: 0.95rem;
    cursor: pointer;
  }
  .small {
    font-size: 0.9rem;
    margin: 4px 0 0;
  }
  .error {
    color: #ffb4a8;
  }

  .play {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: calc(8px + env(safe-area-inset-top)) 12px 8px;
    background: var(--panel);
    border-bottom: 1px solid var(--border);
  }
  .where {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .table {
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 1.05rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .turn {
    font-size: 0.85rem;
    color: var(--muted);
  }
  .turn.mine {
    color: var(--accent);
    font-weight: 650;
  }
  .me {
    display: flex;
    align-items: center;
    gap: 2px;
  }
  .chip.warn {
    border-color: rgba(227, 107, 91, 0.6);
  }
  .body {
    flex: 1;
    min-height: 0;
    display: flex;
    position: relative;
  }
  .mapwrap {
    flex: 1;
    min-width: 0;
    position: relative;
  }
  .mapwrap.hidden {
    position: absolute;
    inset: 0;
    visibility: hidden;
  }
  .page {
    flex: 1;
    min-width: 0;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .page > :global(*) {
    flex: 1;
    min-height: 0;
  }
  .side {
    width: 420px;
    display: flex;
    flex-direction: column;
    border-left: 1px solid var(--border);
    background: var(--bg);
  }
  .sidetabs {
    display: flex;
    gap: 2px;
    padding: 6px 8px 0;
    border-bottom: 1px solid var(--border);
    background: var(--panel);
  }
  .sidetabs button {
    border: 0;
    border-bottom: 2px solid transparent;
    border-radius: 0;
    background: none;
    color: var(--muted);
    padding: 8px 12px;
  }
  .sidetabs button.on {
    color: var(--text);
    border-bottom-color: var(--accent);
  }
  .sidebody {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .sidebody > :global(*) {
    flex: 1;
    min-height: 0;
  }
  .tabs {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    background: var(--panel);
    border-top: 1px solid var(--border);
    padding-bottom: env(safe-area-inset-bottom);
  }
  .tabs button {
    position: relative;
    border: 0;
    border-radius: 0;
    background: none;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 8px 2px 6px;
    min-height: 56px;
    color: var(--muted);
    font-size: 0.72rem;
  }
  .tabs button.on {
    color: var(--accent);
  }
  .tabs svg {
    width: 22px;
    height: 22px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.7;
    stroke-linejoin: round;
    stroke-linecap: round;
  }
  .badge {
    min-width: 18px;
    height: 18px;
    padding: 0 5px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-size: 0.7rem;
    font-weight: 700;
    display: inline-grid;
    place-items: center;
    margin-left: 6px;
  }
  .tabs .badge {
    position: absolute;
    top: 4px;
    left: calc(50% + 6px);
    margin: 0;
  }
</style>
