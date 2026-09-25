<!--
  Over the map while a fight is on: which fight, the round, whose turn,
  and the buttons that run it — roll initiative, next turn, end the fight.
-->
<script lang="ts">
  import { dmOp, game, intent, type Dict } from '../lib/game.svelte';
  import { initiativeAction, orderRows } from './fight';

  let { fight }: { fight: Dict } = $props();
  const turns = $derived((game.scene.turns ?? {}) as Dict);
  const rows = $derived(orderRows(game.scene));
  const up = $derived(rows.find((r) => r.current));
  const roll = $derived(initiativeAction(game.view));
  let ending = $state(false);
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
      <button type="button" onclick={() => dmOp('turns', { do: 'previous' })}>‹ Back</button>
      <button type="button" class="accent" onclick={() => dmOp('turns', { do: 'next' })}>Next turn ›</button>
    {:else if roll}
      <button type="button" class="accent" onclick={() => intent({ kind: 'action', plugin: roll.plugin, action: roll.action, ctx: { scene: String(game.scene.id ?? '') } })}>Roll initiative</button>
    {:else}
      <button type="button" class="accent" onclick={() => dmOp('turns', { do: 'start' })}>Start turns</button>
    {/if}
    {#if ending}
      <span class="confirm">
        End it? The creatures leave; the party keeps its wounds.
        <button type="button" class="danger" onclick={() => { ending = false; dmOp('end_fight'); }}>End the fight</button>
        <button type="button" class="quiet" onclick={() => (ending = false)}>Not yet</button>
      </span>
    {:else}
      <button type="button" class="quiet" onclick={() => (ending = true)}>End the fight</button>
    {/if}
  </div>
</div>

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
  .confirm {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.9rem;
  }
</style>
