<!--
  The table as a player sees it: whose turn, the day, questions for them,
  rolls they may help with, the ruleset's status views (the party at a
  glance), and tracks.
-->
<script lang="ts">
  import View from '../lib/views/View.svelte';
  import { game, intent, type Dict } from '../lib/game.svelte';
  import { turnSummary } from '../lib/turns';

  const v = $derived(game.view);
  const turn = $derived(turnSummary(game.scene, game.me));
  const clock = $derived((v.clock ?? {}) as Dict);
  const rolls = $derived(((v.rolls as Dict[]) ?? []).filter((r) => r && typeof r === 'object'));
  const tracks = $derived(((v.tracks as Dict[]) ?? []).filter((t) => t && typeof t === 'object'));
  const status = $derived(((v.status as Dict[]) ?? []).filter((s) => s && typeof s === 'object'));

  function time(m: number): string {
    return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  }
</script>

<div class="pane scroll">
  <header>
    <h2 class:mine={turn.mine}>{turn.text}</h2>
    {#if clock.day !== undefined}
      <p class="dim">Day {clock.day ?? 1}, {time(Number(clock.minute ?? 0))}{Number(clock.session ?? 0) > 0 ? ` · session ${clock.session}` : ''}</p>
    {/if}
  </header>
  {#if (v.prompts ?? []).length}
    <section>
      <h3>For you</h3>
      {#each v.prompts as _p, i (i)}
        <View node={{ type: 'prompt', bind: `/prompts/${i}` }} ctx={v} />
      {/each}
    </section>
  {/if}
  {#if rolls.length}
    <section>
      <h3>Open rolls</h3>
      {#each rolls as r (r.id)}
        <div class="roll">
          <span>{r.label ?? 'A roll'} <span class="dim">({r.by ?? ''})</span></span>
          <button type="button" onclick={() => intent({ kind: 'contribute', roll: String(r.id ?? ''), name: `help_${game.me}`, expr: '1d6' })}>Help (1d6)</button>
        </div>
      {/each}
    </section>
  {/if}
  {#each status as st (st.plugin)}
    <section class="status"><View node={st.schema} ctx={st.data} /></section>
  {/each}
  {#if tracks.length}
    <section>
      <h3>Tracks</h3>
      {#each tracks as _t, i (i)}<View node={{ type: 'tracker', bind: `/tracks/${i}` }} ctx={v} />{/each}
    </section>
  {/if}
</div>

<style>
  .pane {
    height: 100%;
    padding: 16px 16px 32px;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }
  header h2 {
    font-size: 1.4rem;
  }
  header h2.mine {
    color: var(--accent);
  }
  section {
    display: flex;
    flex-direction: column;
    gap: 10px;
    max-width: 760px;
  }
  section h3 {
    font-size: 1.05rem;
  }
  .roll {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 10px;
  }
</style>
