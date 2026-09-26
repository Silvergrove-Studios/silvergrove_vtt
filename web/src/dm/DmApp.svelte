<!--
  The DM's screen, in a browser window on the computer that runs the
  table. Three places and no modes: the book on the left (everything in
  the campaign, and the rules), the map the players see in the middle
  (a card opens over it), the party and the talk on the right. A fight
  adds a bar over the map and its order beside it. Nothing here the
  players see until the DM shows it.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import MapView from '../lib/map/MapView.svelte';
  import View from '../lib/views/View.svelte';
  import Chat from '../common/Chat.svelte';
  import Book from './Book.svelte';
  import Card from './Card.svelte';
  import Invite from './Invite.svelte';
  import Modal from '../common/Modal.svelte';
  import RulesSettings from './RulesSettings.svelte';
  import FightBar from './FightBar.svelte';
  import FightPanel from './FightPanel.svelte';
  import { comp, connect, dmOp, game, intent, join, notice, playerColors, request, type Dict } from '../lib/game.svelte';
  import { provideViewUi } from '../lib/views/context';
  import { pictureUrl } from '../lib/art';
  import { Grid } from '../lib/grid';
  import { pickCount, pickTarget, pickWords, togglePicked, withTarget } from '../lib/map/pick';
  import { liveFight } from './fight';
  import { currentTurnTokens } from '../lib/turns';

  const token = new URLSearchParams(location.hash.slice(1)).get('t') ?? '';
  let card = $state('');
  let history = $state<string[]>([]);
  let side = $state<'party' | 'chat' | 'fight'>('party');
  let inviting = $state(false);
  let rulesOpen = $state(false);
  let bookOpen = $state(false);
  let selected = $state('');
  let pick = $state<Dict | null>(null);
  // the creatures tapped so far, for a pick of several (Bless: up to three)
  let picked = $state<string[]>([]);
  let mapsMenu = $state(false);
  let guideGone = $state('');
  let seenChat = $state(0);
  let wasLive = false;

  provideViewUi({
    intent: (p) => {
      if (p?.kind === 'lookup') open(`entry:${p.collection}/${p.id}`);
      else if (p?.kind === 'show' && p.actor) open(`actor:${p.actor}`);
      else intent(p);
    },
    pick: (p) => {
      pick = p;
      picked = [];
    },
    comp,
    picture: pictureUrl,
  });

  const dm = $derived(game.dm);
  const fight = $derived(liveFight(dm));
  const map = $derived(game.maps[String(game.scene.map ?? '')] ?? null);
  const sceneName = $derived(String(game.scene.name ?? '') || String(((dm.maps as Dict[]) ?? []).find((m) => m.id === game.scene.map)?.name ?? ''));
  const online = $derived(new Set(game.online.map(String)));
  const session = $derived((dm.session ?? {}) as Dict);
  const chatCount = $derived((((game.view.log as Dict[]) ?? []).filter((e) => e?.kind === 'chat' || e?.kind === 'roll')).length);
  const activeToken = $derived(currentTurnTokens((game.scene.turns ?? {}) as Dict, (game.scene.tokens as Dict[]) ?? [])[0] ?? '');
  // the fight panel follows the turn to a creature the DM runs (a playtest's DM
  // kept seeing the last creature tapped, not the one whose turn it was)
  let followedTurn = '';
  $effect(() => {
    const at = activeToken;
    if (!fight || !at || at === followedTurn) return;
    followedTurn = at;
    const t = ((game.scene.tokens as Dict[]) ?? []).find((x) => String(x.id) === at);
    if (t && !t.owner) selected = at;
  });
  const people = $derived((dm.people as Dict[]) ?? []);
  // what the rules ask the DM (a monster's opportunity attack): answered here, first come
  const prompts = $derived(((game.view.prompts as Dict[]) ?? []).map((p, i) => ({ p, i })).filter(({ p }) => p && String(p.to ?? 'gm') === 'gm'));
  let putOff = $state<string[]>([]);
  const asking = $derived(prompts.find(({ p }) => !putOff.includes(String(p.id))));

  // a fight that starts brings its order beside the map; one that ends puts the party back
  $effect(() => {
    const live = !!fight;
    if (live && !wasLive) {
      side = 'fight';
      // the fight's card gives way to its map
      card = '';
      history = [];
    }
    if (!live && wasLive && side === 'fight') side = 'party';
    wasLive = live;
  });

  $effect(() => {
    if (side === 'chat') seenChat = chatCount;
  });

  const guide = $derived.by((): { key: string; text: string; button?: string; act?: () => void } | null => {
    if (!dm.campaign || fight) return null;
    if (game.players.every((p) => !online.has(String(p.id))))
      return { key: 'invite', text: 'Invite your players: they scan a code with their phone, or open an address. Nothing to install.', button: 'Invite players', act: () => (inviting = true) };
    if (!session.open) return { key: 'session', text: 'Start the session when everyone is here: what happens is kept as the session’s.', button: `Start session ${Number(session.n ?? 0) + 1}`, act: () => dmOp('session', { do: 'start' }) };
    const withoutCharacter = game.players.filter((p) => online.has(String(p.id)) && !people.some((a) => a.kind === 'pc' && String(a.owner ?? '') === String(p.id)));
    if (withoutCharacter.length)
      return { key: `chars:${withoutCharacter.map((p) => p.id).join(',')}`, text: `${withoutCharacter.map((p) => p.name).join(' and ')} ${withoutCharacter.length > 1 ? 'are' : 'is'} making a character on their own screen. Meanwhile, read what the adventure says first.`, button: startHere() ? `Open “${startTitle()}”` : undefined, act: () => open(startHere()) };
    return { key: 'play', text: 'Tap a place on the map to open its card; “Show the players” puts its picture and words on their screens.', button: startHere() ? `Open “${startTitle()}”` : undefined, act: () => open(startHere()) };
  });

  // the note the adventure says to read first (tagged "start"), whatever its title
  function startNote(): Dict | undefined {
    return ((dm.journal as Dict[]) ?? []).find((j) => ((j.tags as string[]) ?? []).includes('start'));
  }

  function startHere(): string {
    const n = startNote();
    return n ? `note:${n.id}` : '';
  }

  function startTitle(): string {
    return String(startNote()?.title || 'Start here');
  }

  function open(ref: string): void {
    if (!ref) return;
    if (card && card !== ref) history.push(card);
    card = ref;
    bookOpen = false;
  }

  function back(): void {
    card = history.pop() ?? '';
  }

  function popout(): void {
    window.open(`/dm/card#t=${encodeURIComponent(token)}&ref=${encodeURIComponent(card)}`, `card-${card}`, 'width=720,height=900');
  }

  function onTokenClick(t: Dict): void {
    if (pick) {
      resolvePick({ x: Number(t.pos?.[0] ?? 0), y: Number(t.pos?.[1] ?? 0) });
      return;
    }
    const tags: string[] = Array.isArray(t.tags) ? t.tags : [];
    if (tags.includes('place')) {
      open(`place:${t.id}`);
      return;
    }
    selected = String(t.id);
    if (fight) side = 'fight';
    else if (t.actor) open(`actor:${t.actor}`);
  }

  function onCellClick(_c: unknown, at: { x: number; y: number }): void {
    if (pick) resolvePick(at);
    else selected = '';
  }

  function resolvePick(at: { x: number; y: number }): void {
    if (!pick || !map) return;
    const target = pickTarget(new Grid(map.grid ?? {}), (game.scene.tokens as Dict[]) ?? [], pick, at, true);
    if (target === null) {
      notice('Nothing to pick there — try again, or Cancel', 'error');
      return;
    }
    if (pickCount(pick) > 1 && typeof target === 'string') {
      picked = togglePicked(picked, target, pickCount(pick));
      return;
    }
    sendPick(target);
  }

  function sendPick(target: string | Dict | string[]): void {
    if (!pick) return;
    intent(withTarget($state.snapshot(pick) as Dict, target, String(game.scene.id ?? '')));
    pick = null;
    picked = [];
  }

  function pickedName(ref: string): string {
    const t = ((game.scene.tokens as Dict[]) ?? []).find((x) => `token:${x.id}` === ref);
    return String(t?.name ?? 'a creature');
  }

  function onTokenDrop(t: Dict, pos: [number, number]): void {
    const tags: string[] = Array.isArray(t.tags) ? t.tags : [];
    if (tags.includes('party') && map) {
      const c = new Grid(map.grid ?? {}).cellAt({ x: pos[0], y: pos[1] });
      dmOp('party_move', { cell: [c.q, c.r] });
      return;
    }
    request({ t: 'token.set', scene: String(game.scene.id ?? ''), id: String(t.id), changes: { pos } });
  }

  function canDrag(t: Dict): boolean {
    const tags: string[] = Array.isArray(t.tags) ? t.tags : [];
    return !tags.includes('place');
  }

  function endSession(): void {
    if (confirm('End the session? What happened is kept as its recap; the next one starts from here.')) dmOp('session', { do: 'end' });
  }

  onMount(() => {
    if (!token) return;
    void connect('dm').then((ok) => {
      if (ok) join({ token });
    });
    const keys = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's') {
        e.preventDefault();
        dmOp('save');
      }
    };
    window.addEventListener('keydown', keys);
    return () => window.removeEventListener('keydown', keys);
  });

  $effect(() => {
    document.title = dm.campaign?.name ? `${dm.campaign.name} — DM` : 'Hexmap — DM';
  });
