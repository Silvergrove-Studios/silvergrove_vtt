<!--
  A player's characters: each one's sheet as its ruleset draws it. With
  none yet, the ruleset's character maker (the wizard in its status view),
  front and centre.
-->
<script lang="ts">
  import View from '../lib/views/View.svelte';
  import { game, myActors, type Dict } from '../lib/game.svelte';

  const mine = $derived(myActors());
  let chosen = $state('');
  const actor = $derived(mine.find((a) => a.id === chosen) ?? mine[0]);
  const status = $derived(((game.view.status as Dict[]) ?? []).filter((s) => s && typeof s === 'object'));

  /** The wizards in a view: how a player makes a character. */
  function wizards(node: unknown, out: Dict[] = []): Dict[] {
    if (Array.isArray(node)) node.forEach((n) => wizards(n, out));
    else if (node && typeof node === 'object') {
      const n = node as Dict;
      if (n.type === 'wizard') out.push(n);
      else for (const k of ['children', 'tabs', 'item']) if (n[k]) wizards(n[k], out);
    }
    return out;
  }

  const makers = $derived(status.flatMap((s) => wizards(s.schema).map((w) => ({ w, data: s.data as Dict }))));

  const DEFAULT_SHEET: Dict = {
    type: 'column',
    children: [
      { type: 'section', title: 'Numbers', children: [{ type: 'list', expr: '@derived', item: { type: 'text', expr: 'str(@item)' }, empty: 'nothing derived' }] },
      { type: 'section', title: 'Resources', children: [{ type: 'list', expr: '@resources', item: { type: 'text', expr: 'str(@item)' }, empty: 'none' }] },
      { type: 'section', title: 'Effects', children: [{ type: 'effects', bind: '/effects' }] },
    ],
  };
</script>

<div class="character scroll">
  {#if !game.view.actors}
    <p class="dim pad">Waiting for the table…</p>
  {:else if mine.length === 0}
    <section class="maker">
      <h2>Make your character</h2>
      <p class="dim">A few short steps and the table builds your sheet. If the DM made your character already, ask them to give it to you — it appears here.</p>
      {#each makers as m, i (i)}
        <div class="box"><View node={m.w} ctx={m.data} /></div>
      {:else}
        <p class="dim">This table’s rules have no character maker. Ask the DM for a character.</p>
      {/each}
    </section>
  {:else}
    {#if mine.length > 1}
      <div class="who" role="tablist">
        {#each mine as a (a.id)}
          <button type="button" role="tab" aria-selected={actor?.id === a.id} class:on={actor?.id === a.id} onclick={() => (chosen = String(a.id))}>{a.name}</button>
        {/each}
      </div>
    {/if}
    {#if actor}
      {#key actor.id}
        <div class="sheet">
          {#each (actor.sheets as Dict[]) ?? [] as sh, i (i)}
            <View node={sh.schema} ctx={sh.data} />
          {:else}
            <h2>{actor.name}</h2>
            <View node={DEFAULT_SHEET} ctx={{ actor, ext: actor.ext ?? {}, derived: actor.derived ?? {}, resources: actor.resources ?? {}, effects: actor.effects ?? [] }} />
          {/each}
          {#if actor.outdated && Object.keys(actor.outdated).length}
            <p class="dim">Built against older content: {Object.keys(actor.outdated).join(', ')}</p>
          {/if}
        </div>
      {/key}
    {/if}
  {/if}
</div>

<style>
  .character {
    height: 100%;
    padding: 16px 16px 32px;
  }
  .pad {
    padding: 16px 0;
  }
  .maker {
    max-width: 620px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .maker h2 {
    font-size: 1.6rem;
  }
  .box {
    padding: 16px;
    border-radius: 14px;
    background: var(--panel);
    border: 1px solid var(--border);
  }
  .who {
    display: flex;
    gap: 6px;
    margin-bottom: 12px;
    overflow-x: auto;
  }
  .who button.on {
    background: var(--accent-bg);
    border-color: var(--accent);
  }
  .sheet {
    max-width: 760px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .sheet :global(.header) {
    font-family: var(--font-display);
    font-size: 1.5rem;
    color: var(--heading);
  }
</style>
