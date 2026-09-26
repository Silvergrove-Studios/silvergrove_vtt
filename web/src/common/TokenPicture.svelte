<!--
  A character's token picture (the team: players want their own): the
  token as it looks, "Choose a picture" — a photo or a drawing, placed in
  the round window, made smaller here and kept by the table — and "Take it
  off" for the initials again. A player's for their own characters, the
  DM's for anyone's (the Table says).
-->
<script lang="ts">
  import CropPicture from './CropPicture.svelte';
  import { notice, uploadPicture } from '../lib/game.svelte';
  import { assetArt } from '../lib/art';
  import { prepare, type Crop } from '../lib/pictures';

  let {
    actor,
    art = '',
    name = '',
    color = '#4f9cf6',
    label = '',
  }: { actor: string; art?: string; name?: string; color?: string; label?: string } = $props();

  let choosing = $state<File | null>(null);
  let busy = $state(false);
  let input: HTMLInputElement | undefined = $state();

  const url = $derived(art ? assetArt('tokens', art).url : '');
  const initials = $derived(
    label ||
      name
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((w) => w[0]?.toUpperCase() ?? '')
        .join('') ||
      '?',
  );

  function picked(e: Event): void {
    const f = (e.currentTarget as HTMLInputElement).files?.[0] ?? null;
    (e.currentTarget as HTMLInputElement).value = '';
    if (!f) return;
    if (f.size > 40 * 1024 * 1024) {
      notice('That picture is too big to open here', 'error');
      return;
    }
    choosing = f;
  }

  async function use(crop: Crop): Promise<void> {
    const f = choosing;
    choosing = null;
    if (!f) return;
    busy = true;
    try {
      const data = await prepare(f, 'token', crop);
      const r = await uploadPicture('token', data, { actor });
      if (r.ref) notice(name ? `${name}’s token has its picture` : 'The token has its picture');
      else notice(r.why ?? 'The table did not keep it', 'error');
    } catch (err) {
      notice(`That picture could not be used: ${String((err as Error)?.message ?? err)}`, 'error');
    } finally {
      busy = false;
    }
  }

  async function takeOff(): Promise<void> {
    busy = true;
    const r = await uploadPicture('token', '', { actor, clear: true });
    busy = false;
    if (r.why) notice(r.why, 'error');
  }
</script>

<div class="token-picture">
  <div class="disc" style:--ring={color} aria-label={`${name}'s token`}>
    {#if url}<img src={url} alt="" />{:else}<span>{initials}</span>{/if}
  </div>
  <div class="what">
    <strong>Token</strong>
    <span class="dim small">{url ? 'Your picture, on the map.' : 'Initials on the map, or a picture of your own.'}</span>
    <div class="buttons">
      <button type="button" disabled={busy} onclick={() => input?.click()}>{busy ? 'Sending…' : url ? 'Another picture' : 'Choose a picture'}</button>
      {#if url}<button type="button" class="quiet" disabled={busy} onclick={takeOff}>Take it off</button>{/if}
    </div>
  </div>
  <input bind:this={input} class="file" type="file" accept="image/*" aria-label="A picture for the token" onchange={picked} />
</div>
{#if choosing}
  <CropPicture file={choosing} onuse={use} oncancel={() => (choosing = null)} />
{/if}

<style>
  .token-picture {
    display: flex;
    gap: 14px;
    align-items: center;
  }
  .disc {
    flex: none;
    width: 64px;
    height: 64px;
    border-radius: 50%;
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--ring);
    box-shadow: 0 0 0 3px var(--ring);
    color: #fff;
    font-weight: 750;
    font-size: 1.3rem;
  }
  .disc img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .what {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .small {
    font-size: 0.85rem;
  }
  .buttons {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-top: 2px;
  }
  .file {
    display: none;
  }
</style>
