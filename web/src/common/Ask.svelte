<!--
  A question in the table's own words, over the page: yes or no, or a name
  to type. The web screens never use the browser's bare confirm or prompt
  (a playtest's stray click by the map landed on Leave, a bare "OK" took
  it, and the player was out of the table). Enter says yes; Escape, a tap
  outside or the other button says no.
-->
<script lang="ts">
  import Modal from './Modal.svelte';

  let {
    title,
    text = '',
    value = null,
    placeholder = '',
    yes = 'OK',
    no = 'Cancel',
    danger = false,
    onanswer,
  }: {
    title: string;
    text?: string;
    /** A name to type, starting as this; null for a yes or no. */
    value?: string | null;
    placeholder?: string;
    yes?: string;
    no?: string;
    danger?: boolean;
    /** What was typed (or true, for a yes); null for no. */
    onanswer: (answer: string | true | null) => void;
  } = $props();

  // (what was typed, starting from the name it was asked with)
  // svelte-ignore state_referenced_locally
  let typed = $state(value ?? '');
  function ok(): void {
    onanswer(value === null ? true : typed);
  }
</script>

<Modal {title} onclose={() => onanswer(null)}>
  <form class="ask" onsubmit={(e) => { e.preventDefault(); ok(); }}>
    {#if text}<p>{text}</p>{/if}
    {#if value !== null}
      <!-- svelte-ignore a11y_autofocus -->
      <input type="text" bind:value={typed} {placeholder} aria-label={text || title} autofocus />
    {/if}
  </form>
  {#snippet actions()}
    <button type="button" class="quiet" onclick={() => onanswer(null)}>{no}</button>
    <button type="button" class={danger ? 'danger' : 'accent'} onclick={ok}>{yes}</button>
  {/snippet}
</Modal>

<style>
  .ask {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .ask p {
    margin: 0;
  }
  .ask input {
    width: 100%;
  }
</style>
