<!--
  The table's talk and its dice: every message and roll this viewer may
  read, this session's and the campaign's earlier ones, and a box to say
  something — to everyone, to the DM, or to some of the players (privately,
  if the DM should not read it).
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { fade } from 'svelte/transition';
  import LogLine from '../lib/views/LogLine.svelte';
  import { chat, chatLog, dmOp, game, intent, playerName } from '../lib/game.svelte';
  import { TypingSignal, typingWords } from '../lib/typing';

  let { compact = false }: { compact?: boolean } = $props();

  let text = $state('');
  let to = $state<string[]>([]); // [] = everyone
  let priv = $state(false);
  let list: HTMLDivElement;
  let pinned = true;

  const dm = $derived(game.role === 'dm');
  // the DM seeing as a player sees that player's chat too, as far as the DM
  // may read it (a playtest's DM couldn't check whether a hidden creature's
  // roll had reached the players' chat)
  const preview = $derived.by(() => {
    const p = game.view.preview_chat;
    return dm && game.previewAs && p && typeof p === 'object' && String(p.as ?? '') === game.previewAs ? (p as Record<string, unknown>) : null;
  });
  const entries = $derived(preview ? chatLog(preview) : chatLog());
  const others = $derived(game.players.filter((p) => String(p.id) !== game.me));
  const actors = $derived(game.view.actors ?? {});
  const canPrivate = $derived(!dm && to.length > 0 && !to.includes('gm'));
  const who = $derived.by(() => {
    if (to.length === 0) return 'Everyone at the table reads this';
    const names = to.map((id) => (id === 'gm' ? 'the DM' : playerName(id)));
    if (dm) return `Only ${names.join(', ')} and you read this`;
    if (canPrivate && priv) return `Only ${names.join(', ')} and you — not the DM`;
    return `${names.join(', ')}${to.includes('gm') ? '' : ', the DM'} and you read this`;
  });

  // a click chooses who reads it; Shift, Ctrl or ⌘ adds (or takes away) one more.
  // (They used to add up: a playtest's DM wrote to Priya, then clicked Walt for
  // a secret of his, and Priya read it too.)
  function toggle(id: string, e?: MouseEvent): void {
    if (e && (e.shiftKey || e.ctrlKey || e.metaKey)) to = to.includes(id) ? to.filter((x) => x !== id) : [...to, id];
    else to = to.length === 1 && to[0] === id ? [] : [id];
  }

  // "Leo is typing…": the table is told, now and then, while this box holds
  // something being written, and only those who'll read it hear (a playtest's
  // DM and players crossed messages many times)
  const typingSignal = new TypingSignal(() => intent({ kind: 'typing', to: to.length ? [...to] : 'all', private: canPrivate && priv }));
  const typers = $derived(typingWords(Object.keys(game.typing).map((id) => playerName(id))));

  function sendIt(): void {
    const t = text.trim();
    if (!t) return;
    typingSignal.sent();
    // dice: "/roll 1d20+4 Stealth" for everyone, the DM's "/gmroll 2d6" in secret
    // (a playtest's DM had no dice of his own; "/roll" went out as words)
    const r = /^\/(roll|r|gmroll)\s+(\S+)(?:\s+(.*))?$/i.exec(t);
    if (r) {
      intent({ kind: 'roll', expr: r[2], label: r[3] ?? '', secret: dm && r[1].toLowerCase() === 'gmroll' });
      text = '';
      return;
    }
    chat(t, to.length ? [...to] : 'all', canPrivate && priv);
    text = '';
    pinned = true;
  }

  function onscroll(): void {
    pinned = list.scrollHeight - list.scrollTop - list.clientHeight < 40;
  }

  $effect(() => {
    void entries.length;
    if (pinned && list) queueMicrotask(() => (list.scrollTop = list.scrollHeight));
  });

  // the DM's pins: a line kept above the chat until it's dealt with (a playtest's
  // DM missed a player's request for ten minutes as the chat ran on); this
  // browser's own, kept for the table
  const pinKey = $derived(`hexmap.pins/${game.table}`);
  let pins = $state<string[]>([]);
  $effect(() => {
    try {
      const v = JSON.parse(localStorage.getItem(pinKey) ?? '[]');
      pins = Array.isArray(v) ? v.map(String) : [];
    } catch {
      pins = [];
    }
  });
  function pin(id: string): void {
    pins = pins.includes(id) ? pins.filter((x) => x !== id) : [...pins, id];
    try {
      localStorage.setItem(pinKey, JSON.stringify(pins));
    } catch {
      /* private mode */
    }
  }
  const pinnedLines = $derived(dm ? entries.filter((e) => pins.includes(String(e.id ?? ''))) : []);
  const canPin = $derived(dm && !preview);

  // one Pin, on the line the pointer is over (or tapped, or reached with the
  // arrow keys), not one on every line: a playtest's screen reader found 413
  // "Pin" buttons in the chat
  let hot = $state('');
  const pinnable = $derived(canPin ? entries.filter((e) => e.kind === 'chat' && e.id).map((e) => String(e.id)) : []);
  async function arrows(e: KeyboardEvent): Promise<void> {
    if (!canPin || !['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(e.key) || !pinnable.length) return;
    e.preventDefault();
    const at = pinnable.indexOf(hot);
    let i = pinnable.length - 1;
    if (at >= 0 && e.key === 'ArrowUp') i = Math.max(0, at - 1);
    else if (at >= 0 && e.key === 'ArrowDown') i = Math.min(pinnable.length - 1, at + 1);
    else if (e.key === 'Home') i = 0;
    hot = pinnable[i];
    await tick();
    const btn = list?.querySelector<HTMLButtonElement>(`[data-line="${CSS.escape(hot)}"] .pinbtn`);
    btn?.focus();
    btn?.scrollIntoView({ block: 'nearest' });
  }
  function leftList(e: FocusEvent): void {
    if (!list?.contains(e.relatedTarget as Node | null)) hot = '';
  }
</script>

<div class="chat" class:compact>
  {#if preview}
    <div class="seeing" role="status">
      <span><strong>{playerName(game.previewAs)}</strong>’s chat, as they read it (what players keep from you stays theirs)</span>
      <button type="button" class="quiet" onclick={() => dmOp('see_as', { player: '' })}>Back to yours</button>
    </div>
  {/if}
  {#if pinnedLines.length && !preview}
    <div class="pins" role="region" aria-label="Pinned">
      {#each pinnedLines as entry (entry.id)}
        <div class="line-row pinned-row">
          <LogLine {entry} {actors} />
          <button type="button" class="quiet pinbtn on" onclick={() => pin(String(entry.id))}>Unpin</button>
        </div>
      {/each}
    </div>
  {/if}
  <!-- (a region the keyboard can scroll; the DM's arrow keys go line to line, each with its Pin) -->
  <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
  <div class="entries scroll" role="region" aria-label="Messages and rolls" tabindex="0" bind:this={list} {onscroll} onkeydown={arrows} onfocusout={leftList}>
    {#each entries as entry (entry.id ?? JSON.stringify(entry))}
      {#if canPin && entry.kind === 'chat' && entry.id}
        {@const id = String(entry.id)}
        <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
        <div
          class="line-row"
          data-line={id}
          onpointerenter={(e) => e.pointerType === 'mouse' && (hot = id)}
          onpointerleave={(e) => e.pointerType === 'mouse' && hot === id && !e.currentTarget.contains(document.activeElement) && (hot = '')}
          onclick={() => (hot = id)}
        >
          <LogLine {entry} {actors} />
          {#if hot === id || pins.includes(id)}
            <button type="button" class="quiet pinbtn" class:on={pins.includes(id)} onclick={() => pin(id)} title="Keep it above the chat until it's dealt with">{pins.includes(id) ? 'Unpin' : 'Pin'}</button>
          {/if}
        </div>
      {:else}
        <LogLine {entry} {actors} />
      {/if}
    {:else}
      <p class="dim empty">Nothing said or rolled yet. Rolls land here too.</p>
    {/each}
  </div>
  {#if typers}
    <p class="typing dim" transition:fade={{ duration: 400 }}>{typers}</p>
  {/if}
  <form class="compose" onsubmit={(e) => { e.preventDefault(); sendIt(); }}>
    <div class="to" role="group" aria-label="Who reads it">
      <button type="button" class="chip" class:on={to.length === 0} onclick={() => (to = [])}>Everyone</button>
      {#if !dm}<button type="button" class="chip" class:on={to.includes('gm')} onclick={(e) => toggle('gm', e)}>DM</button>{/if}
      {#each others as p (p.id)}
        <button type="button" class="chip" class:on={to.includes(String(p.id))} onclick={(e) => toggle(String(p.id), e)}>
          <span class="dot" style:background={String(p.color ?? '#999')}></span>{p.name}
        </button>
      {/each}
    </div>
    <div class="who" class:dim={to.length === 0} class:aimed={to.length > 0}>
      {who}
      <span class="hint dim">· {to.length ? 'Shift-click adds someone' : '/roll 1d20+4 rolls dice'}{!to.length && dm ? ' (/gmroll in secret)' : ''}</span>
      {#if canPrivate}
        <label class="private"><input type="checkbox" bind:checked={priv} /> keep it from the DM</label>
      {/if}
    </div>
    <div class="line">
      <input type="text" placeholder="Say something…" bind:value={text} maxlength="2000" aria-label="Message" oninput={(e) => typingSignal.input(e.currentTarget.value)} />
      <button type="submit" class="accent" disabled={!text.trim()}>Send</button>
    </div>
  </form>
</div>

<style>
  .line-row {
    display: flex;
    align-items: flex-start;
    gap: 6px;
  }
  .line-row > :global(:first-child) {
    flex: 1;
    min-width: 0;
  }
  .pinbtn {
    flex: none;
    font-size: 0.75rem;
    padding: 2px 8px;
    min-height: 0;
  }
  .pinbtn:not(.on) {
    color: var(--muted);
  }
  .entries:focus-visible {
    outline: 2px solid var(--accent-soft);
    outline-offset: -2px;
  }
  /* who is writing, under the talk */
  .typing {
    flex: none;
    margin: 0;
    padding: 2px 14px 4px;
    font-size: 0.82rem;
    font-style: italic;
  }
  .seeing {
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    font-size: 0.85rem;
    background: color-mix(in srgb, var(--accent) 14%, var(--panel));
    border-bottom: 1px solid var(--border);
  }
  .seeing span {
    flex: 1;
    min-width: 0;
  }
  .pins {
    flex: none;
    max-height: 30%;
    overflow-y: auto;
    padding: 6px 8px;
    border-bottom: 1px solid var(--border);
    background: color-mix(in srgb, var(--accent) 8%, var(--panel));
  }
  /* who is about to read it, plain to see when it isn't everyone */
  .who.aimed {
    color: var(--accent);
    font-weight: 600;
  }
  .hint {
    font-weight: 400;
  }
  .chat {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
  .entries {
    flex: 1;
    min-height: 0;
    padding: 4px 14px;
  }
  .empty {
    padding: 16px 0;
  }
  .compose {
    border-top: 1px solid var(--border);
    padding: 10px 12px calc(10px + env(safe-area-inset-bottom));
    display: flex;
    flex-direction: column;
    gap: 8px;
    background: var(--panel);
  }
  /* the names wrap: a row that scrolled with no scrollbar cut the fifth
     name off at the edge (a playtest's DM saw "W" for Walt) */
  .to {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .chip {
    min-height: 30px;
    padding: 3px 11px;
    cursor: pointer;
  }
  .chip.on {
    background: var(--accent-bg);
    border-color: var(--accent);
    color: var(--heading);
  }
  .who {
    font-size: 0.85rem;
    display: flex;
    flex-wrap: wrap;
    gap: 4px 12px;
    align-items: center;
  }
  .private {
    display: inline-flex;
    gap: 6px;
    align-items: center;
    color: var(--text);
  }
  .line {
    display: flex;
    gap: 8px;
  }
  .line input {
    flex: 1;
    min-width: 0;
  }
  /* compact, beside the fight: the talk gets the room, not the box to write
     in (a playtest's composer took 185 of the pane's 320 px). Who reads it
     shows only when it isn't everyone. */
  .compact .entries {
    padding: 2px 12px;
  }
  .compact .compose {
    padding: 6px 10px calc(6px + env(safe-area-inset-bottom));
    gap: 5px;
  }
  .compact .to {
    gap: 4px;
  }
  .compact .chip {
    min-height: 24px;
    padding: 1px 9px;
    font-size: 0.8rem;
  }
  .compact .hint,
  .compact .who:not(.aimed) {
    display: none;
  }
  .compact .who {
    font-size: 0.8rem;
  }
  .compact .line {
    gap: 6px;
  }
  .compact .line input,
  .compact .line button {
    min-height: 32px;
    padding-top: 4px;
    padding-bottom: 4px;
  }
</style>
