<!--
  The table's tools on the map, for everyone at every level of the rules: a
  Ruler (drag, or tap each point and Done: "Wren: 25 ft", the walk round the
  walls when it differs), a Template (a circle, a cone, a line or a cube of
  any size in feet, moved and turned), a Ping ("look here"; a long press or a
  right-click does it too), and Clear mine. What is made is seen by
  everyone at the table as it is made, in its maker's colour with their
  name. A spell's Preview (from a sheet) comes up here too: moved or turned,
  pinned, and — where the app casts — Cast here. The list says every mark on
  the map in words, with who each template would catch of the creatures
  this screen shows; the DM may take anyone's off, and keep their own to
  themselves (Only me). On the DM's screen a template or a preview offers
  what the rules do on one (Damage those caught: a ruleset's action with
  `target: "template"`), on the creatures it catches.
-->
<script lang="ts">
  import { game, type Dict } from '../game.svelte';
  import { gridless, ruleOf } from './measure';
  import { catchName, catchWords, markLine, markText } from './marks';
  import {
    TURN_STEP,
    cancel,
    castHere,
    catches,
    clearEveryone,
    clearMine,
    done,
    myOwner,
    onTemplate,
    pinMark,
    removeMark,
    reshape,
    startPing,
    startRuler,
    startTemplate,
    stop,
    templateActions,
    togglePin,
    tools,
    turn,
    turnable,
    undoPoint,
    type Where,
  } from './tools.svelte';

  // (`marks`: the ones this screen draws — the DM seeing as a player, that player's)
  let { where, gm = false, hidden = false, marks = undefined }: { where: Where | null; gm?: boolean; hidden?: boolean; marks?: Record<string, Dict> } = $props();

  const owner = $derived(myOwner());
  const sceneId = $derived(String(where?.scene?.id ?? ''));
  const onScene = $derived(Object.values(marks ?? game.marks).filter((m) => String(m.scene ?? '') === sceneId));
  const mineCount = $derived(onScene.filter((m) => String(m.owner ?? '') === owner).length + (tools.draft && !game.marks[String(tools.draft.id)] ? 1 : 0));
  const look = $derived(where ? { grid: where.grid, rule: ruleOf(where.scene), noGrid: gridless(where.map), tokens: where.tokens } : null);
  const draftWords = $derived(tools.draft && look ? markText(tools.draft, look, game.marks[String(tools.draft.id)]) : '');
  const draftCatches = $derived(tools.draft && where && (tools.mode === 'template' || tools.mode === 'preview') ? catches(tools.draft, where).map(catchName) : []);
  // what the rules do on a template (Damage those caught): the DM's, on the creatures it catches
  const acts = $derived(gm ? templateActions(game.view) : []);
  const SHAPES: [string, string][] = [
    ['circle', 'Circle'],
    ['cone', 'Cone'],
    ['line', 'Line'],
    ['square', 'Cube'],
  ];
</script>

