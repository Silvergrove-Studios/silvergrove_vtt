<!-- What the table said just now: a refusal, a saved note, a join. -->
<script lang="ts">
  import { game } from '../lib/game.svelte';
</script>

<div class="notices" aria-live="polite">
  {#each game.notices as n (n.id)}
    <div class="notice" class:error={n.kind === 'error'}>{n.text}</div>
  {/each}
</div>

<style>
  .notices {
    position: fixed;
    left: 50%;
    bottom: calc(16px + env(safe-area-inset-bottom));
    transform: translateX(-50%);
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: center;
    z-index: 1000;
    pointer-events: none;
    width: min(560px, calc(100% - 24px));
  }
  .notice {
    padding: 10px 16px;
    border-radius: 12px;
    background: rgba(32, 36, 44, 0.96);
    border: 1px solid var(--border);
    box-shadow: var(--shadow);
    text-align: center;
  }
  .notice.error {
    border-color: rgba(227, 107, 91, 0.6);
    color: #ffd6cf;
  }
</style>
