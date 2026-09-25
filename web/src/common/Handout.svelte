<!-- Something the DM showed: its picture and its words, over everything until closed. -->
<script lang="ts">
  import Modal from './Modal.svelte';
  import { markdown } from '../lib/markdown';
  import { pictureUrl } from '../lib/art';
  import type { Dict } from '../lib/game.svelte';

  let { handout, onclose, closeLabel = 'Close — it is in your Journal' }: { handout: Dict; onclose: () => void; closeLabel?: string } = $props();
  const img = $derived(handout.image ? pictureUrl(String(handout.image)) : '');
</script>

<Modal title={String(handout.title || 'From the DM')} wide {onclose}>
  <div class="shown">
    {#if img}<img src={img} alt={String(handout.title ?? '')} />{/if}
    {#if String(handout.text ?? '').trim()}
      <div class="prose">{@html markdown(String(handout.text))}</div>
    {/if}
  </div>
  {#snippet actions()}
    <button type="button" class="accent" onclick={onclose}>{closeLabel}</button>
  {/snippet}
</Modal>

<style>
  .shown {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  img {
    width: 100%;
    max-height: 60vh;
    object-fit: contain;
    border-radius: 10px;
    background: #0b0c0f;
  }
  .prose {
    font-size: 1.05rem;
  }
</style>