{#if !hidden}
  {#if tools.mode === ''}
    <div class="tools" role="toolbar" aria-label="Table tools">
      <button type="button" aria-label="Ruler" title="Ruler: measure a distance (everyone sees it). Drag, or tap each point then Done" onclick={startRuler}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z M14.5 12.5l2-2 M11.5 9.5l2-2 M8.5 6.5l2-2 M17.5 15.5l2-2" /></svg>
        <span>Ruler</span>
      </button>
      <button type="button" aria-label="Template" title="Template: a circle, a cone, a line or a cube, any size, for everyone to see" onclick={startTemplate}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 8.9a.7.7 0 0 1-.572 1.1Z M4 14h6v6H4z M17.5 14a3.5 3.5 0 1 0 0 7a3.5 3.5 0 1 0 0-7z" /></svg>
        <span>Template</span>
      </button>
      <button type="button" aria-label="Ping" title="Ping: “look here”, for everyone (a long press or a right-click on the map does it too)" onclick={startPing}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 10a2 2 0 1 0 0 4a2 2 0 1 0 0-4z M12 5a7 7 0 1 0 0 14a7 7 0 1 0 0-14z M12 1v3 M12 20v3 M1 12h3 M20 12h3" /></svg>
        <span>Ping</span>
      </button>
      <button type="button" aria-label="Clear mine" title="Take your rulers, templates and pings off the map" disabled={mineCount === 0} onclick={clearMine}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21 M22 21H7 M5 11l9 9" /></svg>
        <span>Clear mine</span>
      </button>
      <button type="button" aria-label={`Marks on the map (${onScene.length})`} title="Every mark on the map, in words" aria-expanded={tools.list} class:on={tools.list} onclick={() => (tools.list = !tools.list)}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 6h13 M8 12h13 M8 18h13 M3 6h.01 M3 12h.01 M3 18h.01" /></svg>
        <span>Marks{onScene.length ? ` ${onScene.length}` : ''}</span>
      </button>
      {#if gm}
        <button type="button" aria-label="Only me" aria-pressed={tools.private} class:on={tools.private} title="Your marks seen by you alone (off: by everyone at the table, but never over what a player can’t see)" onclick={() => (tools.private = !tools.private)}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 11h14v10H5z M8 11V7a4 4 0 0 1 8 0v4" /></svg>
          <span>Only me</span>
        </button>
      {/if}
    </div>
  {:else}
    <div class="toolbar-banner" role="group" aria-label={tools.mode === 'ruler' ? 'Ruler' : tools.mode === 'template' ? 'Template' : tools.mode === 'ping' ? 'Ping' : 'Preview'}>
      {#if tools.mode === 'ping'}
        <span class="words">Ping: tap where to look</span>
        <div class="buttons"><button type="button" class="quiet" onclick={stop}>Cancel</button></div>
      {:else if tools.mode === 'ruler'}
        {#if !tools.draft}
          <span class="words">Ruler: drag, or tap where it starts</span>
          <div class="buttons"><button type="button" class="quiet" onclick={stop}>Close</button></div>
        {:else}
          <span class="words" aria-live="polite"><strong>{draftWords}</strong>{#if tools.tapping}<span class="dim"> · tap for each point</span>{/if}</span>
          <div class="buttons">
            {#if tools.tapping && where}<button type="button" class="quiet" onclick={() => where && undoPoint(where)}>Undo point</button>{/if}
            <button type="button" class="quiet" aria-pressed={!!tools.draft.pinned} onclick={togglePin}>{tools.draft.pinned ? 'Unpin' : 'Pin'}</button>
            <button type="button" class="quiet" onclick={cancel}>Take it off</button>
            <button type="button" class="accent" onclick={() => done(where)}>Done</button>
          </div>
        {/if}
      {:else}
        {#if tools.mode === 'template'}
          <div class="form">
            <label><span class="sr-only">Shape</span>
              <select aria-label="Shape" bind:value={tools.shape} onchange={() => where && reshape(where)}>
                {#each SHAPES as [k, w] (k)}<option value={k}>{w}</option>{/each}
              </select>
            </label>
            <label class="num"><input type="number" aria-label={tools.shape === 'circle' ? 'Radius in feet' : tools.shape === 'square' ? 'Side in feet' : 'Length in feet'} min="1" max="5000" step="5" bind:value={tools.feet} onchange={() => where && reshape(where)} /><span>ft</span></label>
            {#if tools.shape === 'line'}
              <label class="num"><input type="number" aria-label="Width in feet" min="1" max="5000" step="5" bind:value={tools.widthFeet} onchange={() => where && reshape(where)} /><span>ft wide</span></label>
            {/if}
          </div>
        {/if}
        {#if !tools.draft}
          <span class="words">{tools.mode === 'preview' ? `${tools.preview?.label ?? 'The preview'}: tap where it goes` : 'Tap where it goes'}</span>
          <div class="buttons"><button type="button" class="quiet" onclick={stop}>Cancel</button></div>
        {:else}
          <span class="words" aria-live="polite">
            {#if tools.mode === 'preview'}<strong>{tools.preview?.label}</strong> · {/if}{catchWords(draftCatches)}
          </span>
          <div class="buttons">
            {#if turnable()}
              <button type="button" class="quiet" aria-label="Turn left" title="Turn it {TURN_STEP}° (or drag its round handle)" onclick={() => turn(-TURN_STEP)}>⟲</button>
              <button type="button" class="quiet" aria-label="Turn right" title="Turn it {TURN_STEP}° (or drag its round handle)" onclick={() => turn(TURN_STEP)}>⟳</button>
            {/if}
            {#each acts as act (act.plugin + '/' + act.action)}
              <!-- (the DM's: the rules ask what it deals, then roll and ask the saves as the table does) -->
              <button type="button" class="quiet" disabled={!draftCatches.length} title={act.hint || 'On the creatures it catches'} onclick={() => where && tools.draft && onTemplate(tools.draft, where, act)}>{act.label}</button>
            {/each}
            <button type="button" class="quiet" aria-pressed={!!tools.draft.pinned} title="A pinned mark stays till it’s taken off" onclick={togglePin}>{tools.draft.pinned ? 'Unpin' : 'Pin'}</button>
            {#if tools.mode === 'preview' && tools.preview?.cast && where}
              <!-- (a spell is cast; an ability — a breath, Turn Undead — used) -->
              <button type="button" class="accent" title="Here, as it faces: the rules’ own checks apply" onclick={() => where && castHere(where)}>{tools.preview.cast.action === 'cast' ? 'Cast here' : 'Use here'}</button>
            {/if}
            <button type="button" class="quiet" onclick={cancel}>Take it off</button>
            <button type="button" class={tools.mode === 'preview' && tools.preview?.cast ? 'quiet' : 'accent'} onclick={() => done(where)}>Done</button>
          </div>
        {/if}
      {/if}
    </div>
  {/if}
  {#if tools.list && tools.mode === ''}
    <div class="markslist" role="region" aria-label="Marks on the map">
      {#if !onScene.length}
        <p class="dim">No marks on the map.</p>
      {:else}
        <ul>
          {#each onScene as m (m.id)}
            {@const line = look ? markLine(m, look) : { who: String(m.name ?? ''), what: String(m.kind ?? ''), catches: [] }}
            <li>
              <span class="dot" style:background={String(m.color ?? '#fff')}></span>
              <span class="what">
                <strong>{line.who}</strong>: {line.what}{m.pinned ? ' (pinned)' : ''}{#if gm && m.private}<span class="dim"> · only you</span>{/if}
                {#if m.kind === 'template' || m.kind === 'preview'}<span class="dim catches"> · {catchWords(line.catches)}</span>{/if}
              </span>
              {#if (m.kind === 'template' || m.kind === 'preview') && where}
                {#each acts as act (act.plugin + '/' + act.action)}
                  <button type="button" class="quiet" disabled={!line.catches.length} title={act.hint || 'On the creatures it catches'} aria-label={`${act.label}: ${line.who}’s ${line.what}`} onclick={() => where && onTemplate(m as Dict, where, act)}>{act.label}</button>
                {/each}
              {/if}
              {#if String(m.owner ?? '') === owner}
                <button type="button" class="quiet" onclick={() => pinMark(m as Dict)}>{m.pinned ? 'Unpin' : 'Pin'}</button>
              {/if}
              {#if String(m.owner ?? '') === owner || gm}
                <button type="button" class="quiet" aria-label={`Take off ${line.who}’s ${String(m.kind)}`} onclick={() => removeMark(String(m.id))}>✕</button>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
      <div class="foot">
        <button type="button" class="quiet" disabled={mineCount === 0} onclick={clearMine}>Clear mine</button>
        {#if gm}<button type="button" class="quiet" disabled={!onScene.length} onclick={clearEveryone}>Clear everyone’s</button>{/if}
        <button type="button" class="quiet" onclick={() => (tools.list = false)}>Close</button>
      </div>
    </div>
  {/if}
{/if}

<style>
  /* (on the right, over the zoom: a card the DM reads lies over the map's left) */
  .tools {
    position: absolute;
    right: 10px;
    top: 10px;
    z-index: 5;
    display: flex;
    flex-direction: column;
    gap: 6px;
    /* (clear of the zoom buttons below it on a short screen: it scrolls) */
    max-height: calc(100% - 150px);
    overflow-y: auto;
    scrollbar-width: none;
  }
  .tools button {
    width: 52px;
    min-height: 46px;
    padding: 4px 2px 3px;
    border-radius: 10px;
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: rgba(22, 24, 29, 0.85);
    color: #e8e6e3;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
    cursor: pointer;
    backdrop-filter: blur(6px);
    font: inherit;
  }
  .tools button span {
    font-size: 0.6rem;
    line-height: 1.1;
    text-align: center;
  }
  .tools button:hover:not(:disabled) {
    background: rgba(40, 44, 52, 0.95);
  }
  .tools button:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .tools button.on {
    border-color: var(--accent, #e5a55a);
    color: var(--accent, #e5a55a);
  }
  .tools svg {
    width: 20px;
    height: 20px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linecap: round;
    stroke-linejoin: round;
  }
  .toolbar-banner {
    position: absolute;
    top: 10px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 7;
    width: min(640px, calc(100% - 20px));
    display: flex;
    flex-wrap: wrap;
    gap: 8px 10px;
    align-items: center;
    padding: 8px 10px 8px 14px;
    border-radius: 14px;
    background: var(--panel, #1c1f25);
    border: 1px solid var(--accent-soft, rgba(229, 165, 90, 0.4));
    box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);
  }
  .toolbar-banner .words {
    flex: 1 1 180px;
    min-width: 0;
  }
  .toolbar-banner .buttons {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-left: auto;
  }
  .toolbar-banner .form {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    align-items: center;
    flex-basis: 100%;
  }
  .toolbar-banner .num {
    display: inline-flex;
    align-items: center;
    gap: 4px;
  }
  .toolbar-banner .num input {
    width: 76px;
  }
  .markslist {
    position: absolute;
    right: 70px;
    top: 10px;
    z-index: 6;
    width: min(420px, calc(100% - 82px));
    max-height: 62%;
    overflow-y: auto;
    padding: 10px 12px;
    border-radius: 14px;
    background: var(--panel, #1c1f25);
    border: 1px solid var(--border, rgba(255, 255, 255, 0.12));
    box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);
  }
  .markslist ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .markslist li {
    display: flex;
    gap: 8px;
    align-items: center;
  }
  .markslist .what {
    flex: 1;
    min-width: 0;
    font-size: 0.9rem;
  }
  .markslist .dot {
    flex: none;
    width: 10px;
    height: 10px;
    border-radius: 999px;
    border: 1px solid rgba(0, 0, 0, 0.6);
  }
  .markslist .foot {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    justify-content: flex-end;
    margin-top: 8px;
  }
  .markslist p {
    margin: 0;
  }
  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
  }
</style>
