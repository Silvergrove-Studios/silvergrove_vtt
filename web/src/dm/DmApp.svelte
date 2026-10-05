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
  import Waiting from '../common/Waiting.svelte';
  import { cardHeading, frontPrompt } from '../lib/prompts';
  import { chatLog, comp, connect, dmOp, game, intent, join, notice, playerColors, request, submit, type Dict } from '../lib/game.svelte';
  import { provideViewUi } from '../lib/views/context';
  import { pictureUrl } from '../lib/art';
  import { Grid } from '../lib/grid';
  import { DEAD_WORDS, moveTo, offersNoTarget, onBattleMap, pickChoices, pickCount, pickEach, pickTarget, pickWords, pickedWords, tappedTheDead, togglePicked, unpick, withNoTarget, withTarget } from '../lib/map/pick';
  import PickBanner from '../lib/map/PickBanner.svelte';
  import { startPreview, tools, whereOf } from '../lib/map/tools.svelte';
  import QuickToken from './QuickToken.svelte';
  import { fightToken, liveFight } from './fight';
  import { currentTurnTokens } from '../lib/turns';
  import { ghostsOf } from '../lib/map/sight';
  import { isObject } from '../lib/map/render';
  import { WALL_COLORS, WALL_KEY } from '../lib/map/walls';

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
  let wasLive = false;

  provideViewUi({
    intent: (p) => {
      if (p?.kind === 'lookup') open(`entry:${p.collection}/${p.id}`);
      else if (p?.kind === 'show' && p.actor) open(`actor:${p.actor}`);
      else if (p?.kind === 'preview') {
        // a spell's or a creature's power's shape on the map, for the table to see
        const w = whereOf(game.scene, map);
        if (!w) notice('There is no map shown to put it on', 'error');
        else {
          pick = null;
          placing = null;
          startPreview(p, w);
        }
      } else intent(p);
    },
    submit,
    pick: (p) => startPick(p),
    comp,
    picture: pictureUrl,
  });

  const dm = $derived(game.dm);
  const fight = $derived(liveFight(dm));
  const map = $derived(game.maps[String(game.scene.map ?? '')] ?? null);
  // seeing as a player: the map draws that player's snapshot (a playtest's DM
  // revealed the goblins and couldn't tell that nobody could see them)
  const seeing = $derived(game.preview && game.previewAs ? game.players.find((p) => String(p.id) === game.previewAs) : undefined);
  // …with the creatures they can't see where they are, and why (the next
  // playtest's DM saw a player's black screen and couldn't say why)
  const ghosts = $derived(seeing ? ghostsOf((game.scene.tokens as Dict[]) ?? [], game.previewWhy) : []);
  // the walls on the DM's map, every kind in its colour, and their key (the
  // DM's map showed none, and nobody knew what was blocking the players' sight)
  let showWalls = $state(true);
  try {
    showWalls = localStorage.getItem('hexmap.dm.walls') !== '0';
  } catch {
    /* private mode */
  }
  function toggleWalls(): void {
    showWalls = !showWalls;
    try {
      localStorage.setItem('hexmap.dm.walls', showWalls ? '1' : '0');
    } catch {
      /* private mode */
    }
  }
  // (a painted regional map has no walls: no key for them)
  const hasWalls = $derived((((map?.levels as Dict[]) ?? []).find((l) => String(l.id) === String(game.scene.level ?? ''))?.walls as Dict[] | undefined)?.length ?? 0);
  const LIGHTS: [string, string][] = [['daylight', 'Daylight'], ['dim', 'Dim'], ['dark', 'Dark']];
  // "As the map" says what the map is (a level with none is lit by day)
  const mapLight = $derived(LIGHTS.find(([k]) => k === String(game.scene.map_light ?? ''))?.[1] ?? 'Daylight');
  const sceneName = $derived(String(game.scene.name ?? '') || String(((dm.maps as Dict[]) ?? []).find((m) => m.id === game.scene.map)?.name ?? ''));
  const online = $derived(new Set(game.online.map(String)));
  const session = $derived((dm.session ?? {}) as Dict);
  // the chat under the party and the fight, as tall as the DM drags it (a
  // playtest's DM on a 13-inch laptop went between the Party and Chat tabs
  // dozens of times, and a first message was lost behind Party); its share of
  // the column is kept in this browser
  const CHAT_SHARE = { min: 20, max: 80, start: 40 };
  const SHARE_KEY = 'hexmap.dm.chat_share';
  let chatShare = $state(readShare());
  let rightBody = $state<HTMLDivElement>();
  function readShare(): number {
    try {
      const v = Number(localStorage.getItem(SHARE_KEY));
      return v >= CHAT_SHARE.min && v <= CHAT_SHARE.max ? v : CHAT_SHARE.start;
    } catch {
      return CHAT_SHARE.start;
    }
  }
  function setShare(v: number, keep = true): void {
    chatShare = Math.round(Math.min(CHAT_SHARE.max, Math.max(CHAT_SHARE.min, v)));
    if (!keep) return;
    try {
      localStorage.setItem(SHARE_KEY, String(chatShare));
    } catch {
      // (a browser that keeps nothing: the share lasts the page)
    }
  }
  function dragShare(e: PointerEvent): void {
    const bar = e.currentTarget as HTMLElement;
    bar.setPointerCapture(e.pointerId);
    const move = (m: PointerEvent) => {
      const box = rightBody?.getBoundingClientRect();
      if (box && box.height > 0) setShare(((box.bottom - m.clientY) / box.height) * 100, false);
    };
    const up = () => {
      bar.removeEventListener('pointermove', move);
      bar.removeEventListener('pointerup', up);
      bar.removeEventListener('pointercancel', up);
      setShare(chatShare);
    };
    bar.addEventListener('pointermove', move);
    bar.addEventListener('pointerup', up);
    bar.addEventListener('pointercancel', up);
  }
  // the keys a window splitter takes: arrows a step, Home and End the least and most
  function keyShare(e: KeyboardEvent): void {
    const step = ({ ArrowUp: 5, ArrowDown: -5, PageUp: 20, PageDown: -20 } as Record<string, number>)[e.key];
    if (step) setShare(chatShare + step);
    else if (e.key === 'Home') setShare(CHAT_SHARE.min);
    else if (e.key === 'End') setShare(CHAT_SHARE.max);
    else return;
    e.preventDefault();
  }
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
  // (a monster's reaction, when the campaign asks the DM, before any other: its time is short)
  const asking = $derived.by(() => {
    const open = prompts.filter(({ p }) => !putOff.includes(String(p.id)));
    const front = frontPrompt(open.map(({ p }) => p));
    return open.find(({ p }) => p === front);
  });
  // a player's card the DM answers for them (from what the table waits on: a hit's
  // damage type the player hasn't chosen); it closes as the answer goes
  let answering = $state<{ id: string; who: string } | null>(null);
  const answeringIndex = $derived(answering ? ((game.view.prompts as Dict[]) ?? []).findIndex((p) => p && String(p.id) === answering?.id) : -1);

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

  // the table's rules chosen before anyone makes a character: one is made by
  // the rules as they are then (a playtest's DM found Rules settings just
  // before the players came); once looked at, this browser remembers it
  const rulesKey = $derived(`hexmap.dm.rules-seen/${String(dm.campaign?.id ?? game.table)}`);
  let rulesSeen = $state<Record<string, boolean>>({});
  function seenRules(): boolean {
    if (rulesSeen[rulesKey]) return true;
    try {
      return localStorage.getItem(rulesKey) === '1';
    } catch {
      return false;
    }
  }
  function openRules(): void {
    rulesOpen = true;
    rulesDone();
  }
  function rulesDone(): void {
    rulesSeen[rulesKey] = true;
    try {
      localStorage.setItem(rulesKey, '1');
    } catch {
      /* private mode */
    }
  }
  const hasRules = $derived(((dm.rules as Dict[]) ?? []).some((g) => g && Array.isArray(g.settings) && g.settings.length > 0));

  const guide = $derived.by((): { key: string; text: string; button?: string; act?: () => void; gotIt?: () => void } | null => {
    if (!dm.campaign || fight) return null;
    if (hasRules && !seenRules() && !people.some((a) => a.kind === 'pc'))
      return { key: 'rules', text: 'Before you invite players: choose your table’s rules (Rules settings) — how characters are made, and the optional rules. A character is made by the rules as they are when it’s made.', button: 'Choose the rules', act: openRules, gotIt: rulesDone };
    if (game.players.every((p) => !online.has(String(p.id))))
      return { key: 'invite', text: 'Invite your players: they scan a code with their phone, or open an address. Nothing to install.', button: 'Invite players', act: () => (inviting = true) };
    if (!session.open) return { key: 'session', text: 'Start the session when everyone is here: what happens is kept as the session’s.', button: `Start session ${Number(session.n ?? 0) + 1}`, act: () => dmOp('session', { do: 'start' }) };
    const withoutCharacter = game.players.filter((p) => online.has(String(p.id)) && !people.some((a) => a.kind === 'pc' && String(a.owner ?? '') === String(p.id)));
    if (withoutCharacter.length)
      return { key: `chars:${withoutCharacter.map((p) => p.id).join(',')}`, text: `${withoutCharacter.map((p) => p.name).join(' and ')} ${withoutCharacter.length > 1 ? 'are' : 'is'} making a character on their own screen. Meanwhile, read what the adventure says first.`, button: startHere() ? `Open “${startTitle()}”` : undefined, act: () => open(startHere()) };
    // (once something has been shown, the DM has the way of it: a playtest's DM
    // saw "Open Introduction" halfway through the second part)
    // (the adventure's own handouts are listed too, shown to nobody: only a card shared counts)
    if (((dm.shown as Dict[]) ?? []).some((h) => String(h.ref ?? '') !== '' && String(h.audience ?? 'gm') !== 'gm')) return null;
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

  function onTokenClick(t: Dict, at?: { x: number; y: number }): void {
    if (pick) {
      resolvePick(at ?? { x: Number(t.pos?.[0] ?? 0), y: Number(t.pos?.[1] ?? 0) }, t);
      return;
    }
    if (placing) {
      placeAt(at ?? { x: Number(t.pos?.[0] ?? 0), y: Number(t.pos?.[1] ?? 0) });
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
    else if (placing) placeAt(at);
    else selected = '';
  }

  // (`hit`: the token tapped, of several on one cell)
  function resolvePick(at: { x: number; y: number }, hit: Dict | null = null): void {
    if (!pick || !map) return;
    const target = pickTarget(new Grid(map.grid ?? {}), (game.scene.tokens as Dict[]) ?? [], pick, at, true, hit);
    if (target === null) {
      notice(tappedTheDead(hit, pick) ? DEAD_WORDS : 'Nothing to pick there — try again, or Cancel', 'error');
      return;
    }
    if (pickCount(pick) > 1 && typeof target === 'string') {
      picked = togglePicked(picked, target, pickCount(pick), pickEach(pick) !== '');
      return;
    }
    sendPick(target);
  }

  // --- a pick by name, or with no target ---

  // a creature's Use waits for a target on the map; with no battle map
  // shown (the region, or nothing) it goes at once with no target: rolled,
  // nothing applied, as a player's does (theatre of the mind)
  function startPick(p: Dict): void {
    placing = null;
    if (String(p.pick ?? '') === 'token' && !onBattleMap(game.scene)) {
      intent(withNoTarget(p, String(game.scene.id ?? '')));
      return;
    }
    pick = p;
    picked = [];
  }

  // (the DM's list has every creature; those the pick can't take — the dead,
  // one out of its range — say why)
  const choices = $derived(pick ? pickChoices((game.scene.tokens as Dict[]) ?? [], pick, { gm: true, grid: map ? new Grid(map.grid ?? {}) : undefined }) : []);

  function chooseListed(target: string): void {
    if (!pick) return;
    const many = pickCount(pick);
    picked = many > 1 ? togglePicked(picked, target, many, pickEach(pick) !== '') : picked[0] === target ? [] : [target];
  }

  function pickNoTarget(): void {
    if (!pick) return;
    intent(withNoTarget($state.snapshot(pick) as Dict, String(game.scene.id ?? '')));
    pick = null;
    picked = [];
  }

  function pickDone(): void {
    if (!pick || !picked.length) return;
    sendPick(pickCount(pick) > 1 ? [...picked] : picked[0]);
  }

  // --- the party and things, where the DM taps ---

  // what a tap on the map puts down: the party (a battle map's tokens, the
  // region's star: a playtest's party always came in at the map's edge, and
  // the DM dragged all four inside), or a thing with no stat block
  let placing = $state<{ kind: 'party' } | { kind: 'thing'; name: string; label: string; color: string; hidden: boolean } | null>(null);

  function placeAt(at: { x: number; y: number }): void {
    if (!placing || !map) return;
    const g = new Grid(map.grid ?? {});
    const cell = g.cellAt(at);
    if (!g.inBounds(cell)) {
      notice('That’s off the map', 'error');
      return;
    }
    const scene = String(game.scene.id ?? '');
    if (placing.kind === 'party') {
      const o = g.toOffset(cell);
      dmOp(onBattleMap(game.scene) ? 'party_here' : 'party_move', { scene, cell: [o.col, o.row] });
    } else {
      const to = moveTo(g, { pos: [at.x, at.y] }, at, map.style?.show_grid !== false);
      if (to) dmOp('add_token', { scene, name: placing.name, label: placing.label, color: placing.color, hidden: placing.hidden, pos: to.pos });
    }
    placing = null;
  }

  // a thing the DM put down, or a thing on the map (a spell's light), chosen:
  // shown or hidden, or taken off
  const thing = $derived(((game.scene.tokens as Dict[]) ?? []).find((t) => String(t.id) === selected && Array.isArray(t.tags) && (t.tags.includes('thing') || isObject(t))));
  // what a thing on the map is, and whose
  function thingWords(t: Dict): string {
    if (!isObject(t)) return 'no stat block';
    const who = game.players.find((p) => String(p.id) === String(t.owner ?? ''));
    return who ? `${String(who.name)}’s, moved by them` : 'a thing on the map';
  }

  // in a fight, a creature of it opened from the book is its stat block
  // beside the map (a playtest's DM, the Warden risen, clicked its name in
  // the book and got its picture)
  function openFromBook(ref: string): void {
    const tid = fight ? fightToken(ref, dm, (game.scene.tokens as Dict[]) ?? [], activeToken) : '';
    if (!tid) {
      open(ref);
      return;
    }
    selected = tid;
    side = 'fight';
    card = '';
    history = [];
    bookOpen = false;
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
      // the Table keeps the party's cell as the map's column and row (a
      // playtest's star, sent axial, landed cells away on an odd row)
      const g = new Grid(map.grid ?? {});
      const o = g.toOffset(g.cellAt({ x: pos[0], y: pos[1] }));
      dmOp('party_move', { cell: [o.col, o.row] });
      return;
    }
    request({ t: 'token.set', scene: String(game.scene.id ?? ''), id: String(t.id), changes: { pos } });
  }

  function canDrag(t: Dict): boolean {
    const tags: string[] = Array.isArray(t.tags) ? t.tags : [];
    return !tags.includes('place');
  }

  // End the session asks in the table's own words (never the browser's bare OK)
  let ending = $state(false);
  function endSession(): void {
    ending = false;
    dmOp('session', { do: 'end' });
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
          <button type="button" class="quiet" onclick={() => (ending = true)}>End the session</button>
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
          <button type="button" class="quiet" title="How the rules are played at this table: how characters are made, optional rules" onclick={openRules}>Rules settings</button>
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
        <Book current={card} onopen={openFromBook} />
      </aside>

      <section class="center">
        <!-- the fight's bar has a height of its own: taller (two lines, the
             "already ended their turn" question) it lies over what is below
             it, and the map never moves under a tap (a playtest's DM clicked
             empty ground: "Nothing to pick there") -->
        {#if fight}<div class="fightslot"><FightBar {fight} /></div>{/if}
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
          {#if game.scene.id}
            <!-- how lit the scene is: by day the players see everything in their
                 line of sight; in the dark, only lights and darkvision show -->
            <label class="lightsel">
              <span class="dim">Light</span>
              <select value={String(game.scene.light_set ?? '')} onchange={(e) => dmOp('scene_light', { scene: String(game.scene.id ?? ''), light: e.currentTarget.value })}>
                <option value="">As the map ({mapLight.toLowerCase()})</option>
                {#each LIGHTS as [k, words] (k)}<option value={k}>{words}</option>{/each}
              </select>
            </label>
            {#if hasWalls > 0}
              <button type="button" class="quiet wallsbtn" aria-pressed={showWalls} class:on={showWalls} title="The walls on the map, each kind in its colour" onclick={toggleWalls}>Walls</button>
            {/if}
            <!-- the party where the story has them, and things with no stat block -->
            <button type="button" class="quiet wallsbtn" class:on={placing?.kind === 'party'} aria-pressed={placing?.kind === 'party'} title="Tap the map where the party is" onclick={() => ((pick = null), (placing = placing?.kind === 'party' ? null : { kind: 'party' }))}>Move the party here</button>
            {#if onBattleMap(game.scene)}
              <QuickToken onplace={(spec) => ((pick = null), (placing = { kind: 'thing', ...spec }))} />
            {/if}
          {/if}
          <label class="seeas">
            <span class="dim">See as</span>
            <select value={game.previewAs} onchange={(e) => dmOp('see_as', { player: e.currentTarget.value })}>
              <option value="">yourself: everything</option>
              {#each game.players as p (p.id)}<option value={String(p.id)}>{p.name}</option>{/each}
            </select>
          </label>
        </div>
        {#if showWalls && game.scene.id && hasWalls > 0}
          <div class="wallkey" aria-label="What the walls are">
            {#each WALL_KEY as [kind, words] (kind)}
              <span class="key"><span class="swatch" class:dashed={kind === 'terrain'} style:--c={WALL_COLORS[kind]}></span>{words}</span>
            {/each}
            <span class="key"><span class="swatch dashed"></span>dashed: hidden from the players</span>
          </div>
        {/if}
        {#if seeing}
          <div class="seeing" role="status">
            <span>
              <strong>{seeing.name}</strong>'s screen: <span class="legend navy">hatched</span> in their sight but too dark ·
              <span class="legend black">black</span> behind walls · <span class="legend ring">dashed ring</span> a creature they can't see, and why
            </span>
            <button type="button" class="quiet" onclick={() => dmOp('see_as', { player: '' })}>Back to yours</button>
          </div>
        {/if}
        <div class="mapholder">
          <MapView
            {map}
            scene={seeing ? (game.preview as Dict) : game.scene}
            gm={!seeing}
            showWalls={showWalls || !!seeing}
            seeAs={!!seeing}
            {ghosts}
            playerColors={playerColors()}
            {selected}
            {activeToken}
            fight={!!fight}
            picking={pick ? pickWords(pick) : placing?.kind === 'party' ? 'Move the party here: tap where they are' : placing ? `${placing.name}: tap where it goes` : ''}
            banner={pick ? pickBanner : undefined}
            {canDrag}
            tools
            {onTokenClick}
            {onCellClick}
            {onTokenDrop}
            onCancelPick={() => ((pick = null), (picked = []), (placing = null))}
          />
          <!-- what the table waits on (a player's reaction), over the map's top edge:
               the map never moves under a tap; the DM can go on without waiting -->
          <div class="waitslot"><Waiting dm onanswer={(id, who) => (answering = { id, who })} /></div>
          {#snippet pickBanner()}
            {#if pick}
              <PickBanner
                words={pickWords(pick)}
                {choices}
                {picked}
                many={pickCount(pick)}
                each={pickEach(pick)}
                status={pickedWords(pick, picked, pickedName)}
                noTarget={offersNoTarget(pick)}
                onChoose={chooseListed}
                onUnchoose={(t) => (picked = unpick(picked, t))}
                onDone={pickDone}
                onCancel={() => ((pick = null), (picked = []))}
                onNoTarget={pickNoTarget}
              />
            {/if}
          {/snippet}
          {#if thing && !pick && !placing}
            <div class="thingbar" role="group" aria-label={String(thing.name ?? 'A token')}>
              <span><strong>{thing.name}</strong> <span class="dim">· {thingWords(thing)}{thing.hidden ? ' · hidden from the players' : ''}</span></span>
              <button type="button" class="quiet" onclick={() => dmOp('token', { scene: String(game.scene.id ?? ''), id: thing.id, hidden: !thing.hidden })}>{thing.hidden ? 'Show the players' : 'Hide it'}</button>
              <button type="button" class="quiet" onclick={() => { dmOp('remove_token', { scene: String(game.scene.id ?? ''), id: thing.id }); selected = ''; }}>Take it off the map</button>
            </div>
          {/if}
          {#if guide && guideGone !== guide.key && !card && !thing}
            <div class="guide" role="note">
              <p class="label">Your next step <span class="dim">· only you see this</span></p>
              <p>{guide.text}</p>
              <div class="gbtns">
                {#if guide.button}<button type="button" class="accent" onclick={() => guide.act?.()}>{guide.button}</button>{/if}
                <button type="button" class="quiet" onclick={() => (guide.gotIt?.(), (guideGone = guide.key))}>Got it</button>
              </div>
            </div>
          {/if}
          <!-- (put away while a pick waits, or a tap puts the party or a thing
               down, and back after: a playtest's DM armed a player's attack and
               the card covered the creatures) -->
          {#if card && !pick && !placing && !tools.mode}
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
            Chat &amp; rolls
          </button>
          {#if fight}
            <button type="button" role="tab" aria-selected={side === 'fight'} class:on={side === 'fight'} onclick={() => (side = 'fight')}>Fight</button>
          {/if}
        </div>
        <div class="rightbody" class:split={side !== 'chat'} bind:this={rightBody} style:--top-fr={`${100 - chatShare}fr`} style:--chat-fr={`${chatShare}fr`}>
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
          {:else if side === 'fight'}
            <div class="fightpanel"><FightPanel {selected} onselect={(id) => (selected = id)} onopen={open} /></div>
          {/if}
          {#if side !== 'chat'}
            <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
            <div class="divider" role="separator" aria-orientation="horizontal" aria-label="The chat's height" aria-controls="sidechat"
              aria-valuemin={CHAT_SHARE.min} aria-valuemax={CHAT_SHARE.max} aria-valuenow={chatShare} tabindex="0"
              title="Drag for more or less chat (double-click: as it was)"
              onpointerdown={dragShare} onkeydown={keyShare} ondblclick={() => setShare(CHAT_SHARE.start)}></div>
          {/if}
          <!-- one chat for all three tabs, so a half-written message stays
               put; headed when it shares the column, so the stat block's
               clipped edge doesn't run into the roll cards (a playtest's DM
               took the chat for covering the monster's Use and Save buttons) -->
          <section class="sidechat" class:beside={side !== 'chat'} id="sidechat" aria-labelledby={side !== 'chat' ? 'sidechat-head' : undefined}>
            {#if side !== 'chat'}<h2 class="panehead" id="sidechat-head">Chat &amp; rolls</h2>{/if}
            <Chat compact={side !== 'chat'} />
          </section>
        </div>
      </aside>
    </div>
  </main>
  {#if inviting}<Invite onclose={() => (inviting = false)} />{/if}
  {#if rulesOpen}<RulesSettings onclose={() => (rulesOpen = false)} />{/if}
  {#if ending}
    <Modal title="End the session?" onclose={() => (ending = false)}>
      <p class="ask">What happened is kept as its recap; the next session starts from here.</p>
      {#snippet actions()}
        <button type="button" class="quiet" onclick={() => (ending = false)}>Not yet</button>
        <button type="button" class="danger" onclick={endSession}>End the session</button>
      {/snippet}
    </Modal>
  {/if}
  {#if asking}
    <Modal title={cardHeading(asking.p, true)} onclose={() => (putOff = [...putOff, String(asking.p.id)])}>
      <View node={{ type: 'prompt', bind: `/prompts/${asking.i}` }} ctx={game.view} />
    </Modal>
  {:else if answeringIndex >= 0}
    <Modal title={`For ${answering?.who || 'a player'}: ${cardHeading(((game.view.prompts as Dict[]) ?? [])[answeringIndex]).toLowerCase()}`} onclose={() => (answering = null)}>
      <View node={{ type: 'prompt', bind: `/prompts/${answeringIndex}` }} ctx={game.view} />
    </Modal>
  {/if}
{/if}

<style>
  .lightsel {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .ask {
    margin: 0;
  }
  .wallsbtn {
    min-height: 30px;
    padding: 2px 10px;
    border: 1px solid var(--border);
    border-radius: 999px;
    color: var(--muted);
  }
  .wallsbtn.on {
    color: var(--text);
    border-color: var(--accent-soft, var(--accent));
  }
  .wallkey {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 14px;
    padding: 4px 12px 6px;
    background: var(--bg);
    border-bottom: 1px solid var(--border-soft);
    font-size: 0.78rem;
    color: var(--muted);
  }
  .key {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .swatch {
    width: 18px;
    height: 0;
    border-top: 3px solid var(--c, #d8d8d8);
  }
  .swatch.dashed {
    border-top-style: dashed;
    border-top-color: var(--c, #d8d8d8);
  }
  .legend {
    font-weight: 650;
  }
  .legend.navy {
    color: #a0b0ff;
  }
  .legend.ring {
    text-decoration: underline dashed;
  }
  .seeas {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-left: auto;
  }
  .seeas select {
    max-width: 14em;
  }
  .seeing {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 12px;
    background: color-mix(in srgb, var(--accent) 14%, var(--panel));
    border-bottom: 1px solid var(--border);
    font-size: 0.9rem;
  }
  .seeing span {
    flex: 1;
  }
  .fightpanel {
    min-height: 0;
    overflow: hidden;
  }
  .sidechat {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    min-height: 0;
  }
  .sidechat.beside {
    background: var(--panel);
  }
  .sidechat > :global(.chat) {
    flex: 1;
    min-height: 0;
  }
  .divider {
    cursor: row-resize;
    touch-action: none;
    background: var(--border);
    border-block: 3px solid var(--bg);
  }
  .divider:hover,
  .divider:focus-visible {
    background: var(--accent-soft);
    outline: none;
  }
  .panehead {
    flex: none;
    margin: 0;
    padding: 7px 14px 5px;
    font-family: var(--font-ui);
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--muted);
    border-bottom: 1px solid var(--border-soft);
  }
  /* the fight's bar keeps one height in the column; what grows lies over the map */
  .fightslot {
    position: relative;
    flex: none;
    height: 58px;
    z-index: 12;
  }
  .fightslot > :global(.fightbar) {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    min-height: 58px;
    box-sizing: border-box;
  }
  .thingbar {
    position: absolute;
    left: 12px;
    bottom: 12px;
    z-index: 6;
    display: flex;
    flex-wrap: wrap;
    gap: 6px 8px;
    align-items: center;
    max-width: calc(100% - 80px);
    padding: 8px 10px 8px 14px;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 12px;
    box-shadow: var(--shadow);
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
    flex-wrap: wrap;
    align-items: center;
    gap: 6px 10px;
    padding: 6px 12px;
    background: var(--bg);
    border-bottom: 1px solid var(--border-soft);
  }
  /* (the bar's words on one line each: with Light and Walls in it they wrapped letter-high) */
  .mapbar .dim {
    white-space: nowrap;
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
  /* (the map's width to center in: at left 50% it had half of it, and its words
     lost their seconds once Answer stood beside Go on) */
  .waitslot {
    position: absolute;
    top: 10px;
    left: 12px;
    right: 12px;
    display: flex;
    justify-content: center;
    z-index: 11;
    pointer-events: none;
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
  /* the party or the fight, the bar, the chat: as the DM last dragged it */
  .rightbody.split {
    display: grid;
    grid-template-rows: minmax(0, var(--top-fr, 60fr)) 9px minmax(140px, var(--chat-fr, 40fr));
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
