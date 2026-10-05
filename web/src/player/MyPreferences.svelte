<!--
  My preferences: what a player chooses for themselves, where the DM's table
  lets them — their dice (the app's, or their own typed in), whether they're
  asked about their reactions, the extras the rules say they can add. Each
  change is kept as it's made (on their record at the table: the DM sees it,
  and can change it). From the ⋯ menu.
-->
<script lang="ts">
  import Modal from '../common/Modal.svelte';
  import { game, notice, submit } from '../lib/game.svelte';
  import { prefOwn, prefValue, valueWords, same, type Pref } from '../lib/tablesettings';

  let { prefs, onclose }: { prefs: Pref[]; onclose: () => void } = $props();
  let busy = $state('');

  async function set(p: Pref, value: unknown): Promise<void> {
    busy = p.id;
    const r = await submit({ kind: 'prefs', plugin: p.plugin, key: p.key, value });
    busy = '';
    if (r.ok) notice(`${p.title}: ${valueWords(p, value)}`);
  }
</script>

<Modal title="My preferences" {onclose}>
  <div class="prefs">
    {#if !prefs.length}
      <p class="dim">This table chooses these for everyone: nothing is yours to set here now.</p>
    {/if}
    {#each prefs as p (p.id)}
      {@const v = prefValue(game.players, game.me, p)}
      <div class="pref">
        <div class="what">
          <span class="title">{p.title}</span>
          {#if p.description}<span class="dim small">{p.description}</span>{/if}
          {#if !prefOwn(game.players, game.me, p)}<span class="dim small">As the table has it, until you choose.</span>{/if}
        </div>
        <div class="control">
          {#if Array.isArray(p.enum)}
            <select aria-label={p.title} value={JSON.stringify(v)} disabled={busy === p.id} onchange={(e) => set(p, JSON.parse((e.currentTarget as HTMLSelectElement).value))}>
              {#each p.enum as c, i (JSON.stringify(c))}
                <option value={JSON.stringify(c)} selected={same(c, v)}>{(p.labels ?? [])[i] ?? String(c)}</option>
              {/each}
            </select>
          {:else if p.type === 'boolean'}
            <label class="switch">
              <input type="checkbox" aria-label={p.title} checked={v === true} disabled={busy === p.id} onchange={(e) => set(p, (e.currentTarget as HTMLInputElement).checked)} />
              <span>{v === true ? 'On' : 'Off'}</span>
            </label>
          {/if}
        </div>
      </div>
    {/each}
    <p class="dim small">Kept as you choose. The DM can change any of it.</p>
  </div>
  {#snippet actions()}
    <button type="button" class="accent" onclick={onclose}>Done</button>
  {/snippet}
</Modal>

<style>
  .prefs {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .pref {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding-bottom: 12px;
    border-bottom: 1px solid var(--border-soft);
  }
  .what {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .title {
    font-weight: 600;
  }
  .small {
    font-size: 0.85rem;
  }
  .control select {
    width: 100%;
  }
  .switch {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }
</style>
