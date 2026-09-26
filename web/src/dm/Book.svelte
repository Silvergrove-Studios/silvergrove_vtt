<!--
  The DM's book: everything in the campaign in the DM's own arrangement —
  the sections (renamed as the DM likes), the DM's folders among and
  inside them — and one search over all of it and the rules.
-->
<script lang="ts">
  import { comp, dmOp, game, notice, uploadPicture, type Dict } from '../lib/game.svelte';
  import { prepare } from '../lib/pictures';
  import { book, kindWord, type Item, type Node } from './contents';

  let { current = '', onopen }: { current?: string; onopen: (ref: string) => void } = $props();

  let q = $state('');
  // (Pictures open: a playtest's DM found the Warden's picture only after the game)
  let closed = $state<Record<string, boolean>>({ 'section:shown': true });
  // what was shown and what the players wrote grow all campaign: their newest
  // three, and the rest a press away (a playtest's book was a long column)
  const NEWEST_ONLY = ['section:shown', 'section:from_players'];
  let whole = $state<Record<string, boolean>>({});

  // each kind of thing its icon; its name is said after the label (a place,
  // its fight and its picture can share a name: a playtest's DM opened the
  // picture "The ruined chapel" meaning the place)
  const ICONS: Record<string, string> = {
    place: 'M12 21c-4-4.4-6-7.9-6-11a6 6 0 0 1 12 0c0 3.1-2 6.6-6 11z M12 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
    fight: 'M4 4l11 11 M13 17l4-4 M16 16l4 4 M20 4L9 15 M7 13l4 4 M8 16l-4 4',
    person: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M4 21a8 8 0 0 1 16 0',
    character: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M4 21a8 8 0 0 1 16 0 M9 17l3 2 3-2',
    note: 'M6 3h9l4 4v14H6z M14 3v5h5 M9 13h6 M9 17h4',
    handout: 'M5 4h14v16H5z M8 8h8 M8 12h8 M8 16h5',
    shown: 'M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    from_player: 'M4 5h16v11H9l-5 4z',
    picture: 'M4 5h16v14H4z M4 16l5-5 4 4 2.5-2.5L20 17 M17 9.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0z',
    map: 'M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3z M9 3v15 M15 6v15',
    rule: 'M6 3h11a2 2 0 0 1 2 2v16H8a2 2 0 0 1-2-2z M6 19a2 2 0 0 1 2-2h11',
  };
  let menu = $state('');
  // a picture of the DM's own into Pictures, to show the players (a playtest's DM
  // could add none): made smaller here, kept by the table, filed in the book
  let pictureInput: HTMLInputElement | undefined = $state();
  let addingPicture = $state(false);
  async function addPicture(e: Event): Promise<void> {
    const f = (e.currentTarget as HTMLInputElement).files?.[0] ?? null;
    (e.currentTarget as HTMLInputElement).value = '';
    if (!f) return;
    const name = (prompt('Name the picture', f.name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' ')) ?? '').trim();
    addingPicture = true;
    try {
      const r = await uploadPicture('picture', await prepare(f, 'picture'));
      if (!r.ref) {
        notice(r.why ?? 'The table did not keep it', 'error');
        return;
      }
      dmOp('add_picture', { upload: r.ref, name });
      notice(`${name || 'The picture'} is in Pictures`);
    } catch (err) {
      notice(`That picture could not be used: ${String((err as Error)?.message ?? err)}`, 'error');
    } finally {
      addingPicture = false;
    }
  }
  let rules = $state<Item[]>([]);
  let seq = 0;

  const nodes = $derived(book(game.dm, game.players, q));

  // the rules, when searching: a few from every collection
  $effect(() => {
    const text = q.trim();
    const mine = ++seq;
    rules = [];
    if (text.length < 2) return;
    const found: Item[] = [];
    for (const coll of (game.view.collections as string[]) ?? []) {
      comp(coll, { query: { text, per_page: 6, fields: ['name'] } }).then((reply) => {
        if (mine !== seq) return;
        for (const e of (reply.page?.entries as Dict[]) ?? []) found.push({ label: String(e.name ?? e.id), kind: 'rule', sub: coll.replace(/_/g, ' '), ref: `entry:${coll}/${e.id}` });
        rules = [...found];
      });
    }
  });

  // a fight of the DM's own: made at once over the first battle map, then its
  // card (name it, choose the map, add creatures, start it)
  function newFight(): void {
    menu = '';
    const battle = ((game.dm.maps as Dict[]) ?? []).find((m) => m.role !== 'regional') ?? ((game.dm.maps as Dict[]) ?? [])[0];
    if (!battle) {
      notice('The campaign has no map to fight on: add one on the Table first', 'error');
      return;
    }
    const id = `enc_${Math.random().toString(36).slice(2, 10)}`;
    dmOp('new_fight', { id, name: 'A new fight', map: battle.id });
    onopen(`fight:${id}`);
  }

  function rename(node: Node): void {
    menu = '';
    const t = prompt(node.node.startsWith('section:') ? 'A new name for this section (empty: its own name)' : 'A new name for this folder', node.title);
    if (t !== null) dmOp('folder', { do: 'rename', node: node.node, title: t });
  }

  function newFolder(parent: string): void {
    menu = '';
    const t = prompt('Name the new folder', 'New folder');
    if (t !== null && t.trim()) dmOp('folder', { do: 'new', parent, title: t.trim() });
  }

  function remove(node: Node): void {
    menu = '';
    if (confirm(`Delete the folder “${node.title}”? What is in it goes back to its own section.`)) dmOp('folder', { do: 'delete', id: node.node.slice(7) });
  }

  function first(): string {
    for (const n of nodes) {
      const r = firstIn(n);
      if (r) return r;
    }
    return rules[0]?.ref ?? '';
  }

  function firstIn(n: Node): string {
    for (const f of n.folders) {
      const r = firstIn(f);
      if (r) return r;
    }
    return n.items[0]?.ref ?? '';
  }
