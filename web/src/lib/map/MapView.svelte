<!--
  The map: a scene drawn on a canvas, moved by dragging empty ground (one
  finger or the mouse), zoomed by the wheel, a trackpad pinch or two
  fingers. Tapping a token or a cell tells the page; dragging a token the
  page allows moves it (dropped on a cell's centre). While the page is
  picking a target a banner says so and the cell under the pointer is lit.
-->
<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import type { Cell, Vec } from '../grid';
  import { onArt } from '../art';
  import { game, type Dict } from '../game.svelte';
  import { drawFrame, drawTerrain, prepare, tokenAt, tokenPos, type Camera, type TerrainCache } from './render';

  interface Props {
    map: Dict | null;
    scene: Dict;
    gm?: boolean;
    playerColors?: Record<string, string>;
    selected?: string;
    /** the token whose turn it is */
    activeToken?: string;
    /** what is being picked, said in a banner ("" when nothing is) */
    picking?: string;
    /** a token to centre on when the scene first shows (a player's own) */
    centerOn?: string;
    /** a token to keep in view when it moves (a player's own, moved by the DM) */
    follow?: string;
    showGrid?: boolean;
    /** the DM's walls: every kind, colour-coded (off: the doors alone) */
    showWalls?: boolean;
    /** the DM seeing as a player: all the walls, what's too dark hatched, and
     *  the creatures that player can't see (`ghosts`, each with `why`) */
    seeAs?: boolean;
    ghosts?: Dict[];
    canDrag?: (t: Dict) => boolean;
    onTokenClick?: (t: Dict) => void;
    onCellClick?: (cell: Cell, at: Vec) => void;
    onTokenDrop?: (t: Dict, pos: [number, number]) => void;
    onCancelPick?: () => void;
  }

  let {
    map,
    scene,
    gm = false,
    playerColors = {},
    selected = '',
    activeToken = '',
    picking = '',
    centerOn = '',
    follow = '',
    showGrid = true,
    showWalls = true,
    seeAs = false,
    ghosts = [],
    canDrag = () => false,
    onTokenClick,
    onCellClick,
    onTokenDrop,
    onCancelPick,
  }: Props = $props();

  let host: HTMLDivElement;
  let canvas: HTMLCanvasElement;
  // 0 until the page says how big the view is: a fit before that would
  // fit a made-up size and stay small
  let width = $state(0);
  let height = $state(0);
  let dpr = $state(1);
  const cam: Camera = $state({ x: 0, y: 0, scale: 40 });
  let hover = $state<Cell | null>(null);
  let drag = $state<{ id: string; pos: Vec } | null>(null);
  let artTick = $state(0);
  let fitted = '';
  // the camera is still the one fit() chose (nobody has panned or zoomed
  // since): a resize fits again, with the same `first`
  let auto = { on: false, first: false };

  const prep = $derived(map && scene?.id ? prepare(map, scene, gm, gm || seeAs) : null);
  const tokens = $derived(((scene?.tokens as Dict[]) ?? []) as Dict[]);

  // ----------------------------------------------------------- terrain --
  let terrain: TerrainCache | null = null;
  let terrainFor: unknown = null;
  let terrainKey = '';
  function ensureTerrain(): void {
    if (!map || !prep) {
      terrain = null;
      return;
    }
    // (packs that arrive after the map — a fight's — redraw it)
    const key = `${scene.level}|${artTick}|${Object.keys(game.packs).sort().join(',')}`;
    if (terrain && terrainFor === map && terrainKey === key) return;
    const mid = String(map.id ?? scene.map ?? '');
    terrain = drawTerrain(map, prep.lvl, prep.grid, (file) => `/mapfile/${encodeURIComponent(mid)}/${encodeURIComponent(file)}`);
    terrainFor = map;
    terrainKey = key;
  }

  // -------------------------------------------------------------- draw --
  let frame = 0;
  function schedule(): void {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      draw();
    });
  }

  function draw(): void {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    if (!map || !prep) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.fillStyle = '#101216';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      return;
    }
    if (width <= 0 || height <= 0) return;
    ensureTerrain();
    drawFrame({
      ctx,
      width,
      height,
      dpr,
      cam,
      map,
      scene,
      prep,
      terrain,
      look: { gm, selected, dragging: drag, picking: picking !== '', hoverCell: hover, playerColors, activeToken, showGrid, showWalls, seeAs, ghosts },
    });
  }

  $effect(() => {
    void [prep, cam.x, cam.y, cam.scale, selected, picking, hover, drag, gm, showGrid, activeToken, width, height, dpr, artTick, playerColors, Object.keys(game.packs).length];
    schedule();
  });
  // (what the DM's Walls and See as change)
  $effect(() => {
    void [showWalls, seeAs, ghosts];
    schedule();
  });

  // a new scene (or map, or level): fit it to the view
  $effect(() => {
    const key = `${scene?.id ?? ''}|${scene?.map ?? ''}|${scene?.level ?? ''}|${prep ? 1 : 0}|${width > 0 ? 1 : 0}`;
    if (prep && key !== fitted) {
      fitted = key;
      fit(true);
    }
  });

  // a dropped token stays where it was dropped until the table says where it is
  $effect(() => {
    if (!drag) return;
    const t = tokens.find((x) => x.id === drag!.id);
    if (!t || !pressing) {
      const p = t ? tokenPos(t) : null;
      if (!t || (p && Math.hypot(p.x - drag.pos.x, p.y - drag.pos.y) < 0.01)) drag = null;
    }
  });

  // the token followed moved (the DM moved it, or its player on another
  // screen): brought back into view if it went near the edge
  let lastFollow = '';
  $effect(() => {
    const t = follow ? tokens.find((x) => x.id === follow) : undefined;
    if (!t) {
      lastFollow = '';
      return;
    }
    const p = tokenPos(t);
    const key = `${scene?.id}|${p.x},${p.y}`;
    if (key === lastFollow) return;
    const first = !lastFollow.startsWith(`${scene?.id}|`);
    lastFollow = key;
    if (first) return;
    untrack(() => {
      const sx = width / 2 + (p.x - cam.x) * cam.scale;
      const sy = height / 2 + (p.y - cam.y) * cam.scale;
      if (sx < width * 0.18 || sx > width * 0.82 || sy < height * 0.18 || sy > height * 0.82) {
        auto.on = false;
        cam.x = p.x;
        cam.y = p.y;
      }
    });
  });

  // ------------------------------------------------------------ camera --
  function limits(): [number, number] {
    if (!prep) return [8, 400];
    const s = prep.grid.size();
    const fitScale = Math.min(width / (s.x + 1), height / (s.y + 1));
    return [Math.max(4, Math.min(fitScale * 0.5, 24)), 320];
  }

  function clampScale(s: number): number {
    const [lo, hi] = limits();
    return Math.max(lo, Math.min(hi, s));
  }

  export function fit(first = false): void {
    if (!prep || width <= 0 || height <= 0) return;
    const s = prep.grid.size();
    const margin = 16;
    cam.scale = clampScale(Math.min((width - margin * 2) / Math.max(s.x, 1), (height - margin * 2) / Math.max(s.y, 1)));
    cam.x = s.x / 2;
    cam.y = s.y / 2;
    if (first && centerOn) {
      const t = tokens.find((x) => x.id === centerOn);
      if (t) {
        const p = tokenPos(t);
        cam.scale = Math.max(cam.scale, clampScale(48));
        cam.x = p.x;
        cam.y = p.y;
      }
    }
    auto = { on: true, first };
  }

  export function centerOnToken(id: string): void {
    const t = tokens.find((x) => x.id === id);
    if (!t) return;
    const p = tokenPos(t);
    cam.x = p.x;
    cam.y = p.y;
    cam.scale = Math.max(cam.scale, clampScale(48));
    auto.on = false;
  }

  function zoomAt(sx: number, sy: number, scale: number): void {
    auto.on = false;
    const w = toWorld(sx, sy);
    cam.scale = clampScale(scale);
    cam.x = w.x - (sx - width / 2) / cam.scale;
    cam.y = w.y - (sy - height / 2) / cam.scale;
  }

  function zoomBy(k: number): void {
    zoomAt(width / 2, height / 2, cam.scale * k);
  }

  function toWorld(sx: number, sy: number): Vec {
    return { x: cam.x + (sx - width / 2) / cam.scale, y: cam.y + (sy - height / 2) / cam.scale };
  }

  function local(e: { clientX: number; clientY: number }): Vec {
    const r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  // ------------------------------------------------------------- input --
  const pointers = new Map<number, Vec>();
  let press: { id: number; at: Vec; token: Dict | null; moved: boolean; cam: Vec } | null = null;
  let pinch: { d: number; scale: number; world: Vec } | null = null;
  let pressing = $state(false);

  function onpointerdown(e: PointerEvent): void {
    if (e.button !== 0 && e.pointerType === 'mouse') return;
    canvas.setPointerCapture(e.pointerId);
    const p = local(e);
    pointers.set(e.pointerId, p);
    if (pointers.size === 1) {
      // (a reach of at least 16 px on screen, 22 on a touch screen)
      const t = tokenAt(tokens, toWorld(p.x, p.y), (e.pointerType === 'mouse' ? 16 : 22) / cam.scale);
      press = { id: e.pointerId, at: p, token: t, moved: false, cam: { x: cam.x, y: cam.y } };
      pressing = true;
    } else if (pointers.size === 2) {
      press = null;
      drag = null;
      const [a, b] = [...pointers.values()];
      const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      pinch = { d: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)), scale: cam.scale, world: toWorld(mid.x, mid.y) };
    }
  }

  function onpointermove(e: PointerEvent): void {
    const p = local(e);
    if (!pointers.has(e.pointerId)) {
      if (prep && e.pointerType === 'mouse') hover = prep.grid.cellAt(toWorld(p.x, p.y));
      return;
    }
    pointers.set(e.pointerId, p);
    if (pinch && pointers.size >= 2) {
      const [a, b] = [...pointers.values()];
      const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      auto.on = false;
      cam.scale = clampScale((pinch.scale * Math.hypot(a.x - b.x, a.y - b.y)) / pinch.d);
      cam.x = pinch.world.x - (mid.x - width / 2) / cam.scale;
      cam.y = pinch.world.y - (mid.y - height / 2) / cam.scale;
      return;
    }
    if (!press || press.id !== e.pointerId) return;
    const dx = p.x - press.at.x;
    const dy = p.y - press.at.y;
    if (!press.moved && Math.hypot(dx, dy) > (e.pointerType === 'mouse' ? 4 : 8)) press.moved = true;
    if (!press.moved) return;
    if (press.token && !picking && canDrag(press.token)) {
      drag = { id: String(press.token.id), pos: toWorld(p.x, p.y) };
    } else {
      auto.on = false;
      cam.x = press.cam.x - dx / cam.scale;
      cam.y = press.cam.y - dy / cam.scale;
    }
    if (prep) hover = prep.grid.cellAt(toWorld(p.x, p.y));
  }

  function onpointerup(e: PointerEvent): void {
    const p = local(e);
    pointers.delete(e.pointerId);
    if (pinch) {
      if (pointers.size < 2) pinch = null;
      press = null;
      pressing = false;
      return;
    }
    if (!press || press.id !== e.pointerId) return;
    const was = press;
    press = null;
    pressing = false;
    if (!was.moved) {
      const w = toWorld(p.x, p.y);
      if (was.token) onTokenClick?.(was.token);
      else if (prep) onCellClick?.(prep.grid.cellAt(w), w);
    } else if (drag && was.token && prep) {
      // onto a cell's centre, or where it was let go on a map with no grid drawn
      const c = map?.style?.show_grid === false ? drag.pos : prep.grid.center(prep.grid.cellAt(drag.pos));
      drag = { id: drag.id, pos: c };
      onTokenDrop?.(was.token, [c.x, c.y]);
      // (if the table refuses, the token goes back)
      const id = drag.id;
      setTimeout(() => {
        if (drag && drag.id === id && !pressing) drag = null;
      }, 1500);
    }
  }

  function onpointercancel(e: PointerEvent): void {
    pointers.delete(e.pointerId);
    if (pointers.size < 2) pinch = null;
    press = null;
    pressing = false;
    drag = null;
  }

  function onwheel(e: WheelEvent): void {
    e.preventDefault();
    const p = local(e);
    // a pinch on a trackpad comes as a wheel with ctrl; a mouse wheel in
    // whole notches; anything else is two fingers scrolling: move
    const zoom = e.ctrlKey || e.deltaMode !== 0 || (e.deltaX === 0 && Number.isInteger(e.deltaY) && Math.abs(e.deltaY) >= 40);
    if (zoom) zoomAt(p.x, p.y, cam.scale * Math.exp(-e.deltaY * (e.ctrlKey ? 0.012 : 0.0016) * (e.deltaMode === 1 ? 30 : 1)));
    else {
      auto.on = false;
      cam.x += e.deltaX / cam.scale;
      cam.y += e.deltaY / cam.scale;
    }
  }

  function onkeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape' && picking) onCancelPick?.();
  }

  /** Where a token is on the screen (client pixels): for tests and for pointing at things. */
  export function screenOf(id: string): { x: number; y: number } | null {
    const t = tokens.find((x) => x.id === id);
    if (!t || !canvas) return null;
    const p = tokenPos(t);
    const r = canvas.getBoundingClientRect();
    return { x: r.left + width / 2 + (p.x - cam.x) * cam.scale, y: r.top + height / 2 + (p.y - cam.y) * cam.scale };
  }

  onMount(() => {
    Object.assign(canvas, { screenOf, pxPerHex: () => cam.scale });
    const ro = new ResizeObserver(() => {
      const r = host.getBoundingClientRect();
      dpr = Math.min(window.devicePixelRatio || 1, 3);
      width = Math.max(1, Math.floor(r.width));
      height = Math.max(1, Math.floor(r.height));
      canvas.width = Math.floor(width * dpr);
      canvas.height = Math.floor(height * dpr);
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      if (auto.on && !pressing) fit(auto.first);
      schedule();
    });
    ro.observe(host);
    canvas.addEventListener('wheel', onwheel, { passive: false });
    // images arrive a few at a time: redraw, and redo the terrain once they settle
    let t: ReturnType<typeof setTimeout> | null = null;
    const off = onArt(() => {
      schedule();
      if (terrain?.pending && !t)
        t = setTimeout(() => {
          t = null;
          artTick++;
        }, 150);
    });
    window.addEventListener('keydown', onkeydown);
    return () => {
      ro.disconnect();
      canvas.removeEventListener('wheel', onwheel);
      window.removeEventListener('keydown', onkeydown);
      off();
      if (t) clearTimeout(t);
      if (frame) cancelAnimationFrame(frame);
    };
  });
