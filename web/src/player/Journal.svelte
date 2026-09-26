<!--
  A player's own book (the host's PlayerJournal): their notes, in folders
  of their own and on the things they were shown; what the DM has shown
  them — places, people, pictures, handouts — for as long as the DM leaves
  it shown; and the notes other players shared with them. One search over
  all of it. Notes are kept by the Table in the campaign: private unless
  shared with the DM, some of the players, or everyone.
-->
<script lang="ts">
  import { clone } from '../lib/views/viewlib';
  import { game, handouts, intent, playerName, type Dict } from '../lib/game.svelte';
  import { markdown } from '../lib/markdown';
  import { pictureUrl } from '../lib/art';
  import AddPicture from '../common/AddPicture.svelte';

  let q = $state('');
  let current = $state('');
  /** Notes changed here and not yet echoed back by the Table (a late echo must not undo typing). */
  let local = $state<Record<string, Dict>>({});
  let deleted = $state<Record<string, boolean>>({});
  let armed = $state('');
  let timer: ReturnType<typeof setTimeout> | null = null;

  const me = $derived(game.me);
  const viewNotes = $derived(((game.view.notes as Dict[]) ?? []).filter((n) => n && typeof n === 'object'));
  const mine = $derived.by(() => {
    const out: Dict[] = [];
    const seen = new Set<string>();
    for (const n of viewNotes) {
      const id = String(n.id ?? '');
      if (String(n.owner ?? '') !== me || deleted[id]) continue;
      seen.add(id);
      out.push(local[id] ?? n);
    }
    for (const [id, n] of Object.entries(local)) if (!seen.has(id) && !deleted[id]) out.push(n);
    return out;
  });
  const others = $derived(viewNotes.filter((n) => String(n.owner ?? '') !== me));
  const shown = $derived(handouts());

  // local copies the Table has caught up with, and deletions it has made, are let go
  $effect(() => {
    const there = new Map(viewNotes.map((n) => [String(n.id ?? ''), n]));
    for (const [id, l] of Object.entries(local)) {
      const t = there.get(id);
      if (t && t.title === l.title && t.text === l.text && (t.folder ?? '') === (l.folder ?? '') && JSON.stringify(t.share ?? []) === JSON.stringify(l.share ?? [])) delete local[id];
    }
    for (const id of Object.keys(deleted)) if (!there.has(id)) delete deleted[id];
  });

  function matches(rec: Dict, text: string): boolean {
    if (!text) return true;
    return `${rec.title ?? ''} ${rec.text ?? ''} ${rec.folder ?? ''}`.toLowerCase().includes(text);
  }

  function label(n: Dict): string {
    if (String(n.title ?? '').trim()) return String(n.title);
    const t = String(n.text ?? '').trim().split('\n')[0];
    return t ? t.slice(0, 40) : 'Untitled note';
  }

  function refOf(h: Dict): string {
    return String(h.ref || h.id || '');
  }

  const GROUPS: Record<string, string> = { place: 'Places', actor: 'People', picture: 'Pictures', '': 'Handouts' };

  const tree = $derived.by(() => {
    const text = q.trim().toLowerCase();
    const folders = new Map<string, Dict[]>();
    const loose: Dict[] = [];
    for (const n of mine) {
      if (!matches(n, text) || n.about) continue;
      const f = String(n.folder ?? '');
      if (f) folders.set(f, [...(folders.get(f) ?? []), n]);
      else loose.push(n);
    }
    const fromDm = new Map<string, { h: Dict; notes: Dict[] }[]>();
    for (const h of shown) {
      const ref = String(h.ref ?? '');
      const onIt = mine.filter((n) => ref && n.about === ref);
      if (!matches(h, text) && !onIt.some((n) => matches(n, text))) continue;
      let kind = ref.includes(':') ? ref.split(':')[0] : '';
      if (!(kind in GROUPS)) kind = '';
      fromDm.set(kind, [...(fromDm.get(kind) ?? []), { h, notes: onIt }]);
    }
    // notes on things no longer shown stay with my notes
    for (const n of mine) {
      if (!n.about || !matches(n, text)) continue;
      if (!shown.some((h) => refOf(h) === n.about)) loose.push(n);
    }
    return { folders: [...folders.entries()].sort(([a], [b]) => a.localeCompare(b)), loose, fromDm, others: others.filter((n) => matches(n, text)) };
  });

  function open(key: string): void {
    current = key;
    armed = '';
  }

  function save(n: Dict): void {
    intent({ kind: 'note', op: 'save', note: { id: n.id, title: n.title ?? '', text: n.text ?? '', folder: n.folder ?? '', about: n.about ?? '', share: n.share ?? [] } });
  }

  function newNote(about = '', title = ''): void {
    const id = `pn_${Math.floor(Math.random() * 0xffffffff).toString(16).padStart(8, '0')}${Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0')}`;
    const n = { id, owner: me, title, text: '', folder: '', about, share: [] };
    local[id] = n;
    save(n);
    open(`mine:${id}`);
    queueMicrotask(() => (document.getElementById('note-title') as HTMLInputElement | null)?.focus());
  }

  let noteArea: HTMLTextAreaElement | undefined = $state();

  function edit(id: string, field: 'title' | 'text' | 'folder', value: string): void {
    const cur = { ...(mine.find((n) => n.id === id) ?? {}) };
    cur[field] = value;
    local[id] = cur;
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => save(local[id] ?? cur), 800);
  }

  function flush(id: string): void {
    if (timer) clearTimeout(timer);
    timer = null;
    if (local[id]) save(local[id]);
  }

  function setShare(id: string, who: string, on: boolean): void {
    const cur = clone($state.snapshot(mine.find((n) => n.id === id) ?? {})) as Dict;
    let share: string[] = [...((cur.share as string[]) ?? [])];
    if (who === 'all') share = on ? ['all'] : [];
    else {
      share = share.filter((s) => s !== 'all');
      if (on && !share.includes(who)) share.push(who);
      if (!on) share = share.filter((s) => s !== who);
    }
    share.sort();
    cur.share = share;
    local[id] = cur;
    save(cur);
  }

  function remove(id: string): void {
    if (armed !== id) {
      armed = id;
      return;
    }
    deleted[id] = true;
    delete local[id];
    intent({ kind: 'note', op: 'delete', id });
    current = '';
  }

  function shareWords(share: string[]): string {
    if (share.includes('all')) return 'everyone';
    if (!share.length) return 'only you';
    return `you and ${share.map((s) => (s === 'gm' ? 'the DM' : playerName(s))).join(', ')}`;
  }

  const kind = $derived(current.split(':')[0]);
  const id = $derived(current.slice(kind.length + 1));
  const myNote = $derived(kind === 'mine' ? mine.find((n) => n.id === id) : undefined);
  const otherNote = $derived(kind === 'other' ? others.find((n) => n.id === id) : undefined);
  const shownThing = $derived(kind === 'shown' ? shown.find((h) => refOf(h) === id) : undefined);
  const targets = $derived([['gm', 'The DM'], ...game.players.filter((p) => String(p.id) !== me).map((p) => [String(p.id), String(p.name ?? p.id)]), ['all', 'Everyone']]);
  const hasCard = $derived(!!(myNote || otherNote || shownThing));
