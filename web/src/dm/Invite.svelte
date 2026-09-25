<!--
  How the players join: a code to scan with a phone's camera, the address
  to type, and a player's screen on this very computer (another window).
-->
<script lang="ts">
  import qrcode from 'qrcode-generator';
  import Modal from '../common/Modal.svelte';
  import { game } from '../lib/game.svelte';

  let { onclose }: { onclose: () => void } = $props();

  const urls = $derived(((game.dm.hosting?.urls as string[]) ?? []).map(String));
  let chosen = $state(0);
  const url = $derived(urls[chosen] ?? '');
  const svg = $derived.by(() => {
    if (!url) return '';
    const qr = qrcode(0, 'M');
    qr.addData(url);
    qr.make();
    return qr.createSvgTag({ cellSize: 6, margin: 2, scalable: true });
  });
  const here = `${location.protocol}//${location.host}/`;
</script>

<Modal title="Invite your players" {onclose}>
  <div class="invite">
    {#if url}
      <div class="qr" aria-label={`A QR code for ${url}`}>{@html svg}</div>
      <p class="how">Point a phone’s camera at the code, or open this address in any browser on the same Wi-Fi:</p>
      <p class="url">{url}</p>
      {#if urls.length > 1}
        <label class="dim small">This computer has several networks. Players are on:
          <select bind:value={chosen}>
            {#each urls as u, i (u)}<option value={i}>{u}</option>{/each}
          </select>
        </label>
      {/if}
    {:else}
      <p>This computer is not on a network other devices can reach. Players on this computer can still join:</p>
    {/if}
    <p class="dim">Nothing to install. They type their name and they are in; a player who has been here before taps their name.</p>
    <a class="button" href={here} target="_blank" rel="noopener">Open a player’s screen on this computer</a>
  </div>
</Modal>

<style>
  .invite {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    gap: 10px;
  }
  .qr {
    width: min(280px, 70vw);
    padding: 12px;
    background: #fff;
    border-radius: 16px;
  }
  .qr :global(svg) {
    display: block;
    width: 100%;
    height: auto;
  }
  .how {
    margin: 6px 0 0;
  }
  .url {
    margin: 0;
    font-size: 1.35rem;
    font-weight: 650;
    font-variant-numeric: tabular-nums;
    color: var(--heading);
    user-select: all;
  }
  .small {
    font-size: 0.88rem;
  }
  .button {
    display: inline-block;
    margin-top: 6px;
    padding: 9px 16px;
    border-radius: 10px;
    border: 1px solid var(--border);
    background: var(--panel-2);
    color: var(--text);
    text-decoration: none;
  }
  .button:hover {
    background: var(--panel-3);
  }
</style>
