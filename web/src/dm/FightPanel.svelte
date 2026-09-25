<!--
  The fight, beside the map: the turn order (tap one to choose it), and the
  chosen creature — hidden or seen, its stat block, its actions. An action
  that needs a target asks for one on the map.
-->
<script lang="ts">
  import View from '../lib/views/View.svelte';
  import { dmOp, game, type Dict } from '../lib/game.svelte';
  import { orderRows } from './fight';

  let { selected = '', onselect, onopen }: { selected?: string; onselect: (id: string) => void; onopen: (ref: string) => void } = $props();

  const rows = $derived(orderRows(game.scene));
  const tokens = $derived((game.scene.tokens as Dict[]) ?? []);
  const token = $derived(tokens.find((t) => t.id === selected));
  const actor = $derived(token?.actor ? ((game.view.actors ?? {}) as Dict)[String(token.actor)] : undefined);
  const hiddenOnes = $derived(tokens.filter((t) => t.hidden && t.actor));
  const scene = $derived(String(game.scene.id ?? ''));
</script>

<div class="panel scroll">
  {#if rows.length}
    <section>
      <h3>Turn order</h3>
      <ol class="order">
        {#each rows as r (r.entry)}
          <li>
            <button type="button" class="row" class:current={r.current} class:on={r.ids.includes(selected)} onclick={() => onselect(r.ids[0] ?? '')}>
              <span class="init">{r.label}</span>
              <span class="name">{r.name}</span>
              {#if r.hidden}<span class="tag">hidden</span>{/if}
            </button>
          </li>
        {/each}
      </ol>
    </section>
  {/if}
  {#if hiddenOnes.length}
    <section class="hidden">
      <p class="dim">{hiddenOnes.length} hidden from the players.</p>
      <button type="button" onclick={() => hiddenOnes.forEach((t) => dmOp('token', { scene, id: t.id, hidden: false }))}>Reveal them all</button>
    </section>
  {/if}
  {#if token}
    <section class="chosen">
      <div class="who">
        {#if !actor}<h3>{token.name}</h3>{/if}
        <div class="tools">
          <button type="button" onclick={() => dmOp('token', { scene, id: token.id, hidden: !token.hidden })}>{token.hidden ? 'Reveal' : 'Hide'}</button>
          {#if token.actor}<button type="button" class="quiet" onclick={() => onopen(`actor:${token.actor}`)}>Open the card</button>{/if}
        </div>
      </div>
      {#if actor}
        {#each (actor.sheets as Dict[]) ?? [] as sh, i (i)}
          <View node={sh.schema} ctx={sh.data} />
        {/each}
      {:else}
        <p class="dim">No rules behind this token.</p>
      {/if}
    </section>
  {:else}
    <p class="dim hint">Tap a creature on the map, or in the order, to see its stat block and act with it.</p>
  {/if}
</div>

<style>
  .panel {
    height: 100%;
    padding: 12px 14px 32px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  h3 {
    font-size: 1rem;
    margin: 0 0 6px;
  }
  .order {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .row {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    text-align: left;
    border: 1px solid transparent;
    background: none;
    padding: 6px 8px;
    min-height: 36px;
    border-radius: 8px;
  }
  .row.on {
    border-color: rgba(255, 255, 77, 0.5);
  }
  .row.current {
    background: rgba(255, 215, 90, 0.14);
    color: var(--heading);
    font-weight: 600;
  }
  .init {
    min-width: 26px;
    text-align: right;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .name {
    flex: 1;
  }
  .tag {
    font-size: 0.75rem;
    color: var(--muted);
    border: 1px dashed var(--muted);
    border-radius: 999px;
    padding: 0 7px;
  }
  .hidden {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .hidden p {
    margin: 0;
  }
  .chosen {
    display: flex;
    flex-direction: column;
    gap: 10px;
    border-top: 1px solid var(--border-soft);
    padding-top: 12px;
  }
  .who {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    flex-wrap: wrap;
  }
  .who h3 {
    font-family: var(--font-display);
    font-size: 1.35rem;
    margin: 0;
  }
  .tools {
    display: flex;
    gap: 4px;
  }
  .hint {
    margin: 8px 0;
  }
</style>
