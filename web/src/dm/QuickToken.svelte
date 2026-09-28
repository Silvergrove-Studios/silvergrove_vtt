<!--
  A token for a thing or a person with no stat block — a cart, a villager,
  a bell frame — on the DM's battle map: a name, the initials it shows (its
  name's, unless given), a colour, whether the players see it; then a tap
  on the map puts it there. A playtest's DM couldn't put the peddler's cart,
  nor the two on the bell rope, on the map, and described them instead.
-->
<script lang="ts">
  let { onplace }: { onplace: (spec: { name: string; label: string; color: string; hidden: boolean }) => void } = $props();

  // a few colours that read on any map, apart from the party's and the creatures' crimson
  const COLORS: [string, string][] = [
    ['#8a6a3a', 'brown'],
    ['#6b7a8f', 'slate'],
    ['#4f8a5b', 'green'],
    ['#b08d2e', 'gold'],
    ['#7a4f8a', 'purple'],
    ['#d8d8d8', 'white'],
  ];
  let open = $state(false);
  let name = $state('');
  let label = $state('');
  let color = $state(COLORS[0][0]);
  let hidden = $state(false);

  /** The initials a name shows: its first two words', or its first two letters. */
  function initials(n: string): string {
    const words = n.trim().split(/\s+/).filter(Boolean);
    if (!words.length) return '';
    return (words[0][0] + (words.length > 1 ? words[1][0] : (words[0][1] ?? ''))).toUpperCase();
  }

  function place(): void {
    if (!name.trim()) return;
    onplace({ name: name.trim(), label: (label.trim() || initials(name)).toUpperCase().slice(0, 3), color, hidden });
    open = false;
    name = '';
    label = '';
    hidden = false;
  }
</script>

<div class="quick">
  <button type="button" class="quiet toggle" aria-expanded={open} title="A token for a thing or a person with no stat block: a cart, a villager" onclick={() => (open = !open)}>+ A token</button>
  {#if open}
    <form class="pop" aria-label="A token with no stat block" onsubmit={(e) => { e.preventDefault(); place(); }}>
      <label>Name <input type="text" bind:value={name} placeholder="Vask’s cart" maxlength="40" /></label>
      <label>Initials <input type="text" class="short" bind:value={label} placeholder={initials(name) || 'VC'} maxlength="3" /></label>
      <fieldset>
        <legend>Colour</legend>
        {#each COLORS as [c, word] (c)}
          <label class="swatch" title={word}><input type="radio" name="quick-color" value={c} bind:group={color} aria-label={word} /><span style:background={c}></span></label>
        {/each}
      </fieldset>
      <label class="check"><input type="checkbox" bind:checked={hidden} /> Hidden from the players</label>
      <div class="btns">
        <button type="button" class="quiet" onclick={() => (open = false)}>Cancel</button>
        <button type="submit" class="accent" disabled={!name.trim()}>Put it on the map</button>
      </div>
    </form>
  {/if}
</div>

<style>
  .quick {
    position: relative;
  }
  .toggle {
    min-height: 30px;
    padding: 2px 10px;
    border: 1px solid var(--border);
    border-radius: 999px;
    color: var(--muted);
  }
  .pop {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    z-index: 30;
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: 280px;
    padding: 12px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 12px;
    box-shadow: var(--shadow);
  }
  .pop label {
    display: flex;
    flex-direction: column;
    gap: 3px;
    font-size: 0.85rem;
    color: var(--muted);
  }
  .pop input[type='text'] {
    color: var(--text);
  }
  .short {
    width: 5em;
    text-transform: uppercase;
  }
  fieldset {
    display: flex;
    gap: 6px;
    margin: 0;
    padding: 0;
    border: 0;
  }
  legend {
    font-size: 0.85rem;
    color: var(--muted);
    margin-bottom: 3px;
  }
  .swatch {
    position: relative;
  }
  .swatch input {
    position: absolute;
    opacity: 0;
    inset: 0;
    margin: 0;
    cursor: pointer;
  }
  .swatch span {
    display: block;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    border: 2px solid rgba(0, 0, 0, 0.6);
  }
  .swatch input:checked + span {
    box-shadow: 0 0 0 2px var(--accent);
  }
  .swatch input:focus-visible + span {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }
  .pop .check {
    flex-direction: row;
    align-items: center;
    gap: 6px;
  }
  .btns {
    display: flex;
    justify-content: flex-end;
    gap: 6px;
  }
</style>