</script>

<!-- a box the Journal measures itself by: in the wide screen's side panel it is
     narrow though the window is not (a playtest's editor was squeezed to a sliver) -->
<div class="journal-box">
<div class="journal" class:reading={hasCard}>
  <div class="index">
    <div class="top">
      <input type="search" placeholder="Search your journal" bind:value={q} />
      <button type="button" class="accent" onclick={() => newNote()}>New note</button>
    </div>
    <div class="list scroll">
      <h3>My notes</h3>
      {#each tree.folders as [folder, notes] (folder)}
        <div class="folder">{folder}</div>
        {#each notes as n (n.id)}
          <button type="button" class="row nested" class:on={current === `mine:${n.id}`} onclick={() => open(`mine:${n.id}`)}>{label(n)}</button>
        {/each}
      {/each}
      {#each tree.loose as n (n.id)}
        <button type="button" class="row" class:on={current === `mine:${n.id}`} onclick={() => open(`mine:${n.id}`)}>{label(n)}</button>
      {/each}
      {#if !tree.folders.length && !tree.loose.length}
        <p class="dim none">{q ? 'Nothing matches' : 'None yet — New note'}</p>
      {/if}
      {#if tree.fromDm.size}
        <h3>From the DM</h3>
        {#each Object.keys(GROUPS) as g}
          {#if tree.fromDm.get(g)}
            <div class="folder">{GROUPS[g]}</div>
            {#each tree.fromDm.get(g) ?? [] as { h, notes } (refOf(h))}
              <button type="button" class="row nested" class:on={current === `shown:${refOf(h)}`} onclick={() => open(`shown:${refOf(h)}`)}>{h.title || 'From the DM'}</button>
              {#each notes as n (n.id)}
                <button type="button" class="row nested2" class:on={current === `mine:${n.id}`} onclick={() => open(`mine:${n.id}`)}>✎ {label(n)}</button>
              {/each}
            {/each}
          {/if}
        {/each}
      {/if}
      {#if tree.others.length}
        <h3>From other players</h3>
        {#each tree.others as n (n.id)}
          <button type="button" class="row" class:on={current === `other:${n.id}`} onclick={() => open(`other:${n.id}`)}>{label(n)} <span class="dim">— {playerName(String(n.owner ?? ''))}</span></button>
        {/each}
      {/if}
    </div>
  </div>

  <div class="card scroll">
    {#if hasCard}<button type="button" class="quiet back" onclick={() => (current = '')}>‹ Journal</button>{/if}
    {#if myNote}
      {@const n = myNote}
      <input id="note-title" class="title" type="text" placeholder="Title" value={n.title ?? ''} oninput={(e) => edit(n.id, 'title', e.currentTarget.value)} onblur={() => flush(n.id)} />
      <label class="field"><span class="dim">Folder</span>
        <input type="text" placeholder="none — or name one to group your notes" value={n.folder ?? ''} oninput={(e) => edit(n.id, 'folder', e.currentTarget.value)} onblur={() => flush(n.id)} />
      </label>
      {#if n.about}
        {@const on = shown.find((h) => refOf(h) === n.about)}
        <p class="dim">On: {on ? on.title || 'From the DM' : 'something no longer shown'}
          {#if on}<button type="button" class="quiet" onclick={() => open(`shown:${n.about}`)}>Open</button>{/if}
        </p>
      {/if}
      <textarea bind:this={noteArea} rows="10" placeholder="Your note" value={n.text ?? ''} oninput={(e) => edit(n.id, 'text', e.currentTarget.value)} onblur={() => flush(n.id)}></textarea>
      <!-- a picture into the note, where the cursor is (the team) -->
      <AddPicture target={noteArea} onvalue={(v) => { edit(n.id, 'text', v); flush(n.id); }} />
      {#if /!\[[^\]]*\]\(/.test(String(n.text ?? ''))}
        <div class="preview">
          <p class="dim small">How it reads</p>
          <div class="prose">{@html markdown(String(n.text ?? ''))}</div>
        </div>
      {/if}
      <fieldset class="share">
        <legend>Who can read it: {shareWords((n.share as string[]) ?? [])}</legend>
        {#each targets as [who, name] (who)}
          <label><input type="checkbox" checked={((n.share as string[]) ?? []).includes(who)} onchange={(e) => setShare(n.id, who, e.currentTarget.checked)} /> {name}</label>
        {/each}
      </fieldset>
      <button type="button" class="danger" onclick={() => remove(n.id)}>{armed === n.id ? 'Tap again to delete it' : 'Delete this note'}</button>
    {:else if otherNote}
      <h2>{otherNote.title || 'A note'}</h2>
      <p class="dim">From {playerName(String(otherNote.owner ?? ''))}</p>
      <div class="prose">{@html markdown(String(otherNote.text ?? ''))}</div>
    {:else if shownThing}
      {@const h = shownThing}
      <h2>{h.title || 'From the DM'}</h2>
      <p class="dim">{h.session ? `Shown to you in session ${h.session}` : 'Shown to you this session'}</p>
      {#if h.image && pictureUrl(String(h.image))}<img src={pictureUrl(String(h.image))} alt="" />{/if}
      <div class="prose">{@html markdown(String(h.text ?? ''))}</div>
      {@const notes = mine.filter((n) => n.about === refOf(h))}
      {#if notes.length}
        <h3>My notes on this</h3>
        {#each notes as n (n.id)}<button type="button" class="row" onclick={() => open(`mine:${n.id}`)}>{label(n)}</button>{/each}
      {/if}
      <button type="button" onclick={() => newNote(refOf(h), String(h.title ?? ''))}>Add a note on this</button>
    {:else}
      <p class="dim hint">Your notes, and everything the DM has shown you. Write a note with <strong>New note</strong>; it is yours alone until you share it.</p>
    {/if}
  </div>
</div>
</div>

<style>
  .journal-box {
    container-type: inline-size;
    height: 100%;
    min-height: 0;
  }
  .journal {
    display: grid;
    grid-template-columns: minmax(220px, 300px) 1fr;
    height: 100%;
    min-height: 0;
  }
  .index {
    display: flex;
    flex-direction: column;
    min-height: 0;
    border-right: 1px solid var(--border-soft);
  }
  .top {
    display: flex;
    gap: 8px;
    padding: 12px;
  }
  .top input {
    flex: 1;
    min-width: 0;
  }
  .list {
    flex: 1;
    padding: 0 8px 16px;
  }
  .list h3 {
    font-size: 0.8rem;
    font-family: var(--font-ui);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    margin: 14px 8px 6px;
  }
  .folder {
    margin: 8px 8px 2px;
    color: #c9b27f;
    font-size: 0.9rem;
  }
  .row {
    display: block;
    width: 100%;
    text-align: left;
    border: 0;
    background: none;
    padding: 8px 10px;
    min-height: 38px;
    border-radius: 8px;
  }
  .row.nested {
    padding-left: 20px;
  }
  .row.nested2 {
    padding-left: 32px;
    color: var(--muted);
  }
  .row.on {
    background: var(--accent-bg);
    color: var(--heading);
  }
  .none {
    margin: 4px 10px;
  }
  .card {
    padding: 16px 20px 32px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-height: 0;
  }
  .card h2 {
    font-size: 1.4rem;
  }
  .card h3 {
    font-size: 1rem;
  }
  .card img {
    max-width: 100%;
    max-height: 50vh;
    object-fit: contain;
    border-radius: 10px;
    align-self: flex-start;
  }
  .title {
    font-size: 1.15rem;
    font-weight: 600;
  }
  .field {
    display: flex;
    gap: 10px;
    align-items: center;
  }
  .field input {
    flex: 1;
  }
  .preview {
    padding: 10px 12px;
    border-radius: 12px;
    border: 1px dashed var(--border);
  }
  .preview .small {
    margin: 0 0 6px;
    font-size: 0.8rem;
  }
  .share {
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 8px 12px 12px;
    display: flex;
    flex-wrap: wrap;
    gap: 8px 18px;
  }
  .share legend {
    color: var(--muted);
    padding: 0 4px;
  }
  .share label {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 36px;
  }
  .back {
    display: none;
    align-self: flex-start;
  }
  .hint {
    max-width: 440px;
    margin-top: 24px;
  }
  @container (max-width: 760px) {
    .journal {
      grid-template-columns: 1fr;
    }
    .index {
      border-right: 0;
    }
    .journal .card {
      display: none;
    }
    .journal.reading .index {
      display: none;
    }
    .journal.reading .card {
      display: flex;
    }
    .back {
      display: inline-flex;
    }
  }
</style>
