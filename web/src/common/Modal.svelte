<!--
  A card over the page: a title, what it holds, a close button. Escape or
  a tap outside closes it (unless `sticky`). Full screen on a phone.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    title = '',
    onclose,
    wide = false,
    sticky = false,
    children,
    actions,
  }: { title?: string; onclose?: () => void; wide?: boolean; sticky?: boolean; children: Snippet; actions?: Snippet } = $props();

  function key(e: KeyboardEvent): void {
    if (e.key === 'Escape' && !sticky) onclose?.();
  }
</script>

<svelte:window onkeydown={key} />
<div class="backdrop" role="presentation" onclick={(e) => { if (e.target === e.currentTarget && !sticky) onclose?.(); }}>
  <div class="modal" class:wide role="dialog" aria-modal="true" aria-label={title}>
    <header>
      <h2>{title}</h2>
      {#if onclose}<button type="button" class="quiet close" aria-label="Close" onclick={() => onclose?.()}>✕</button>{/if}
    </header>
    <div class="body scroll">{@render children()}</div>
    {#if actions}<footer>{@render actions()}</footer>{/if}
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(5, 6, 8, 0.6);
    backdrop-filter: blur(3px);
    display: grid;
    place-items: center;
    z-index: 500;
    padding: 16px;
  }
  .modal {
    width: min(560px, 100%);
    max-height: min(86vh, 900px);
    display: flex;
    flex-direction: column;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 16px;
    box-shadow: var(--shadow);
    overflow: hidden;
  }
  .modal.wide {
    width: min(860px, 100%);
  }
  header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 16px 10px 20px;
    border-bottom: 1px solid var(--border-soft);
  }
  header h2 {
    flex: 1;
    font-size: 1.3rem;
  }
  .close {
    width: 36px;
    padding: 0;
  }
  /* a finger's worth (a playtest's phone player tapped the ✕ and had to use Escape) */
  @media (pointer: coarse) {
    .close {
      width: 44px;
      min-height: 44px;
      font-size: 1.1rem;
    }
  }
  .body {
    padding: 16px 20px 20px;
    flex: 1;
  }
  footer {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    padding: 12px 16px;
    border-top: 1px solid var(--border-soft);
  }
  @media (max-width: 600px) {
    .backdrop {
      padding: 0;
    }
    .modal,
    .modal.wide {
      width: 100%;
      height: 100%;
      max-height: none;
      border-radius: 0;
      border: 0;
      padding-top: env(safe-area-inset-top);
      padding-bottom: env(safe-area-inset-bottom);
    }
  }
</style>
