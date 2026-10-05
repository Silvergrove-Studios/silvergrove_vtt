<!--
  Whether the players know a creature's name, at a table whose rules keep
  monsters' names from them: what they call it ("a creature (1)": its label
  on their maps, for the DM to call it by) and Reveal its name — or, told,
  Keep it hidden again. On its token's stat block in the fight, and its card.
-->
<script lang="ts">
  import { dmOp, game, type Dict } from '../lib/game.svelte';

  let { actor }: { actor: string } = $props();

  // (the DM's scene says, of a creature no player owns, whether the players know its name)
  const tok = $derived(((game.scene.tokens as Dict[]) ?? []).find((t) => String(t.actor ?? '') === actor && typeof t.name_known === 'boolean'));
  const label = $derived(String(tok?.player_label ?? ''));
</script>

{#if tok}
  <div class="known" role="group" aria-label="Its name, to the players">
    {#if tok.name_known === false}
      <span class="dim">To the players: a creature{label && label !== '?' ? ` (${label})` : ''}</span>
      <button type="button" class="quiet" onclick={() => dmOp('reveal_names', { actors: [actor], known: true })}>Reveal its name</button>
    {:else}
      <span class="dim">The players know its name</span>
      <button type="button" class="quiet" onclick={() => dmOp('reveal_names', { actors: [actor], known: false })}>Keep it hidden</button>
    {/if}
  </div>
{/if}

<style>
  .known {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    flex-wrap: wrap;
    font-size: 0.9rem;
  }
</style>
