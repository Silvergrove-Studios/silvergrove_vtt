<!--
  The DM's Rules settings: each ruleset's settings as its manifest
  declares them (a choice, a switch, a number), the campaign's values.
  A change is checked, kept in the campaign and the rules loaded again
  with it: new characters are made the new way at once.
-->
<script lang="ts">
  import Modal from '../common/Modal.svelte';
  import { dmOp, game, notice, type Dict } from '../lib/game.svelte';

  let { onclose }: { onclose: () => void } = $props();

  const groups = $derived(((game.dm.rules as Dict[]) ?? []).filter((g) => g && Array.isArray(g.settings) && g.settings.length));

  function set(plugin: string, it: Dict, value: unknown): void {
    dmOp('rules_setting', { plugin, key: String(it.key), value });
    notice(`${it.title}: changed`);
  }

  function label(it: Dict, v: unknown): string {
    const i = ((it.enum as unknown[]) ?? []).indexOf(v);
    return i >= 0 ? String(((it.labels as unknown[]) ?? [])[i] ?? v) : String(v);
  }
</script>

<Modal title="Rules settings" wide {onclose}>
  {#if groups.length === 0}
    <p class="dim">This campaign's rules have no settings.</p>
  {/if}
  {#each groups as g (g.plugin)}
    <section>
      {#if groups.length > 1}<h3>{g.name}</h3>{/if}
      <ul>
        {#each g.settings as it (it.key)}
          <li>
            <div class="what">
              <span class="title">{it.title}</span>
              {#if it.description}<span class="dim small">{it.description}</span>{/if}
            </div>
            <div class="control">
              {#if Array.isArray(it.enum)}
                <select aria-label={String(it.title)} value={JSON.stringify(it.value)} onchange={(e) => set(String(g.plugin), it, JSON.parse((e.currentTarget as HTMLSelectElement).value))}>
                  {#each it.enum as v (JSON.stringify(v))}
                    <option value={JSON.stringify(v)}>{label(it, v)}</option>
                  {/each}
                </select>
              {:else if it.type === 'boolean'}
                <label class="switch">
                  <input type="checkbox" checked={it.value === true} onchange={(e) => set(String(g.plugin), it, (e.currentTarget as HTMLInputElement).checked)} />
                  <span>{it.value === true ? 'On' : 'Off'}</span>
                </label>
              {:else}
                <input
                  type="number"
                  aria-label={String(it.title)}
                  min={it.minimum}
                  max={it.maximum}
                  step={it.type === 'integer' ? 1 : 'any'}
                  value={Number(it.value ?? 0)}
                  onchange={(e) => set(String(g.plugin), it, Number((e.currentTarget as HTMLInputElement).value))}
                />
              {/if}
            </div>
          </li>
        {/each}
      </ul>
    </section>
  {/each}
</Modal>

<style>
  section + section {
    margin-top: 16px;
  }
  h3 {
    margin: 0 0 8px;
    font-family: var(--font-display);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }
  li {
    display: flex;
    gap: 16px;
    align-items: center;
    justify-content: space-between;
    padding: 10px 0;
    border-bottom: 1px solid var(--border-soft);
  }
  .what {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .title {
    line-height: 1.35;
  }
  .small {
    font-size: 0.85rem;
  }
  .control {
    flex: none;
  }
  select {
    max-width: 24em;
  }
  input[type='number'] {
    width: 6em;
  }
  .switch {
    display: inline-flex;
    gap: 8px;
    align-items: center;
  }
  @media (max-width: 560px) {
    li {
      flex-direction: column;
      align-items: stretch;
      gap: 6px;
    }
  }
</style>
