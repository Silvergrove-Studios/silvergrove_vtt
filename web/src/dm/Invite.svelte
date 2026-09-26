<!--
  How the players join: a code to scan with a phone's camera, the address
  to type, and a player's screen on this very computer (another window).
  One address, the likeliest; this computer's others folded away, each
  said for what it is; and how players somewhere else can join.
-->
<script lang="ts">
  import qrcode from 'qrcode-generator';
  import Modal from '../common/Modal.svelte';
  import { game } from '../lib/game.svelte';
  import { addressKind } from './invite';

  let { onclose }: { onclose: () => void } = $props();

  // (the host lists them likeliest first)
  const urls = $derived(((game.dm.hosting?.urls as string[]) ?? []).map(String));
  let chosen = $state('');
  const url = $derived(urls.includes(chosen) ? chosen : (urls[0] ?? ''));
  const others = $derived(urls.filter((u) => u !== url));
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
      <p class="how">Players with you: scan the code, or open this address in any browser. Their phone or computer must be on the same network as this one (the same Wi-Fi or router).</p>
      <p class="url">{url}</p>
      {#if others.length}
        <details class="others">
          <summary>Other addresses of this computer</summary>
          <ul>
            {#each others as u (u)}
              <li>
                <span class="addr">{u}</span>
                <span class="dim">{addressKind(u)}</span>
                <button type="button" class="quiet show" onclick={() => (chosen = u)}>Show its code</button>
              </li>
            {/each}
          </ul>
        </details>
      {/if}
    {:else}
      <p>This computer is not on a network other devices can reach. Players on this computer can still join:</p>
    {/if}
    <p class="dim">Nothing to install. They type their name and they are in; a player who has been here before taps their name.</p>
    <a class="button" href={here} target="_blank" rel="noopener">Open a player’s screen on this computer</a>
    <p class="apart">
      <strong>Players somewhere else?</strong> Hexmap serves your local network only and does not reach them over the internet by itself. To play apart,
      first put this computer and their devices on one private network with a VPN app (Tailscale, ZeroTier), then send them this computer’s address on
      it. If nobody can open the address, check that this computer’s firewall lets Hexmap accept connections.
    </p>
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
  /* (room below it for how players somewhere else join, on a laptop's screen) */
  .qr {
    width: min(220px, 60vw);
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
  .others {
    align-self: stretch;
    text-align: left;
    font-size: 0.9rem;
  }
  .others summary {
    cursor: pointer;
    color: var(--muted);
    text-align: center;
  }
  .others ul {
    list-style: none;
    margin: 8px 0 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .others li {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 4px 10px;
  }
  .addr {
    font-variant-numeric: tabular-nums;
    user-select: all;
  }
  .show {
    margin-left: auto;
    min-height: 28px;
    padding: 2px 10px;
    font-size: 0.85rem;
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
  .apart {
    align-self: stretch;
    margin: 6px 0 0;
    padding-top: 12px;
    border-top: 1px solid var(--border-soft);
    text-align: left;
    font-size: 0.88rem;
    color: var(--muted);
  }
  .apart strong {
    color: var(--text);
  }
</style>
