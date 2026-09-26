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
  import { chatLog, comp, connect, game, handouts, intent, join, leave, myActors, notice, playerColors, rememberedName, request, sessionPlayer, submit, type Dict } from '../lib/game.svelte';
  import { chatIds, loadRead, saveRead, startFrom, unreadAfter } from '../lib/unread';
  import { provideViewUi } from '../lib/views/context';
  import { pictureUrl } from '../lib/art';
  import { Grid } from '../lib/grid';
  import { pickCount, pickTarget, pickWords, togglePicked, withTarget } from '../lib/map/pick';
  import { turnSummary } from '../lib/turns';

  type Tab = 'map' | 'character' | 'table' | 'chat' | 'journal';
  const TAB_KEYS: Tab[] = ['map', 'character', 'table', 'chat', 'journal'];
  // the tab a reload comes back to (a phone may drop the page while it is in another app)
  function savedTab(): Tab | null {
    try {
      const t = sessionStorage.getItem('hexmap.tab') as Tab | null;
      return t && TAB_KEYS.includes(t) ? t : null;
    } catch {
      return null;
    }
  }
  let tab = $state<Tab>(savedTab() ?? 'map');
  let name = $state(rememberedName());
  let wide = $state(false);
  let side = $state<Exclude<Tab, 'map'>>(((t) => (t && t !== 'map' ? t : 'character'))(savedTab()));
  $effect(() => {
    try {
      sessionStorage.setItem('hexmap.tab', wide ? side : tab);
    } catch {
      /* private mode */
    }
  });
  let pick = $state<Dict | null>(null);
  // the creatures tapped so far, for a pick of several (Bless: up to three)
  let picked = $state<string[]>([]);
  // on a touch screen a tap on a creature asks before it acts: in a playtest a
  // phone's double tap to zoom fired an attack
  const coarse = typeof matchMedia === 'function' && matchMedia('(pointer: coarse)').matches;
  let confirmPick = $state<{ target: string | Dict; words: string } | null>(null);
  // none of a playtest's four players knew they could drag their own token: a
  // tip, until they have (or say they've got it)
  let dragTipDone = $state(false);
  try {
    dragTipDone = localStorage.getItem('hexmap.tip.drag') === '1';
  } catch {
    /* private mode */
  }
  const dragTip = $derived(!dragTipDone && ((game.scene.tokens as Dict[]) ?? []).some((t) => String(t.owner ?? '') === game.me && game.me !== ''));
  function dragTipSeen(): void {
    dragTipDone = true;
    try {
      localStorage.setItem('hexmap.tip.drag', '1');
    } catch {
      /* private mode */
    }
  }
  let lookup = $state<{ collection: string; id: string } | null>(null);
  let lookingUp = $state(false);
  let showing = $state<Dict | null>(null);
  // something new from the DM while you type or are in a dialog of your own waits
  // for you, behind a pill (a playtest's player lost a half-placed portrait to one,
  // another a journal note's thread)
  let waitingHandout = $state<Dict | null>(null);
  // when this screen was last pressed (a tap, a click)
  let pressedAt = -Infinity;
  function busyHere(): boolean {
    const el = document.activeElement as HTMLElement | null;
    const typing = !!el && (el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && !['checkbox', 'radio', 'button', 'range', 'file', 'submit'].includes((el as HTMLInputElement).type)));
    // (a message written but not yet sent counts too: playtest players' Send
    // clicks landed on a card that came up between typing and sending)
    const draft = (document.querySelector('[aria-label="Message"]') as HTMLTextAreaElement | HTMLInputElement | null)?.value?.trim() ?? '';
    // (and a press just made: a card that came up as a click was on its way
    // took the click and closed unseen)
    const pressing = performance.now() - pressedAt < 800;
    return typing || draft !== '' || pressing || document.querySelector('[role="dialog"][aria-modal="true"]') !== null;
  }
  let asked = $state<string>('');
  let selected = $state('');
  let greeted = false;
  let primed = false;
  const seenHandouts = new Set<string>();
  const seenPrompts = new Set<string>();

  provideViewUi({
    intent: (p) => {
      if (p?.kind === 'lookup') lookup = { collection: String(p.collection ?? ''), id: String(p.id ?? '') };
      else intent(p);
    },
    submit,
    pick: (p) => {
      pick = p;
      picked = [];
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
  // what of the chat is new to me: the lines after the last one read, which
  // this browser keeps (a reload counted the whole log as new: a playtest's
  // badge said 279)
  const chatLines = $derived(chatIds(chatLog()));
  let lastRead = $state<string | null>(null); // (null till the first view)
  const unread = $derived(lastRead === null ? 0 : unreadAfter(chatLines, lastRead));
  const chatShown = $derived(wide ? side === 'chat' : tab === 'chat');

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
    if (newest) {
      if (!showing && busyHere()) waitingHandout = newest;
      else showing = newest;
    }
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
    if (lastRead === null && 'log' in game.view) lastRead = startFrom(chatLines, loadRead(game.table, game.me));
  });
  $effect(() => {
    const newest = chatLines[chatLines.length - 1] ?? '';
    if (lastRead !== null && chatShown && newest !== '' && newest !== lastRead) lastRead = newest;
  });
  $effect(() => {
    if (lastRead && game.me) saveRead(game.table, game.me, lastRead);
  });

  // my turn: said, and felt on a phone
  let wasMine = false;
  $effect(() => {
    const mine = turn.mine && String(game.scene.turns?.mode ?? 'free') !== 'free';
    if (mine && !wasMine) {
      notice(turn.text);
      try {
        // (only once the page has been touched: before that the browser refuses, and says so)
        if ((navigator as Navigator & { userActivation?: { hasBeenActive: boolean } }).userActivation?.hasBeenActive !== false) navigator.vibrate?.(180);
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
    const press = () => (pressedAt = performance.now());
    window.addEventListener('pointerdown', press, true);
    void connect('player').then((ok) => {
      // this tab's player after a reload, else the name this browser remembers
      const again = sessionPlayer();
      if (ok && again) join({ player: again, name: name.trim() });
      else if (ok && name.trim()) join({ name: name.trim() });
    });
    return () => {
      mq.removeEventListener('change', fit);
      window.removeEventListener('pointerdown', press, true);
    };
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
    if (pickCount(pick) > 1 && typeof target === 'string') {
      picked = togglePicked(picked, target, pickCount(pick));
      return;
    }
    if (coarse) {
      confirmPick = { target, words: `${String(pick.label ?? 'This')} → ${targetName(target)}` };
      return;
    }
    sendPick(target);
  }

  function sendPick(target: string | Dict | string[]): void {
    if (!pick) return;
    intent(withTarget($state.snapshot(pick) as Dict, target, String(game.scene.id ?? '')));
    pick = null;
    picked = [];
    confirmPick = null;
  }

  function targetName(target: string | Dict): string {
    if (typeof target !== 'string') return 'that space';
    const id = target.replace(/^token:/, '');
    const t = ((game.scene.tokens as Dict[]) ?? []).find((x) => String(x.id) === id);
    const actor = t?.actor ? (game.view.actors as Dict)?.[String(t.actor)] : null;
    return String(t?.name || (actor as Dict | null)?.name || 'that creature');
  }

  function onTokenDrop(t: Dict, pos: [number, number]): void {
    dragTipSeen();
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
        <!-- (its name is what it says: three playtest players looked for "Look up" and didn't find it) -->
        <button type="button" class="quiet" onclick={() => (lookingUp = true)} title="Look up a spell, a creature, an item or a rule">Look up</button>
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
          onCancelPick={() => ((pick = null), (picked = []), (confirmPick = null))}
        />
        {#if dragTip && !pick}
          <div class="drag-tip" role="status">
            <span>Your token is yours to move: drag it on the map.</span>
            <button type="button" class="quiet" onclick={dragTipSeen}>Got it</button>
          </div>
        {/if}
        {#if game.scene.fog && !confirmPick && !(pick && pickCount(pick) > 1)}
          <!-- (a playtest's players all took the dark for a broken map, the
               enemies it hid for missing ones) -->
          <p class="sight-note">The dark is out of your character's sight: walls, trees and distance hide what's there.</p>
        {/if}
        {#if pick && pickCount(pick) > 1}
          <div class="confirm-pick" role="dialog" aria-label="Choose the targets">
            <span>{String(pick.label ?? 'Cast')} → {picked.length ? picked.map(targetName).join(', ') : 'tap each one'} ({picked.length} of up to {pickCount(pick)})</span>
            <button type="button" class="quiet" onclick={() => ((pick = null), (picked = []))}>Cancel</button>
            <button type="button" class="accent" disabled={!picked.length} onclick={() => sendPick([...picked])}>Done</button>
          </div>
        {/if}
        {#if confirmPick}
          <div class="confirm-pick" role="dialog" aria-label="Confirm the target">
            <span>{confirmPick.words}</span>
            <button type="button" class="quiet" onclick={() => (confirmPick = null)}>Choose again</button>
            <button type="button" class="accent" onclick={() => confirmPick && sendPick(confirmPick.target)}>Do it</button>
          </div>
        {/if}
      </section>
      {#if wide}
        <aside class="side">
          <div class="sidetabs" role="tablist">
            {#each TABS.filter((t) => t.key !== 'map') as t (t.key)}
              <button type="button" role="tab" aria-selected={side === t.key} class:on={side === t.key} onclick={() => (side = t.key as typeof side)}>
                {t.label}{#if t.key === 'chat' && !chatShown && unread > 0}<span class="badge">{unread}</span>{/if}{#if t.key === 'table' && prompts.length}<span class="badge">{prompts.length}</span>{/if}
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
            {#if t.key === 'chat' && !chatShown && unread > 0}<span class="badge">{unread}</span>{/if}
            {#if t.key === 'table' && prompts.length}<span class="badge">{prompts.length}</span>{/if}
          </button>
        {/each}
      </div>
    {/if}
  </main>

  <!-- a question still waiting, whatever tab is open (three of a playtest's players
       missed the DM's roll request once its pop-up was closed) -->
  {#if waitingHandout && !showing}
    <!-- (what a press does, with an eye: "…something: look" didn't read as a button to a playtest's player) -->
    <button type="button" class="accent waiting look" onclick={() => ((showing = waitingHandout), (waitingHandout = null))}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z" /></svg>
      See what the DM is showing ›
    </button>
  {:else if prompts.length && promptIndex < 0 && !showing}
    <!-- (the newest first: a playtest's player was sent to an old question left open, not the live one) -->
    <button type="button" class="accent waiting" onclick={() => (asked = String(prompts[prompts.length - 1].id ?? ''))}>
      The DM is waiting for you{prompts.length > 1 ? ` (${prompts.length})` : ''}: answer
    </button>
  {/if}
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
  .waiting {
    position: fixed;
    left: 50%;
    top: calc(10px + env(safe-area-inset-top));
    transform: translateX(-50%);
    z-index: 40;
    border-radius: 999px;
    box-shadow: var(--shadow);
    max-width: calc(100% - 24px);
  }
  .waiting.look {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    white-space: nowrap;
  }
  .waiting.look svg {
    flex: none;
    width: 20px;
    height: 20px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linejoin: round;
    stroke-linecap: round;
  }
  .drag-tip {
    position: absolute;
    left: 50%;
    top: 12px;
    transform: translateX(-50%);
    z-index: 5;
    display: flex;
    gap: 8px;
    align-items: center;
    max-width: calc(100% - 24px);
    padding: 6px 6px 6px 12px;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 999px;
    box-shadow: var(--shadow);
    font-size: 0.9rem;
  }
  .sight-note {
    position: absolute;
    left: 12px;
    bottom: 12px;
    z-index: 4;
    margin: 0;
    max-width: calc(100% - 110px);
    padding: 4px 10px;
    border-radius: 12px;
    background: color-mix(in srgb, var(--panel) 82%, transparent);
    color: var(--muted);
    font-size: 0.8rem;
    line-height: 1.3;
    pointer-events: none;
  }
  .confirm-pick {
    position: absolute;
    left: 12px;
    right: 12px;
    bottom: 12px;
    z-index: 6;
    display: flex;
    gap: 8px;
    align-items: center;
    padding: 10px 12px;
    background: var(--panel);
    border: 1px solid var(--accent-soft);
    border-radius: 12px;
    box-shadow: var(--shadow);
  }
  .confirm-pick span {
    flex: 1;
    min-width: 0;
    font-weight: 600;
  }
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