</script>

{#snippet item(it: Item, depth: number)}
  <button type="button" class="item" class:on={current === it.ref} style:padding-left={`${12 + depth * 14}px`} onclick={() => onopen(it.ref)}>
    <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d={ICONS[it.kind] ?? ''} /></svg>
    <span class="label">{it.label}</span>
    <!-- what it is, after its name (a name is what's looked for first): in sight
         when searching and when something else has the name, else for a screen reader -->
    <span class="kindword" class:sr-only={!q && !it.twin}>{kindWord(it.kind)}</span>
    {#if it.sub}<span class="sub">{it.sub}</span>{/if}
  </button>
  {#each it.children ?? [] as c (c.ref)}
    {@render item(c, depth + 1)}
  {/each}
{/snippet}

{#snippet group(n: Node, depth: number)}
  {@const isClosed = !q && (closed[n.node] ?? false)}
  {@const newestOnly = !q && !whole[n.node] && NEWEST_ONLY.includes(n.node) && n.items.length > 3}
  <div class="group" class:folder={n.node.startsWith('folder:')}>
    <div class="head" style:padding-left={`${6 + depth * 14}px`}>
      <button type="button" class="fold" aria-expanded={!isClosed} onclick={() => (closed[n.node] = !isClosed)}>
        <span class="caret" class:closed={isClosed}>▸</span>
        <span class="title">{n.title}</span>
        <!-- (beside the title, not in it: the title is the section's name alone) -->
        {#if n.count}<span class="count">{n.count}</span>{/if}
      </button>
      <button type="button" class="quiet dots" aria-label={`Arrange ${n.title}`} onclick={() => (menu = menu === n.node ? '' : n.node)}>⋯</button>
      {#if menu === n.node}
        <div class="menu" role="menu">
          <button type="button" role="menuitem" class="quiet" onclick={() => rename(n)}>Rename</button>
          <button type="button" role="menuitem" class="quiet" onclick={() => newFolder(n.node)}>New folder inside</button>
          {#if n.node === 'section:fights'}
            <button type="button" role="menuitem" class="quiet" onclick={newFight}>New fight…</button>
          {/if}
          {#if n.node === 'section:pictures'}
            <button type="button" role="menuitem" class="quiet" disabled={addingPicture} onclick={() => { menu = ''; pictureInput?.click(); }}>{addingPicture ? 'Sending the picture…' : 'Add a picture…'}</button>
          {/if}
          {#if n.node.startsWith('folder:')}
            <button type="button" role="menuitem" class="quiet" onclick={() => { menu = ''; dmOp('folder', { do: 'move', id: n.node.slice(7), parent: '' }); }}>Move to the top</button>
            <button type="button" role="menuitem" class="quiet danger" onclick={() => remove(n)}>Delete the folder</button>
          {/if}
        </div>
      {/if}
    </div>
    {#if !isClosed}
      {#each n.folders as f (f.node)}{@render group(f, depth + 1)}{/each}
      {#each newestOnly ? n.items.slice(0, 3) : n.items as it (it.ref)}{@render item(it, depth + 1)}{/each}
      {#if newestOnly}
        <button type="button" class="item more" style:padding-left={`${12 + (depth + 1) * 14}px`} onclick={() => (whole[n.node] = true)}>Show all {n.items.length}</button>
      {/if}
      {#if n.node === 'section:fights' && !q}
        <button type="button" class="item newfight" style:padding-left={`${12 + (depth + 1) * 14}px`} onclick={newFight}>+ New fight</button>
      {:else if n.folders.length === 0 && n.items.length === 0}
        <p class="empty" style:padding-left={`${26 + depth * 14}px`}>Empty. Put things here from their cards (“In the book”).</p>
      {/if}
    {/if}
  </div>
{/snippet}

<div class="book">
  <div class="search">
    <input
      type="search"
      placeholder="Look up anything — a person, a place, a spell…"
      bind:value={q}
      onkeydown={(e) => {
        if (e.key === 'Enter') {
          const r = first();
          if (r) onopen(r);
        }
      }}
    />
  </div>
  <div class="tree scroll">
    {#each nodes as n (n.node)}{@render group(n, 0)}{/each}
    {#if rules.length}
      <div class="group">
        <div class="head"><span class="title plain">Rules</span></div>
        {#each rules as it (it.ref)}{@render item(it, 1)}{/each}
      </div>
    {/if}
    {#if q && nodes.length === 0 && rules.length === 0}
      <p class="empty">Nothing by that name.</p>
    {/if}
    {#if !q}
      <button type="button" class="quiet newtop" onclick={() => newFolder('')}>+ New folder</button>
    {/if}
  </div>
</div>

<input bind:this={pictureInput} type="file" accept="image/*" aria-label="A picture for the book" style="display:none" onchange={addPicture} />

<style>
  .book {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }
  .search {
    padding: 12px;
  }
  .search input {
    width: 100%;
  }
  .tree {
    flex: 1;
    padding: 0 6px 24px;
  }
  .group {
    margin-bottom: 4px;
  }
  .head {
    position: relative;
    display: flex;
    align-items: center;
  }
  .fold {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    text-align: left;
    border: 0;
    background: none;
    padding: 6px 4px;
    min-height: 32px;
  }
  .caret {
    display: inline-block;
    transition: transform 0.12s;
    transform: rotate(90deg);
    color: var(--muted);
    font-size: 0.8rem;
  }
  .caret.closed {
    transform: none;
  }
  .title {
    font-size: 0.78rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
  }
  .count {
    flex: none;
    min-width: 20px;
    padding: 0 6px;
    border-radius: 999px;
    background: var(--panel-2);
    color: var(--muted);
    font-size: 0.72rem;
    font-weight: 650;
    text-align: center;
    font-variant-numeric: tabular-nums;
  }
  .title.plain {
    padding: 6px 10px;
  }
  .folder > .head .title {
    text-transform: none;
    letter-spacing: 0;
    font-size: 0.92rem;
    font-weight: 600;
    color: #d6bf8a;
  }
  .dots {
    visibility: hidden;
    min-height: 28px;
    padding: 0 8px;
  }
  .head:hover .dots,
  .dots:focus-visible {
    visibility: visible;
  }
  .menu {
    position: absolute;
    right: 4px;
    top: 100%;
    z-index: 10;
    display: flex;
    flex-direction: column;
    min-width: 190px;
    padding: 4px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 10px;
    box-shadow: var(--shadow);
  }
  .menu button {
    text-align: left;
  }
  .newfight {
    color: var(--accent);
  }
  .more {
    color: var(--muted);
    font-size: 0.88rem;
  }
  .item {
    position: relative;
    display: flex;
    align-items: baseline;
    gap: 6px;
    width: 100%;
    text-align: left;
    border: 0;
    background: none;
    padding: 6px 10px;
    min-height: 34px;
    border-radius: 8px;
  }
  .item .icon {
    flex: none;
    align-self: center;
    width: 15px;
    height: 15px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.7;
    stroke-linejoin: round;
    stroke-linecap: round;
    color: var(--muted);
  }
  .item.on .icon {
    color: var(--accent);
  }
  /* short of room, the line beside a name gives way first (it has only the
     room left over), then the name */
  .item .label {
    flex: 0 1 auto;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .item .kindword {
    flex: none;
    padding: 0 5px;
    border: 1px solid var(--border);
    border-radius: 999px;
    color: var(--muted);
    font-size: 0.7rem;
    white-space: nowrap;
  }
  .item .sub {
    flex: 1 1 0;
    min-width: 0;
    color: var(--muted);
    font-size: 0.82rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .item.on {
    background: var(--accent-bg);
    color: var(--heading);
    box-shadow: inset 2px 0 0 var(--accent);
  }
  .empty {
    color: var(--muted);
    font-size: 0.85rem;
    margin: 4px 10px 8px;
  }
  .newtop {
    margin: 8px 6px;
    color: var(--muted);
  }
</style>
