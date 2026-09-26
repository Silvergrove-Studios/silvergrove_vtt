<!--
  The table's talk and its dice: every message and roll this viewer may
  read, this session's and the campaign's earlier ones, and a box to say
  something — to everyone, to the DM, or to some of the players (privately,
  if the DM should not read it).
-->
<script lang="ts">
  import LogLine from '../lib/views/LogLine.svelte';
  import { chat, chatLog, game, intent, playerName } from '../lib/game.svelte';

  let { compact = false }: { compact?: boolean } = $props();

  let text = $state('');
  let to = $state<string[]>([]); // [] = everyone
  let priv = $state(false);
  let list: HTMLDivElement;
  let pinned = true;

  const entries = $derived(chatLog());
  const dm = $derived(game.role === 'dm');
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

  function sendIt(): void {
    const t = text.trim();
    if (!t) return;
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
</script>

<div class="chat" class:compact>
  <div class="entries scroll" bind:this={list} {onscroll}>
    {#each entries as entry (entry.id ?? JSON.stringify(entry))}
      <LogLine {entry} {actors} />
    {:else}
      <p class="dim empty">Nothing said or rolled yet. Rolls land here too.</p>
    {/each}
  </div>
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
      <input type="text" placeholder="Say something…" bind:value={text} maxlength="2000" aria-label="Message" />
      <button type="submit" class="accent" disabled={!text.trim()}>Send</button>
    </div>
  </form>
</div>

<style>
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
</style>
