<!--
  A card the DM popped out of the book: a window of its own, kept up to
  date, for a second screen or beside the map. It is the DM's screen too
  (the same token), showing one card.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Card from './Card.svelte';
  import { comp, connect, game, intent, join } from '../lib/game.svelte';
  import { provideViewUi } from '../lib/views/context';
  import { pictureUrl } from '../lib/art';

  const params = new URLSearchParams(location.hash.slice(1));
  const token = params.get('t') ?? '';
  let ref = $state(params.get('ref') ?? '');

  provideViewUi({
    intent: (p) => {
      if (p?.kind === 'lookup') ref = `entry:${p.collection}/${p.id}`;
      else if (p?.kind === 'show' && p.actor) ref = `actor:${p.actor}`;
      else intent(p);
    },
    pick: () => {},
    comp,
    picture: pictureUrl,
  });

  onMount(() => {
    if (token)
      void connect('dm').then((ok) => {
        if (ok) join({ token });
      });
  });

  $effect(() => {
    history.replaceState(null, '', `#t=${encodeURIComponent(token)}&ref=${encodeURIComponent(ref)}`);
  });
</script>

<main class="window scroll">
  {#if !token}
    <p class="dim pad">Pop a card out from the DM’s screen.</p>
  {:else if !game.joined}
    <p class="dim pad">{game.error || 'Connecting to the table…'}</p>
  {:else}
    {#key ref}<Card {ref} onopen={(r) => (ref = r)} />{/key}
  {/if}
</main>

<style>
  .window {
    height: 100%;
    background: var(--panel);
  }
  .pad {
    padding: 24px;
  }
</style>