</script>

<div class="map" bind:this={host}>
  <canvas
    bind:this={canvas}
    class:picking={picking !== ''}
    {onpointerdown}
    {onpointermove}
    {onpointerup}
    {onpointercancel}
    onpointerleave={() => {
      if (!pressing) hover = null;
    }}
  ></canvas>
  {#if !map || !scene?.id}
    <div class="empty">{scene?.id ? 'The map is on its way…' : 'Nothing is on the table yet.'}</div>
  {/if}
  {#if picking}
    <div class="banner" role="status">
      <span>{picking}</span>
      {#if onCancelPick}<button type="button" onclick={() => onCancelPick?.()}>Cancel</button>{/if}
    </div>
  {/if}
  <div class="zoom">
    <button type="button" aria-label="Zoom in" onclick={() => zoomBy(1.4)}>+</button>
    <button type="button" aria-label="Zoom out" onclick={() => zoomBy(1 / 1.4)}>−</button>
    <button type="button" aria-label="Show the whole map" onclick={() => fit()}>⤢</button>
  </div>
</div>

<style>
  .map {
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
    background: #101216;
  }
  canvas {
    display: block;
    touch-action: none;
    cursor: grab;
  }
  canvas:active {
    cursor: grabbing;
  }
  canvas.picking {
    cursor: crosshair;
  }
  .empty {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    color: var(--muted, #9aa0aa);
    pointer-events: none;
    font-size: 0.95rem;
  }
  .banner {
    position: absolute;
    top: 12px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    gap: 12px;
    align-items: center;
    padding: 8px 10px 8px 16px;
    border-radius: 999px;
    background: #ffd75a;
    color: #1b1600;
    font-weight: 600;
    box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);
    max-width: calc(100% - 24px);
  }
  .banner button {
    border: 0;
    border-radius: 999px;
    padding: 4px 12px;
    background: rgba(0, 0, 0, 0.8);
    color: #fff;
    font: inherit;
    font-weight: 600;
    cursor: pointer;
  }
  .zoom {
    position: absolute;
    right: 12px;
    bottom: 12px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .zoom button {
    width: 36px;
    height: 36px;
    border-radius: 10px;
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: rgba(22, 24, 29, 0.85);
    color: #e8e6e3;
    font-size: 18px;
    line-height: 1;
    cursor: pointer;
    backdrop-filter: blur(6px);
  }
  .zoom button:hover {
    background: rgba(40, 44, 52, 0.95);
  }
</style>
