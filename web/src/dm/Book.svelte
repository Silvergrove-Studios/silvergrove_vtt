<!--
  The DM's book: everything in the campaign in the DM's own arrangement —
  the sections (renamed as the DM likes), the DM's folders among and
  inside them — and one search over all of it and the rules.
-->
<script lang="ts">
  import { comp, dmOp, game, type Dict } from '../lib/game.svelte';
  import { book, type Item, type Node } from './contents';

  let { current = '', onopen }: { current?: string; onopen: (ref: string) => void } = $props();

  let q = $state('');
  let closed = $state<Record<string, boolean>>({ 'section:shown': true, 'section:pictures': true });
  let menu = $state('');
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
        for (const e of (reply.page?.entries as Dict[]) ?? []) found.push({ label: String(e.name ?? e.id), sub: coll.replace(/_/g, ' '), ref: `entry:${coll}/${e.id}` });
        rules = [...found];
      });
    }
  });

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
    <span class="label">{it.label}</span>
    {#if it.sub}<span class="sub">{it.sub}</span>{/if}
  </button>
  {#each it.children ?? [] as c (c.ref)}
    {@render item(c, depth + 1)}
  {/each}
{/snippet}

{#snippet group(n: Node, depth: number)}
  {@const isClosed = !q && (closed[n.node] ?? false)}
  <div class="group" class:folder={n.node.startsWith('folder:')}>
    <div class="head" style:padding-left={`${6 + depth * 14}px`}>
      <button type="button" class="fold" aria-expanded={!isClosed} onclick={() => (closed[n.node] = !isClosed)}>
        <span class="caret" class:closed={isClosed}>▸</span>
        <span class="title">{n.title}</span>
      </button>
      <button type="button" class="quiet dots" aria-label={`Arrange ${n.title}`} onclick={() => (menu = menu === n.node ? '' : n.node)}>⋯</button>
      {#if menu === n.node}
        <div class="menu" role="menu">
          <button type="button" role="menuitem" class="quiet" onclick={() => rename(n)}>Rename</button>
          <button type="button" role="menuitem" class="quiet" onclick={() => newFolder(n.node)}>New folder inside</button>
          {#if n.node.startsWith('folder:')}
            <button type="button" role="menuitem" class="quiet" onclick={() => { menu = ''; dmOp('folder', { do: 'move', id: n.node.slice(7), parent: '' }); }}>Move to the top</button>
            <button type="button" role="menuitem" class="quiet danger" onclick={() => remove(n)}>Delete the folder</button>
          {/if}
        </div>
      {/if}
    </div>
    {#if !isClosed}
      {#each n.folders as f (f.node)}{@render group(f, depth + 1)}{/each}
      {#each n.items as it (it.ref)}{@render item(it, depth + 1)}{/each}
      {#if n.folders.length === 0 && n.items.length === 0}
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
  .item {
    display: flex;
    align-items: baseline;
    gap: 8px;
    width: 100%;
    text-align: left;
    border: 0;
    background: none;
    padding: 6px 10px;
    min-height: 34px;
    border-radius: 8px;
  }
  .item .label {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .item .sub {
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
