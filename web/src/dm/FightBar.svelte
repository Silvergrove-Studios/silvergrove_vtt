<!--
  Over the map while a fight is on: which fight, the round, whose turn
  (and who ended the one before), and the buttons that run it — roll
  initiative, next turn, end the fight.
-->
<script lang="ts">
  import { dmOp, game, intent, type Dict } from '../lib/game.svelte';
  import Modal from '../common/Modal.svelte';
  import { endedByPlayer, initiativeAction, nothingSince, orderRows } from './fight';

  let { fight }: { fight: Dict } = $props();
  const turns = $derived((game.scene.turns ?? {}) as Dict);
  const rows = $derived(orderRows(game.scene));
  const up = $derived(rows.find((r) => r.current));
  const roll = $derived(initiativeAction(game.view));
  const players = $derived(game.players.map((p) => String(p.id)));
  // the turn before this one, ended from a player's sheet
  const ended = $derived(endedByPlayer(game.scene, players));
  let ending = $state(false);
  // Next with nothing done since a player ended their turn: asked first
  let asking = $state<{ ended: string; up: string } | null>(null);
  // one step at a time: a button waits for the turn to move (or three seconds);
  // a playtest's DM double-clicked Next turn on a slow table and skipped a turn
  let stepping = $state(false);
  let steppedFrom = '';
  let askedAt = '';
  $effect(() => {
    const now = `${turns.round}/${turns.turn}/${turns.running}`;
    if (stepping && now !== steppedFrom) stepping = false;
    // (the turn moved while the question was up: it no longer stands)
    if (asking && now !== askedAt) asking = null;
  });
  function next(): void {
    if (stepping) return;
    const quiet = nothingSince(game.scene, (game.view.log as Dict[]) ?? [], players);
    if (quiet) {
      asking = quiet;
      askedAt = `${turns.round}/${turns.turn}/${turns.running}`;
      return;
    }
    step('next');
  }
  function step(what: string): void {
    if (stepping) return;
    asking = null;
    stepping = true;
    steppedFrom = `${turns.round}/${turns.turn}/${turns.running}`;
    // Next says the turn it ends: one a player ended meanwhile is not ended twice
    dmOp('turns', what === 'next' ? { do: what, from: { round: turns.round, turn: turns.turn } } : { do: what });
    setTimeout(() => (stepping = false), 3000);
  }
</script>

<div class="fightbar" role="region" aria-label="The fight">
  <span class="swords" aria-hidden="true">⚔</span>
  <div class="what">
    <strong>{fight.name ?? 'A fight'}</strong>
    {#if turns.running}
      <span>Round {turns.round ?? 1}{up ? ` · ${up.name}’s turn` : ''}{#if ended}<span class="dim"> · {ended} ended their turn</span>{/if}</span>
    {:else}
      <span class="dim">Not started: roll initiative when everyone is ready.</span>
    {/if}
  </div>
  {#if asking}
    <div class="buttons ask" role="group" aria-label="End this turn too?">
      <span>{asking.ended} already ended their turn. End {asking.up}’s turn too?</span>
      <button type="button" class="accent" disabled={stepping} onclick={() => step('next')}>End {asking.up}’s turn</button>
      <button type="button" class="quiet" onclick={() => (asking = null)}>Not yet</button>
    </div>
  {:else}
    <div class="buttons">
      {#if turns.running}
        <button type="button" disabled={stepping} onclick={() => step('previous')}>‹ Back</button>
        <button type="button" class="accent" disabled={stepping} onclick={next}>Next turn ›</button>
      {:else if roll}
        <button type="button" class="accent" onclick={() => intent({ kind: 'action', plugin: roll.plugin, action: roll.action, ctx: { scene: String(game.scene.id ?? '') } })}>Roll initiative</button>
      {:else}
        <button type="button" class="accent" disabled={stepping} onclick={() => step('start')}>Start turns</button>
      {/if}
      <button type="button" class="quiet" onclick={() => (ending = true)}>End the fight</button>
    </div>
  {/if}
</div>
<!-- a question that can't be left behind (a playtest's DM went to another tab
     past an inline one, and the fight never ended) -->
{#if ending}
  <Modal title="End the fight?" onclose={() => (ending = false)}>
    <p>{fight.name ?? 'The fight'} ends: its creatures leave the map, the party keeps its wounds, and whatever lasted rounds is over.</p>
    {#snippet actions()}
      <button type="button" class="quiet" onclick={() => (ending = false)}>Not yet</button>
      <button type="button" class="danger" onclick={() => { ending = false; dmOp('end_fight'); }}>End the fight</button>
    {/snippet}
  </Modal>
{/if}

<style>
  .fightbar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 12px;
    background: linear-gradient(180deg, rgba(60, 22, 18, 0.96), rgba(40, 16, 14, 0.96));
    border-bottom: 1px solid rgba(227, 107, 91, 0.4);
    flex-wrap: wrap;
  }
  .swords {
    font-size: 1.3rem;
    color: #ff9d8a;
  }
  .what {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 180px;
  }
  .buttons {
    display: flex;
    gap: 6px;
    align-items: center;
    flex-wrap: wrap;
  }
  .ask span {
    font-weight: 600;
    margin-right: 4px;
  }
</style>
