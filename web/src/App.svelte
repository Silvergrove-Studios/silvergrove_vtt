<!--
  One page for every screen the Table serves; the path decides whose:
  /dm the DM's, /dm/card a card the DM popped out, anything else a
  player's.
-->
<script lang="ts">
  import PlayerApp from './player/PlayerApp.svelte';
  import DmApp from './dm/DmApp.svelte';
  import CardWindow from './dm/CardWindow.svelte';
  import Notices from './common/Notices.svelte';

  const path = location.pathname.replace(/\/+$/, '') || '/';
</script>

{#if path === '/dm/card'}
  <CardWindow />
{:else if path === '/dm'}
  <DmApp />
{:else}
  <PlayerApp />
{/if}
<Notices />
