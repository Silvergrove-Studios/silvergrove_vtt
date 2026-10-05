<!--
  How this table runs, for a player: how much the app does here (the
  DM's level, in plain words), where fights happen, the house rules, and
  the answers a player notices (who rolls, what lands by itself, the
  rules options). Shown once on joining a table that has been set up, and
  from the ⋯ menu any time.
-->
<script lang="ts">
  import Modal from '../common/Modal.svelte';
  import { markdown } from '../lib/markdown';
  import type { PlayerSummary } from '../lib/tablesettings';

  let { summary, onclose }: { summary: PlayerSummary; onclose: () => void } = $props();
</script>

<Modal title="How this table runs" {onclose}>
  <div class="runs">
    <p class="level"><strong>{summary.title}</strong> <span class="dim">— {summary.tagline}</span></p>
    <ul class="lines">
      {#each summary.lines as line (line)}<li>{line}</li>{/each}
    </ul>
    <p><span class="dim">Fights:</span> {summary.space_title}. <span class="dim">{summary.space_words}</span></p>
    {#if summary.house_rules.trim()}
      <h3>House rules</h3>
      <div class="prose house">{@html markdown(summary.house_rules)}</div>
    {/if}
    {#each summary.answers as a (a.question)}
      <h3>{a.title}</h3>
      <ul class="answers">
        {#each a.items as it (it.title)}<li><span>{it.title}</span> <strong>{it.value}</strong></li>{/each}
      </ul>
    {/each}
    <p class="dim small">The DM can change any of this. It's here again in the ⋯ menu.</p>
  </div>
  {#snippet actions()}
    <button type="button" class="accent" onclick={onclose}>Got it</button>
  {/snippet}
</Modal>

<style>
  .runs h3 {
    margin: 14px 0 6px;
    font-size: 1.05rem;
  }
  .level {
    margin: 0 0 6px;
    font-size: 1.05rem;
  }
  .lines {
    margin: 0 0 10px;
    padding-left: 1.2em;
  }
  .lines li {
    margin: 3px 0;
  }
  .answers {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .answers li {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    padding: 5px 0;
    border-bottom: 1px solid var(--border-soft);
  }
  .answers strong {
    flex: none;
    text-align: right;
    max-width: 50%;
  }
  .house {
    border-left: 3px solid var(--accent-soft);
    padding-left: 10px;
  }
  .small {
    font-size: 0.85rem;
    margin-top: 14px;
  }
</style>
