<!--
  What the table waits on: a player's reaction (Shield against a hit, an
  opportunity attack), said to everyone with the seconds it has left, so
  nobody takes the pause for a stuck table. The DM's can go on without
  waiting: the card is answered with its default (no reaction), and the
  fight goes on; or answer it for them (`onanswer`: the DM's screen opens
  the player's own card — a hit's choice of damage type, whose default
  chooses nothing). A screen's own card isn't in it: that card is in front —
  but one the DM put aside (`putOff`: an outcome to approve, a monster's
  reaction) waits here, with Open to bring it back and Go on.
-->
<script lang="ts">
  import { game, submit, type Dict } from '../lib/game.svelte';
  import { clock } from '../lib/clock.svelte';
  import { secondsLeft, waitingOn, waitingText } from '../lib/prompts';

  let {
    dm = false,
    onanswer,
    putOff = [],
    onreopen,
  }: { dm?: boolean; onanswer?: (id: string, who: string) => void; putOff?: string[]; onreopen?: (id: string) => void } = $props();
  const list = $derived(waitingOn(game.view.waiting as Dict[], game.me, dm, putOff));
  // the cards the DM's view has (all of them): one of these the DM can answer for its player
  const open = $derived(new Set(((game.view.prompts as Dict[]) ?? []).filter((p) => p && typeof p === 'object').map((p) => String(p.id ?? ''))));
  let going = $state<string[]>([]);
  function goOn(w: Dict): void {
    const id = String(w.id ?? '');
    if (!id || going.includes(id)) return;
    going = [...going, id];
    const answer = { ...(w.default && typeof w.default === 'object' ? (w.default as Dict) : {}), waved: true };
    void submit({ kind: 'answer', prompt: id, answer }).then(() => (going = going.filter((x) => x !== id)));
  }
</script>

{#if list.length}
  <div class="waitstrip" class:dm role="status" aria-label="What the table waits on">
    {#each list as w (String(w.id))}
      {@const mine = dm && String(w.to ?? '') === 'gm'}
      <div class="wait">
        <span class="pulse" aria-hidden="true"></span>
        <span class="words">{waitingText(w, game.me, secondsLeft(w, game.viewAt, clock.now), dm)}</span>
        {#if dm}
          {#if mine}
            <button type="button" class="quiet" onclick={() => onreopen?.(String(w.id))} title="Your card, in front again">Open</button>
          {:else if onanswer && open.has(String(w.id))}
            <button type="button" class="quiet" onclick={() => onanswer?.(String(w.id), String(w.who ?? ''))}
              title="Their card, to answer for them">Answer</button>
          {/if}
          <button type="button" class="quiet" disabled={going.includes(String(w.id))} onclick={() => goOn(w)}
            title={mine ? 'Go on without answering it now: what it holds waits for you (the log keeps it)' : 'Answer for them with the card’s default (no reaction; a hit’s extra damage left to you), and go on'}>Go on</button>
        {/if}
      </div>
    {/each}
  </div>
{/if}

<style>
  .waitstrip {
    display: flex;
    flex-direction: column;
    gap: 4px;
    align-items: center;
    pointer-events: none;
  }
  .wait {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    max-width: 100%;
    padding: 5px 12px;
    border-radius: 999px;
    border: 1px solid var(--accent-soft);
    background: var(--panel);
    box-shadow: var(--shadow);
    font-size: 0.9rem;
  }
  .dm .wait {
    pointer-events: auto;
  }
  .words {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .pulse {
    flex: none;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
    animation: pulse 1.2s ease-in-out infinite;
  }
  .wait button {
    flex: none;
    min-height: 28px;
    padding: 2px 10px;
  }
  @keyframes pulse {
    50% {
      opacity: 0.3;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .pulse {
      animation: none;
    }
  }
</style>
