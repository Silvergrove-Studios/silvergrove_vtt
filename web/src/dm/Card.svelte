<!--
  One thing in the DM's book, as a card that reads well: a place (its
  picture, the words to read aloud, the DM's notes, who is there, the
  fight it holds), a person (what the players may learn, what the DM
  knows, their stat block or sheet), a note, a picture, a map, a rule.
  Anything a player may see has "Show the players" on it.
-->
<script lang="ts">
  import View from '../lib/views/View.svelte';
  import { comp, dmOp, game, playerName, type Dict } from '../lib/game.svelte';
  import { markdown } from '../lib/markdown';
  import { pictureUrl } from '../lib/art';
  import AddPicture from '../common/AddPicture.svelte';
  import FightCard from './FightCard.svelte';
  import TokenPicture from '../common/TokenPicture.svelte';
  import { cardData, cardSchema } from '../lib/views/viewlib';
  import { audienceWords, folderChoices, kindWord, layout } from './contents';

  let starting = $state(false);
  let { ref, onopen, onclose, popout }: { ref: string; onopen: (ref: string) => void; onclose?: () => void; popout?: () => void } = $props();

  const dm = $derived(game.dm);
  const kind = $derived(ref.split(':')[0]);
  const id = $derived(ref.slice(kind.length + 1));
  const place = $derived(kind === 'place' ? ((dm.places as Dict[]) ?? []).find((p) => String(p.id) === id) : undefined);
  const person = $derived(kind === 'actor' ? ((dm.people as Dict[]) ?? []).find((a) => String(a.id) === id) ?? viewActorAsPerson(id) : undefined);
  const note = $derived(kind === 'note' || kind === 'handout' ? ((dm.journal as Dict[]) ?? []).find((n) => String(n.id) === id) : undefined);
  const picture = $derived(kind === 'picture' ? ((dm.pictures as Dict[]) ?? []).find((p) => String(p.ref) === id) : undefined);
  const mapEntry = $derived(kind === 'map' ? ((dm.maps as Dict[]) ?? []).find((m) => String(m.id) === id) : undefined);
  const pnote = $derived(kind === 'pnote' ? ((dm.player_notes as Dict[]) ?? []).find((n) => String(n.id) === id) : undefined);
  const encounter = $derived(place?.kind === 'encounter' ? ((dm.encounters as Dict[]) ?? []).find((e) => String(e.id) === String(place.target ?? '')) : undefined);
  // a fight prepared or of the DM's own (fight:<id>)
  const fightEntry = $derived(kind === 'fight' ? ((dm.encounters as Dict[]) ?? []).find((e) => String(e.id) === id) : undefined);
  const viewActor = $derived(kind === 'actor' ? ((game.view.actors ?? {}) as Dict)[id] : undefined);
  // what it is, in the book's words: a place that holds a fight is a place
  const itsKind = $derived(
    kind === 'actor' ? (person?.kind === 'pc' ? 'character' : 'person')
    : kind === 'note' ? (note?.kind === 'handout' ? 'handout' : 'note')
    : ({ handout: 'shown', pnote: 'from_player', entry: 'rule' } as Record<string, string>)[kind] ?? kind,
  );
  const shownNow = $derived(((dm.shown as Dict[]) ?? []).filter((h) => String(h.ref ?? '') === ref));
  const folders = $derived(folderChoices(dm));
  const filedIn = $derived(String(layout(dm).in[ref] ?? ''));
  let editing = $state(false);
  let editingNotes = $state(false);
  // the text boxes a picture can go into (the team: pictures in notes)
  let yoursArea: HTMLTextAreaElement | undefined = $state();
  let readAloudArea: HTMLTextAreaElement | undefined = $state();
  let publicArea: HTMLTextAreaElement | undefined = $state();
  let entry = $state<Dict | null>(null);
  let entryError = $state('');
  let showMenu = $state(false);

  function viewActorAsPerson(aid: string): Dict | undefined {
    const a = ((game.view.actors ?? {}) as Dict)[aid];
    return a ? { id: a.id, name: a.name, kind: a.kind, owner: a.owner, place: '', image: '', public: '', notes: '' } : undefined;
  }

  // a rule: fetched from the compendium
  $effect(() => {
    entry = null;
    entryError = '';
    if (kind !== 'entry') return;
    const [coll, ...rest] = id.split('/');
    comp(coll, { id: rest.join('/') }).then((reply) => {
      if (reply.entry) entry = { collection: coll, data: cardData(reply.entry, 'gm') };
      else entryError = String(reply.error ?? 'not found');
    });
  });

  /** What "Show the players" sends for this card. */
  const share = $derived.by((): Dict | null => {
    if (place) return { ref, title: place.name, text: place.text ?? '', image: place.image ?? '' };
    if (person) return { ref, title: person.name, text: person.public ?? '', image: person.image ?? '' };
    if (note && kind === 'note') return { ref, title: note.title ?? '', text: note.text ?? '', image: note.image ?? '' };
    if (picture) return { ref, title: picture.name, text: '', image: picture.ref };
    return null;
  });

  function show(audience: string): void {
    if (!share) return;
    dmOp('share', { ...share, audience });
    showMenu = false;
  }

  let timers: Record<string, ReturnType<typeof setTimeout>> = {};
  function later(key: string, f: () => void): void {
    clearTimeout(timers[key]);
    timers[key] = setTimeout(f, 700);
  }

  function setPlace(field: string, value: string): void {
    later(`p:${field}`, () => dmOp('place_set', { place: id, [field]: value }));
  }

  function setActor(field: string, value: string): void {
    later(`a:${field}`, () => dmOp('actor_set', { actor: id, [field]: value }));
  }

  const peopleHere = $derived(place ? ((dm.people as Dict[]) ?? []).filter((a) => String(a.place ?? '') === String(place.id) && a.kind !== 'pc') : []);
  const isLive = $derived(!!encounter?.live && Object.keys(encounter.live).length > 0);
  const players = $derived(game.players);
