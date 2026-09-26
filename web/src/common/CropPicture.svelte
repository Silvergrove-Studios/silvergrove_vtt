<!--
  Choosing the part of a picture a token shows: the picture under a round
  window the token's shape; drag it to move, the slider (or a wheel, or two
  fingers) to come closer. "Use this" hands back the square chosen, in the
  picture's own pixels.
-->
<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import Modal from './Modal.svelte';
  import type { Crop } from '../lib/pictures';

  let { file, onuse, oncancel }: { file: Blob; onuse: (crop: Crop) => void; oncancel: () => void } = $props();

  // (the dialog is made for one picture: a new one opens a new dialog)
  const url = untrack(() => URL.createObjectURL(file));
  onDestroy(() => URL.revokeObjectURL(url));

  const VIEW = 280;
  let w = $state(0);
  let h = $state(0);
  let zoom = $state(1);
  let cx = $state(0);
  let cy = $state(0);
  let failed = $state(false);

  const side = $derived(Math.min(w, h) / zoom);
  const scale = $derived(side > 0 ? VIEW / side : 1);

  function loaded(e: Event): void {
    const img = e.currentTarget as HTMLImageElement;
    w = img.naturalWidth;
    h = img.naturalHeight;
    cx = w / 2;
    cy = h / 2;
  }

  function clamp(): void {
    const half = side / 2;
    cx = Math.max(half, Math.min(w - half, cx));
    cy = Math.max(half, Math.min(h - half, cy));
  }

  let drag: { x: number; y: number; cx: number; cy: number } | null = null;
  const touches = new Map<number, { x: number; y: number }>();
  let pinch: { d: number; zoom: number } | null = null;

  function down(e: PointerEvent): void {
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    touches.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (touches.size === 1) drag = { x: e.clientX, y: e.clientY, cx, cy };
    if (touches.size === 2) {
      const [a, b] = [...touches.values()];
      pinch = { d: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)), zoom };
      drag = null;
    }
  }

  function move(e: PointerEvent): void {
    if (!touches.has(e.pointerId)) return;
    touches.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pinch && touches.size >= 2) {
      const [a, b] = [...touches.values()];
      zoom = Math.max(1, Math.min(4, (pinch.zoom * Math.hypot(a.x - b.x, a.y - b.y)) / pinch.d));
      clamp();
      return;
    }
    if (drag) {
      cx = drag.cx - (e.clientX - drag.x) / scale;
      cy = drag.cy - (e.clientY - drag.y) / scale;
      clamp();
    }
  }

  function up(e: PointerEvent): void {
    touches.delete(e.pointerId);
    if (touches.size < 2) pinch = null;
    if (touches.size === 0) drag = null;
  }

  function wheel(e: WheelEvent): void {
    e.preventDefault();
    zoom = Math.max(1, Math.min(4, zoom * Math.exp(-e.deltaY * 0.0015)));
    clamp();
  }

  function use(): void {
    onuse({ x: cx - side / 2, y: cy - side / 2, size: side });
  }
</script>

<Modal title="Your token's picture" onclose={oncancel}>
  <div class="crop">
    {#if failed}
      <p class="dim">That picture could not be opened. Try another (a photo, a PNG or a JPEG).</p>
    {:else}
      <p class="dim">Drag the picture to place it; the slider brings it closer. The circle is what the token shows.</p>
      <div
        class="view"
        style:width={`${VIEW}px`}
        style:height={`${VIEW}px`}
        role="application"
        aria-label="The picture: drag to move it"
        onpointerdown={down}
        onpointermove={move}
        onpointerup={up}
        onpointercancel={up}
        onwheel={wheel}
      >
        <img
          src={url}
          alt=""
          draggable="false"
          onload={loaded}
          onerror={() => (failed = true)}
          style:width={w ? `${w * scale}px` : 'auto'}
          style:height={h ? `${h * scale}px` : 'auto'}
          style:transform={`translate(${VIEW / 2 - cx * scale}px, ${VIEW / 2 - cy * scale}px)`}
        />
        <div class="mask" aria-hidden="true"></div>
      </div>
      <label class="zoom">
        <span>Closer</span>
        <input type="range" min="1" max="4" step="0.01" bind:value={zoom} oninput={clamp} aria-label="How close" />
      </label>
    {/if}
  </div>
  {#snippet actions()}
    <button type="button" class="quiet" onclick={oncancel}>Cancel</button>
    <button type="button" class="accent" disabled={failed || !w} onclick={use}>Use this picture</button>
  {/snippet}
</Modal>

<style>
  .crop {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
  }
  .crop p {
    margin: 0;
    text-align: center;
    max-width: 34ch;
  }
  .view {
    position: relative;
    overflow: hidden;
    border-radius: 14px;
    background: #0b0c0f;
    touch-action: none;
    cursor: grab;
    max-width: 100%;
  }
  .view img {
    position: absolute;
    left: 0;
    top: 0;
    max-width: none;
    user-select: none;
    -webkit-user-drag: none;
  }
  .mask {
    position: absolute;
    inset: 0;
    pointer-events: none;
    background: radial-gradient(circle at center, transparent 0, transparent calc(50% - 1px), rgba(0, 0, 0, 0.6) 50%);
    box-shadow: inset 0 0 0 2px rgba(255, 255, 255, 0.15);
  }
  .zoom {
    display: flex;
    gap: 10px;
    align-items: center;
    width: 100%;
    max-width: 280px;
  }
  .zoom input {
    flex: 1;
  }
</style>
