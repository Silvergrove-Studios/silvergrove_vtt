<!--
  A card over the page: a title, what it holds, a close button. Escape or
  a tap outside closes it (unless `sticky`). Full screen on a phone. The
  keyboard's focus comes into it as it opens and goes back as it closes;
  what it holds scrolls inside it, and "More ↓" says when there is more.
-->
<script lang="ts">
  import { onMount, type Snippet } from 'svelte';

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

  // a tap outside closes it only if it began and ended outside, and the card
  // has been up half a second: one that came up while a click was on its way
  // took that click and closed unseen (a playtest's player; what the DM shows
  // is in the Journal all the same)
  const upAt = performance.now();
  let pressedOutside = false;
  let releasedOutside = false;
  function outside(e: MouseEvent): void {
    const closes = pressedOutside && releasedOutside && e.target === e.currentTarget && performance.now() - upAt > 500;
    pressedOutside = releasedOutside = false;
    if (closes && !sticky) onclose?.();
  }

  // the keyboard's focus: into the card as it opens (its [autofocus] field,
  // else the card), round and round inside it with Tab, and back where it
  // was when it closes. A playtest's player typed a search into the Look up
  // card and the words went into the chat box underneath, which still had it.
  let dialog: HTMLDivElement;
  const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
  onMount(() => {
    const before = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const first = dialog.querySelector<HTMLElement>('[autofocus], [data-autofocus]');
    (first ?? dialog).focus({ preventScroll: true });
    return () => {
      const now = document.activeElement;
      if (before && before.isConnected && (!now || now === document.body || dialog.contains(now))) before.focus({ preventScroll: true });
    };
  });
  function trap(e: KeyboardEvent): void {
    if (e.key !== 'Tab') return;
    const els = [...dialog.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.getClientRects().length > 0);
    if (!els.length) {
      e.preventDefault();
      return;
    }
    const at = document.activeElement;
    if (e.shiftKey && (at === els[0] || at === dialog)) {
      e.preventDefault();
      els[els.length - 1].focus();
    } else if (!e.shiftKey && at === els[els.length - 1]) {
      e.preventDefault();
      els[0].focus();
    }
  }

  // more below what shows: said, and a press away (a playtest's place card
  // showed its picture and a paragraph; the paragraph after it was there to
  // scroll to, unseen, and a player who found it in the page's text took it
  // for a leak of the DM's notes)
  let body: HTMLDivElement;
  let content: HTMLDivElement;
  let more = $state(false);
  function measure(): void {
    if (body) more = body.scrollHeight - body.scrollTop - body.clientHeight > 24;
  }
  function down(): void {
    body.scrollBy({ top: Math.max(120, body.clientHeight * 0.8), behavior: 'smooth' });
  }
  onMount(() => {
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(body);
    ro.observe(content);
    return () => ro.disconnect();
  });
</script>

<svelte:window onkeydown={key} />
<div
  class="backdrop"
  role="presentation"
  onpointerdown={(e) => (pressedOutside = e.target === e.currentTarget)}
  onpointerup={(e) => (releasedOutside = e.target === e.currentTarget)}
  onclick={outside}
>
  <div class="modal" class:wide role="dialog" aria-modal="true" aria-label={title} tabindex="-1" bind:this={dialog} onkeydown={trap}>
    <header>
      <h2>{title}</h2>
      {#if onclose}<button type="button" class="quiet close" aria-label="Close" onclick={() => onclose?.()}>✕</button>{/if}
    </header>
    <div class="body scroll" bind:this={body} onscroll={measure}>
      <div class="content" bind:this={content}>{@render children()}</div>
      {#if more}
        <div class="morewrap"><button type="button" class="more" title="There is more below" onclick={down}>More ↓</button></div>
      {/if}
    </div>
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
  .modal:focus {
    outline: none;
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
  /* "More ↓" rides the bottom of what shows, taking no room of its own */
  .morewrap {
    position: sticky;
    bottom: 0;
    height: 0;
    display: flex;
    justify-content: center;
  }
  .more {
    transform: translateY(calc(-100% - 6px));
    border-radius: 999px;
    padding: 4px 16px;
    min-height: 32px;
    background: var(--panel-3);
    border-color: var(--accent-soft);
    box-shadow: 0 -10px 24px 12px color-mix(in srgb, var(--panel) 85%, transparent);
    font-weight: 600;
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