</script>

{#snippet yours(text: string, placeholder: string, save: (v: string) => void)}
  <section class="yours">
    <div class="yourshead">
      <h3>For you <span class="dim">— the players never see this</span></h3>
      <button type="button" class="quiet small" onclick={() => (editingNotes = !editingNotes)}>{editingNotes ? 'Done' : text.trim() ? 'Edit' : 'Write some'}</button>
    </div>
    {#if editingNotes}
      <textarea bind:this={yoursArea} rows="10" {placeholder} value={text} oninput={(e) => save(e.currentTarget.value)}></textarea>
      <AddPicture target={yoursArea} onvalue={save} />
    {:else if text.trim()}
      <div class="prose notes">{@html markdown(text)}</div>
    {/if}
  </section>
{/snippet}

<article class="card">
  <header class="head">
    <div class="titles">
      <p class="kind">{kindWord(itsKind)}</p>
      <h2>{place?.name ?? person?.name ?? note?.title ?? picture?.name ?? mapEntry?.name ?? pnote?.title ?? fightEntry?.name ?? entry?.data?.entry?.name ?? (kind === 'entry' || kind === 'fight' ? '' : 'Not found')}</h2>
    </div>
    <div class="tools">
      {#if popout}<button type="button" class="quiet" title="Open this card in a window of its own" onclick={popout}>Pop out ↗</button>{/if}
      {#if onclose}<button type="button" class="quiet close" aria-label="Close the card" onclick={onclose}>✕</button>{/if}
    </div>
  </header>

  {#if share}
    <div class="sharebar">
      <div class="showbtn">
        <button type="button" class="accent" onclick={() => show('all')}>Show the players</button>
        {#if players.length > 1}
          <button type="button" class="accent more" aria-label="Show only some players" onclick={() => (showMenu = !showMenu)}>▾</button>
        {/if}
        {#if showMenu}
          <div class="menu" role="menu">
            {#each players as p (p.id)}
              <button type="button" role="menuitem" class="quiet" onclick={() => show(`players:${p.id}`)}>Only {p.name}</button>
            {/each}
          </div>
        {/if}
      </div>
      {#if shownNow.length}
        <span class="dim">Shown to {shownNow.map((h) => h.words ?? audienceWords(dm, players, String(h.audience ?? ''))).join(', ')}</span>
        <button type="button" class="quiet" onclick={() => dmOp('unshare', { ref })}>Take it back</button>
      {:else}
        <span class="dim">Only you can see this until you show it.</span>
      {/if}
    </div>
  {/if}

  <div class="body">
    {#if place}
      {#if place.image && pictureUrl(String(place.image))}<img class="hero" src={pictureUrl(String(place.image))} alt="" />{/if}
      {#if place.kind === 'encounter'}
        <div class="fight" class:live={isLive}>
          {#if isLive}
            <strong>The fight is on.</strong>
            <span class="dim">Run it from the fight bar over the map.</span>
            <button type="button" onclick={() => dmOp('end_fight')}>End the fight</button>
          {:else}
            <div>
              <strong>{encounter?.name ?? 'A fight'}</strong>
              {#if encounter?.creatures?.length}
                <p class="dim">{encounter.creatures.map((c: Dict) => `${c.count ?? 1} × ${c.name ?? c.entry ?? c.id ?? '?'}`).join(', ')}</p>
              {/if}
            </div>
            <!-- (one press: the fight takes a moment to set up, and a second press started it twice) -->
            <button type="button" class="accent" disabled={starting} onclick={() => { starting = true; dmOp('go_place', { place: id }); setTimeout(() => (starting = false), 5000); }}>{starting ? 'Starting…' : 'Start the fight'}</button>
          {/if}
          {#if encounter}<button type="button" class="quiet" onclick={() => onopen(`fight:${encounter.id}`)}>Its creatures and map</button>{/if}
        </div>
        {#if encounter?.notes}<div class="prose dmnotes">{@html markdown(String(encounter.notes))}</div>{/if}
      {:else if place.kind === 'map'}
        <button type="button" onclick={() => dmOp('go_place', { place: id })}>Show its map</button>
      {/if}
      {#if editing}
        <label class="edit">Name <input type="text" value={place.name ?? ''} oninput={(e) => setPlace('name', e.currentTarget.value)} /></label>
        <label class="edit">Read aloud <textarea bind:this={readAloudArea} rows="8" value={place.text ?? ''} oninput={(e) => setPlace('text', e.currentTarget.value)}></textarea></label>
        <AddPicture target={readAloudArea} onvalue={(v) => setPlace('text', v)} label="Add a picture to the words" />
      {:else if String(place.text ?? '').trim()}
        <section class="readaloud">
          <h3>Read aloud</h3>
          <div class="prose">{@html markdown(String(place.text))}</div>
        </section>
      {/if}
      {@render yours(String(place.notes ?? ''), 'What you know about this place', (v) => setPlace('notes', v))}
      {#if peopleHere.length}
        <section>
          <h3>Here</h3>
          <div class="links">
            {#each peopleHere as a (a.id)}<button type="button" class="link" onclick={() => onopen(`actor:${a.id}`)}>{a.name}</button>{/each}
          </div>
        </section>
      {/if}
      {#if place.marker?.scene}
        <label class="toggle">
          <input type="checkbox" checked={!place.marker.hidden} onchange={(e) => dmOp('token', { scene: place.marker.scene, id: place.id, hidden: !e.currentTarget.checked })} />
          The players can see it on the map
        </label>
      {/if}
      <button type="button" class="quiet small" onclick={() => (editing = !editing)}>{editing ? 'Done editing' : 'Edit the name and the words'}</button>
    {:else if person}
      {#if person.image && pictureUrl(String(person.image))}<img class="portrait" src={pictureUrl(String(person.image))} alt="" />{/if}
      {#if person.kind === 'pc' && person.owner}<p class="dim">Played by {playerName(String(person.owner))}</p>{/if}
      {#if person.place}
        <p class="dim">At <button type="button" class="link" onclick={() => onopen(`place:${person.place}`)}>{((dm.places as Dict[]) ?? []).find((p) => p.id === person.place)?.name ?? 'somewhere'}</button></p>
      {/if}
      {#if person.kind !== 'pc'}
        <section>
          <h3>What the players may learn</h3>
          {#if editing}
            <textarea bind:this={publicArea} rows="5" value={person.public ?? ''} oninput={(e) => setActor('public', e.currentTarget.value)}></textarea>
            <AddPicture target={publicArea} onvalue={(v) => setActor('public', v)} />
          {:else if String(person.public ?? '').trim()}
            <div class="prose">{@html markdown(String(person.public))}</div>
          {:else}
            <p class="dim">Nothing yet.</p>
          {/if}
        </section>
        {@render yours(String(person.notes ?? ''), 'What they want, what they know, how they talk', (v) => setActor('notes', v))}
        <button type="button" class="quiet small" onclick={() => (editing = !editing)}>{editing ? 'Done editing' : 'Edit what the players may learn'}</button>
      {/if}
      {#if viewActor}
        <!-- the token's picture: the DM's for anyone (the team) -->
        <section class="token">
          <TokenPicture actor={id} art={String((viewActor.token as Dict)?.art ?? '')} name={String(viewActor.name ?? '')} color={person.kind === 'pc' && person.owner ? (game.players.find((p) => String(p.id) === String(person.owner))?.color ?? '#4f9cf6') : '#c0392b'} label={String((viewActor.token as Dict)?.label ?? '')} />
        </section>
        <section class="sheet">
          {#each (viewActor.sheets as Dict[]) ?? [] as sh, i (i)}
            <View node={sh.schema} ctx={sh.data} />
          {/each}
        </section>
      {/if}
    {:else if note}
      {#if note.image && pictureUrl(String(note.image))}<img class="hero" src={pictureUrl(String(note.image))} alt="" />{/if}
      {#if kind === 'handout'}
        <p class="dim">Shown to {audienceWords(dm, players, String(note.audience ?? 'gm'))}{note.session ? ` in session ${note.session}` : ''}</p>
      {/if}
      <div class="prose">{@html markdown(String(note.text ?? ''))}</div>
      {#if kind === 'handout' && note.ref}
        <button type="button" onclick={() => onopen(String(note.ref))}>Open what was shown</button>
      {/if}
    {:else if picture}
      <img class="big" src={pictureUrl(String(picture.ref))} alt={String(picture.name ?? '')} />
    {:else if mapEntry}
      <p class="dim">{mapEntry.role === 'regional' ? 'The region: where the party travels' : 'A battle map'}</p>
      {#if String(game.scene.map ?? '') === String(mapEntry.id)}
        <p><strong>The players are looking at it now.</strong></p>
      {:else}
        <button type="button" class="accent" onclick={() => dmOp('show_map', { map: mapEntry.id })}>Show the players this map</button>
      {/if}
    {:else if pnote}
      <p class="dim">From {playerName(String(pnote.owner ?? ''))}</p>
      <div class="prose">{@html markdown(String(pnote.text ?? ''))}</div>
    {:else if kind === 'fight'}
      <FightCard fightId={id} {onclose} {onopen} />
    {:else if kind === 'entry'}
      {#if entry}
        <View node={cardSchema(game.view.cards ?? {}, String(entry.collection))} ctx={{ ...entry.data, role: 'gm' }} />
      {:else}
        <p class="dim">{entryError || 'Looking it up…'}</p>
      {/if}
    {:else}
      <p class="dim">This is no longer in the campaign.</p>
    {/if}

    {#if kind !== 'handout' && kind !== 'pnote' && (place || person || note || picture || mapEntry || kind === 'entry')}
      <label class="file dim">
        In the book:
        <select value={filedIn} onchange={(e) => dmOp('folder', { do: 'file', ref, folder: e.currentTarget.value })}>
          <option value="">its own section</option>
          {#each folders as f (f.id)}<option value={f.id}>{f.path}</option>{/each}
        </select>
      </label>
    {/if}
  </div>
</article>

<style>
  .card {
    display: flex;
    flex-direction: column;
    min-height: 100%;
  }
  .head {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    padding: 18px 20px 10px 24px;
  }
  .titles {
    flex: 1;
    min-width: 0;
  }
  .kind {
    margin: 0 0 2px;
    color: var(--accent);
    font-size: 0.75rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    font-weight: 650;
  }
  h2 {
    font-size: 1.75rem;
    line-height: 1.15;
  }
  .tools {
    display: flex;
    gap: 4px;
  }
  .close {
    width: 38px;
    padding: 0;
  }
  .sharebar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px 12px;
    padding: 0 24px 12px;
    border-bottom: 1px solid var(--border-soft);
  }
  .showbtn {
    position: relative;
    display: flex;
    gap: 1px;
  }
  .showbtn .accent:first-child:not(:last-child) {
    border-radius: 10px 0 0 10px;
  }
  .more {
    border-radius: 0 10px 10px 0;
    padding: 0 10px;
  }
  .menu {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    z-index: 5;
    display: flex;
    flex-direction: column;
    min-width: 180px;
    padding: 4px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 10px;
    box-shadow: var(--shadow);
  }
  .menu button {
    text-align: left;
  }
  .body {
    padding: 16px 24px 32px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
  .body h3 {
    font-size: 0.95rem;
    font-family: var(--font-ui);
    font-weight: 650;
    margin: 0 0 6px;
    color: var(--heading);
  }
  .hero {
    width: 100%;
    max-height: 300px;
    object-fit: cover;
    border-radius: 12px;
  }
  .portrait {
    width: 160px;
    height: 160px;
    object-fit: cover;
    border-radius: 12px;
  }
  .big {
    width: 100%;
    max-height: 70vh;
    object-fit: contain;
    border-radius: 12px;
    background: #0b0c0f;
  }
  .readaloud {
    padding: 14px 16px;
    border-radius: 12px;
    background: #1f1a14;
    border: 1px solid rgba(229, 165, 90, 0.28);
    font-family: var(--font-display);
    font-size: 1.08rem;
  }
  .readaloud h3 {
    font-family: var(--font-ui);
    font-size: 0.72rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--accent);
  }
  .yours textarea,
  .edit textarea,
  .edit input {
    width: 100%;
  }
  .yourshead {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px;
  }
  .notes {
    padding: 12px 14px;
    border-radius: 12px;
    background: rgba(184, 156, 255, 0.07);
    border: 1px solid rgba(184, 156, 255, 0.22);
  }
  .edit {
    display: flex;
    flex-direction: column;
    gap: 4px;
    color: var(--muted);
  }
  .fight {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 12px 14px;
    border-radius: 12px;
    border: 1px solid rgba(227, 107, 91, 0.35);
    background: rgba(227, 107, 91, 0.08);
  }
  .fight p {
    margin: 2px 0 0;
  }
  .fight.live {
    flex-wrap: wrap;
  }
  .dmnotes {
    color: var(--muted);
  }
  .links {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .link {
    background: none;
    border: 0;
    padding: 0;
    min-height: 0;
    color: var(--accent);
    text-decoration: underline;
    text-underline-offset: 3px;
  }
  .links .link {
    padding: 4px 0;
    margin-right: 12px;
  }
  .toggle {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .small {
    align-self: flex-start;
    font-size: 0.88rem;
    color: var(--muted);
  }
  .sheet {
    border-top: 1px solid var(--border-soft);
    padding-top: 12px;
  }
  .file {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.88rem;
  }
  .file select {
    min-height: 32px;
    padding: 4px 8px;
  }
</style>
