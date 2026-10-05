<!--
  Whether the players know a creature's name, at a table whose rules keep
  monsters' names from them: what they call it ("a creature (1)": its label
  on their maps, for the DM to call it by) and Reveal its name — or, told,
  Keep it hidden again. On its token's stat block in the fight, and its card.
-->
<script lang="ts">
  import { dmOp, game, type Dict } from '../lib/game.svelte';

  let { actor }: { actor: string } = $props();

  // (the DM's view and scene say, of a creature no player owns, whether the
  // players know its name; its token on the scene, the label they see it by)
  const tok = $derived(((game.scene.tokens as Dict[]) ?? []).find((t) => String(t.actor ?? '') === actor && typeof t.name_known === 'boolean'));
  const known = $derived.by((): boolean | null => {
    const a = ((game.view.actors ?? {}) as Dict)[actor];
    if (a && typeof a.name_known === 'boolean') return a.name_known;
    return tok ? tok.name_known === true : null;
  });
  const label = $derived(String(tok?.player_label ?? ''));
</script>

{#if known !== null}
  <div class="known" role="group" aria-label="Its name, to the players">
    {#if known === false}
      <span class="dim">To the players: a creature{label && label !== '?' && !tok?.hidden ? ` (${label})` : ''}</span>
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
