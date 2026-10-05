<!--
  The map: a scene drawn on a canvas, moved by dragging empty ground (one
  finger or the mouse), zoomed by the wheel, a trackpad pinch or two
  fingers. Tapping a token or a cell tells the page; dragging a token the
  page allows moves it (dropped on a cell's centre). While the page is
  picking a target a banner says so and the cell under the pointer is lit.
  With `tools`, the table's tools are on it for everyone — a ruler, a
  template, a ping, a spell's preview (MapTools) — and the table's shared
  marks are drawn over it; a long press (or a right-click) pings.
-->
<script lang="ts">
  import { onMount, untrack, type Snippet } from 'svelte';
  import { cellKey, type Cell, type Vec } from '../grid';
  import { onArt } from '../art';
  import { game, mapFileUrl, type Dict } from '../game.svelte';
  import { drawFrame, drawTerrain, layout, prepare, tokenAt, tokenPos, type Camera, type TerrainCache } from './render';
  import MapTools from './MapTools.svelte';
  import { gridless, ruleOf } from './measure';
  import { PING_MS } from './marks';
  import { abort as toolAbort, done as toolDone, drag as toolDrag, hover as toolHover, ping as toolPing, press as toolPress, release as toolRelease, stop as toolStop, tools, type Where } from './tools.svelte';

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
    /** a fight is on: the DM's notes lie under the tokens */
    fight?: boolean;
    /** what the pick's banner holds, instead of its words and Cancel (the
     *  creatures to choose by name, No target, Done) */
    banner?: Snippet;
    canDrag?: (t: Dict) => boolean;
    /** a token tapped, and where (in map units) */
    onTokenClick?: (t: Dict, at: Vec) => void;
    onCellClick?: (cell: Cell, at: Vec) => void;
    onTokenDrop?: (t: Dict, pos: [number, number]) => void;
    onCancelPick?: () => void;
    /** the table's tools on the map (a ruler, a template, a ping, previews) and the shared marks drawn */
    tools?: boolean;
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
    fight = false,
    banner,
    canDrag = () => false,
    onTokenClick,
    onCellClick,
    onTokenDrop,
    onCancelPick,
    tools: withTools = false,
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
  // a token being dragged, or dropped and waiting for the table: where it is
  // drawn, and (dropped) where the table last had it
  let drag = $state<{ id: string; pos: Vec; from?: Vec } | null>(null);
  let artTick = $state(0);
  // a token chosen from a list (showToken), pulsing a moment so the eye finds
  // it; and the last one shown (for tests)
  let flash: { id: string; at: number } | null = null;
  let lastShown = '';
  const FLASH_MS = 1400;
  let fitted = '';
  // the camera is still the one fit() chose (nobody has panned or zoomed
  // since): a resize fits again, with the same `first`
  let auto = { on: false, first: false };

  const prep = $derived(map && scene?.id ? prepare(map, scene, gm, gm || seeAs) : null);
  const tokens = $derived(((scene?.tokens as Dict[]) ?? []) as Dict[]);
  // where each token is drawn: tokens sharing a cell fan out, and a tap is
  // theirs where they are drawn
  const placed = $derived(prep ? layout(tokens, prep.grid, drag?.id ?? '') : undefined);

  // ------------------------------------------------------------- marks --
  // where the table's tools work: this map's grid, the scene, the tokens this
  // screen shows (a ruler never snaps to one it doesn't), its zoom
  const where = $derived<Where | null>(withTools && prep && map ? { grid: prep.grid, scene, map, tokens, scale: cam.scale } : null);
  // the table's shared marks: the DM seeing as a player, the ones that player
  // is sent (not those over what they can't see; a creature they don't know
  // unnamed), else this screen's own
  const shownMarks = $derived(seeAs && game.previewMarks ? game.previewMarks : game.marks);
  // the shared marks on this scene; the one being made here drawn from here
  const sceneMarks = $derived.by((): Dict[] => {
    if (!withTools || !scene?.id) return [];
    const sid = String(scene.id);
    const out = Object.values(shownMarks).filter((m) => String(m.scene ?? '') === sid);
    const d = tools.draft;
    if (d && !seeAs && String(d.scene ?? '') === sid) {
      const echo = game.marks[String(d.id)];
      const me = game.players.find((p) => String(p.id) === game.me);
      const mine: Dict = { name: echo?.name ?? (game.role === 'dm' ? 'DM' : String(me?.name ?? '')), color: echo?.color ?? (game.role === 'dm' ? '#ffffff' : String(me?.color ?? '#ffffff')), owner: game.role === 'dm' ? 'gm' : game.me, ...$state.snapshot(d) };
      const i = out.findIndex((m) => String(m.id) === String(d.id));
      if (i >= 0) out[i] = mine;
      else out.push(mine);
    }
    return out;
  });
  const markEchoes = $derived(tools.draft ? { [String(tools.draft.id)]: game.marks[String(tools.draft.id)] } : {});

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
    // (a map's own files by the key the table sent with it)
    terrain = drawTerrain(map, prep.lvl, prep.grid, (file) => mapFileUrl(mid, file));
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
    const flashT = flash ? (performance.now() - flash.at) / FLASH_MS : 1;
    if (flashT >= 1) flash = null;
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
      look: {
        gm,
        selected,
        dragging: drag,
        picking: picking !== '',
        hoverCell: hover,
        playerColors,
        activeToken,
        showGrid,
        showWalls,
        seeAs,
        ghosts,
        fight,
        flash: flash ? { id: flash.id, t: flashT } : undefined,
        marks: withTools
          ? {
              list: sceneMarks,
              echoes: markEchoes as Record<string, Dict>,
              look: {
                grid: prep.grid,
                scale: cam.scale,
                tokens,
                rule: ruleOf(scene),
                noGrid: gridless(map),
                draft: String(tools.draft?.id ?? ''),
                now: performance.now(),
                born: (id) => game.marksBorn[id] ?? performance.now(),
                // (the view, in hex units: a mark's words stay inside it)
                view: { x0: cam.x - width / 2 / cam.scale, y0: cam.y - height / 2 / cam.scale, x1: cam.x + width / 2 / cam.scale, y1: cam.y + height / 2 / cam.scale },
              },
            }
          : undefined,
      },
    });
    // a ping's rings move and fade, and a token's pulse: drawn again till they have gone
    if (flash || sceneMarks.some((m) => m.kind === 'ping' && performance.now() - (game.marksBorn[String(m.id)] ?? 0) < PING_MS)) schedule();
  }

  $effect(() => {
    void [prep, cam.x, cam.y, cam.scale, selected, picking, hover, drag, gm, showGrid, activeToken, width, height, dpr, artTick, playerColors, Object.keys(game.packs).length];
    schedule();
  });
  // (the table's marks, as they come and go and as one is made here)
  $effect(() => {
    void [sceneMarks, markEchoes];
    schedule();
  });
  // (what the DM's Walls and See as change, and a fight starting or ending)
  $effect(() => {
    void [showWalls, seeAs, ghosts, fight];
    schedule();
  });

  // another scene shown: a tool out on the one before is put away (what it made stays there)
  $effect(() => {
    const sid = String(scene?.id ?? '');
    untrack(() => {
      if (withTools && tools.draft && String(tools.draft.scene ?? '') !== sid) toolStop();
    });
  });

  // a new scene (or map, or level): fit it to the view
  $effect(() => {
    const key = `${scene?.id ?? ''}|${scene?.map ?? ''}|${scene?.level ?? ''}|${prep ? 1 : 0}|${width > 0 ? 1 : 0}`;
    if (prep && key !== fitted) {
      fitted = key;
      fit(true);
    }
  });

  // a dropped token stays where it was dropped until the table says where it
  // is: there, or anywhere else it moved it to (a playtest's party star, put
  // on a cell of the table's choosing, hung where it was dropped, and the
  // DM's next drag started on nothing)
  $effect(() => {
    if (!drag) return;
    const t = tokens.find((x) => x.id === drag!.id);
    if (!t) {
      drag = null;
      return;
    }
    if (pressing) return;
    const p = tokenPos(t);
    const moved = !!drag.from && Math.hypot(p.x - drag.from.x, p.y - drag.from.y) > 0.01;
    if (moved || Math.hypot(p.x - drag.pos.x, p.y - drag.pos.y) < 0.01) drag = null;
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

  /** A token chosen from a list (the DM's fight): brought into view where it
   *  isn't well inside it (the zoom kept), and pulsed a moment so the eye
   *  finds it — which of three Goblin Warriors it is. A token this screen
   *  doesn't draw (another scene's) is left alone. */
  export function showToken(id: string): void {
    const t = tokens.find((x) => String(x.id) === id);
    if (!t || !prep) return;
    const p = placed?.get(id)?.pos ?? tokenPos(t);
    const sx = width / 2 + (p.x - cam.x) * cam.scale;
    const sy = height / 2 + (p.y - cam.y) * cam.scale;
    if (sx < width * 0.15 || sx > width * 0.85 || sy < height * 0.15 || sy > height * 0.85) {
      auto.on = false;
      cam.x = p.x;
      cam.y = p.y;
    }
    flash = { id, at: performance.now() };
    lastShown = id;
    schedule();
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
  // what a press is on: the token nearest (a tap's), and the nearest the
  // page lets be dragged (a drag's); a table tool's (`tool`), or one held
  // long enough to ping (`long`: no tap when it is let go)
  let press: { id: number; at: Vec; token: Dict | null; drags: Dict | null; moved: boolean; cam: Vec; tool?: boolean; long?: boolean } | null = null;
  let pinch: { d: number; scale: number; world: Vec } | null = null;
  let pressing = $state(false);
  // a press held still this long pings: "look here" (a phone has no right button)
  const LONG_MS = 550;
  let longTimer: ReturnType<typeof setTimeout> | null = null;
  let longAt = -Infinity;
  function clearLong(): void {
    if (longTimer) clearTimeout(longTimer);
    longTimer = null;
  }

  function onpointerdown(e: PointerEvent): void {
    if (e.button !== 0 && e.pointerType === 'mouse') return;
    canvas.setPointerCapture(e.pointerId);
    const p = local(e);
    pointers.set(e.pointerId, p);
    if (pointers.size === 1) {
      const w = toWorld(p.x, p.y);
      // a table tool that is out takes the press (a ruler's point, a template
      // moved or turned) — not while a pick waits for its target
      if (where && tools.mode && !picking && toolPress(where, w)) {
        press = { id: e.pointerId, at: p, token: null, drags: null, moved: false, cam: { x: cam.x, y: cam.y }, tool: true };
        pressing = true;
        return;
      }
      // (a reach of at least 16 px on screen, 22 on a touch screen)
      const reach = (e.pointerType === 'mouse' ? 16 : 22) / cam.scale;
      // a token dropped and not yet where the table has it is where it is
      // drawn, and where the table has it too
      const drawn = drag && placed ? new Map(placed).set(drag.id, { pos: drag.pos, k: 1 }) : placed;
      const t = tokenAt(tokens, w, reach, drawn) ?? tokenAt(tokens, w, reach, placed);
      // a drag takes the token that can be dragged of those fanned out on
      // one cell, when the one nearer the press can't be: the party's star
      // at a place is drawn small beside the place's marker, and a drag begun
      // a few pixels to the marker's side panned the map instead (a
      // playtest's DM, the star left at a place: it "stopped following my drags")
      let drags = t && canDrag(t) ? t : null;
      if (t && !drags && prep) {
        const cell = cellKey(prep.grid.cellAt(tokenPos(t)));
        const movable = tokens.filter((x) => canDrag(x) && cellKey(prep!.grid.cellAt(tokenPos(x))) === cell);
        drags = tokenAt(movable, w, reach, drawn) ?? tokenAt(movable, w, reach, placed);
      }
      press = { id: e.pointerId, at: p, token: t, drags, moved: false, cam: { x: cam.x, y: cam.y } };
      pressing = true;
      // held still: a ping where it is
      clearLong();
      if (where && !picking) {
        const id = e.pointerId;
        longTimer = setTimeout(() => {
          longTimer = null;
          if (!where || !press || press.id !== id || press.moved || pinch) return;
          press.long = true;
          longAt = performance.now();
          toolPing(where, toWorld(p.x, p.y));
        }, LONG_MS);
      }
    } else if (pointers.size === 2) {
      clearLong();
      // (a pinch, not a ruler's point)
      if (press?.tool && where) toolAbort(where);
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
      // a ruler being clicked out follows the mouse from its last point
      if (where && tools.mode && e.pointerType === 'mouse') toolHover(where, toWorld(p.x, p.y));
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
    if (!press.moved && Math.hypot(dx, dy) > (e.pointerType === 'mouse' ? 4 : 8)) {
      press.moved = true;
      clearLong();
    }
    if (!press.moved) return;
    if (press.tool) {
      if (where) toolDrag(where, toWorld(p.x, p.y));
      return;
    }
    if (press.drags && !picking) {
      drag = { id: String(press.drags.id), pos: toWorld(p.x, p.y) };
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
    clearLong();
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
    if (was.tool) {
      if (where) toolRelease(where, toWorld(p.x, p.y), was.moved);
      return;
    }
    // (held still, it pinged: not a tap too)
    if (was.long && !was.moved) return;
    if (!was.moved) {
      const w = toWorld(p.x, p.y);
      if (was.token) onTokenClick?.(was.token, w);
      else if (prep) onCellClick?.(prep.grid.cellAt(w), w);
    } else if (drag && was.drags && prep) {
      // onto a cell's centre, or where it was let go on a map with no grid drawn
      const c = map?.style?.show_grid === false ? drag.pos : prep.grid.center(prep.grid.cellAt(drag.pos));
      const now = tokens.find((x) => x.id === drag!.id);
      drag = { id: drag.id, pos: c, from: now ? tokenPos(now) : undefined };
      onTokenDrop?.(was.drags, [c.x, c.y]);
      // (if the table refuses, the token goes back)
      const id = drag.id;
      setTimeout(() => {
        if (drag && drag.id === id && !pressing) drag = null;
      }, 1500);
    }
  }

  function onpointercancel(e: PointerEvent): void {
    pointers.delete(e.pointerId);
    clearLong();
    if (pointers.size < 2) pinch = null;
    if (press?.tool && where) toolRelease(where, toWorld(press.at.x, press.at.y), false);
    press = null;
    pressing = false;
    drag = null;
  }

  // a right-click pings ("look here"); never the browser's menu over the map
  function oncontextmenu(e: MouseEvent): void {
    e.preventDefault();
    if (!where || picking) return;
    // (a phone's long press says contextmenu too: it pinged already)
    if ((e as PointerEvent).pointerType === 'touch' || performance.now() - longAt < 1000) return;
    const p = local(e);
    toolPing(where, toWorld(p.x, p.y));
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
    // (a table tool put away: what it made stays on the map, lingering or pinned)
    else if (e.key === 'Escape' && withTools && tools.mode) toolStop();
  }

  /** Where a token is on the screen (client pixels): for tests and for pointing at things. */
  export function screenOf(id: string): { x: number; y: number } | null {
    const t = tokens.find((x) => x.id === id);
    if (!t || !canvas) return null;
    const p = placed?.get(String(t.id))?.pos ?? tokenPos(t);
    const r = canvas.getBoundingClientRect();
    return { x: r.left + width / 2 + (p.x - cam.x) * cam.scale, y: r.top + height / 2 + (p.y - cam.y) * cam.scale };
  }

  onMount(() => {
    Object.assign(canvas, { screenOf, pxPerHex: () => cam.scale, shown: () => lastShown });
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
    class:picking={picking !== '' || (withTools && tools.mode !== '')}
    {onpointerdown}
    {onpointermove}
    {onpointerup}
    {onpointercancel}
    {oncontextmenu}
    ondblclick={() => {
      // a ruler clicked out: a double click ends it
      if (withTools && tools.mode === 'ruler' && tools.tapping) toolDone(where);
    }}
    onpointerleave={() => {
      if (!pressing) hover = null;
    }}
  ></canvas>
  {#if withTools && scene?.id && map}
    <MapTools {where} {gm} hidden={picking !== ''} marks={shownMarks} />
  {/if}
  {#if !map || !scene?.id}
    <div class="empty">{scene?.id ? 'The map is on its way…' : 'Nothing is on the table yet.'}</div>
  {/if}
  {#if picking && banner}
    <div class="banner rich">{@render banner()}</div>
  {:else if picking}
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
  /* a pick's banner with its creatures to choose: a card, scrolling when long */
  .banner.rich {
    display: block;
    width: min(620px, calc(100% - 24px));
    max-height: 48%;
    overflow-y: auto;
    padding: 10px 12px;
    border-radius: 16px;
    z-index: 7;
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