</script>

{#if !token}
  <main class="nope">
    <h1>The DM’s screen</h1>
    <p>Open it from Hexmap on the computer that runs the game: <strong>Run a game</strong>, then <strong>Open the DM’s screen</strong>.</p>
  </main>
{:else if !game.joined}
  <main class="nope">
    <h1>{game.table || 'The DM’s screen'}</h1>
    <p class="dim">{game.error || (game.status === 'closed' ? 'Hexmap is not answering. Is the game still running?' : 'Connecting to the table…')}</p>
  </main>
{:else}
  <main class="dm">
    <header class="top">
      <button type="button" class="quiet booktoggle" onclick={() => (bookOpen = !bookOpen)} aria-expanded={bookOpen}>☰ Book</button>
      <div class="campaign">
        <span class="brand">Hexmap</span>
        <h1>{dm.campaign?.name ?? game.table}</h1>
      </div>
      <div class="session">
        {#if session.open}
          <span class="chip"><span class="dot on"></span>Session {session.n}</span>
          <button type="button" class="quiet" onclick={endSession}>End the session</button>
        {:else}
          <span class="chip">{Number(session.n ?? 0) > 0 ? `Between sessions (${session.n} played)` : 'No session yet'}</span>
          <button type="button" onclick={() => dmOp('session', { do: 'start' })}>Start session {Number(session.n ?? 0) + 1}</button>
        {/if}
        {#if dm.campaign && !dm.campaign.saved}
          <button type="button" class="quiet" title="Save the campaign (⌘S / Ctrl+S)" onclick={() => dmOp('save')}>Save</button>
        {:else}
          <span class="dim saved">Saved</span>
        {/if}
        {#if ((dm.rules as Dict[]) ?? []).length}
          <button type="button" class="quiet" title="How the rules are played at this table: how characters are made, optional rules" onclick={() => (rulesOpen = true)}>Rules settings</button>
        {/if}
      </div>
      <div class="players">
        {#each game.players as p (p.id)}
          <span class="chip" title={online.has(String(p.id)) ? `${p.name} is here` : `${p.name} is not connected`}>
            <span class="dot" class:on={online.has(String(p.id))} style:background={online.has(String(p.id)) ? String(p.color ?? '') : undefined}></span>{p.name}
          </span>
        {/each}
        <button type="button" class="accent" onclick={() => (inviting = true)}>Invite players</button>
      </div>
    </header>

    <div class="main">
      <aside class="book" class:open={bookOpen}>
        <Book current={card} onopen={open} />
      </aside>

      <section class="center">
        {#if fight}<FightBar {fight} />{/if}
        <div class="mapbar">
          <div class="seen">
            <span class="dim">The players see</span>
            <button type="button" class="scene" onclick={() => (mapsMenu = !mapsMenu)} aria-expanded={mapsMenu}>{sceneName || 'nothing yet'} ▾</button>
            {#if mapsMenu}
              <div class="menu" role="menu">
                <p class="dim">Show the players another map:</p>
                {#each (dm.maps as Dict[]) ?? [] as m (m.id)}
                  <button type="button" role="menuitem" class="quiet" class:current={m.id === game.scene.map} onclick={() => { mapsMenu = false; dmOp('show_map', { map: m.id }); }}>
                    {m.name}<span class="dim"> · {m.role === 'regional' ? 'the region' : 'a battle map'}</span>
                  </button>
                {/each}
              </div>
            {/if}
          </div>
        </div>
        <div class="mapholder">
          <MapView
            {map}
            scene={game.scene}
            gm
            playerColors={playerColors()}
            {selected}
            {activeToken}
            picking={pick ? pickWords(pick) : ''}
            {canDrag}
            {onTokenClick}
            {onCellClick}
            {onTokenDrop}
            onCancelPick={() => ((pick = null), (picked = []))}
          />
          {#if pick && pickCount(pick) > 1}
            <div class="multi-pick" role="dialog" aria-label="Choose the targets">
              <span>{String(pick.label ?? 'Cast')} → {picked.length ? picked.map(pickedName).join(', ') : 'tap each one'} ({picked.length} of up to {pickCount(pick)})</span>
              <button type="button" class="quiet" onclick={() => ((pick = null), (picked = []))}>Cancel</button>
              <button type="button" class="accent" disabled={!picked.length} onclick={() => sendPick([...picked])}>Done</button>
            </div>
          {/if}
          {#if guide && guideGone !== guide.key && !card}
            <div class="guide" role="note">
              <p class="label">Your next step <span class="dim">· only you see this</span></p>
              <p>{guide.text}</p>
              <div class="gbtns">
                {#if guide.button}<button type="button" class="accent" onclick={() => guide.act?.()}>{guide.button}</button>{/if}
                <button type="button" class="quiet" onclick={() => (guideGone = guide.key)}>Got it</button>
              </div>
            </div>
          {/if}
          <!-- (put away while a pick waits, and back after: a playtest's DM
               armed a player's attack and the card covered the creatures) -->
          {#if card && !pick}
            <div class="reader scroll">
              {#if history.length}<button type="button" class="quiet backbtn" onclick={back}>‹ Back</button>{/if}
              {#key card}
                <Card ref={card} onopen={open} onclose={() => { card = ''; history = []; }} {popout} />
              {/key}
            </div>
          {/if}
        </div>
      </section>

      <aside class="right">
        <div class="tabs" role="tablist">
          <button type="button" role="tab" aria-selected={side === 'party'} class:on={side === 'party'} onclick={() => (side = 'party')}>Party</button>
          <button type="button" role="tab" aria-selected={side === 'chat'} class:on={side === 'chat'} onclick={() => (side = 'chat')}>
            Chat &amp; rolls{#if side !== 'chat' && chatCount > seenChat}<span class="badge">{chatCount - seenChat}</span>{/if}
          </button>
          {#if fight}
            <button type="button" role="tab" aria-selected={side === 'fight'} class:on={side === 'fight'} onclick={() => (side = 'fight')}>Fight</button>
          {/if}
        </div>
        <div class="rightbody">
          {#if side === 'party'}
            <div class="party scroll">
              {#each (dm.party_views as Dict[]) ?? [] as pv (pv.plugin)}
                <View node={pv.schema} ctx={pv.data} />
              {:else}
                {#each people.filter((a) => a.kind === 'pc') as a (a.id)}
                  <button type="button" class="quiet pc" onclick={() => open(`actor:${a.id}`)}>{a.name}</button>
                {:else}
                  <p class="dim">No characters yet: players make theirs on their own screens.</p>
                {/each}
              {/each}
            </div>
          {:else if side === 'chat'}
            <Chat />
          {:else}
            <FightPanel {selected} onselect={(id) => (selected = id)} onopen={open} />
          {/if}
        </div>
      </aside>
    </div>
  </main>
  {#if inviting}<Invite onclose={() => (inviting = false)} />{/if}
  {#if rulesOpen}<RulesSettings onclose={() => (rulesOpen = false)} />{/if}
  {#if asking}
    <Modal title="The rules ask you" onclose={() => (putOff = [...putOff, String(asking.p.id)])}>
      <View node={{ type: 'prompt', bind: `/prompts/${asking.i}` }} ctx={game.view} />
    </Modal>
  {/if}
{/if}

<style>
  .multi-pick {
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
    border: 1px solid var(--accent);
    border-radius: 12px;
    box-shadow: var(--shadow);
  }
  .multi-pick span {
    flex: 1;
  }
  .nope {
    height: 100%;
    display: grid;
    place-content: center;
    text-align: center;
    padding: 24px;
    gap: 8px;
  }
  .dm {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .top {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 8px 14px;
    background: var(--panel);
    border-bottom: 1px solid var(--border);
    min-height: 56px;
  }
  .booktoggle {
    display: none;
  }
  .campaign {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .brand {
    font-size: 0.68rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--accent);
    font-weight: 700;
  }
  .campaign h1 {
    font-size: 1.25rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .session {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .saved {
    font-size: 0.85rem;
  }
  .players {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: 6px;
    flex-wrap: wrap;
    justify-content: flex-end;
  }
  .main {
    flex: 1;
    min-height: 0;
    display: grid;
    grid-template-columns: 290px minmax(0, 1fr) 380px;
  }
  .book {
    border-right: 1px solid var(--border);
    background: var(--panel);
    min-height: 0;
  }
  .center {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
  }
  .mapbar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 12px;
    background: var(--bg);
    border-bottom: 1px solid var(--border-soft);
  }
  .seen {
    position: relative;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .scene {
    font-weight: 650;
    min-height: 32px;
  }
  .menu {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    z-index: 30;
    min-width: 280px;
    display: flex;
    flex-direction: column;
    padding: 6px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 12px;
    box-shadow: var(--shadow);
  }
  .menu p {
    margin: 4px 8px 6px;
    font-size: 0.85rem;
  }
  .menu button {
    text-align: left;
  }
  .menu button.current {
    color: var(--accent);
  }
  .mapholder {
    position: relative;
    flex: 1;
    min-height: 0;
  }
  .guide {
    position: absolute;
    left: 14px;
    bottom: 14px;
    max-width: 380px;
    padding: 12px 14px;
    border-radius: 14px;
    background: rgba(24, 27, 33, 0.96);
    border: 1px solid var(--border);
    border-left: 3px solid var(--dm);
    box-shadow: var(--shadow);
    display: flex;
    flex-direction: column;
    gap: 6px;
    z-index: 5;
  }
  .guide p {
    margin: 0;
  }
  .guide .label {
    font-size: 0.72rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--dm);
    font-weight: 700;
  }
  .gbtns {
    display: flex;
    gap: 6px;
    margin-top: 4px;
  }
  .reader {
    position: absolute;
    top: 0;
    left: 0;
    bottom: 0;
    width: min(640px, 100%);
    background: var(--panel);
    border-right: 1px solid var(--border);
    box-shadow: 12px 0 40px rgba(0, 0, 0, 0.45);
    z-index: 10;
  }
  .backbtn {
    position: absolute;
    top: 10px;
    left: 8px;
    z-index: 2;
    min-height: 28px;
    padding: 2px 8px;
    font-size: 0.85rem;
    color: var(--muted);
  }
  .reader :global(.card .head) {
    padding-top: 30px;
  }
  .right {
    display: flex;
    flex-direction: column;
    border-left: 1px solid var(--border);
    background: var(--bg);
    min-height: 0;
  }
  .tabs {
    display: flex;
    gap: 2px;
    padding: 6px 8px 0;
    background: var(--panel);
    border-bottom: 1px solid var(--border);
  }
  .tabs button {
    border: 0;
    border-bottom: 2px solid transparent;
    border-radius: 0;
    background: none;
    color: var(--muted);
    padding: 8px 12px;
  }
  .tabs button.on {
    color: var(--text);
    border-bottom-color: var(--accent);
  }
  .badge {
    margin-left: 6px;
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
  }
  .rightbody {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .rightbody > :global(*) {
    flex: 1;
    min-height: 0;
  }
  .party {
    padding: 12px 14px 32px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .pc {
    text-align: left;
  }
  @media (max-width: 1180px) {
    .main {
      grid-template-columns: minmax(0, 1fr) 340px;
    }
    .booktoggle {
      display: inline-flex;
    }
    .book {
      position: fixed;
      top: 56px;
      left: 0;
      bottom: 0;
      width: 320px;
      z-index: 40;
      transform: translateX(-100%);
      transition: transform 0.18s;
      box-shadow: var(--shadow);
    }
    .book.open {
      transform: none;
    }
  }
  @media (max-width: 820px) {
    .main {
      grid-template-columns: 1fr;
    }
    .right {
      display: none;
    }
  }
</style>
