<!--
  A button whose press goes to the table and waits for its answer: busy (a
  small spinner, and a second press does nothing) until the table says it
  is done or refuses it, then ✓ for a moment. A refusal says why where the
  table's refusals always do. A playtest's players pressed Cast and Gain a
  level twice because nothing on screen said the first press had gone, and
  a cleric went from level 1 to 3. `act` returns the answer to wait for,
  or nothing when there is none to wait for (a pick goes to the map; a
  lookup opens on this page).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    act,
    label = '',
    accent = false,
    danger = false,
    quiet = false,
    title = '',
    disabled = false,
    class: cls = '',
    children,
  }: {
    act: () => Promise<{ ok: boolean }> | void;
    label?: string;
    accent?: boolean;
    danger?: boolean;
    quiet?: boolean;
    title?: string;
    disabled?: boolean;
    class?: string;
    children?: Snippet;
  } = $props();

  // '' ready; 'working' sent, waiting; 'done' taken (✓)
  let phase = $state<'' | 'working' | 'done'>('');
  let timer: ReturnType<typeof setTimeout> | undefined;
  $effect(() => () => clearTimeout(timer));

  // (a double click is two presses within half a second, and a table on the
  // LAN answers sooner than that: the ✓ holds the button a moment too)
  const HOLD_MS = 1200;

  async function press(): Promise<void> {
    if (phase !== '' || disabled) return;
    const at = performance.now();
    const answer = act();
    if (!answer) return;
    phase = 'working';
    const r = await answer;
    if (!r?.ok) {
      phase = '';
      return;
    }
    phase = 'done';
    clearTimeout(timer);
    timer = setTimeout(() => (phase = ''), Math.max(HOLD_MS - (performance.now() - at), 700));
  }
</script>

<!-- (held by aria-disabled rather than disabled: a button disabled under the
     keyboard's focus drops it) -->
<button
  type="button"
  class={cls}
  class:accent
  class:danger
  class:quiet
  class:held={phase !== ''}
  title={title || undefined}
  {disabled}
  aria-disabled={phase !== '' ? 'true' : undefined}
  aria-busy={phase === 'working' ? 'true' : undefined}
  onclick={press}
>
  {#if children}{@render children()}{:else}{label}{/if}{#if phase === 'working'}<span class="spin" aria-hidden="true"></span>{:else if phase === 'done'}<span class="tick" aria-hidden="true">✓</span>{/if}
</button>

<style>
  .held {
    opacity: 0.75;
  }
  .tick {
    margin-left: 0.4em;
    font-weight: 700;
  }
  button:not(.accent) .tick {
    color: var(--ok);
  }
</style>
