<!--
  Over the map while a fight is on: which fight, the round, whose turn,
  and the buttons that run it — roll initiative, next turn, end the fight.
-->
<script lang="ts">
  import { dmOp, game, intent, type Dict } from '../lib/game.svelte';
  import Modal from '../common/Modal.svelte';
  import { initiativeAction, orderRows } from './fight';

  let { fight }: { fight: Dict } = $props();
  const turns = $derived((game.scene.turns ?? {}) as Dict);
  const rows = $derived(orderRows(game.scene));
  const up = $derived(rows.find((r) => r.current));
  const roll = $derived(initiativeAction(game.view));
  let ending = $state(false);
  // one step at a time: a button waits for the turn to move (or three seconds);
  // a playtest's DM double-clicked Next turn on a slow table and skipped a turn
  let stepping = $state(false);
  let steppedFrom = '';
  $effect(() => {
    const now = `${turns.round}/${turns.turn}/${turns.running}`;
    if (stepping && now !== steppedFrom) stepping = false;
  });
  function step(what: string): void {
    if (stepping) return;
    stepping = true;
    steppedFrom = `${turns.round}/${turns.turn}/${turns.running}`;
    dmOp('turns', { do: what });
    setTimeout(() => (stepping = false), 3000);
  }
</script>

<div class="fightbar" role="region" aria-label="The fight">
  <span class="swords" aria-hidden="true">⚔</span>
  <div class="what">
    <strong>{fight.name ?? 'A fight'}</strong>
    {#if turns.running}
      <span>Round {turns.round ?? 1}{up ? ` · ${up.name}’s turn` : ''}</span>
    {:else}
      <span class="dim">Not started: roll initiative when everyone is ready.</span>
    {/if}
  </div>
  <div class="buttons">
    {#if turns.running}
      <button type="button" disabled={stepping} onclick={() => step('previous')}>‹ Back</button>
      <button type="button" class="accent" disabled={stepping} onclick={() => step('next')}>Next turn ›</button>
    {:else if roll}
      <button type="button" class="accent" onclick={() => intent({ kind: 'action', plugin: roll.plugin, action: roll.action, ctx: { scene: String(game.scene.id ?? '') } })}>Roll initiative</button>
    {:else}
      <button type="button" class="accent" disabled={stepping} onclick={() => step('start')}>Start turns</button>
    {/if}
    <button type="button" class="quiet" onclick={() => (ending = true)}>End the fight</button>
  </div>
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
</style>
